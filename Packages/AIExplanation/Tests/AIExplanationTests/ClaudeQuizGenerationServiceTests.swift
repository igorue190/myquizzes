//
//  ClaudeQuizGenerationServiceTests.swift
//  AIExplanationTests
//
//  Exercises the Claude-backed quiz generator against a stubbed URLProtocol (no
//  real network) plus the pure Markdown renderer. Covers the not-configured and
//  empty-source guards, a valid structured response rendered to the app's Markdown
//  format, and an API error payload.
//

import Testing
import Foundation
@testable import AIExplanation
import CoreModels

// MARK: - Fixtures

private func request(source: String = "Mitochondria are the powerhouse of the cell.") -> QuizGenerationRequest {
    QuizGenerationRequest(sourceText: source, questionCount: 5, title: "Biology")
}

private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [GenStubURLProtocol.self]
    return URLSession(configuration: config)
}

/// A dedicated stub for this suite. swift-testing runs suites in parallel and
/// static storage is shared across a class hierarchy, so the generation tests use
/// their own URLProtocol class to avoid racing the explanation suite's stub.
final class GenStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastBody = request.httpBody ?? Self.readBody(from: request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(from request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// A valid Messages response whose text block is the structured quiz JSON.
private func responseBody(_ innerJSON: String) -> String {
    "{\"content\":[{\"type\":\"text\",\"text\":\(jsonString(innerJSON))}]}"
}

private let sampleInner = """
{"title":"Cell Biology","questions":[\
{"prompt":"What is the powerhouse of the cell?","type":"single",\
"choices":[{"text":"Mitochondria","correct":true},{"text":"Nucleus","correct":false}],\
"explanation":"Mitochondria produce ATP."},\
{"prompt":"Cells are alive.","type":"truefalse",\
"choices":[{"text":"True","correct":true},{"text":"False","correct":false}],\
"explanation":"By definition."}\
]}
"""

// MARK: - Tests

@Suite("ClaudeQuizGenerationService", .serialized)
struct ClaudeQuizGenerationServiceTests {

    @Test("throws notConfigured when no key is available")
    func noKeyThrows() async {
        let service = ClaudeQuizGenerationService(session: session(), keyProvider: { nil })
        await #expect(throws: QuizGenerationError.notConfigured) {
            try await service.generate(request())
        }
    }

    @Test("throws emptySource for blank material")
    func emptySourceThrows() async {
        let service = ClaudeQuizGenerationService(session: session(), keyProvider: { "sk-test" })
        await #expect(throws: QuizGenerationError.emptySource) {
            try await service.generate(request(source: "   \n  "))
        }
    }

    @Test("renders a valid response into the app's Markdown format")
    func parsesAndRenders() async throws {
        GenStubURLProtocol.handler = { _ in (200, Data(responseBody(sampleInner).utf8)) }

        let service = ClaudeQuizGenerationService(session: session(), keyProvider: { "sk-test" })
        let markdown = try await service.generate(request())

        #expect(markdown.contains("title: Cell Biology"))
        #expect(markdown.contains("## What is the powerhouse of the cell?"))
        #expect(markdown.contains("<!-- type: single -->"))
        #expect(markdown.contains("<!-- type: truefalse -->"))
        #expect(markdown.contains("- [x] Mitochondria"))
        #expect(markdown.contains("- [ ] Nucleus"))
        #expect(markdown.contains("> **Explanation:** Mitochondria produce ATP."))
    }

    @Test("renderMarkdown falls back to the request title and normalizes types")
    func rendererFallbacksAndNormalization() {
        let quiz = GeneratedQuiz(
            title: "  ",
            questions: [
                GeneratedQuiz.Question(
                    prompt: "Pick the prime numbers.",
                    type: "MULTIPLE",
                    choices: [
                        GeneratedQuiz.Choice(text: "2", correct: true),
                        GeneratedQuiz.Choice(text: "3", correct: true),
                        GeneratedQuiz.Choice(text: "4", correct: false)
                    ],
                    explanation: ""
                ),
                // Blank prompt is skipped entirely.
                GeneratedQuiz.Question(prompt: "  ", type: "single", choices: [
                    GeneratedQuiz.Choice(text: "x", correct: true)
                ], explanation: "")
            ]
        )
        let markdown = ClaudeQuizGenerationService.renderMarkdown(quiz, fallbackTitle: "Numbers")
        #expect(markdown.contains("title: Numbers"))
        #expect(markdown.contains("<!-- type: multiple -->"))
        #expect(!markdown.contains("##  "))           // blank-prompt question dropped
        #expect(!markdown.contains("**Explanation:**")) // no explanation line when empty
    }

    @Test("surfaces the API error message on a non-2xx response")
    func apiError() async {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        GenStubURLProtocol.handler = { _ in (401, Data(body.utf8)) }

        let service = ClaudeQuizGenerationService(session: session(), keyProvider: { "sk-bad" })
        await #expect(throws: QuizGenerationError.api("invalid x-api-key")) {
            try await service.generate(request())
        }
    }

    @Test("throws decoding when the model returns no questions")
    func emptyQuestionsThrows() async {
        let inner = #"{"title":"Empty","questions":[]}"#
        GenStubURLProtocol.handler = { _ in (200, Data(responseBody(inner).utf8)) }

        let service = ClaudeQuizGenerationService(session: session(), keyProvider: { "sk-test" })
        await #expect(throws: QuizGenerationError.decoding) {
            try await service.generate(request())
        }
    }

    @Test("sends model id, key header, and structured-output config")
    func requestShape() async throws {
        GenStubURLProtocol.handler = { req in
            #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test")
            #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            if let sent = GenStubURLProtocol.lastBody,
               let json = try? JSONSerialization.jsonObject(with: sent) as? [String: Any] {
                #expect(json["model"] as? String == "claude-opus-4-8")
                #expect(json["output_config"] != nil)
            } else {
                Issue.record("request body was not captured/parseable")
            }
            return (200, Data(responseBody(sampleInner).utf8))
        }

        let service = ClaudeQuizGenerationService(session: session(), keyProvider: { "sk-test" })
        _ = try await service.generate(request())
    }
}

// MARK: - Helpers

/// JSON-encode a string so it can be embedded as a value in a larger JSON literal.
private func jsonString(_ s: String) -> String {
    String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
}

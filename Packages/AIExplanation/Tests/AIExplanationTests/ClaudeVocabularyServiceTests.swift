//
//  ClaudeVocabularyServiceTests.swift
//  AIExplanationTests
//
//  Exercises the Claude-backed vocabulary structurer against a stubbed URLProtocol
//  (no real network). Covers the not-configured and empty-source guards, a valid
//  structured response rendered to the app's Markdown vocab format (and parsed back
//  via the real VocabularyParser so the renderer and parser can't drift), an empty
//  response, and an API error payload.
//

import Testing
import Foundation
@testable import AIExplanation
import CoreModels
import MarkdownParser

// MARK: - Fixtures

private func request(source: String = "dobar dan = good day, hvala = thank you") -> VocabularyGenerationRequest {
    VocabularyGenerationRequest(
        sourceText: source,
        foreignLanguage: .croatian,
        nativeLanguage: .english,
        maxEntries: 20,
        title: "Croatian Basics"
    )
}

private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [VocabGenStubURLProtocol.self]
    return URLSession(configuration: config)
}

/// A dedicated stub for this suite. swift-testing runs suites in parallel and the
/// static handler is shared per class, so the vocab tests use their own URLProtocol
/// class to avoid racing the quiz-generation suite's stub.
final class VocabGenStubURLProtocol: URLProtocol {
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

private func responseBody(_ innerJSON: String) -> String {
    "{\"content\":[{\"type\":\"text\",\"text\":\(jsonStringV(innerJSON))}]}"
}

private let sampleInner = """
{"title":"Croatian — Basics","entries":[\
{"term":"dobar dan","translation":"good day","phonetic":"DOH-bar dahn","transcription":"добар дан","example":"Dobar dan!"},\
{"term":"hvala","translation":"thank you"}\
]}
"""

// MARK: - Tests

@Suite("ClaudeVocabularyService", .serialized)
struct ClaudeVocabularyServiceTests {

    @Test("throws notConfigured when no key is available")
    func noKeyThrows() async {
        let service = ClaudeVocabularyService(session: session(), keyProvider: { nil })
        await #expect(throws: VocabularyGenerationError.notConfigured) {
            try await service.generate(request())
        }
    }

    @Test("throws emptySource for blank material")
    func emptySourceThrows() async {
        let service = ClaudeVocabularyService(session: session(), keyProvider: { "sk-test" })
        await #expect(throws: VocabularyGenerationError.emptySource) {
            try await service.generate(request(source: "   \n  "))
        }
    }

    @Test("renders a valid response that parses back into the expected set")
    func parsesAndRenders() async throws {
        VocabGenStubURLProtocol.handler = { _ in (200, Data(responseBody(sampleInner).utf8)) }

        let service = ClaudeVocabularyService(session: session(), keyProvider: { "sk-test" })
        let markdown = try await service.generate(request())

        #expect(markdown.contains("kind: vocabulary"))
        #expect(markdown.contains("foreign: Croatian (hr)"))
        #expect(markdown.contains("native: English (en)"))

        // The renderer's output must be readable by the real parser.
        let set = try #require(VocabularyParser().parse(markdown))
        #expect(set.title == "Croatian — Basics")
        #expect(set.entries.count == 2)
        #expect(set.entries[0].term == "dobar dan")
        #expect(set.entries[0].translation == "good day")
        #expect(set.entries[0].phonetic == "DOH-bar dahn")
        #expect(set.entries[0].transcription == "добар дан")
        #expect(set.entries[1].phonetic == nil)
        #expect(set.entries[1].transcription == nil)
    }

    @Test("surfaces the API error message on a non-2xx response")
    func apiError() async {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        VocabGenStubURLProtocol.handler = { _ in (401, Data(body.utf8)) }

        let service = ClaudeVocabularyService(session: session(), keyProvider: { "sk-bad" })
        await #expect(throws: VocabularyGenerationError.api("invalid x-api-key")) {
            try await service.generate(request())
        }
    }

    @Test("throws decoding when the model returns no entries")
    func emptyEntriesThrows() async {
        let inner = #"{"title":"Empty","entries":[]}"#
        VocabGenStubURLProtocol.handler = { _ in (200, Data(responseBody(inner).utf8)) }

        let service = ClaudeVocabularyService(session: session(), keyProvider: { "sk-test" })
        await #expect(throws: VocabularyGenerationError.decoding) {
            try await service.generate(request())
        }
    }

    @Test("sends model id, key header, and structured-output config")
    func requestShape() async throws {
        VocabGenStubURLProtocol.handler = { req in
            #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test")
            if let sent = VocabGenStubURLProtocol.lastBody,
               let json = try? JSONSerialization.jsonObject(with: sent) as? [String: Any] {
                #expect(json["model"] as? String == "claude-opus-4-8")
                #expect(json["output_config"] != nil)
            } else {
                Issue.record("request body was not captured/parseable")
            }
            return (200, Data(responseBody(sampleInner).utf8))
        }

        let service = ClaudeVocabularyService(session: session(), keyProvider: { "sk-test" })
        _ = try await service.generate(request())
    }
}

// MARK: - Helpers

private func jsonStringV(_ s: String) -> String {
    String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
}

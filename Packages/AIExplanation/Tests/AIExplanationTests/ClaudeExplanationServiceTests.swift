//
//  ClaudeExplanationServiceTests.swift
//  AIExplanationTests
//
//  Exercises the Claude-backed service end-to-end against a stubbed URLProtocol,
//  so no real network is touched (CI stays offline). Covers the not-configured
//  guard, a valid structured response, and an API error payload.
//

import Testing
import Foundation
@testable import AIExplanation
import CoreModels

// MARK: - Fixtures

private func request() -> ExplanationRequest {
    ExplanationRequest(
        prompt: "What is 2 + 2?",
        choices: [
            AttemptChoice(id: 0, text: "3", isCorrect: false),
            AttemptChoice(id: 1, text: "4", isCorrect: true)
        ],
        selectedChoiceIDs: [0],
        correctChoiceIDs: [1]
    )
}

private func session() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Tests

// Serialized: the tests share `StubURLProtocol.handler` (process-global), so they
// must not run concurrently.
@Suite("ClaudeExplanationService", .serialized)
struct ClaudeExplanationServiceTests {

    @Test("throws notConfigured when no key is available")
    func noKeyThrows() async {
        let service = ClaudeExplanationService(session: session(), keyProvider: { nil })
        await #expect(throws: ExplanationError.notConfigured) {
            try await service.explain(request())
        }
    }

    @Test("parses a valid structured response into an Explanation")
    func parsesValidResponse() async throws {
        let inner = """
        {"explanation":"4 is correct because 2+2=4.","sources":[{"title":"Math","url":"https://example.com"}]}
        """
        let body = """
        {"content":[{"type":"text","text":\(jsonString(inner))}]}
        """
        StubURLProtocol.handler = { _ in (200, Data(body.utf8)) }

        let service = ClaudeExplanationService(session: session(), keyProvider: { "sk-test" })
        let explanation = try await service.explain(request())

        #expect(explanation.text == "4 is correct because 2+2=4.")
        #expect(explanation.sources.count == 1)
        #expect(explanation.sources.first?.url == "https://example.com")
    }

    @Test("surfaces the API error message on a non-2xx response")
    func apiError() async {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        StubURLProtocol.handler = { _ in (401, Data(body.utf8)) }

        let service = ClaudeExplanationService(session: session(), keyProvider: { "sk-bad" })
        await #expect(throws: ExplanationError.api("invalid x-api-key")) {
            try await service.explain(request())
        }
    }

    @Test("sends model, key header, and structured-output config")
    func requestShape() async throws {
        let body = #"{"content":[{"type":"text","text":"{\"explanation\":\"ok\",\"sources\":[]}"}]}"#
        StubURLProtocol.handler = { req in
            #expect(req.value(forHTTPHeaderField: "x-api-key") == "sk-test")
            #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            // URLProtocol strips httpBody into a stream; assert via the captured copy.
            if let sent = StubURLProtocol.lastBody,
               let json = try? JSONSerialization.jsonObject(with: sent) as? [String: Any] {
                #expect(json["model"] as? String == "claude-opus-4-8")
                #expect(json["output_config"] != nil)
            } else {
                Issue.record("request body was not captured/parseable")
            }
            return (200, Data(body.utf8))
        }

        let service = ClaudeExplanationService(session: session(), keyProvider: { "sk-test" })
        _ = try await service.explain(request())
    }

    @Test("user message asks for the explanation language when one is requested")
    func includesRequestedLanguage() {
        var req = request()
        req = ExplanationRequest(
            prompt: req.prompt,
            choices: req.choices,
            selectedChoiceIDs: req.selectedChoiceIDs,
            correctChoiceIDs: req.correctChoiceIDs,
            explanationLanguage: "Russian"
        )
        let message = ClaudeExplanationService.userMessage(for: req)
        #expect(message.contains("Write your explanation in Russian."))
    }

    @Test("user message omits the language line when none is requested")
    func omitsLanguageWhenAbsent() {
        let message = ClaudeExplanationService.userMessage(for: request())
        #expect(!message.contains("Write your explanation in"))
    }
}

// MARK: - Helpers

/// JSON-encode a string so it can be embedded as a value in a larger JSON literal.
private func jsonString(_ s: String) -> String {
    String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
}

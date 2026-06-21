//
//  ClaudeExplanationService.swift
//  AIExplanation
//
//  The concrete `ExplanationService`: it asks Anthropic's Messages API to explain
//  a missed question and returns a structured `Explanation`. Implemented over raw
//  `URLSession` (Anthropic ships no Swift SDK, and the product avoids third-party
//  deps). An `actor` behind the `Sendable` protocol, with an injectable session
//  and key provider so it's testable against a stubbed `URLProtocol`.
//

import Foundation
import CoreModels

public actor ClaudeExplanationService: ExplanationService {

    /// Where the user's key comes from. Defaults to the Keychain; tests inject.
    private let keyProvider: @Sendable () -> String?
    /// The model id to send, read per call so the Profile picker takes effect.
    private let modelProvider: @Sendable () -> String
    private let session: URLSession

    private let maxTokens = 1024
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"

    public init(
        session: URLSession = .shared,
        keyProvider: @escaping @Sendable () -> String? = { KeychainStore.loadAPIKey() },
        modelProvider: @escaping @Sendable () -> String = { "claude-opus-4-8" }
    ) {
        self.session = session
        self.keyProvider = keyProvider
        self.modelProvider = modelProvider
    }

    // MARK: - ExplanationService

    public func explain(_ request: ExplanationRequest) async throws -> Explanation {
        guard let key = keyProvider(), !key.isEmpty else {
            throw ExplanationError.notConfigured
        }

        let urlRequest = try makeURLRequest(for: request, key: key)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ExplanationError.network
        }

        guard let http = response as? HTTPURLResponse else { throw ExplanationError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw ExplanationError.api(Self.errorMessage(from: data, status: http.statusCode))
        }

        return try Self.parseExplanation(from: data)
    }

    // MARK: - Request building

    func makeURLRequest(for request: ExplanationRequest, key: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": modelProvider(),
            "max_tokens": maxTokens,
            "system": Self.systemPrompt,
            "messages": [
                ["role": "user", "content": Self.userMessage(for: request)]
            ],
            "output_config": ["format": Self.outputFormat()]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// The JSON-schema we constrain the model to, so the first text block is
    /// always parseable as an `Explanation`. A function (not a stored static) so
    /// the non-`Sendable` dictionary is built fresh per call, never shared.
    static func outputFormat() -> [String: Any] { [
        "type": "json_schema",
        "schema": [
            "type": "object",
            "properties": [
                "explanation": ["type": "string"],
                "sources": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "url": ["type": "string"]
                        ],
                        "required": ["title", "url"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["explanation", "sources"],
            "additionalProperties": false
        ]
    ] }

    static let systemPrompt = """
    You help a student understand why they got a quiz question wrong. Explain which \
    answer is correct and why the chosen answer is not. Write the explanation in the \
    language requested in the message; if none is requested, use the same language as \
    the question. Be concise and concrete. Provide reputable sources when you are \
    confident they exist; otherwise return an empty sources array. Do not invent \
    URLs. Respond only with the requested JSON object.
    """

    static func userMessage(for request: ExplanationRequest) -> String {
        var lines: [String] = ["Question: \(request.prompt)", "", "Options:"]
        for choice in request.choices {
            var tags: [String] = []
            if request.selectedChoiceIDs.contains(choice.id) { tags.append("chosen") }
            if request.correctChoiceIDs.contains(choice.id) { tags.append("correct") }
            let suffix = tags.isEmpty ? "" : " [\(tags.joined(separator: ", "))]"
            lines.append("- \(choice.text)\(suffix)")
        }
        if let existing = request.existingExplanation,
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Author note (expand on this, don't contradict it): \(existing)")
        }
        if let language = request.explanationLanguage,
           !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Write your explanation in \(language).")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Response parsing

    static func parseExplanation(from data: Data) throws -> Explanation {
        guard let message = try? JSONDecoder().decode(MessagesResponse.self, from: data),
              let text = message.content.first(where: { $0.type == "text" })?.text,
              let payloadData = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ExplanationPayload.self, from: payloadData)
        else {
            throw ExplanationError.decoding
        }
        return Explanation(text: payload.explanation, sources: payload.sources ?? [])
    }

    static func errorMessage(from data: Data, status: Int) -> String {
        if let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return decoded.error.message
        }
        return "Request failed (HTTP \(status))."
    }
}

// MARK: - Wire types

/// The subset of the Messages API response we read.
private struct MessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
}

/// The JSON the model returns inside the text block, matching `outputFormat`.
private struct ExplanationPayload: Decodable {
    let explanation: String
    let sources: [Source]?
}

private struct APIErrorResponse: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

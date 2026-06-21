//
//  ClaudeVocabularyService.swift
//  AIExplanation
//
//  The concrete `VocabularyGenerationService`: it asks Anthropic's Messages API to
//  *extract and clean* bilingual word/phrase pairs from arbitrary text, then renders
//  them into the app's Markdown vocab format so the result flows through the existing
//  import pipeline. The model only structures the pairs — the app builds quizzes and
//  flashcards from them offline. The sibling of `ClaudeQuizGenerationService`: same
//  raw-`URLSession` approach (no SDK, no third-party deps), an `actor` behind the
//  `Sendable` protocol, with injectable session/key/model providers so it's testable
//  against a stubbed `URLProtocol`.
//

import Foundation
import CoreModels

public actor ClaudeVocabularyService: VocabularyGenerationService {

    private let keyProvider: @Sendable () -> String?
    private let modelProvider: @Sendable () -> String
    private let session: URLSession

    private let maxTokens = 8192
    /// Guard against runaway prompts: trim the source so the request stays bounded.
    private let maxSourceCharacters = 24_000
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

    // MARK: - VocabularyGenerationService

    public func generate(_ request: VocabularyGenerationRequest) async throws -> String {
        guard let key = keyProvider(), !key.isEmpty else {
            throw VocabularyGenerationError.notConfigured
        }
        guard !request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VocabularyGenerationError.emptySource
        }

        let urlRequest = try makeURLRequest(for: request, key: key)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw VocabularyGenerationError.network
        }

        guard let http = response as? HTTPURLResponse else { throw VocabularyGenerationError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw VocabularyGenerationError.api(Self.errorMessage(from: data, status: http.statusCode))
        }

        let vocab = try Self.parseGeneratedVocab(from: data)
        return Self.renderMarkdown(
            vocab,
            request: request
        )
    }

    // MARK: - Request building

    func makeURLRequest(for request: VocabularyGenerationRequest, key: String) throws -> URLRequest {
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
                ["role": "user", "content": userMessage(for: request)]
            ],
            "output_config": ["format": Self.outputFormat()]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    /// The JSON-schema we constrain the model to, so the first text block is always
    /// parseable as a `GeneratedVocab`. A function (not a stored static) so the
    /// non-`Sendable` dictionary is built fresh per call, never shared.
    static func outputFormat() -> [String: Any] { [
        "type": "json_schema",
        "schema": [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "entries": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "term": ["type": "string"],
                            "translation": ["type": "string"],
                            "phonetic": ["type": "string"],
                            "transcription": ["type": "string"],
                            "example": ["type": "string"]
                        ],
                        "required": ["term", "translation"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["title", "entries"],
            "additionalProperties": false
        ]
    ] }

    static let systemPrompt = """
    You extract foreign-language vocabulary from study material into clean bilingual \
    pairs. The user tells you the foreign language (the `term`) and their native \
    language (the `translation`). Pull out the most useful words AND short phrases; \
    keep multi-word phrases intact. Do NOT invent vocabulary the source doesn't \
    contain, and do not add commentary. Put the foreign word/phrase in `term` and its \
    meaning in the native language in `translation`. When you are confident, add a \
    short `phonetic` pronunciation hint (Latin/IPA-style), a `transcription` that \
    spells out the foreign term's pronunciation using the NATIVE language's own \
    script/alphabet (e.g. Croatian "hvala" → Russian "хвала"; leave empty when the \
    native language already uses the Latin alphabet and a transcription would just \
    repeat the term), and a brief `example` sentence in the foreign language; omit \
    any of these when unsure rather than guessing. De-duplicate entries. \
    Respond only with the requested JSON object.
    """

    func userMessage(for request: VocabularyGenerationRequest) -> String {
        let source = String(request.sourceText.prefix(maxSourceCharacters))
        var lines: [String] = [
            "Foreign language (term): \(request.foreignLanguage.label)",
            "Native language (translation): \(request.nativeLanguage.label)",
            "Extract up to \(request.maxEntries) vocabulary pairs from the material below."
        ]
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            lines.append("Suggested title: \(title)")
        }
        lines.append("")
        lines.append("Source material:")
        lines.append(source)
        return lines.joined(separator: "\n")
    }

    // MARK: - Response parsing

    static func parseGeneratedVocab(from data: Data) throws -> GeneratedVocab {
        guard let message = try? JSONDecoder().decode(VocabMessagesResponse.self, from: data),
              let text = message.content.first(where: { $0.type == "text" })?.text,
              let payloadData = text.data(using: .utf8),
              let vocab = try? JSONDecoder().decode(GeneratedVocab.self, from: payloadData)
        else {
            throw VocabularyGenerationError.decoding
        }
        guard !vocab.entries.isEmpty else { throw VocabularyGenerationError.decoding }
        return vocab
    }

    static func errorMessage(from data: Data, status: Int) -> String {
        if let decoded = try? JSONDecoder().decode(VocabAPIErrorResponse.self, from: data) {
            return decoded.error.message
        }
        return "Request failed (HTTP \(status))."
    }

    // MARK: - Markdown rendering

    /// Render a structured `GeneratedVocab` into the app's Markdown vocab format
    /// (front matter + a pipe table). Kept in lock-step with `VocabularyParser`; a
    /// test parses the output back to guard against drift.
    static func renderMarkdown(_ vocab: GeneratedVocab, request: VocabularyGenerationRequest) -> String {
        let title = firstNonEmpty(vocab.title, request.title) ?? "Vocabulary"
        var out: [String] = []
        out.append("---")
        out.append("kind: vocabulary")
        out.append("title: \(singleLine(title))")
        out.append("foreign: \(singleLine(request.foreignLanguage.label))")
        out.append("native: \(singleLine(request.nativeLanguage.label))")
        out.append("---")
        out.append("")
        out.append("| Term | Translation | Pronunciation | Transcription | Example |")
        out.append("|------|-------------|---------------|---------------|---------|")
        for entry in vocab.entries {
            let term = singleLine(entry.term)
            let translation = singleLine(entry.translation)
            guard !term.isEmpty, !translation.isEmpty else { continue }
            let cells = [
                term,
                translation,
                singleLine(entry.phonetic ?? ""),
                singleLine(entry.transcription ?? ""),
                singleLine(entry.example ?? "")
            ].map { $0.replacingOccurrences(of: "|", with: "\\|") }
            out.append("| \(cells.joined(separator: " | ")) |")
        }
        return out.joined(separator: "\n") + "\n"
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Wire types

/// The JSON the model returns inside the text block, matching `outputFormat`.
struct GeneratedVocab: Decodable {
    struct Entry: Decodable {
        let term: String
        let translation: String
        let phonetic: String?
        let transcription: String?
        let example: String?
    }
    let title: String
    let entries: [Entry]
}

/// The subset of the Messages API response we read.
private struct VocabMessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
}

private struct VocabAPIErrorResponse: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

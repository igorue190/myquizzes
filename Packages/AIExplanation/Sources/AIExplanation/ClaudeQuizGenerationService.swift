//
//  ClaudeQuizGenerationService.swift
//  AIExplanation
//
//  The concrete `QuizGenerationService`: it asks Anthropic's Messages API to turn
//  arbitrary study material into a structured quiz, then renders that into the
//  app's own Markdown quiz format so the result flows through the existing import
//  pipeline. The sibling of `ClaudeExplanationService` — same raw-`URLSession`
//  approach (no Swift SDK, no third-party deps), an `actor` behind the `Sendable`
//  protocol, with injectable session/key/model providers so it's testable against
//  a stubbed `URLProtocol`.
//

import Foundation
import CoreModels

public actor ClaudeQuizGenerationService: QuizGenerationService {

    /// Where the user's key comes from. Defaults to the Keychain; tests inject.
    private let keyProvider: @Sendable () -> String?
    /// The model id to send, read per call so the Profile picker takes effect.
    private let modelProvider: @Sendable () -> String
    private let session: URLSession

    /// Generous budget: a multi-question quiz with explanations is far larger than
    /// a single explanation response.
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

    // MARK: - QuizGenerationService

    public func generate(_ request: QuizGenerationRequest) async throws -> String {
        guard let key = keyProvider(), !key.isEmpty else {
            throw QuizGenerationError.notConfigured
        }
        guard !request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuizGenerationError.emptySource
        }

        let urlRequest = try makeURLRequest(for: request, key: key)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw QuizGenerationError.network
        }

        guard let http = response as? HTTPURLResponse else { throw QuizGenerationError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw QuizGenerationError.api(Self.errorMessage(from: data, status: http.statusCode))
        }

        let quiz = try Self.parseGeneratedQuiz(from: data)
        return Self.renderMarkdown(quiz, fallbackTitle: request.title)
    }

    // MARK: - Request building

    func makeURLRequest(for request: QuizGenerationRequest, key: String) throws -> URLRequest {
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
    /// parseable as a `GeneratedQuiz`. A function (not a stored static) so the
    /// non-`Sendable` dictionary is built fresh per call, never shared.
    static func outputFormat() -> [String: Any] { [
        "type": "json_schema",
        "schema": [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "questions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "prompt": ["type": "string"],
                            "type": ["type": "string", "enum": ["single", "multiple", "truefalse"]],
                            "choices": [
                                "type": "array",
                                "items": [
                                    "type": "object",
                                    "properties": [
                                        "text": ["type": "string"],
                                        "correct": ["type": "boolean"]
                                    ],
                                    "required": ["text", "correct"],
                                    "additionalProperties": false
                                ]
                            ],
                            "explanation": ["type": "string"]
                        ],
                        "required": ["prompt", "type", "choices", "explanation"],
                        "additionalProperties": false
                    ]
                ]
            ],
            "required": ["title", "questions"],
            "additionalProperties": false
        ]
    ] }

    static let systemPrompt = """
    You create study quizzes from source material. Write questions in the same \
    language as the source. Cover the most important facts and concepts; do not \
    invent facts the source doesn't support. For each question pick a type: \
    "single" (exactly one correct choice), "multiple" (two or more correct \
    choices), or "truefalse" (exactly the choices True and False, one correct). \
    Give "single" questions 3-4 plausible choices; mark the correct ones with \
    correct=true. Write a brief explanation of why the correct answer is right. \
    Respond only with the requested JSON object.
    """

    func userMessage(for request: QuizGenerationRequest) -> String {
        let source = String(request.sourceText.prefix(maxSourceCharacters))
        var lines: [String] = [
            "Generate \(request.questionCount) quiz questions from the material below."
        ]
        if let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            lines.append("Suggested topic/title: \(title)")
        }
        lines.append("")
        lines.append("Source material:")
        lines.append(source)
        return lines.joined(separator: "\n")
    }

    // MARK: - Response parsing

    static func parseGeneratedQuiz(from data: Data) throws -> GeneratedQuiz {
        guard let message = try? JSONDecoder().decode(MessagesResponse.self, from: data),
              let text = message.content.first(where: { $0.type == "text" })?.text,
              let payloadData = text.data(using: .utf8),
              let quiz = try? JSONDecoder().decode(GeneratedQuiz.self, from: payloadData)
        else {
            throw QuizGenerationError.decoding
        }
        guard !quiz.questions.isEmpty else { throw QuizGenerationError.decoding }
        return quiz
    }

    static func errorMessage(from data: Data, status: Int) -> String {
        if let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
            return decoded.error.message
        }
        return "Request failed (HTTP \(status))."
    }

    // MARK: - Markdown rendering

    /// Render a structured `GeneratedQuiz` into the app's Markdown quiz format
    /// (front matter + `## question` blocks with `<!-- type -->`, `- [x]` choices,
    /// and a `> **Explanation:**` blockquote). Pure and unit-tested so the wire
    /// shape and the parser's expected shape stay in lock-step.
    static func renderMarkdown(_ quiz: GeneratedQuiz, fallbackTitle: String?) -> String {
        var out: [String] = []

        let title = firstNonEmpty(quiz.title, fallbackTitle) ?? "Generated Quiz"
        out.append("---")
        out.append("title: \(escapeFrontMatter(title))")
        out.append("---")
        out.append("")

        for question in quiz.questions {
            let prompt = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !question.choices.isEmpty else { continue }

            out.append("## \(prompt)")
            out.append("<!-- type: \(normalizedType(question.type)) -->")
            out.append("")
            for choice in question.choices {
                let mark = choice.correct ? "x" : " "
                out.append("- [\(mark)] \(choice.text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            let explanation = question.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !explanation.isEmpty {
                out.append("")
                out.append("> **Explanation:** \(explanation)")
            }
            out.append("")
        }

        return out.joined(separator: "\n")
    }

    /// Map the model's type string onto the parser's expected raw values, defaulting
    /// to `single` for anything unexpected.
    private static func normalizedType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "multiple":  return "multiple"
        case "truefalse", "true/false", "boolean": return "truefalse"
        default:          return "single"
        }
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    /// Keep a title on a single front-matter line: collapse newlines to spaces.
    private static func escapeFrontMatter(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Wire types

/// The JSON the model returns inside the text block, matching `outputFormat`.
struct GeneratedQuiz: Decodable {
    struct Question: Decodable {
        let prompt: String
        let type: String
        let choices: [Choice]
        let explanation: String
    }
    struct Choice: Decodable {
        let text: String
        let correct: Bool
    }
    let title: String
    let questions: [Question]
}

/// The subset of the Messages API response we read.
private struct MessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
}

private struct APIErrorResponse: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

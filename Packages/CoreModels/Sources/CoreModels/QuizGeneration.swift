//
//  QuizGeneration.swift
//  CoreModels
//
//  The AI quiz-generation boundary: value types for asking an external model to
//  turn arbitrary study material into a quiz, and the `QuizGenerationService`
//  protocol the feature layer talks to. The sibling of `Explanation.swift` — it
//  lives here so features depend only on the abstraction; a concrete Claude-backed
//  actor lives in the `AIExplanation` package and is injected at the AppFeature
//  composition root. The service returns Markdown in the app's own quiz format, so
//  generated output flows straight into the existing parse → review → save import
//  pipeline. Like explanations, this is an opt-in cloud call using the user's key.
//

import Foundation

// MARK: - Request

/// Everything the model needs to generate a quiz from study material. A pure
/// value type so it crosses the actor boundary freely.
public struct QuizGenerationRequest: Sendable, Equatable, Codable, Hashable {
    /// The source material the questions should be drawn from (pasted notes or
    /// the text of an imported file).
    public let sourceText: String
    /// How many questions to ask the model for. The model may return fewer if the
    /// source is thin; the review screen surfaces the actual count.
    public let questionCount: Int
    /// An optional title hint (e.g. the imported file's name) used to seed the
    /// quiz title; the model may refine it.
    public let title: String?

    public init(
        sourceText: String,
        questionCount: Int = 10,
        title: String? = nil
    ) {
        self.sourceText = sourceText
        self.questionCount = questionCount
        self.title = title
    }
}

// MARK: - Service boundary

/// What can go wrong generating a quiz. Surfaced to the UI as a friendly message;
/// `notConfigured` is never thrown for "feature disabled" (the caller hides the
/// CTA then). Mirrors `ExplanationError`.
public enum QuizGenerationError: Error, Sendable, Equatable {
    /// No API key configured (or the feature is off). The UI should hide the CTA.
    case notConfigured
    /// The source material was empty or too short to generate from.
    case emptySource
    /// A transport-level failure (offline, timeout).
    case network
    /// The response wasn't the structured shape we asked for.
    case decoding
    /// The API returned an error payload; the string is a human-readable reason.
    case api(String)
}

/// The abstraction features depend on. `Sendable` + `async throws`, mirroring the
/// repository and explanation protocols. Returns Markdown in the app's quiz format
/// (front matter + `## question` blocks) so it slots into the import pipeline.
/// Concrete implementations: `InMemoryQuizGenerationService` (here, for
/// previews/tests) and `ClaudeQuizGenerationService` (in `AIExplanation`).
public protocol QuizGenerationService: Sendable {
    func generate(_ request: QuizGenerationRequest) async throws -> String
}

/// A dependency-free `QuizGenerationService` returning a fixed Markdown quiz. Used
/// by SwiftUI previews and tests so the feature layer is exercisable without
/// network access.
public actor InMemoryQuizGenerationService: QuizGenerationService {
    private let canned: String

    public init(canned: String = InMemoryQuizGenerationService.sample) {
        self.canned = canned
    }

    public func generate(_ request: QuizGenerationRequest) async throws -> String {
        let trimmed = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw QuizGenerationError.emptySource }
        return canned
    }

    /// A minimal, valid two-question quiz in the app's Markdown format.
    public static let sample = """
    ---
    title: Generated Quiz
    ---

    ## Which statement best describes the source material?
    <!-- type: single -->

    - [x] It is sample study content
    - [ ] It is a billing invoice
    - [ ] It is a legal contract

    > **Explanation:** This is canned preview output from InMemoryQuizGenerationService.

    ## The generated quiz uses the app's Markdown format. (True or False)
    <!-- type: truefalse -->

    - [x] True
    - [ ] False
    """
}

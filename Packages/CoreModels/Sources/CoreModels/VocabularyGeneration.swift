//
//  VocabularyGeneration.swift
//  CoreModels
//
//  The AI vocabulary-structuring boundary: value types for asking an external
//  model to turn messy bilingual text into a clean vocabulary set, and the
//  `VocabularyGenerationService` protocol the feature layer talks to. The sibling
//  of `QuizGeneration.swift` — the model only *structures* the pairs; the app then
//  builds quizzes and flashcards from them deterministically and offline. Like the
//  quiz generator, the service returns Markdown in the app's own vocab format, so
//  generated output flows straight into the existing parse → review → save import
//  pipeline. Opt-in cloud call using the user's key; a concrete Claude-backed actor
//  lives in `AIExplanation` and is injected at the AppFeature composition root.
//

import Foundation

// MARK: - Request

/// Everything the model needs to extract a vocabulary set from raw material. A
/// pure value type so it crosses the actor boundary freely.
public struct VocabularyGenerationRequest: Sendable, Equatable, Codable, Hashable {
    /// The source material: a pasted word list, notes, or the text of a file.
    public let sourceText: String
    /// The language being learned (the `term` side).
    public let foreignLanguage: Language
    /// The learner's own language (the `translation` side).
    public let nativeLanguage: Language
    /// Upper bound on how many pairs to return; the model may return fewer.
    public let maxEntries: Int
    /// An optional title hint (e.g. the file's name); the model may refine it.
    public let title: String?

    public init(
        sourceText: String,
        foreignLanguage: Language,
        nativeLanguage: Language,
        maxEntries: Int = 50,
        title: String? = nil
    ) {
        self.sourceText = sourceText
        self.foreignLanguage = foreignLanguage
        self.nativeLanguage = nativeLanguage
        self.maxEntries = maxEntries
        self.title = title
    }
}

// MARK: - Service boundary

/// What can go wrong structuring a vocabulary set. Surfaced to the UI as a
/// friendly message; `notConfigured` means the feature is off / no key, and the
/// caller hides the CTA. Mirrors `QuizGenerationError`.
public enum VocabularyGenerationError: Error, Sendable, Equatable {
    case notConfigured
    case emptySource
    case network
    case decoding
    case api(String)
}

/// The abstraction features depend on. `Sendable` + `async throws`, mirroring the
/// repository and quiz-generation protocols. Returns Markdown in the app's
/// vocabulary format (front matter + a table) so it slots into the import
/// pipeline. Concrete implementations: `InMemoryVocabularyGenerationService`
/// (here, for previews/tests) and `ClaudeVocabularyService` (in `AIExplanation`).
public protocol VocabularyGenerationService: Sendable {
    func generate(_ request: VocabularyGenerationRequest) async throws -> String
}

/// A dependency-free `VocabularyGenerationService` returning a fixed Markdown
/// vocab set. Used by SwiftUI previews and tests so the feature layer is
/// exercisable without network access.
public actor InMemoryVocabularyGenerationService: VocabularyGenerationService {
    private let canned: String

    public init(canned: String = InMemoryVocabularyGenerationService.sample) {
        self.canned = canned
    }

    public func generate(_ request: VocabularyGenerationRequest) async throws -> String {
        let trimmed = request.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VocabularyGenerationError.emptySource }
        return canned
    }

    /// A minimal, valid vocab set in the app's Markdown format.
    public static let sample = """
    ---
    kind: vocabulary
    title: Generated Vocabulary
    foreign: Croatian (hr)
    native: English (en)
    ---

    | Term | Translation | Pronunciation | Transcription | Example |
    |------|-------------|---------------|---------------|---------|
    | dobar dan | good day | DOH-bar dahn | добар дан | Dobar dan, kako ste? |
    | hvala | thank you | HVAH-lah | хвала | Hvala lijepa! |
    | molim | please | MOH-leem | молим |  |
    """
}

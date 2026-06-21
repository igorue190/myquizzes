//
//  Vocabulary.swift
//  CoreModels
//
//  The vocabulary-learning domain: pure value types for a set of bilingual
//  word/phrase pairs. A `VocabularySet` is the single source of truth for the
//  foreign-words feature — both the flashcard deck and the translation quizzes
//  are *derived* from it (the quiz by `VocabularyQuizBuilder` in VocabularyKit,
//  the cards by stepping `CardReviewState`). Like the rest of CoreModels these
//  are transient, Foundation-only value types with deterministic zero-based ids;
//  a set persists as a Markdown vocab file via MarkdownParser, so it rides the
//  existing import/Library/Backup machinery rather than a new content store.
//

import Foundation

// MARK: - Language

/// A language tag for one side of a vocabulary set. `code` is a short BCP-47-ish
/// identifier ("hr", "ru", "en"); `displayName` is what the UI shows. Renders to
/// and parses from the `"Croatian (hr)"` form used in the vocab file's front
/// matter, so the renderer and parser share one representation.
public struct Language: Sendable, Equatable, Codable, Hashable {
    public let code: String
    public let displayName: String

    public init(code: String, displayName: String) {
        self.code = code
        self.displayName = displayName
    }

    /// The front-matter / display label, e.g. `"Croatian (hr)"`. Falls back to
    /// just the name when there's no code.
    public var label: String {
        code.isEmpty ? displayName : "\(displayName) (\(code))"
    }

    /// Parse a `"Display Name (code)"` label back into a `Language`. A bare name
    /// with no parenthetical becomes the display name with an empty code.
    public init(label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard let open = trimmed.lastIndex(of: "("),
              let close = trimmed.lastIndex(of: ")"),
              open < close else {
            self.init(code: "", displayName: trimmed)
            return
        }
        let name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
        let code = String(trimmed[trimmed.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        self.init(code: code, displayName: name.isEmpty ? trimmed : name)
    }

    // A few common languages offered as defaults in the generation form.
    public static let english = Language(code: "en", displayName: "English")
    public static let russian = Language(code: "ru", displayName: "Russian")
    public static let croatian = Language(code: "hr", displayName: "Croatian")
    public static let spanish = Language(code: "es", displayName: "Spanish")
    public static let german = Language(code: "de", displayName: "German")
    public static let french = Language(code: "fr", displayName: "French")

    /// The set offered in the language pickers; the user can still type their own.
    public static let common: [Language] = [
        .english, .russian, .croatian, .spanish, .german, .french
    ]
}

// MARK: - Direction

/// Which way a derived card/question is posed. Both directions are mixed so the
/// learner practises recognition *and* recall from the same set.
public enum QuizDirection: String, Sendable, Codable, CaseIterable, Hashable {
    /// Show the foreign term, answer with the native meaning (recognition).
    case foreignToNative
    /// Show the native meaning, answer with the foreign term (recall).
    case nativeToForeign
}

// MARK: - Entry

/// One bilingual pair. `id` is its zero-based index within the set, so derived
/// quizzes and per-card review state key off it deterministically.
public struct VocabularyEntry: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: Int
    /// The word/phrase in the language being learned.
    public let term: String
    /// Its meaning in the learner's own language.
    public let translation: String
    /// Optional pronunciation hint, typically Latin/IPA-style (e.g. "DOH-bar dahn").
    public let phonetic: String?
    /// Optional transcription of the foreign term written in the *native*
    /// language's script (e.g. Croatian "hvala" → Russian "хвала"), so a learner
    /// can read the pronunciation in an alphabet they already know. Distinct from
    /// `phonetic`, which is a Latin/IPA hint.
    public let transcription: String?
    /// Optional usage example in the foreign language.
    public let example: String?
    public let tags: [String]

    public init(
        id: Int,
        term: String,
        translation: String,
        phonetic: String? = nil,
        transcription: String? = nil,
        example: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.term = term
        self.translation = translation
        self.phonetic = phonetic
        self.transcription = transcription
        self.example = example
        self.tags = tags
    }

    /// The prompt text for a given direction.
    public func prompt(for direction: QuizDirection) -> String {
        direction == .foreignToNative ? term : translation
    }

    /// The expected answer text for a given direction.
    public func answer(for direction: QuizDirection) -> String {
        direction == .foreignToNative ? translation : term
    }
}

// MARK: - Set

/// A complete vocabulary set: a titled list of pairs plus the two languages.
/// The source of truth for the feature; flashcards and quizzes derive from it.
public struct VocabularySet: Sendable, Equatable, Codable, Hashable {
    public var title: String
    /// The language being learned (shown as the card "front" in foreign→native).
    public var foreignLanguage: Language
    /// The learner's own language.
    public var nativeLanguage: Language
    public var entries: [VocabularyEntry]

    public init(
        title: String,
        foreignLanguage: Language,
        nativeLanguage: Language,
        entries: [VocabularyEntry] = []
    ) {
        self.title = title
        self.foreignLanguage = foreignLanguage
        self.nativeLanguage = nativeLanguage
        self.entries = entries
    }

    /// Entries with both sides filled in — the only ones that can be studied or
    /// turned into a question. Mirrors `ParsedQuiz.usableQuestions`.
    public var usableEntries: [VocabularyEntry] {
        entries.filter {
            !$0.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

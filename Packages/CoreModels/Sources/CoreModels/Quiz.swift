//
//  Quiz.swift
//  CoreModels
//
//  The canonical quiz domain — value types derived from a parsed Markdown file.
//  These are transient/value types (not persisted records): the MarkdownParser
//  produces them and the QuizEngine consumes them. No UI, no IO, no framework
//  dependency beyond Foundation — so the product's correctness-critical core
//  compiles and tests on any platform.
//

import Foundation

// MARK: - Difficulty

/// Self-reported difficulty, from front matter or a per-question tag.
public enum Difficulty: String, Sendable, Codable, CaseIterable, Hashable {
    case beginner, intermediate, advanced
}

// MARK: - Question type

/// How a question is answered. Mirrors the `<!-- type: ... -->` hint in the
/// Markdown format. `trueFalse` serializes as `truefalse` to match the spec.
public enum QuestionType: String, Sendable, Codable, CaseIterable, Hashable {
    case single
    case multiple
    case trueFalse = "truefalse"
}

// MARK: - Choice

/// A single answer option. `id` is its zero-based index within its question, so
/// parsed output is fully deterministic and `Identifiable` for SwiftUI lists.
public struct Choice: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: Int
    public let text: String
    public let isCorrect: Bool

    public init(id: Int, text: String, isCorrect: Bool) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
    }
}

// MARK: - Question

/// A fully parsed question. `id` is its zero-based index within the quiz.
public struct Question: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: Int
    public let prompt: String
    public let type: QuestionType
    public let choices: [Choice]
    public let explanation: String?
    public let reference: String?
    public let tags: [String]
    public let difficulty: Difficulty?

    public init(
        id: Int,
        prompt: String,
        type: QuestionType,
        choices: [Choice],
        explanation: String? = nil,
        reference: String? = nil,
        tags: [String] = [],
        difficulty: Difficulty? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.type = type
        self.choices = choices
        self.explanation = explanation
        self.reference = reference
        self.tags = tags
        self.difficulty = difficulty
    }

    /// The set of choice ids the author marked correct.
    public var correctChoiceIDs: Set<Int> {
        Set(choices.filter(\.isCorrect).map(\.id))
    }

    /// True when more than one answer is correct (drives the square indicator).
    public var isMultipleAnswer: Bool { type == .multiple }
}

// MARK: - Metadata

/// File-level metadata from optional YAML front matter. Values not present in
/// the file fall back to these defaults.
public struct QuizMetadata: Sendable, Equatable, Codable, Hashable {
    public var title: String?
    public var category: String?
    public var topic: String?
    public var difficulty: Difficulty?
    public var passThreshold: Int
    public var shuffleQuestions: Bool
    public var shuffleAnswers: Bool

    public init(
        title: String? = nil,
        category: String? = nil,
        topic: String? = nil,
        difficulty: Difficulty? = nil,
        passThreshold: Int = 70,
        shuffleQuestions: Bool = false,
        shuffleAnswers: Bool = false
    ) {
        self.title = title
        self.category = category
        self.topic = topic
        self.difficulty = difficulty
        self.passThreshold = passThreshold
        self.shuffleQuestions = shuffleQuestions
        self.shuffleAnswers = shuffleAnswers
    }
}

// MARK: - Parsed quiz

/// The complete output of the parser: metadata, every parsed question, and any
/// diagnostics. Invalid questions remain in `questions` so the caller can show
/// them; `usableQuestions` filters to those that can actually be scored.
public struct ParsedQuiz: Sendable, Equatable, Codable, Hashable {
    public var metadata: QuizMetadata
    public var questions: [Question]
    public var diagnostics: [Diagnostic]

    public init(
        metadata: QuizMetadata = QuizMetadata(),
        questions: [Question] = [],
        diagnostics: [Diagnostic] = []
    ) {
        self.metadata = metadata
        self.questions = questions
        self.diagnostics = diagnostics
    }

    /// Questions that have at least one choice and exactly the right shape to be
    /// scored (≥1 correct answer, ≥2 choices). Error-level diagnostics flag the
    /// rest; warnings do not disqualify a question.
    public var usableQuestions: [Question] {
        let brokenIndices = Set(
            diagnostics
                .filter { $0.severity == .error }
                .compactMap(\.questionIndex)
        )
        return questions.filter { !brokenIndices.contains($0.id) }
    }

    public var hasErrors: Bool {
        diagnostics.contains { $0.severity == .error }
    }
}

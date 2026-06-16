//
//  Diagnostics.swift
//  CoreModels
//
//  Structured parser diagnostics. The parser never throws on bad content — it
//  emits diagnostics and keeps going, so one malformed question can't take down
//  a whole file. The UI surfaces these (see DiagnosticBanner in DesignSystem).
//

import Foundation

/// A single structured parser finding, optionally tied to a question index.
public struct Diagnostic: Sendable, Equatable, Codable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Codable, Hashable, Comparable {
        case info, warning, error

        private var rank: Int {
            switch self {
            case .info: 0
            case .warning: 1
            case .error: 2
            }
        }
        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    /// The category of finding. Severity is derived from the kind so callers
    /// can't accidentally mismatch them.
    public enum Kind: String, Sendable, Codable, Hashable {
        case noCorrectAnswer       // error: nothing marked [x]
        case allAnswersCorrect     // warning: every option is [x]
        case duplicateAnswers      // warning: two identical answer texts
        case tooFewChoices         // error: fewer than two options
        case emptyPrompt           // error: heading had no text
        case malformedTypeHint     // warning: unrecognized type comment
        case typeCountMismatch     // warning: declared type disagrees with [x] count

        public var severity: Severity {
            switch self {
            case .noCorrectAnswer, .tooFewChoices, .emptyPrompt:
                .error
            case .allAnswersCorrect, .duplicateAnswers, .malformedTypeHint, .typeCountMismatch:
                .warning
            }
        }
    }

    public let id: Int
    public let kind: Kind
    public let message: String
    /// Index of the offending question (`Question.id`), or nil for file-level.
    public let questionIndex: Int?

    public var severity: Severity { kind.severity }

    public init(id: Int, kind: Kind, message: String, questionIndex: Int? = nil) {
        self.id = id
        self.kind = kind
        self.message = message
        self.questionIndex = questionIndex
    }
}

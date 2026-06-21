//
//  MarkdownQuizParser.swift
//  MarkdownParser
//
//  The contract between the user's Markdown and the app's domain model (§5).
//  A single linear pass over the AST builds questions; a validation pass emits
//  structured diagnostics. The parser NEVER throws on bad content — every
//  problem becomes a Diagnostic so one malformed question can't break a file.
//

import CoreModels
import Foundation
import Markdown

public struct MarkdownQuizParser: Sendable {

    /// Heading levels that start a new question. The spec uses `##`/`###`.
    public let questionHeadingLevels: Set<Int>

    public init(questionHeadingLevels: Set<Int> = [2, 3]) {
        self.questionHeadingLevels = questionHeadingLevels
    }

    public func parse(_ source: String) -> ParsedQuiz {
        let (frontMatter, body) = FrontMatter.split(source)
        let metadata = FrontMatter.parse(frontMatter)
        let document = Document(parsing: body)

        let builders = collectBuilders(from: document)
        var diagnostics = DiagnosticCollector()
        let questions = builders.enumerated().map { index, builder in
            buildQuestion(builder, index: index, defaultDifficulty: metadata.difficulty, into: &diagnostics)
        }

        return ParsedQuiz(metadata: metadata, questions: questions, diagnostics: diagnostics.all)
    }

    // MARK: - AST → builders

    private func collectBuilders(from document: Document) -> [QuestionBuilder] {
        var builders: [QuestionBuilder] = []
        var current: QuestionBuilder?

        func flush() {
            if let current { builders.append(current) }
            current = nil
        }

        for block in document.children {
            switch block {
            case let heading as Heading where questionHeadingLevels.contains(heading.level):
                flush()
                current = QuestionBuilder(prompt: heading.inlineMarkdown)

            case let html as HTMLBlock where current != nil:
                let directive = CommentDirective.parse(html.rawHTML)
                if let type = directive.type { current?.typeHintRaw = type }
                if let tags = directive.tags { current?.tags = tags }

            case let list as UnorderedList where current != nil:
                let checkboxItems = list.children.compactMap { $0 as? ListItem }.filter { $0.checkbox != nil }
                if checkboxItems.isEmpty {
                    // A plain bullet list in the question body, not the answers.
                    current?.bodyBlocks.append(list.format())
                } else {
                    for item in checkboxItems {
                        current?.choices.append((text: item.answerText, isCorrect: item.isChecked))
                    }
                }

            case let quote as BlockQuote where current != nil:
                let (explanation, reference) = quote.explanationAndReference
                current?.explanation = explanation
                current?.reference = reference

            default:
                // Any other block inside a question (code block, table, paragraph,
                // image, numbered list, math) is rich body content under the prompt.
                if current != nil { current?.bodyBlocks.append(block.format()) }
            }
        }
        flush()
        return builders
    }

    // MARK: - Builder → validated Question

    private func buildQuestion(
        _ builder: QuestionBuilder,
        index: Int,
        defaultDifficulty: Difficulty?,
        into diagnostics: inout DiagnosticCollector
    ) -> Question {
        let choices = builder.choices.enumerated().map { offset, choice in
            Choice(id: offset, text: choice.text, isCorrect: choice.isCorrect)
        }
        let correctCount = choices.filter(\.isCorrect).count
        let label = "Question \(index + 1)"

        // --- Type resolution ---
        let resolvedType: QuestionType
        if let raw = builder.typeHintRaw {
            if let hinted = QuestionType(rawValue: raw.lowercased()) {
                resolvedType = hinted
            } else {
                resolvedType = Self.inferType(choices)
                diagnostics.add(.malformedTypeHint,
                                "\(label): unknown type hint “\(raw)”. Inferred \(resolvedType.rawValue).",
                                index)
            }
        } else {
            resolvedType = Self.inferType(choices)
        }

        let question = Question(
            id: index,
            prompt: builder.prompt,
            body: builder.body,
            type: resolvedType,
            choices: choices,
            explanation: builder.explanation,
            reference: builder.reference,
            tags: builder.tags,
            difficulty: defaultDifficulty
        )

        // --- Validation (order: errors that disqualify, then warnings) ---
        if builder.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.add(.emptyPrompt, "\(label) has an empty prompt.", index)
        }
        if choices.count < 2 {
            diagnostics.add(.tooFewChoices, "\(label) has fewer than two answers.", index)
        }
        if correctCount == 0 {
            diagnostics.add(.noCorrectAnswer, "\(label) has no correct answer marked.", index)
        } else if choices.count >= 2 && correctCount == choices.count {
            diagnostics.add(.allAnswersCorrect, "\(label) marks every answer correct.", index)
        }

        let normalized = choices.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if Set(normalized).count != normalized.count {
            diagnostics.add(.duplicateAnswers, "\(label) has duplicate answers.", index)
        }

        // Declared type vs. actual correct count (only when an explicit, valid hint exists).
        if let raw = builder.typeHintRaw, let hinted = QuestionType(rawValue: raw.lowercased()) {
            if hinted == .single, correctCount > 1 {
                diagnostics.add(.typeCountMismatch,
                                "\(label) is marked single but has \(correctCount) correct answers.", index)
            }
            if hinted == .multiple, correctCount == 1 {
                diagnostics.add(.typeCountMismatch,
                                "\(label) is marked multiple but has only one correct answer.", index)
            }
        }

        return question
    }

    /// Infer type when no (valid) hint is present: True/False pair → trueFalse,
    /// ≥2 correct → multiple, otherwise single (§5.3).
    static func inferType(_ choices: [Choice]) -> QuestionType {
        let texts = Set(choices.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        if choices.count == 2, texts == ["true", "false"] {
            return .trueFalse
        }
        return choices.filter(\.isCorrect).count >= 2 ? .multiple : .single
    }
}

// MARK: - Internal scaffolding

/// Mutable accumulator for one question while walking the AST.
private struct QuestionBuilder {
    var prompt: String
    var typeHintRaw: String?
    var tags: [String] = []
    var choices: [(text: String, isCorrect: Bool)] = []
    var explanation: String?
    var reference: String?
    /// Rich Markdown blocks between the prompt heading and the answers.
    var bodyBlocks: [String] = []

    init(prompt: String) { self.prompt = prompt }

    /// The captured body as one Markdown string, or nil if there was none.
    var body: String? {
        let joined = bodyBlocks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }
}

/// Auto-incrementing diagnostic ids so they're stable and Identifiable.
private struct DiagnosticCollector {
    private(set) var all: [Diagnostic] = []
    private var nextID = 0

    mutating func add(_ kind: Diagnostic.Kind, _ message: String, _ questionIndex: Int?) {
        all.append(Diagnostic(id: nextID, kind: kind, message: message, questionIndex: questionIndex))
        nextID += 1
    }
}

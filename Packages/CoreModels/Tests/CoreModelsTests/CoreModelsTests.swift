//
//  CoreModelsTests.swift
//  CoreModelsTests
//

import Testing
import Foundation
@testable import CoreModels

@Suite("CoreModels value types")
struct CoreModelsTests {

    @Test("QuestionType round-trips the truefalse raw value from the format spec")
    func questionTypeRawValues() {
        #expect(QuestionType.trueFalse.rawValue == "truefalse")
        #expect(QuestionType(rawValue: "single") == .single)
        #expect(QuestionType(rawValue: "multiple") == .multiple)
        #expect(QuestionType(rawValue: "truefalse") == .trueFalse)
        #expect(QuestionType(rawValue: "nonsense") == nil)
    }

    @Test("Question exposes its correct choice ids")
    func correctChoiceIDs() {
        let q = Question(
            id: 0,
            prompt: "Pick the right ones",
            type: .multiple,
            choices: [
                Choice(id: 0, text: "A", isCorrect: true),
                Choice(id: 1, text: "B", isCorrect: false),
                Choice(id: 2, text: "C", isCorrect: true)
            ]
        )
        #expect(q.correctChoiceIDs == [0, 2])
        #expect(q.isMultipleAnswer)
    }

    @Test("Diagnostic severity is derived from its kind")
    func diagnosticSeverity() {
        #expect(Diagnostic.Kind.noCorrectAnswer.severity == .error)
        #expect(Diagnostic.Kind.emptyPrompt.severity == .error)
        #expect(Diagnostic.Kind.tooFewChoices.severity == .error)
        #expect(Diagnostic.Kind.allAnswersCorrect.severity == .warning)
        #expect(Diagnostic.Kind.duplicateAnswers.severity == .warning)
        #expect(Diagnostic.Severity.error > .warning)
        #expect(Diagnostic.Severity.warning > .info)
    }

    @Test("usableQuestions drops only those with error-level diagnostics")
    func usableQuestionsFilter() {
        let quiz = ParsedQuiz(
            questions: [
                Question(id: 0, prompt: "ok", type: .single,
                         choices: [Choice(id: 0, text: "a", isCorrect: true),
                                   Choice(id: 1, text: "b", isCorrect: false)]),
                Question(id: 1, prompt: "broken", type: .single, choices: [])
            ],
            diagnostics: [
                // A warning on q0 must NOT disqualify it.
                Diagnostic(id: 0, kind: .duplicateAnswers, message: "dup", questionIndex: 0),
                // An error on q1 must disqualify it.
                Diagnostic(id: 1, kind: .tooFewChoices, message: "few", questionIndex: 1)
            ]
        )
        #expect(quiz.usableQuestions.map(\.id) == [0])
        #expect(quiz.hasErrors)
    }

    @Test("SessionResult scores percentage and pass/fail against the threshold")
    func sessionResultScoring() {
        let attempts = (0..<10).map { i in
            QuestionAttempt(questionID: i, selectedChoiceIDs: [0],
                            correctChoiceIDs: [0], isCorrect: i < 7)
        }
        let result = SessionResult(mode: .exam, attempts: attempts, passThreshold: 70)
        #expect(result.correctCount == 7)
        #expect(result.percentage == 70)
        #expect(result.passed)            // exactly at threshold passes

        let failing = SessionResult(
            mode: .exam,
            attempts: Array(attempts.prefix(6)) + attempts.suffix(4).map {
                QuestionAttempt(questionID: $0.questionID, selectedChoiceIDs: [],
                                correctChoiceIDs: [0], isCorrect: false)
            },
            passThreshold: 70
        )
        #expect(failing.correctCount == 6)
        #expect(failing.percentage == 60)
        #expect(!failing.passed)
    }

    @Test("SeededGenerator is deterministic and seed-dependent")
    func seededGeneratorDeterminism() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        var c = SeededGenerator(seed: 43)
        let seqA = (0..<5).map { _ in a.next() }
        let seqB = (0..<5).map { _ in b.next() }
        let seqC = (0..<5).map { _ in c.next() }
        #expect(seqA == seqB)        // same seed → same stream
        #expect(seqA != seqC)        // different seed → different stream
    }

    @Test("Domain types are Codable round-trip safe")
    func codableRoundTrip() throws {
        let quiz = ParsedQuiz(
            metadata: QuizMetadata(title: "AZ-900", passThreshold: 80, shuffleQuestions: true),
            questions: [
                Question(id: 0, prompt: "p", type: .trueFalse,
                         choices: [Choice(id: 0, text: "True", isCorrect: false),
                                   Choice(id: 1, text: "False", isCorrect: true)],
                         explanation: "because", tags: ["networking"])
            ]
        )
        let data = try JSONEncoder().encode(quiz)
        let decoded = try JSONDecoder().decode(ParsedQuiz.self, from: data)
        #expect(decoded == quiz)
    }
}

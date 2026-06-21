//
//  VocabularyQuizBuilderTests.swift
//  VocabularyKitTests
//

import Testing
import CoreModels
@testable import VocabularyKit

// MARK: - Fixtures

private func entry(_ id: Int, _ term: String, _ translation: String) -> VocabularyEntry {
    VocabularyEntry(id: id, term: term, translation: translation)
}

private func set(_ pairs: [(String, String)], title: String = "Set") -> VocabularySet {
    VocabularySet(
        title: title,
        foreignLanguage: .croatian,
        nativeLanguage: .english,
        entries: pairs.enumerated().map { entry($0.offset, $0.element.0, $0.element.1) }
    )
}

private let sample = set([
    ("dobar dan", "good day"),
    ("hvala", "thank you"),
    ("molim", "please"),
    ("da", "yes"),
    ("ne", "no")
])

// MARK: - Determinism

@Suite("VocabularyQuizBuilder")
struct VocabularyQuizBuilderTests {

    @Test("Same seed yields an identical quiz")
    func deterministic() {
        let builder = VocabularyQuizBuilder()
        let a = builder.makeQuiz(from: sample, seed: 42)
        let b = builder.makeQuiz(from: sample, seed: 42)
        #expect(a == b)
    }

    @Test("Different seeds change the quiz")
    func seedMatters() {
        let builder = VocabularyQuizBuilder()
        let a = builder.makeQuiz(from: sample, seed: 1)
        let b = builder.makeQuiz(from: sample, seed: 2)
        #expect(a != b)
    }

    @Test("One usable question per entry, all scoreable")
    func oneQuestionPerEntry() {
        let quiz = VocabularyQuizBuilder().makeQuiz(from: sample, seed: 7)
        #expect(quiz.questions.count == sample.usableEntries.count)
        #expect(quiz.usableQuestions.count == quiz.questions.count)
        for question in quiz.questions {
            #expect(question.type == .single)
            #expect(question.correctChoiceIDs.count == 1)
            #expect(question.choices.count >= 2)
        }
    }

    @Test("Choice count is capped by the builder and the available pool")
    func choiceCount() {
        let quiz = VocabularyQuizBuilder(choiceCount: 4).makeQuiz(from: sample, seed: 7)
        for question in quiz.questions {
            #expect(question.choices.count <= 4)
        }
        // A two-entry set can only ever offer 2 choices.
        let tiny = set([("a", "x"), ("b", "y")])
        let tinyQuiz = VocabularyQuizBuilder(choiceCount: 4).makeQuiz(from: tiny, seed: 7)
        for question in tinyQuiz.questions {
            #expect(question.choices.count == 2)
        }
    }

    @Test("Both directions appear across the set")
    func mixedDirections() {
        let quiz = VocabularyQuizBuilder().makeQuiz(from: sample, seed: 3)
        let foreignTerms = Set(sample.entries.map(\.term))
        // Some prompts are foreign words (foreign→native) and some are not.
        let prompts = quiz.questions.map { $0.prompt.replacingOccurrences(of: "Translate: ", with: "") }
        let askedForeign = prompts.contains { foreignTerms.contains($0) }
        let askedNative = prompts.contains { !foreignTerms.contains($0) }
        #expect(askedForeign && askedNative)
    }

    @Test("A set with fewer than two entries yields no questions")
    func tooSmall() {
        let quiz = VocabularyQuizBuilder().makeQuiz(from: set([("a", "x")]), seed: 1)
        #expect(quiz.questions.isEmpty)
    }

    @Test("The correct answer is the entry's true translation")
    func correctAnswerMatches() {
        let quiz = VocabularyQuizBuilder(directions: [.foreignToNative]).makeQuiz(from: sample, seed: 9)
        for question in quiz.questions {
            let word = question.prompt.replacingOccurrences(of: "Translate: ", with: "")
            let entry = sample.entries.first { $0.term == word }
            let correct = question.choices.first { $0.isCorrect }
            #expect(correct?.text == entry?.translation)
        }
    }
}

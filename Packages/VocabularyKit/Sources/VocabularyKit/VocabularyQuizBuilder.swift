//
//  VocabularyQuizBuilder.swift
//  VocabularyKit
//
//  Derives a `ParsedQuiz` from a `VocabularySet` so translation quizzes flow
//  through the existing QuizEngine and quiz runner unchanged — no new quiz
//  machinery. Each usable entry becomes one `single`-type question: the prompt is
//  one side of the pair, the correct choice is the other side, and the distractors
//  are other entries' answers in the same direction. Directions are mixed across
//  the set. Everything is seeded via `SeededGenerator`, so the same seed yields
//  the same quiz — the determinism the engine tests rely on.
//

import CoreModels
import Foundation

public struct VocabularyQuizBuilder: Sendable {

    /// How many choices each question offers (1 correct + distractors), clamped to
    /// what the set can supply.
    public let choiceCount: Int
    /// Which directions to draw from. With both, each question's direction is
    /// chosen by the seeded generator.
    public let directions: [QuizDirection]

    public init(
        choiceCount: Int = 4,
        directions: [QuizDirection] = QuizDirection.allCases
    ) {
        self.choiceCount = max(2, choiceCount)
        self.directions = directions.isEmpty ? QuizDirection.allCases : directions
    }

    /// Build a quiz from the set. Returns a `ParsedQuiz` whose questions are ready
    /// for `QuizSessionViewModel.make(fromQuestions:)`. Entries that can't supply
    /// at least one distractor are skipped (a single-choice question isn't useful).
    public func makeQuiz(from set: VocabularySet, seed: UInt64) -> ParsedQuiz {
        var generator = SeededGenerator(seed: seed)
        let entries = set.usableEntries
        guard entries.count >= 2 else {
            return ParsedQuiz(metadata: metadata(for: set), questions: [])
        }

        var questions: [Question] = []
        for entry in entries {
            let direction = directions.count == 1
                ? directions[0]
                : directions[Int(generator.next() % UInt64(directions.count))]

            guard let question = makeQuestion(
                for: entry,
                in: entries,
                direction: direction,
                index: questions.count,
                using: &generator
            ) else { continue }
            questions.append(question)
        }

        return ParsedQuiz(metadata: metadata(for: set), questions: questions)
    }

    // MARK: - Question

    private func makeQuestion(
        for entry: VocabularyEntry,
        in entries: [VocabularyEntry],
        direction: QuizDirection,
        index: Int,
        using generator: inout SeededGenerator
    ) -> Question? {
        let correctAnswer = entry.answer(for: direction)
        let prompt = entry.prompt(for: direction)
        guard !correctAnswer.isEmpty, !prompt.isEmpty else { return nil }

        // Candidate distractors: other entries' answers in the same direction,
        // de-duplicated and excluding any that match the correct answer.
        var seen: Set<String> = [correctAnswer]
        var pool: [String] = []
        for other in entries where other.id != entry.id {
            let candidate = other.answer(for: direction)
            guard !candidate.isEmpty, !seen.contains(candidate) else { continue }
            seen.insert(candidate)
            pool.append(candidate)
        }
        guard !pool.isEmpty else { return nil }

        let distractors = Array(pool.shuffled(using: &generator).prefix(choiceCount - 1))
        var options = distractors + [correctAnswer]
        options.shuffle(using: &generator)

        let choices = options.enumerated().map { offset, text in
            Choice(id: offset, text: text, isCorrect: text == correctAnswer)
        }

        return Question(
            id: index,
            prompt: questionPrompt(prompt, direction: direction),
            type: .single,
            choices: choices,
            explanation: nil,
            reference: nil,
            tags: entry.tags
        )
    }

    /// A short instruction so the learner knows which way to translate.
    private func questionPrompt(_ word: String, direction: QuizDirection) -> String {
        "Translate: \(word)"
    }

    private func metadata(for set: VocabularySet) -> QuizMetadata {
        QuizMetadata(
            title: set.title,
            category: set.foreignLanguage.displayName,
            topic: "Vocabulary",
            shuffleQuestions: true,
            shuffleAnswers: false   // already shuffled deterministically here
        )
    }
}

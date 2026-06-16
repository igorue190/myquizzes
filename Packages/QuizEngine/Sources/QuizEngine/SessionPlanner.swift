//
//  SessionPlanner.swift
//  QuizEngine
//
//  Turns a candidate pool of questions + a SessionConfig into a prepared
//  QuizSession. Selection and shuffling are driven by the config's seed, so the
//  same (pool, config) always yields the same session — reproducible and
//  testable, per the plan's "pure and deterministic given a seed".
//

import CoreModels

public enum SessionPlanner {

    /// Build a session from a candidate pool. Only `usable` questions should be
    /// passed in (the parser/caller filters out error-flagged ones first).
    ///
    /// Ordering rules (matching the technical plan §8.4):
    ///   1. If `questionCount` is set and smaller than the pool, take a seeded
    ///      random subset of that size.
    ///   2. If `shuffleQuestions` is on, present them in shuffled order;
    ///      otherwise present them in their original document order.
    ///   3. If `shuffleAnswers` is on, each question's choices are reordered
    ///      (ids are preserved, so scoring is order-independent).
    public static func makeSession(
        from pool: [Question],
        config: SessionConfig
    ) -> QuizSession {
        var rng = SeededGenerator(seed: config.seed)

        // 1. Selection — seeded random subset, remembering original order.
        var working = pool
        if let count = config.questionCount, count >= 0, count < working.count {
            working.shuffle(using: &rng)
            working = Array(working.prefix(count))
        }

        // 2. Question ordering.
        if config.shuffleQuestions {
            working.shuffle(using: &rng)
        } else {
            // Restore document order (the subset shuffle above may have disturbed it).
            working.sort { $0.id < $1.id }
        }

        // 3. Answer ordering — reorder choices but keep their ids.
        if config.shuffleAnswers {
            working = working.map { question in
                var choices = question.choices
                choices.shuffle(using: &rng)
                return question.withChoices(choices)
            }
        }

        return QuizSession(config: config, questions: working)
    }
}

extension Question {
    /// A copy with a different choice ordering. Choice ids are unchanged, so
    /// this only affects presentation, never scoring.
    func withChoices(_ choices: [Choice]) -> Question {
        Question(
            id: id,
            prompt: prompt,
            type: type,
            choices: choices,
            explanation: explanation,
            reference: reference,
            tags: tags,
            difficulty: difficulty
        )
    }
}

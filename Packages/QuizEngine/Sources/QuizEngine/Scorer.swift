//
//  Scorer.swift
//  QuizEngine
//
//  Pure scoring. Single / true-false: exact match. Multiple: all correct
//  selected AND no incorrect selected (Microsoft "select all that apply"
//  semantics, §8.3). Partial credit is intentionally NOT done here — it would
//  be a pluggable strategy in a later phase.
//

import CoreModels
import Foundation  // TimeInterval

public enum Scorer {

    /// Score a finished session into a `SessionResult`.
    /// - Parameter duration: wall-clock seconds the caller measured (the engine
    ///   is timing-agnostic, so the caller supplies this).
    public static func score(_ session: QuizSession, duration: TimeInterval = 0) -> SessionResult {
        let attempts = session.questions.map { question -> QuestionAttempt in
            let selected = session.selection(for: question.id)
            let correct = question.correctChoiceIDs
            return QuestionAttempt(
                questionID: question.id,
                selectedChoiceIDs: selected,
                correctChoiceIDs: correct,
                isCorrect: isCorrect(selected: selected, correct: correct),
                prompt: question.prompt
            )
        }

        return SessionResult(
            mode: session.config.mode,
            attempts: attempts,
            passThreshold: session.config.passThreshold,
            duration: duration,
            topicBreakdown: topicBreakdown(session: session, attempts: attempts)
        )
    }

    /// All-or-nothing correctness. An empty correct set (a malformed question
    /// that slipped through) can never be "correct".
    static func isCorrect(selected: Set<Int>, correct: Set<Int>) -> Bool {
        !correct.isEmpty && selected == correct
    }

    /// Aggregate accuracy by each question's tags (the per-topic breakdown shown
    /// on the result screen, and the raw feed for the Statistics package).
    static func topicBreakdown(session: QuizSession, attempts: [QuestionAttempt]) -> [TopicScore] {
        let attemptsByID = Dictionary(uniqueKeysWithValues: attempts.map { ($0.questionID, $0) })

        var totals: [String: (correct: Int, total: Int)] = [:]
        for question in session.questions {
            guard let attempt = attemptsByID[question.id] else { continue }
            for tag in question.tags {
                var entry = totals[tag] ?? (0, 0)
                entry.total += 1
                if attempt.isCorrect { entry.correct += 1 }
                totals[tag] = entry
            }
        }

        return totals
            .map { TopicScore(topic: $0.key, correct: $0.value.correct, total: $0.value.total) }
            .sorted { $0.topic < $1.topic }
    }
}

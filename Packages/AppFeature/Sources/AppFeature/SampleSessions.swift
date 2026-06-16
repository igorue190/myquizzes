//
//  SampleSessions.swift
//  AppFeature
//
//  A few synthetic finished sessions seeded on first launch so the Stats tab
//  has a trend and topic mastery to show before the user has taken real quizzes.
//

import Foundation
import CoreModels

enum SampleSessions {
    /// Stable prompts per question index so the same higher-index questions are
    /// missed across sessions — giving the "Most missed" card something to show.
    private static let prompts = [
        "Which service model gives the most control over the OS?",
        "What does cloud elasticity mean?",
        "Define high availability vs. fault tolerance.",
        "What is a resource group?",
        "Which Azure service provides object storage?",
        "What is the shared responsibility model?",
        "Availability Zones protect against what kind of failure?",
        "What is the difference between RPO and RTO?",
        "When should you use a hub-and-spoke network topology?",
        "How does Azure Policy differ from RBAC?"
    ]

    static func make() -> [SessionRecord] {
        [
            record(daysAgo: 6, cloud: (3, 6), security: (2, 4)),
            record(daysAgo: 4, cloud: (4, 6), security: (2, 4)),
            record(daysAgo: 2, cloud: (5, 6), security: (3, 4)),
            record(daysAgo: 0, cloud: (6, 6), security: (3, 4))
        ]
    }

    private static func record(
        daysAgo: Int,
        cloud: (correct: Int, total: Int),
        security: (correct: Int, total: Int)
    ) -> SessionRecord {
        let breakdown = [
            TopicScore(topic: "Cloud Concepts", correct: cloud.correct, total: cloud.total),
            TopicScore(topic: "Security", correct: security.correct, total: security.total)
        ]
        let total = cloud.total + security.total
        let correct = cloud.correct + security.correct
        let attempts = (0..<total).map { index in
            QuestionAttempt(questionID: index, selectedChoiceIDs: [0],
                            correctChoiceIDs: [0], isCorrect: index < correct,
                            prompt: prompts[index % prompts.count])
        }
        let result = SessionResult(
            mode: .exam, attempts: attempts, passThreshold: 70, topicBreakdown: breakdown
        )
        return SessionRecord(
            finishedAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            scopeLabel: "AZ-900 Sample",
            result: result
        )
    }
}

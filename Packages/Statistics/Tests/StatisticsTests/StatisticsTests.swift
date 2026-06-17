//
//  StatisticsTests.swift
//  StatisticsTests
//

import Testing
import Foundation
import CoreModels
@testable import Statistics

@Suite("Statistics aggregation")
struct StatisticsTests {

    private func record(daysAgo: Int, topics: [(String, correct: Int, total: Int)]) -> SessionRecord {
        let breakdown = topics.map { TopicScore(topic: $0.0, correct: $0.correct, total: $0.total) }
        let totalCorrect = topics.reduce(0) { $0 + $1.correct }
        let totalCount = topics.reduce(0) { $0 + $1.total }
        let attempts = (0..<totalCount).map {
            QuestionAttempt(questionID: $0, selectedChoiceIDs: [0],
                            correctChoiceIDs: [0], isCorrect: $0 < totalCorrect)
        }
        let result = SessionResult(
            mode: .exam, attempts: attempts, passThreshold: 70, topicBreakdown: breakdown
        )
        return SessionRecord(
            finishedAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            result: result
        )
    }

    @Test("Empty history yields the empty overview")
    func empty() {
        let overview = Statistics.overview(from: [])
        #expect(overview == .empty)
        #expect(overview.overallAccuracy == 0)
    }

    // MARK: - Review scheduling

    /// A one-question session: `prompt` answered `correct` at `daysAgo`.
    private func attemptRecord(_ prompt: String, correct: Bool, daysAgo: Int) -> SessionRecord {
        let attempt = QuestionAttempt(
            questionID: 0, selectedChoiceIDs: [correct ? 0 : 1],
            correctChoiceIDs: [0], isCorrect: correct, prompt: prompt
        )
        return SessionRecord(
            finishedAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            result: SessionResult(mode: .training, attempts: [attempt], passThreshold: 70)
        )
    }

    @Test("A never-missed question is not due for review")
    func reviewSkipsCorrect() {
        let due = Statistics.dueForReview(from: [attemptRecord("Q1", correct: true, daysAgo: 1)])
        #expect(due.isEmpty)
    }

    @Test("A missed question becomes due, and graduates after two correct in a row")
    func reviewGraduation() {
        let learned = [
            attemptRecord("Q1", correct: false, daysAgo: 3),
            attemptRecord("Q1", correct: true, daysAgo: 2),
            attemptRecord("Q1", correct: true, daysAgo: 1)
        ]
        #expect(Statistics.dueForReview(from: learned).isEmpty)

        let stillWeak = [
            attemptRecord("Q1", correct: false, daysAgo: 2),
            attemptRecord("Q1", correct: true, daysAgo: 1)
        ]
        #expect(Statistics.dueForReview(from: stillWeak) == ["Q1"])
    }

    @Test("A just-missed question outranks an older miss")
    func reviewPriorityOrder() {
        let records = [
            attemptRecord("Older", correct: false, daysAgo: 5),
            attemptRecord("Older", correct: true, daysAgo: 4),
            attemptRecord("Recent", correct: false, daysAgo: 1)
        ]
        let due = Statistics.dueForReview(from: records)
        #expect(due.first == "Recent")
        #expect(Set(due) == ["Recent", "Older"])
    }

    @Test("Topic accuracy is summed across sessions, weakest first")
    func topicAggregation() {
        let records = [
            record(daysAgo: 2, topics: [("Networking", correct: 1, total: 4), ("Security", correct: 4, total: 4)]),
            record(daysAgo: 1, topics: [("Networking", correct: 2, total: 4), ("Security", correct: 3, total: 4)])
        ]
        let overview = Statistics.overview(from: records)
        #expect(overview.sessionCount == 2)

        let networking = overview.topics.first { $0.topic == "Networking" }
        let security = overview.topics.first { $0.topic == "Security" }
        #expect(networking?.correct == 3)
        #expect(networking?.total == 8)
        #expect(security?.correct == 7)
        // Weakest first: Networking (0.375) before Security (0.875).
        #expect(overview.topics.first?.topic == "Networking")
    }

    @Test("Overall accuracy spans all questions")
    func overall() {
        let records = [record(daysAgo: 0, topics: [("A", correct: 7, total: 10)])]
        let overview = Statistics.overview(from: records)
        #expect(overview.totalCorrect == 7)
        #expect(overview.totalQuestions == 10)
        #expect(overview.overallAccuracy == 0.7)
    }

    @Test("Trend is chronological")
    func trend() {
        let records = [
            record(daysAgo: 1, topics: [("A", correct: 8, total: 10)]),
            record(daysAgo: 3, topics: [("A", correct: 5, total: 10)]),
            record(daysAgo: 0, topics: [("A", correct: 9, total: 10)])
        ]
        let trend = Statistics.overview(from: records).trend
        #expect(trend.map(\.date) == trend.map(\.date).sorted())
        #expect(trend.first?.percentage == 50)   // oldest (3 days ago)
        #expect(trend.last?.percentage == 90)     // newest
    }

    @Test("Most-missed aggregates wrong answers by prompt across sessions")
    func mostMissed() {
        func rec(_ items: [(prompt: String, correct: Bool)]) -> SessionRecord {
            let attempts = items.enumerated().map { i, item in
                QuestionAttempt(questionID: i, selectedChoiceIDs: [0],
                                correctChoiceIDs: [0], isCorrect: item.correct, prompt: item.prompt)
            }
            return SessionRecord(result: SessionResult(mode: .exam, attempts: attempts, passThreshold: 70))
        }
        let records = [
            rec([("Q-hard", false), ("Q-easy", true)]),
            rec([("Q-hard", false), ("Q-easy", true)]),
            rec([("Q-hard", true), ("Q-medium", false)])
        ]
        let missed = Statistics.overview(from: records).mostMissed
        #expect(missed.first?.prompt == "Q-hard")
        #expect(missed.first?.misses == 2)
        #expect(missed.first?.attempts == 3)
        #expect(missed.contains { $0.prompt == "Q-easy" } == false)   // never missed
    }

    @Test("Mastery levels map from accuracy")
    func mastery() {
        #expect(Statistics.masteryLevel(correct: 10, total: 10) == .mastered)
        #expect(Statistics.masteryLevel(correct: 8, total: 10) == .proficient)
        #expect(Statistics.masteryLevel(correct: 6, total: 10) == .developing)
        #expect(Statistics.masteryLevel(correct: 2, total: 10) == .novice)
        #expect(Statistics.masteryLevel(correct: 0, total: 0) == .novice)
        #expect(MasteryLevel.mastered > MasteryLevel.developing)
    }
}

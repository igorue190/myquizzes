//
//  Statistics.swift
//  Statistics
//
//  Derives mastery and trends from stored session history. Pure functions over
//  `[SessionRecord]` — the same input always yields the same overview.
//

import Foundation
import CoreModels

/// A coarse mastery bucket for a topic, from accuracy (with a small-sample guard).
public enum MasteryLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case novice, developing, proficient, mastered

    private var rank: Int {
        switch self {
        case .novice: 0
        case .developing: 1
        case .proficient: 2
        case .mastered: 3
        }
    }
    public static func < (lhs: MasteryLevel, rhs: MasteryLevel) -> Bool { lhs.rank < rhs.rank }

    public var label: String { rawValue.capitalized }
}

public struct TopicMastery: Sendable, Equatable, Identifiable {
    public var id: String { topic }
    public let topic: String
    public let correct: Int
    public let total: Int

    public init(topic: String, correct: Int, total: Int) {
        self.topic = topic
        self.correct = correct
        self.total = total
    }

    public var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
    public var level: MasteryLevel { Statistics.masteryLevel(correct: correct, total: total) }
}

/// One point on the accuracy-over-time chart.
public struct TrendPoint: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let percentage: Double
    public let passed: Bool
    public let mode: SessionMode

    public init(id: UUID, date: Date, percentage: Double, passed: Bool, mode: SessionMode) {
        self.id = id
        self.date = date
        self.percentage = percentage
        self.passed = passed
        self.mode = mode
    }
}

/// A question the user gets wrong most often, identified across sessions by its
/// prompt text (a stable cross-file identity).
public struct MissedQuestion: Sendable, Equatable, Identifiable {
    public var id: String { prompt }
    public let prompt: String
    public let misses: Int
    public let attempts: Int

    public init(prompt: String, misses: Int, attempts: Int) {
        self.prompt = prompt
        self.misses = misses
        self.attempts = attempts
    }

    public var missRate: Double { attempts == 0 ? 0 : Double(misses) / Double(attempts) }
}

/// The full statistics view computed from history.
public struct StatsOverview: Sendable, Equatable {
    public let sessionCount: Int
    public let totalQuestions: Int
    public let totalCorrect: Int
    public let topics: [TopicMastery]    // weakest first
    public let trend: [TrendPoint]       // chronological
    public let mostMissed: [MissedQuestion]

    public init(
        sessionCount: Int,
        totalQuestions: Int,
        totalCorrect: Int,
        topics: [TopicMastery],
        trend: [TrendPoint],
        mostMissed: [MissedQuestion] = []
    ) {
        self.sessionCount = sessionCount
        self.totalQuestions = totalQuestions
        self.totalCorrect = totalCorrect
        self.topics = topics
        self.trend = trend
        self.mostMissed = mostMissed
    }

    public static let empty = StatsOverview(
        sessionCount: 0, totalQuestions: 0, totalCorrect: 0, topics: [], trend: [], mostMissed: []
    )

    public var overallAccuracy: Double {
        totalQuestions == 0 ? 0 : Double(totalCorrect) / Double(totalQuestions)
    }

    /// The lowest-accuracy topics with enough data to be meaningful.
    public func weakestTopics(limit: Int = 3) -> [TopicMastery] {
        topics.filter { $0.total >= 2 }.prefix(limit).map { $0 }
    }
}

public enum Statistics {

    public static func overview(from records: [SessionRecord]) -> StatsOverview {
        guard !records.isEmpty else { return .empty }

        let chronological = records.sorted { $0.finishedAt < $1.finishedAt }

        var topicTotals: [String: (correct: Int, total: Int)] = [:]
        var questionTotals: [String: (misses: Int, attempts: Int)] = [:]
        var totalCorrect = 0
        var totalQuestions = 0

        for record in chronological {
            totalCorrect += record.result.correctCount
            totalQuestions += record.result.totalQuestions
            for score in record.result.topicBreakdown {
                var entry = topicTotals[score.topic] ?? (0, 0)
                entry.correct += score.correct
                entry.total += score.total
                topicTotals[score.topic] = entry
            }
            for attempt in record.result.attempts {
                guard let prompt = attempt.prompt, !prompt.isEmpty else { continue }
                var entry = questionTotals[prompt] ?? (0, 0)
                entry.attempts += 1
                if !attempt.isCorrect { entry.misses += 1 }
                questionTotals[prompt] = entry
            }
        }

        let topics = topicTotals
            .map { TopicMastery(topic: $0.key, correct: $0.value.correct, total: $0.value.total) }
            .sorted { ($0.accuracy, $0.topic) < ($1.accuracy, $1.topic) }   // weakest first

        let trend = chronological.map {
            TrendPoint(
                id: $0.id,
                date: $0.finishedAt,
                percentage: $0.percentage,
                passed: $0.passed,
                mode: $0.mode
            )
        }

        let mostMissed = questionTotals
            .filter { $0.value.misses > 0 }
            .map { MissedQuestion(prompt: $0.key, misses: $0.value.misses, attempts: $0.value.attempts) }
            .sorted { ($0.misses, $0.missRate, $0.prompt) > ($1.misses, $1.missRate, $1.prompt) }
            .prefix(5)
            .map { $0 }

        return StatsOverview(
            sessionCount: chronological.count,
            totalQuestions: totalQuestions,
            totalCorrect: totalCorrect,
            topics: topics,
            trend: trend,
            mostMissed: mostMissed
        )
    }

    static func masteryLevel(correct: Int, total: Int) -> MasteryLevel {
        guard total > 0 else { return .novice }
        let accuracy = Double(correct) / Double(total)
        switch accuracy {
        case 0.9...:      return .mastered
        case 0.75..<0.9:  return .proficient
        case 0.5..<0.75:  return .developing
        default:          return .novice
        }
    }
}

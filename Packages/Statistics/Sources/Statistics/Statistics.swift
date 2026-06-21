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

/// Motivational, easy-to-read study-habit signals derived from session dates —
/// the kind of numbers that make the Stats page feel alive (streaks, totals,
/// recent activity) rather than abstract. Pure ⇒ deterministic given a calendar.
public struct StudyHabits: Sendable, Equatable {
    /// Consecutive days up to (and including) today with at least one session.
    /// 0 if the user hasn't studied today or yesterday.
    public let studyStreakDays: Int
    /// The longest run of consecutive study-days ever recorded.
    public let bestStreakDays: Int
    /// Total questions answered across all sessions.
    public let questionsAnswered: Int
    /// Sessions finished within the last 7 days (rolling, not calendar week).
    public let sessionsThisWeek: Int

    public init(
        studyStreakDays: Int,
        bestStreakDays: Int,
        questionsAnswered: Int,
        sessionsThisWeek: Int
    ) {
        self.studyStreakDays = studyStreakDays
        self.bestStreakDays = bestStreakDays
        self.questionsAnswered = questionsAnswered
        self.sessionsThisWeek = sessionsThisWeek
    }

    public static let empty = StudyHabits(
        studyStreakDays: 0, bestStreakDays: 0, questionsAnswered: 0, sessionsThisWeek: 0
    )
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

    /// Study-habit signals from session dates. `now`/`calendar` are injected so
    /// tests stay deterministic (per the testing rules). The streak counts back
    /// from today: if the most recent study-day is neither today nor yesterday the
    /// streak has lapsed and is 0.
    public static func habits(
        from records: [SessionRecord],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> StudyHabits {
        guard !records.isEmpty else { return .empty }

        let questionsAnswered = records.reduce(0) { $0 + $1.result.totalQuestions }

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let sessionsThisWeek = records.filter { $0.finishedAt >= weekAgo }.count

        // Distinct study-days, newest first.
        let days = Set(records.map { calendar.startOfDay(for: $0.finishedAt) })
            .sorted(by: >)

        // Best streak: longest run of consecutive calendar days, ever.
        var bestStreak = 0
        var run = 0
        var previous: Date?
        for day in days.sorted() {   // oldest first for a forward scan
            if let prev = previous,
               let next = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(next, inSameDayAs: day) {
                run += 1
            } else {
                run = 1
            }
            bestStreak = max(bestStreak, run)
            previous = day
        }

        // Current streak: walk back from today while days stay consecutive.
        let today = calendar.startOfDay(for: now)
        var currentStreak = 0
        if let mostRecent = days.first {
            let gap = calendar.dateComponents([.day], from: mostRecent, to: today).day ?? .max
            if gap <= 1 {   // studied today or yesterday → streak is live
                var cursor = mostRecent
                let daySet = Set(days)
                while daySet.contains(cursor) {
                    currentStreak += 1
                    guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
                    cursor = prev
                }
            }
        }

        return StudyHabits(
            studyStreakDays: currentStreak,
            bestStreakDays: bestStreak,
            questionsAnswered: questionsAnswered,
            sessionsThisWeek: sessionsThisWeek
        )
    }

    /// A trailing moving average of a trend's percentages, one value per point
    /// (`window` points back, clamped at the start). Smooths the noisy
    /// per-session line into a readable arc. Empty in ⇒ empty out.
    public static func rollingAverage(_ trend: [TrendPoint], window: Int = 5) -> [Double] {
        guard window > 0 else { return trend.map(\.percentage) }
        let values = trend.map(\.percentage)
        return values.indices.map { i in
            let start = max(0, i - window + 1)
            let slice = values[start...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// Prompts currently *due for review*, highest priority first — a lightweight
    /// spaced-repetition signal derived purely from history. A question is due if
    /// it has ever been missed and hasn't yet been answered correctly
    /// `masteryStreak` times in a row (after which it's considered learned and
    /// drops out). Priority favors the ones whose most-recent answer was wrong,
    /// then by total misses and miss rate. Pure ⇒ deterministic and testable.
    public static func dueForReview(from records: [SessionRecord], masteryStreak: Int = 2) -> [String] {
        let chronological = records.sorted { $0.finishedAt < $1.finishedAt }

        var history: [String: [Bool]] = [:]   // prompt → isCorrect, oldest first
        var firstSeen: [String] = []          // stable order for tie-breaks
        for record in chronological {
            for attempt in record.result.attempts {
                guard let prompt = attempt.prompt, !prompt.isEmpty else { continue }
                if history[prompt] == nil { firstSeen.append(prompt) }
                history[prompt, default: []].append(attempt.isCorrect)
            }
        }

        struct Scored { let prompt: String; let priority: Double }
        var due: [Scored] = []
        for prompt in firstSeen {
            let outcomes = history[prompt] ?? []
            let misses = outcomes.filter { !$0 }.count
            guard misses > 0 else { continue }            // never missed → not weak

            var trailingCorrect = 0
            for correct in outcomes.reversed() {
                if correct { trailingCorrect += 1 } else { break }
            }
            guard trailingCorrect < masteryStreak else { continue }   // learned → drop

            let lastWasWrong = outcomes.last == false
            let missRate = Double(misses) / Double(outcomes.count)
            let priority = (lastWasWrong ? 1000.0 : 0) + Double(misses) * 10 + missRate
            due.append(Scored(prompt: prompt, priority: priority))
        }

        return due
            .sorted { $0.priority != $1.priority ? $0.priority > $1.priority : $0.prompt < $1.prompt }
            .map(\.prompt)
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

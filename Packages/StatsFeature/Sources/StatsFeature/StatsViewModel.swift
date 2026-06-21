//
//  StatsViewModel.swift
//  StatsFeature
//
//  The one stateful object behind the Stats tab. It loads session history through
//  a SessionRepository, keeps the raw records, and derives everything the view
//  renders: a *filtered* StatsOverview (by quiz, mode, and date range), global
//  study-habit signals, and the count of questions due for review. All quiz/stat
//  logic lives in the Statistics package — the view just reads these and forwards
//  the "practice this" intents back out through injected closures.
//

import Foundation
import Observation
import CoreModels
import Statistics

/// The time window the Stats screen is scoped to. Drives the date picker.
public enum StatsDateRange: String, CaseIterable, Sendable {
    case allTime, last30, last7

    public var label: String {
        switch self {
        case .allTime: "All time"
        case .last30:  "Last 30 days"
        case .last7:   "Last 7 days"
        }
    }

    /// Whether `date` falls inside the window measured back from `now`.
    func contains(_ date: Date, now: Date = Date()) -> Bool {
        switch self {
        case .allTime: true
        case .last30:  date >= now.addingTimeInterval(-30 * 86_400)
        case .last7:   date >= now.addingTimeInterval(-7 * 86_400)
        }
    }
}

@MainActor
@Observable
public final class StatsViewModel {
    private let repository: any SessionRepository

    /// Every saved session, oldest first. The source for all derived state.
    public private(set) var records: [SessionRecord] = []

    // MARK: Derived display state (recomputed on load / filter change)

    /// Aggregates for the *current filter* — what the cards render.
    public private(set) var overview: StatsOverview = .empty
    /// Streaks/totals computed from *all* history (habits aren't scoped).
    public private(set) var habits: StudyHabits = .empty
    /// Questions currently due for spaced review across all history.
    public private(set) var dueCount: Int = 0

    // MARK: Filter state (mutate only through the intents below)

    public private(set) var selectedScope: String?      // nil ⇒ all quizzes
    public private(set) var selectedMode: SessionMode?   // nil ⇒ all modes
    public private(set) var dateRange: StatsDateRange = .allTime

    // MARK: Injected actions (set at the composition root)

    /// Launch a Training session over the spaced-review queue. nil ⇒ button hidden.
    @ObservationIgnored public var onReviewWeakAreas: (() -> Void)?
    /// Practice all questions tagged with a topic.
    @ObservationIgnored public var onPracticeTopic: ((String) -> Void)?
    /// Re-quiz a single missed question by its prompt.
    @ObservationIgnored public var onPracticeMissed: ((String) -> Void)?

    public init(repository: any SessionRepository) {
        self.repository = repository
    }

    // MARK: - Loading

    public func load() async {
        records = (try? await repository.allRecords()) ?? []
        habits = Statistics.habits(from: records)
        dueCount = Statistics.dueForReview(from: records).count
        recompute()
    }

    /// Wipe all saved sessions, then reload (the view falls back to its empty
    /// state). Shares the session store with History, so this clears both.
    public func clear() async {
        try? await repository.deleteAll()
        await load()
    }

    // MARK: - Filter intents

    public func setScope(_ scope: String?) { selectedScope = scope; recompute() }
    public func setMode(_ mode: SessionMode?) { selectedMode = mode; recompute() }
    public func setDateRange(_ range: StatsDateRange) { dateRange = range; recompute() }

    // MARK: - Picker options

    /// Distinct quiz labels present in history, alphabetical (for the scope picker).
    public var availableScopes: [String] {
        Set(records.compactMap(\.scopeLabel)).sorted()
    }

    /// Modes actually present in history, in a stable display order.
    public var availableModes: [SessionMode] {
        let present = Set(records.map(\.mode))
        return [.training, .exam].filter(present.contains)
    }

    /// True when any filter narrows the data (drives a "Clear filters" affordance).
    public var isFiltered: Bool {
        selectedScope != nil || selectedMode != nil || dateRange != .allTime
    }

    // MARK: - Implementation

    private func recompute() {
        let now = Date()
        let filtered = records.filter { record in
            (selectedScope == nil || record.scopeLabel == selectedScope)
                && (selectedMode == nil || record.mode == selectedMode)
                && dateRange.contains(record.finishedAt, now: now)
        }
        overview = Statistics.overview(from: filtered)
    }
}

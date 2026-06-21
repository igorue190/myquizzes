//
//  VocabularyReview.swift
//  CoreModels
//
//  The spaced-repetition state for flashcards and its persistence boundary. Each
//  card carries a Leitner `box` and a `dueAt` date; the pure stepping logic lives
//  in `LeitnerScheduler` (VocabularyKit). This is distinct from the quiz-history
//  `Statistics.dueForReview` signal: that one is derived from answered questions,
//  whereas a flashcard's box is an explicit per-card record the user advances by
//  tapping Known / Again. Declared here like the other repository protocols so the
//  feature layer depends only on the abstraction; the SwiftData `ModelActor` lives
//  in Persistence and the `InMemory` double below serves previews/tests.
//

import Foundation

// MARK: - Card review state

/// Per-card spaced-repetition state, keyed by its entry id within a set. A brand
/// new card has `box == 0` and is due immediately (`dueAt == .distantPast`).
public struct CardReviewState: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: Int { entryID }
    /// The `VocabularyEntry.id` this state tracks.
    public let entryID: Int
    /// The Leitner box (0 = just-learning). Higher boxes review less often.
    public var box: Int
    /// When the card next becomes due for review.
    public var dueAt: Date
    /// When the card was last reviewed, or nil if never.
    public var lastReviewed: Date?

    public init(
        entryID: Int,
        box: Int = 0,
        dueAt: Date = .distantPast,
        lastReviewed: Date? = nil
    ) {
        self.entryID = entryID
        self.box = box
        self.dueAt = dueAt
        self.lastReviewed = lastReviewed
    }

    /// True when the card is due at or before `now`.
    public func isDue(asOf now: Date = Date()) -> Bool { dueAt <= now }
}

// MARK: - Repository boundary

/// The persistence boundary for flashcard review state, scoped per vocab file.
/// `Sendable` with `async throws` methods, mirroring `SessionRepository` etc.
/// A card with no stored state is treated as new (box 0, due now).
public protocol VocabReviewRepository: Sendable {
    /// Every stored card state for a file, in no guaranteed order.
    func states(forFile fileID: UUID) async throws -> [CardReviewState]
    /// Insert or replace one card's state.
    func save(_ state: CardReviewState, forFile fileID: UUID) async throws
    /// Drop all review state for a file (call when the file is deleted).
    func clear(forFile fileID: UUID) async throws
}

/// An in-memory `VocabReviewRepository` for previews and tests.
public actor InMemoryVocabReviewRepository: VocabReviewRepository {
    /// fileID → (entryID → state).
    private var storage: [UUID: [Int: CardReviewState]]

    public init(_ seed: [UUID: [Int: CardReviewState]] = [:]) {
        self.storage = seed
    }

    public func states(forFile fileID: UUID) -> [CardReviewState] {
        Array((storage[fileID] ?? [:]).values)
    }

    public func save(_ state: CardReviewState, forFile fileID: UUID) {
        storage[fileID, default: [:]][state.entryID] = state
    }

    public func clear(forFile fileID: UUID) {
        storage[fileID] = nil
    }
}

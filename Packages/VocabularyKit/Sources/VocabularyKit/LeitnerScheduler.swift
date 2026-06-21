//
//  LeitnerScheduler.swift
//  VocabularyKit
//
//  The pure spaced-repetition stepping for flashcards. A card lives in a Leitner
//  "box"; answering Known promotes it to the next box and pushes its due date out
//  by that box's interval, while Again sends it back to box 0 (due immediately).
//  Kept pure and Foundation-only so the deck view model just applies a transition
//  and persists the result via `VocabReviewRepository`. Deterministic given the
//  same `now`, so it's straightforward to unit-test.
//

import CoreModels
import Foundation

public struct LeitnerScheduler: Sendable {

    /// Days until a card in each box is due again after a Known answer. The last
    /// interval repeats for any box at or beyond the top. Box 0 = "still learning".
    public let intervalsInDays: [Int]

    /// The box at which a card counts as "mastered" (drives the hub's progress).
    public let masteryBox: Int

    public init(
        intervalsInDays: [Int] = [0, 1, 3, 7, 16, 35],
        masteryBox: Int = 4
    ) {
        self.intervalsInDays = intervalsInDays.isEmpty ? [0] : intervalsInDays
        self.masteryBox = masteryBox
    }

    /// How the learner rated their recall on a card.
    public enum Answer: Sendable, Equatable {
        case known
        case again
    }

    /// The highest box index (cards never advance past it).
    public var topBox: Int { intervalsInDays.count - 1 }

    /// Apply an answer to a card, returning its updated state. `again` resets to
    /// box 0 due now; `known` promotes one box and schedules by that box's interval.
    public func apply(_ answer: Answer, to state: CardReviewState, now: Date = Date()) -> CardReviewState {
        var updated = state
        updated.lastReviewed = now
        switch answer {
        case .again:
            updated.box = 0
            updated.dueAt = now
        case .known:
            updated.box = min(state.box + 1, topBox)
            let days = intervalsInDays[min(updated.box, intervalsInDays.count - 1)]
            updated.dueAt = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        }
        return updated
    }

    /// Whether a card has reached the mastery box.
    public func isMastered(_ state: CardReviewState) -> Bool {
        state.box >= masteryBox
    }

    /// Order entry ids for a study session: due cards first (lowest box, then
    /// earliest due), then not-yet-due cards. Entries with no stored state are
    /// treated as new (box 0, due now) so they lead. Pure and stable.
    public func studyOrder(
        entryIDs: [Int],
        states: [CardReviewState],
        now: Date = Date()
    ) -> [Int] {
        let byID = Dictionary(states.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
        return entryIDs.sorted { lhs, rhs in
            let l = byID[lhs] ?? CardReviewState(entryID: lhs)
            let r = byID[rhs] ?? CardReviewState(entryID: rhs)
            let lDue = l.isDue(asOf: now)
            let rDue = r.isDue(asOf: now)
            if lDue != rDue { return lDue }            // due cards first
            if l.box != r.box { return l.box < r.box } // less-learned first
            if l.dueAt != r.dueAt { return l.dueAt < r.dueAt }
            return lhs < rhs                            // stable tiebreak
        }
    }
}

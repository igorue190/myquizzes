//
//  LeitnerSchedulerTests.swift
//  VocabularyKitTests
//

import Testing
import Foundation
import CoreModels
@testable import VocabularyKit

@Suite("LeitnerScheduler")
struct LeitnerSchedulerTests {

    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Known promotes a box and schedules the next due date")
    func knownPromotes() {
        let scheduler = LeitnerScheduler(intervalsInDays: [0, 1, 3, 7])
        let start = CardReviewState(entryID: 0, box: 1, dueAt: now)
        let next = scheduler.apply(.known, to: start, now: now)
        #expect(next.box == 2)
        let expected = Calendar.current.date(byAdding: .day, value: 3, to: now)
        #expect(next.dueAt == expected)
        #expect(next.lastReviewed == now)
    }

    @Test("Again resets to box 0 due immediately")
    func againResets() {
        let scheduler = LeitnerScheduler()
        let start = CardReviewState(entryID: 0, box: 4, dueAt: now)
        let next = scheduler.apply(.again, to: start, now: now)
        #expect(next.box == 0)
        #expect(next.dueAt == now)
    }

    @Test("Box never advances past the top")
    func clampsAtTop() {
        let scheduler = LeitnerScheduler(intervalsInDays: [0, 1, 3])
        var state = CardReviewState(entryID: 0, box: 2, dueAt: now)
        state = scheduler.apply(.known, to: state, now: now)
        state = scheduler.apply(.known, to: state, now: now)
        #expect(state.box == scheduler.topBox)
    }

    @Test("Mastery is reached at the mastery box")
    func mastery() {
        let scheduler = LeitnerScheduler(masteryBox: 3)
        #expect(!scheduler.isMastered(CardReviewState(entryID: 0, box: 2)))
        #expect(scheduler.isMastered(CardReviewState(entryID: 0, box: 3)))
    }

    @Test("Study order puts due cards first, least-learned ahead")
    func studyOrder() {
        let scheduler = LeitnerScheduler()
        let future = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        let states = [
            CardReviewState(entryID: 0, box: 3, dueAt: future),   // not due
            CardReviewState(entryID: 1, box: 2, dueAt: now),      // due, higher box
            CardReviewState(entryID: 2, box: 0, dueAt: now)       // due, lower box
        ]
        let order = scheduler.studyOrder(entryIDs: [0, 1, 2, 3], states: states, now: now)
        // Entry 3 has no state → new → due, box 0; ties broken by id.
        #expect(order.prefix(3).contains(0) == false) // not-due card is last
        #expect(order.last == 0)
        #expect(Set(order.prefix(3)) == [1, 2, 3])
    }

    @Test("A brand-new card (no state) is due now")
    func newCardDue() {
        let state = CardReviewState(entryID: 0)
        #expect(state.isDue(asOf: now))
        #expect(state.box == 0)
    }
}

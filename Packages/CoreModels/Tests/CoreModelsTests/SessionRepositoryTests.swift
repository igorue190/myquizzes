//
//  SessionRepositoryTests.swift
//  CoreModelsTests
//

import Testing
import Foundation
@testable import CoreModels

@Suite("SessionRepository contract (in-memory)")
struct SessionRepositoryTests {

    private func record(daysAgo: Int, correct: Int, total: Int) -> SessionRecord {
        let attempts = (0..<total).map {
            QuestionAttempt(questionID: $0, selectedChoiceIDs: [0],
                            correctChoiceIDs: [0], isCorrect: $0 < correct)
        }
        let result = SessionResult(mode: .exam, attempts: attempts, passThreshold: 70)
        return SessionRecord(
            finishedAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            scopeLabel: "Cloud Concepts",
            result: result
        )
    }

    @Test("Saved records come back oldest-first")
    func savesAndOrders() async throws {
        let repo = InMemorySessionRepository()
        try await repo.save(record(daysAgo: 1, correct: 8, total: 10))
        try await repo.save(record(daysAgo: 3, correct: 5, total: 10))
        try await repo.save(record(daysAgo: 0, correct: 9, total: 10))

        let all = try await repo.allRecords()
        #expect(all.count == 3)
        let dates = all.map(\.finishedAt)
        #expect(dates == dates.sorted())     // chronological
        #expect(all.last?.correctCount == 9) // newest last
    }

    @Test("deleteAll clears history")
    func deleteAll() async throws {
        let repo = InMemorySessionRepository()
        try await repo.save(record(daysAgo: 0, correct: 7, total: 10))
        try await repo.deleteAll()
        #expect(try await repo.allRecords().isEmpty)
    }

    @Test("SessionRecord forwards score accessors")
    func accessors() {
        let r = record(daysAgo: 0, correct: 7, total: 10)
        #expect(r.correctCount == 7)
        #expect(r.totalQuestions == 10)
        #expect(r.percentage == 70)
        #expect(r.passed)
        #expect(r.mode == .exam)
    }
}

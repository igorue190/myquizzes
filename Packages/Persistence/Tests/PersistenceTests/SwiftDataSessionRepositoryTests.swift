//
//  SwiftDataSessionRepositoryTests.swift
//  PersistenceTests
//

import Testing
import Foundation
@testable import Persistence
import CoreModels

@Suite("SwiftDataSessionRepository")
struct SwiftDataSessionRepositoryTests {

    private func record(daysAgo: Int, correct: Int, total: Int) -> SessionRecord {
        let attempts = (0..<total).map {
            QuestionAttempt(questionID: $0, selectedChoiceIDs: [0],
                            correctChoiceIDs: [0], isCorrect: $0 < correct)
        }
        let result = SessionResult(
            mode: .exam, attempts: attempts, passThreshold: 70,
            topicBreakdown: [TopicScore(topic: "Cloud", correct: correct, total: total)]
        )
        return SessionRecord(
            finishedAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            scopeLabel: "AZ-900", result: result
        )
    }

    @Test("Saves survive a round trip, ordered chronologically")
    func roundTrip() async throws {
        let repo = try PersistenceStack.makeSessionRepository(inMemory: true)
        try await repo.save(record(daysAgo: 1, correct: 8, total: 10))
        try await repo.save(record(daysAgo: 3, correct: 5, total: 10))

        let all = try await repo.allRecords()
        #expect(all.count == 2)
        #expect(all.first?.correctCount == 5)   // oldest first
        #expect(all.last?.correctCount == 8)
        #expect(all.last?.result.topicBreakdown.first?.topic == "Cloud")
        #expect(all.last?.scopeLabel == "AZ-900")
    }

    @Test("deleteAll clears history")
    func deleteAll() async throws {
        let repo = try PersistenceStack.makeSessionRepository(inMemory: true)
        try await repo.save(record(daysAgo: 0, correct: 7, total: 10))
        try await repo.deleteAll()
        #expect(try await repo.allRecords().isEmpty)
    }

    @Test("Library and session repositories can share one container")
    func sharedContainer() async throws {
        let repos = try PersistenceStack.makeAppRepositories(inMemory: true)
        let category = try await repos.library.createCategory(name: "Azure")
        #expect(try await repos.library.categories().map(\.name) == ["Azure"])
        try await repos.session.save(record(daysAgo: 0, correct: 9, total: 10))
        #expect(try await repos.session.allRecords().count == 1)
        #expect(category.name == "Azure")
    }
}

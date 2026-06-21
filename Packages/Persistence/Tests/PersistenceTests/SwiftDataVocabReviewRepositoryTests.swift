//
//  SwiftDataVocabReviewRepositoryTests.swift
//  PersistenceTests
//
//  The SwiftData vocab-review store must save, load per file, upsert by entry,
//  and clear — the same contract as CoreModels' InMemoryVocabReviewRepository.
//  Runs against an in-memory ModelContainer.
//

import Testing
import Foundation
@testable import Persistence
import CoreModels

@Suite("SwiftDataVocabReviewRepository contract")
struct SwiftDataVocabReviewRepositoryTests {

    private func makeRepo() throws -> SwiftDataVocabReviewRepository {
        SwiftDataVocabReviewRepository(modelContainer: try PersistenceStack.makeContainer(inMemory: true))
    }

    @Test("a fresh file has no states")
    func startsEmpty() async throws {
        let repo = try makeRepo()
        #expect(try await repo.states(forFile: UUID()).isEmpty)
    }

    @Test("saves and loads per file")
    func roundTrip() async throws {
        let repo = try makeRepo()
        let file = UUID()
        try await repo.save(CardReviewState(entryID: 0, box: 2), forFile: file)
        try await repo.save(CardReviewState(entryID: 1, box: 1), forFile: file)
        // A different file is isolated.
        try await repo.save(CardReviewState(entryID: 0, box: 5), forFile: UUID())

        let states = try await repo.states(forFile: file).sorted { $0.entryID < $1.entryID }
        #expect(states.map(\.entryID) == [0, 1])
        #expect(states.map(\.box) == [2, 1])
    }

    @Test("save upserts the same entry rather than duplicating")
    func upsert() async throws {
        let repo = try makeRepo()
        let file = UUID()
        try await repo.save(CardReviewState(entryID: 0, box: 1), forFile: file)
        try await repo.save(CardReviewState(entryID: 0, box: 3), forFile: file)
        let states = try await repo.states(forFile: file)
        #expect(states.count == 1)
        #expect(states.first?.box == 3)
    }

    @Test("clear drops only that file's states")
    func clear() async throws {
        let repo = try makeRepo()
        let file = UUID()
        let other = UUID()
        try await repo.save(CardReviewState(entryID: 0), forFile: file)
        try await repo.save(CardReviewState(entryID: 0), forFile: other)
        try await repo.clear(forFile: file)
        #expect(try await repo.states(forFile: file).isEmpty)
        #expect(try await repo.states(forFile: other).count == 1)
    }
}

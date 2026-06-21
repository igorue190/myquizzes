//
//  SwiftDataExplanationCacheTests.swift
//  PersistenceTests
//
//  The SwiftData explanation cache must store, return, and upsert by key — the
//  same contract as CoreModels' InMemoryExplanationCache. Runs against an
//  in-memory ModelContainer, so nothing touches the real device store.
//

import Testing
import Foundation
@testable import Persistence
import CoreModels

@Suite("SwiftDataExplanationCache contract")
struct SwiftDataExplanationCacheTests {

    private func makeCache() throws -> SwiftDataExplanationCache {
        SwiftDataExplanationCache(modelContainer: try PersistenceStack.makeContainer(inMemory: true))
    }

    @Test("a fresh cache misses")
    func startsEmpty() async throws {
        let cache = try makeCache()
        #expect(await cache.explanation(forKey: "nope") == nil)
    }

    @Test("stores and returns by key")
    func roundTrip() async throws {
        let cache = try makeCache()
        let explanation = Explanation(
            text: "Because 2+2=4.",
            sources: [Source(title: "Math", url: "https://example.com")]
        )
        await cache.store(explanation, forKey: "k1")
        #expect(await cache.explanation(forKey: "k1") == explanation)
    }

    @Test("store upserts rather than duplicating a key")
    func upsert() async throws {
        let cache = try makeCache()
        await cache.store(Explanation(text: "first"), forKey: "k1")
        await cache.store(Explanation(text: "second"), forKey: "k1")
        #expect(await cache.explanation(forKey: "k1")?.text == "second")
    }
}

//
//  ExplanationCacheTests.swift
//  CoreModelsTests
//
//  Covers the explanation cache key (content-derived, selection-independent) and
//  the in-memory cache double.
//

import Testing
import Foundation
@testable import CoreModels

private func request(
    prompt: String = "What is 2 + 2?",
    correct: Set<Int> = [1],
    selected: Set<Int> = [0]
) -> ExplanationRequest {
    ExplanationRequest(
        prompt: prompt,
        choices: [
            AttemptChoice(id: 0, text: "3", isCorrect: false),
            AttemptChoice(id: 1, text: "4", isCorrect: true)
        ],
        selectedChoiceIDs: selected,
        correctChoiceIDs: correct
    )
}

@Suite("Explanation cache key")
struct ExplanationCacheKeyTests {

    @Test("same question yields the same key")
    func stable() {
        #expect(request().cacheKey == request().cacheKey)
    }

    @Test("key ignores which answer the user selected")
    func selectionIndependent() {
        #expect(request(selected: [0]).cacheKey == request(selected: [1]).cacheKey)
    }

    @Test("different prompt or correct set yields a different key")
    func contentSensitive() {
        #expect(request().cacheKey != request(prompt: "Different?").cacheKey)
        #expect(request(correct: [1]).cacheKey != request(correct: [0]).cacheKey)
    }
}

@Suite("InMemoryExplanationCache")
struct InMemoryExplanationCacheTests {

    @Test("stores and returns by key; misses are nil")
    func roundTrip() async {
        let cache = InMemoryExplanationCache()
        let key = request().cacheKey
        #expect(await cache.explanation(forKey: key) == nil)

        let explanation = Explanation(text: "Because 2+2=4.")
        await cache.store(explanation, forKey: key)
        #expect(await cache.explanation(forKey: key) == explanation)
    }

    @Test("store replaces the prior value for a key")
    func upsert() async {
        let cache = InMemoryExplanationCache()
        let key = request().cacheKey
        await cache.store(Explanation(text: "first"), forKey: key)
        await cache.store(Explanation(text: "second"), forKey: key)
        #expect(await cache.explanation(forKey: key)?.text == "second")
    }
}

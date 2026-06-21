//
//  SwiftDataExplanationCache.swift
//  Persistence
//
//  SwiftData implementation of CoreModels.ExplanationCache. A ModelActor that
//  encodes each Explanation to JSON, keyed by the question's content hash, so a
//  generated explanation is reused instantly and offline on the next review (and
//  survives relaunches) — the local-first promise. Stores are upserts.
//

import Foundation
import SwiftData
import CoreModels

public actor SwiftDataExplanationCache: ModelActor, ExplanationCache {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    public func explanation(forKey key: String) -> Explanation? {
        var descriptor = FetchDescriptor<ExplanationCacheEntity>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        guard let entity = try? modelContext.fetch(descriptor).first else { return nil }
        return try? JSONDecoder().decode(Explanation.self, from: entity.payload)
    }

    public func store(_ explanation: Explanation, forKey key: String) {
        guard let payload = try? JSONEncoder().encode(explanation) else { return }
        var descriptor = FetchDescriptor<ExplanationCacheEntity>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.payload = payload
            existing.createdAt = Date()
        } else {
            modelContext.insert(ExplanationCacheEntity(key: key, payload: payload, createdAt: Date()))
        }
        try? modelContext.save()
    }

    public func clear() {
        guard let entities = try? modelContext.fetch(FetchDescriptor<ExplanationCacheEntity>()) else { return }
        for entity in entities { modelContext.delete(entity) }
        try? modelContext.save()
    }
}

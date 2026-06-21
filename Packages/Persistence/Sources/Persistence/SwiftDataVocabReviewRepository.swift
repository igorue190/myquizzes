//
//  SwiftDataVocabReviewRepository.swift
//  Persistence
//
//  SwiftData implementation of CoreModels.VocabReviewRepository. A ModelActor that
//  encodes each `CardReviewState` to JSON, keyed by file + entry, so a learner's
//  flashcard progress survives relaunches and works offline. Saves are upserts;
//  `clear(forFile:)` drops a file's states when it's deleted. Mirrors
//  `SwiftDataExplanationCache`.
//

import Foundation
import SwiftData
import CoreModels

public actor SwiftDataVocabReviewRepository: ModelActor, VocabReviewRepository {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    public func states(forFile fileID: UUID) -> [CardReviewState] {
        let descriptor = FetchDescriptor<VocabReviewEntity>(
            predicate: #Predicate { $0.fileID == fileID }
        )
        guard let entities = try? modelContext.fetch(descriptor) else { return [] }
        return entities.compactMap { try? JSONDecoder().decode(CardReviewState.self, from: $0.payload) }
    }

    public func save(_ state: CardReviewState, forFile fileID: UUID) {
        guard let payload = try? JSONEncoder().encode(state) else { return }
        let key = VocabReviewEntity.key(file: fileID, entry: state.entryID)
        var descriptor = FetchDescriptor<VocabReviewEntity>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.payload = payload
        } else {
            modelContext.insert(VocabReviewEntity(key: key, fileID: fileID, payload: payload))
        }
        try? modelContext.save()
    }

    public func clear(forFile fileID: UUID) {
        let descriptor = FetchDescriptor<VocabReviewEntity>(
            predicate: #Predicate { $0.fileID == fileID }
        )
        guard let entities = try? modelContext.fetch(descriptor) else { return }
        for entity in entities { modelContext.delete(entity) }
        try? modelContext.save()
    }
}

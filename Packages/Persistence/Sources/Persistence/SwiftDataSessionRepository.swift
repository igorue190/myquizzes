//
//  SwiftDataSessionRepository.swift
//  Persistence
//
//  SwiftData implementation of CoreModels.SessionRepository. A ModelActor that
//  encodes each SessionRecord to JSON for storage and decodes on read.
//

import Foundation
import SwiftData
import CoreModels

public actor SwiftDataSessionRepository: ModelActor, SessionRepository {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    public func save(_ record: SessionRecord) throws {
        let payload = try JSONEncoder().encode(record)
        modelContext.insert(
            SessionRecordEntity(id: record.id, finishedAt: record.finishedAt, payload: payload)
        )
        try modelContext.save()
    }

    public func allRecords() throws -> [SessionRecord] {
        let entities = try modelContext.fetch(
            FetchDescriptor<SessionRecordEntity>(sortBy: [SortDescriptor(\.finishedAt)])
        )
        let decoder = JSONDecoder()
        return entities.compactMap { try? decoder.decode(SessionRecord.self, from: $0.payload) }
    }

    public func deleteAll() throws {
        for entity in try modelContext.fetch(FetchDescriptor<SessionRecordEntity>()) {
            modelContext.delete(entity)
        }
        try modelContext.save()
    }
}

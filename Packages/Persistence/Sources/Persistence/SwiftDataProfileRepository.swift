//
//  SwiftDataProfileRepository.swift
//  Persistence
//
//  SwiftData implementation of CoreModels.ProfileRepository. Upserts the single
//  active profile as JSON; returns the default when none has been saved yet.
//

import Foundation
import SwiftData
import CoreModels

public actor SwiftDataProfileRepository: ModelActor, ProfileRepository {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
    }

    public func load() throws -> Profile {
        guard let entity = try active(),
              let profile = try? JSONDecoder().decode(Profile.self, from: entity.payload)
        else {
            return .default
        }
        return profile
    }

    public func save(_ profile: Profile) throws {
        let payload = try JSONEncoder().encode(profile)
        if let entity = try active() {
            entity.payload = payload
        } else {
            modelContext.insert(ProfileEntity(payload: payload))
        }
        try modelContext.save()
    }

    private func active() throws -> ProfileEntity? {
        try modelContext.fetch(FetchDescriptor<ProfileEntity>()).first
    }
}

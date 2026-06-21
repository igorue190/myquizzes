//
//  PersistenceContainer.swift
//  Persistence
//
//  The composition helpers the app root uses to stand up the persistence stack.
//  Library and session history share one ModelContainer (one store), with a
//  repository actor each.
//

import Foundation
import SwiftData
import CoreModels

public enum PersistenceStack {
    /// The SwiftData schema: the content tree + session history + profile.
    public static var schema: Schema {
        Schema([
            CategoryEntity.self, TopicEntity.self, FolderEntity.self, QuizFileEntity.self,
            SessionRecordEntity.self, ProfileEntity.self, ExplanationCacheEntity.self,
            VocabReviewEntity.self
        ])
    }

    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - From an existing container (shared store)

    public static func makeLibraryRepository(
        container: ModelContainer, fileStore: FileStore
    ) -> SwiftDataLibraryRepository {
        SwiftDataLibraryRepository(modelContainer: container, fileStore: fileStore)
    }

    public static func makeSessionRepository(
        container: ModelContainer
    ) -> SwiftDataSessionRepository {
        SwiftDataSessionRepository(modelContainer: container)
    }

    public static func makeProfileRepository(
        container: ModelContainer
    ) -> SwiftDataProfileRepository {
        SwiftDataProfileRepository(modelContainer: container)
    }

    public static func makeExplanationCache(
        container: ModelContainer
    ) -> SwiftDataExplanationCache {
        SwiftDataExplanationCache(modelContainer: container)
    }

    public static func makeVocabReviewRepository(
        container: ModelContainer
    ) -> SwiftDataVocabReviewRepository {
        SwiftDataVocabReviewRepository(modelContainer: container)
    }

    // MARK: - Convenience (standalone)

    /// Build a ready-to-use library repository. `inMemory` + a temporary
    /// `fileStore` give a fully ephemeral stack for tests and previews.
    public static func makeRepository(
        inMemory: Bool = false,
        fileStore: FileStore? = nil
    ) throws -> SwiftDataLibraryRepository {
        let container = try makeContainer(inMemory: inMemory)
        let store = fileStore ?? (inMemory ? .temporary() : FileStore(root: FileStore.defaultRoot()))
        return makeLibraryRepository(container: container, fileStore: store)
    }

    public static func makeSessionRepository(inMemory: Bool = false) throws -> SwiftDataSessionRepository {
        SwiftDataSessionRepository(modelContainer: try makeContainer(inMemory: inMemory))
    }

    // MARK: - App composition (both repositories over one shared container)

    public struct AppRepositories: Sendable {
        public let library: SwiftDataLibraryRepository
        public let session: SwiftDataSessionRepository
        public let profile: SwiftDataProfileRepository
        public let explanationCache: SwiftDataExplanationCache
        public let vocabReview: SwiftDataVocabReviewRepository
    }

    public static func makeAppRepositories(
        inMemory: Bool = false,
        fileStore: FileStore? = nil
    ) throws -> AppRepositories {
        let container = try makeContainer(inMemory: inMemory)
        let store = fileStore ?? (inMemory ? .temporary() : FileStore(root: FileStore.defaultRoot()))
        return AppRepositories(
            library: makeLibraryRepository(container: container, fileStore: store),
            session: makeSessionRepository(container: container),
            profile: makeProfileRepository(container: container),
            explanationCache: makeExplanationCache(container: container),
            vocabReview: makeVocabReviewRepository(container: container)
        )
    }
}

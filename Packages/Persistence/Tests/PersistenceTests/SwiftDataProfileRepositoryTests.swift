//
//  SwiftDataProfileRepositoryTests.swift
//  PersistenceTests
//

import Testing
@testable import Persistence
import CoreModels

@Suite("SwiftDataProfileRepository")
struct SwiftDataProfileRepositoryTests {

    @Test("Returns the default profile before anything is saved")
    func defaultsBeforeSave() async throws {
        let container = try PersistenceStack.makeContainer(inMemory: true)
        let repo = PersistenceStack.makeProfileRepository(container: container)
        #expect(try await repo.load() == .default)
    }

    @Test("Saving upserts (one row) and round-trips")
    func upsert() async throws {
        let container = try PersistenceStack.makeContainer(inMemory: true)
        let repo = PersistenceStack.makeProfileRepository(container: container)

        var profile = try await repo.load()
        profile.displayName = "Ada"
        profile.themeID = .aurora
        try await repo.save(profile)

        profile.displayName = "Grace"
        try await repo.save(profile)   // second save must update, not duplicate

        let reloaded = try await repo.load()
        #expect(reloaded.displayName == "Grace")
        #expect(reloaded.themeID == .aurora)
    }

    @Test("Profile shares the app container with library + session")
    func sharedContainer() async throws {
        let repos = try PersistenceStack.makeAppRepositories(inMemory: true)
        var profile = try await repos.profile.load()
        profile.displayName = "Linus"
        try await repos.profile.save(profile)
        #expect(try await repos.profile.load().displayName == "Linus")
    }
}

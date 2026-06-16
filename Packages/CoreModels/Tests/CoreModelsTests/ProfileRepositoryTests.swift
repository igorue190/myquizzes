//
//  ProfileRepositoryTests.swift
//  CoreModelsTests
//

import Testing
import Foundation
@testable import CoreModels

@Suite("ProfileRepository contract (in-memory)")
struct ProfileRepositoryTests {

    @Test("A fresh repository returns the default profile")
    func defaults() async throws {
        let repo = InMemoryProfileRepository()
        let profile = try await repo.load()
        #expect(profile == .default)
        #expect(profile.themeID == .standard)
        #expect(profile.defaultPassThreshold == 70)
        #expect(profile.hapticsEnabled)
    }

    @Test("Saving a profile round-trips")
    func roundTrip() async throws {
        let repo = InMemoryProfileRepository()
        var profile = try await repo.load()
        profile.displayName = "Ada"
        profile.themeID = .aurora
        profile.hapticsEnabled = false
        profile.defaultPassThreshold = 80
        try await repo.save(profile)

        let reloaded = try await repo.load()
        #expect(reloaded.displayName == "Ada")
        #expect(reloaded.themeID == .aurora)
        #expect(reloaded.hapticsEnabled == false)
        #expect(reloaded.defaultPassThreshold == 80)
    }

    @Test("Profile is Codable round-trip safe")
    func codable() throws {
        let profile = Profile(displayName: "Grace", themeID: .aurora, defaultQuestionCount: 25)
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        #expect(decoded == profile)
    }
}

//
//  ExplanationTests.swift
//  CoreModelsTests
//
//  Covers the AI-explanation value types and the Profile back-compat decoder for
//  the new `aiExplanationsEnabled` flag.
//

import Testing
import Foundation
@testable import CoreModels

@Suite("Explanation value types")
struct ExplanationTests {

    @Test("Explanation round-trips through Codable")
    func explanationRoundTrip() throws {
        let original = Explanation(
            text: "Because 2 + 2 = 4.",
            sources: [Source(title: "Math", url: "https://example.com")]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Explanation.self, from: data)
        #expect(decoded == original)
    }

    @Test("Source id is its url")
    func sourceID() {
        #expect(Source(title: "X", url: "https://a.b").id == "https://a.b")
    }

    @Test("InMemoryExplanationService returns its canned answer")
    func inMemoryService() async throws {
        let service = InMemoryExplanationService(canned: Explanation(text: "hi"))
        let request = ExplanationRequest(
            prompt: "?", choices: [], selectedChoiceIDs: [], correctChoiceIDs: []
        )
        let result = try await service.explain(request)
        #expect(result.text == "hi")
    }
}

@Suite("Profile AI flag back-compat")
struct ProfileAIFlagTests {

    @Test("decodes a profile saved before aiExplanationsEnabled existed (defaults false)")
    func decodesLegacyProfile() throws {
        let legacy = """
        {
          "displayName": "Old",
          "avatarSymbol": "star.fill",
          "themeID": "standard",
          "hapticsEnabled": true,
          "defaultPassThreshold": 70
        }
        """
        let profile = try JSONDecoder().decode(Profile.self, from: Data(legacy.utf8))
        #expect(profile.aiExplanationsEnabled == false)
        #expect(profile.displayName == "Old")
    }

    @Test("round-trips the flag when set")
    func roundTripsFlag() throws {
        var profile = Profile.default
        profile.aiExplanationsEnabled = true
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(Profile.self, from: data)
        #expect(decoded.aiExplanationsEnabled == true)
    }
}

@Suite("InMemoryAPIKeyStore")
struct InMemoryAPIKeyStoreTests {

    @Test("stores, reports presence, and clears")
    func lifecycle() {
        let store = InMemoryAPIKeyStore()
        #expect(store.hasKey == false)
        store.setKey("  sk-test  ")
        #expect(store.hasKey == true)
        store.setKey("   ")        // whitespace clears
        #expect(store.hasKey == false)
        store.setKey("sk-x")
        store.clearKey()
        #expect(store.hasKey == false)
    }
}

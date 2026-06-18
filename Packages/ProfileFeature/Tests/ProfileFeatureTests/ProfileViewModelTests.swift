//
//  ProfileViewModelTests.swift
//  ProfileFeatureTests
//

import Testing
import CoreModels
import DesignSystem
@testable import ProfileFeature

@MainActor
@Suite("ProfileViewModel")
struct ProfileViewModelTests {

    @Test("Loads the default profile, persists edits")
    func loadPersist() async {
        let repo = InMemoryProfileRepository()
        let model = ProfileViewModel(repository: repo, sessionRepository: InMemorySessionRepository(), libraryRepository: InMemoryLibraryRepository())
        await model.load()
        #expect(model.profile == .default)

        model.profile.displayName = "Ada"
        model.profile.themeID = .aurora
        await model.persist()

        let reloaded = ProfileViewModel(repository: repo, sessionRepository: InMemorySessionRepository(), libraryRepository: InMemoryLibraryRepository())
        await reloaded.load()
        #expect(reloaded.profile.displayName == "Ada")
        #expect(reloaded.profile.themeID == .aurora)
    }

    @Test("theme maps the ThemeID to a DesignSystem Theme")
    func themeMapping() async {
        let model = ProfileViewModel(repository: InMemoryProfileRepository(),
                                     sessionRepository: InMemorySessionRepository(),
                                     libraryRepository: InMemoryLibraryRepository())
        await model.load()
        #expect(model.theme == Theme.standard)
        model.profile.themeID = .aurora
        #expect(model.theme == Theme.aurora)
    }

    @Test("exportHistory includes saved sessions; clearHistory empties them")
    func dataManagement() async {
        let session = InMemorySessionRepository()
        let result = SessionResult(
            mode: .exam,
            attempts: [QuestionAttempt(questionID: 0, selectedChoiceIDs: [0], correctChoiceIDs: [0], isCorrect: true)],
            passThreshold: 70
        )
        try! await session.save(SessionRecord(scopeLabel: "AZ-900", result: result))

        let model = ProfileViewModel(repository: InMemoryProfileRepository(), sessionRepository: session, libraryRepository: InMemoryLibraryRepository())
        let text = await model.exportHistory()
        #expect(text.contains("Session History"))
        #expect(text.contains("AZ-900"))

        await model.clearHistory()
        #expect(try! await session.allRecords().isEmpty)
    }
}

//
//  FlashcardDeckViewModelTests.swift
//  VocabularyFeatureTests
//
//  Exercises the deck and hub view models against an in-memory review repository:
//  the queue is built due-first, answers persist and advance, and the hub's
//  progress counts reflect the saved Leitner boxes.
//

import Testing
import Foundation
import CoreModels
import VocabularyKit
@testable import VocabularyFeature

private func sampleSet() -> VocabularySet {
    VocabularySet(
        title: "Croatian", foreignLanguage: .croatian, nativeLanguage: .english,
        entries: [
            VocabularyEntry(id: 0, term: "dobar dan", translation: "good day"),
            VocabularyEntry(id: 1, term: "hvala", translation: "thank you"),
            VocabularyEntry(id: 2, term: "molim", translation: "please")
        ]
    )
}

@MainActor
@Suite("Flashcard deck & study view models")
struct FlashcardDeckViewModelTests {

    @Test("start builds a queue of every usable card, due first")
    func startsQueue() async {
        let model = FlashcardDeckViewModel(set: sampleSet(), fileID: UUID(), reviewRepository: InMemoryVocabReviewRepository())
        await model.start()
        #expect(model.total == 3)
        #expect(model.cardNumber == 1)
        #expect(!model.isFinished)
        #expect(model.currentEntry != nil)
    }

    @Test("answering advances and finishes the deck")
    func advancesToFinish() async {
        let model = FlashcardDeckViewModel(set: sampleSet(), fileID: UUID(), reviewRepository: InMemoryVocabReviewRepository())
        await model.start()
        model.answer(.known)
        model.answer(.again)
        model.answer(.known)
        #expect(model.isFinished)
        #expect(model.knownThisSession == 2)
    }

    @Test("a Known answer is persisted with a promoted box")
    func persistsAnswer() async {
        let repo = InMemoryVocabReviewRepository()
        let file = UUID()
        let model = FlashcardDeckViewModel(set: sampleSet(), fileID: file, reviewRepository: repo)
        await model.start()
        let firstID = model.currentEntry!.id
        model.answer(.known)
        // The async persist Task needs a tick to land.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let saved = try? await repo.states(forFile: file)
        let state = saved?.first { $0.entryID == firstID }
        #expect(state?.box == 1)
    }

    @Test("flip toggles the revealed side")
    func flip() async {
        let model = FlashcardDeckViewModel(set: sampleSet(), fileID: UUID(), reviewRepository: InMemoryVocabReviewRepository())
        await model.start()
        #expect(!model.isShowingBack)
        model.flip()
        #expect(model.isShowingBack)
    }

    @Test("study hub reports mastery progress from saved state")
    func hubProgress() async {
        let repo = InMemoryVocabReviewRepository()
        let file = UUID()
        // Entry 0 mastered (box 4), entry 1 learning (box 1), entry 2 untouched.
        try? await repo.save(CardReviewState(entryID: 0, box: 4), forFile: file)
        try? await repo.save(CardReviewState(entryID: 1, box: 1), forFile: file)

        let hub = VocabularyStudyViewModel(set: sampleSet(), fileID: file, reviewRepository: repo)
        await hub.load()
        #expect(hub.entryCount == 3)
        #expect(hub.masteredCount == 1)
        #expect(hub.learningCount == 1)
        #expect(hub.newCount == 1)
        #expect(hub.canQuiz)
    }
}

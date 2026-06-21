//
//  VocabularyStudyViewModel.swift
//  VocabularyFeature
//
//  The state behind the vocabulary study hub. It owns the `VocabularySet`, loads
//  per-card review state through `VocabReviewRepository`, and exposes display-ready
//  progress (mastered / learning / due) computed via `LeitnerScheduler`. It also
//  builds a translation `ParsedQuiz` on demand (the view forwards that to the host
//  so the existing quiz runner stays in QuizFeature). No quiz/spaced-rep logic
//  lives in the view — it forwards intents here, here it forwards to VocabularyKit.
//

import Foundation
import Observation
import CoreModels
import VocabularyKit

@MainActor
@Observable
public final class VocabularyStudyViewModel {
    public let vocabulary: VocabularySet
    public let fileID: UUID

    @ObservationIgnored private let reviewRepository: any VocabReviewRepository
    @ObservationIgnored private let scheduler: LeitnerScheduler
    @ObservationIgnored private let builder: VocabularyQuizBuilder

    /// The loaded review states, keyed by entry id. Drives the progress counts.
    public private(set) var states: [CardReviewState] = []
    public private(set) var isLoaded = false

    public init(
        set: VocabularySet,
        fileID: UUID,
        reviewRepository: any VocabReviewRepository,
        scheduler: LeitnerScheduler = LeitnerScheduler(),
        builder: VocabularyQuizBuilder = VocabularyQuizBuilder()
    ) {
        self.vocabulary = set
        self.fileID = fileID
        self.reviewRepository = reviewRepository
        self.scheduler = scheduler
        self.builder = builder
    }

    // MARK: - Loading

    /// (Re)load review state — call on appear and when returning from the deck.
    public func load() async {
        states = (try? await reviewRepository.states(forFile: fileID)) ?? []
        isLoaded = true
    }

    // MARK: - Display state

    public var entryCount: Int { vocabulary.usableEntries.count }

    private var stateByID: [Int: CardReviewState] {
        Dictionary(states.map { ($0.entryID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Cards that have reached the mastery box.
    public var masteredCount: Int {
        vocabulary.usableEntries.filter { entry in
            guard let state = stateByID[entry.id] else { return false }
            return scheduler.isMastered(state)
        }.count
    }

    /// Cards seen at least once but not yet mastered.
    public var learningCount: Int {
        vocabulary.usableEntries.filter { entry in
            guard let state = stateByID[entry.id] else { return false }
            return !scheduler.isMastered(state)
        }.count
    }

    /// Cards never reviewed yet.
    public var newCount: Int {
        vocabulary.usableEntries.filter { stateByID[$0.id] == nil }.count
    }

    /// Cards due for review right now (new cards count as due).
    public var dueCount: Int {
        let now = Date()
        return vocabulary.usableEntries.filter { entry in
            (stateByID[entry.id] ?? CardReviewState(entryID: entry.id)).isDue(asOf: now)
        }.count
    }

    /// 0…1 mastery fraction for a progress bar.
    public var masteryFraction: Double {
        entryCount == 0 ? 0 : Double(masteredCount) / Double(entryCount)
    }

    public var canStudy: Bool { entryCount > 0 }
    public var canQuiz: Bool { entryCount >= 2 }

    // MARK: - Quiz

    /// Build a fresh translation quiz from the set. `seed` defaults to a time-based
    /// value so each launch reshuffles; pass a fixed seed in tests.
    public func makeQuiz(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) -> ParsedQuiz {
        builder.makeQuiz(from: vocabulary, seed: seed)
    }

    /// A deck view model sharing this hub's set, file, repository, and scheduler.
    public func makeDeck() -> FlashcardDeckViewModel {
        FlashcardDeckViewModel(
            set: vocabulary,
            fileID: fileID,
            reviewRepository: reviewRepository,
            scheduler: scheduler
        )
    }
}

//
//  FlashcardDeckViewModel.swift
//  VocabularyFeature
//
//  The one stateful object in the flashcard deck. It owns the study queue (ordered
//  due-first by `LeitnerScheduler`), tracks the current card and whether its back
//  is showing, and on each Known / Again answer steps the card's `CardReviewState`
//  and persists it through `VocabReviewRepository`. Direction is mixed per card so
//  the learner practises both recognition and recall. The view sends intents
//  (`flip`, `answer`) and renders display state — no scheduling logic in the view.
//

import Foundation
import Observation
import CoreModels
import VocabularyKit

@MainActor
@Observable
public final class FlashcardDeckViewModel {
    public let set: VocabularySet

    @ObservationIgnored private let fileID: UUID
    @ObservationIgnored private let reviewRepository: any VocabReviewRepository
    @ObservationIgnored private let scheduler: LeitnerScheduler

    /// The ordered entry ids to study this session (due cards first).
    public private(set) var queue: [Int] = []
    /// Index into `queue` of the card on screen.
    public private(set) var position = 0
    /// Whether the answer side is revealed.
    public private(set) var isShowingBack = false
    /// The direction the current card is posed in (mixed across the deck).
    public private(set) var direction: QuizDirection = .foreignToNative
    public private(set) var isLoaded = false
    /// How many cards were answered Known this session (for the summary).
    public private(set) var knownThisSession = 0

    @ObservationIgnored private var generator = SeededGenerator(seed: UInt64(Date().timeIntervalSince1970))
    @ObservationIgnored private var entriesByID: [Int: VocabularyEntry] = [:]

    public init(
        set: VocabularySet,
        fileID: UUID,
        reviewRepository: any VocabReviewRepository,
        scheduler: LeitnerScheduler = LeitnerScheduler()
    ) {
        self.set = set
        self.fileID = fileID
        self.reviewRepository = reviewRepository
        self.scheduler = scheduler
        self.entriesByID = Dictionary(set.usableEntries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Loading

    /// Build the study queue from persisted state (due cards first), then show the
    /// first card. Call once on appear.
    public func start() async {
        let states = (try? await reviewRepository.states(forFile: fileID)) ?? []
        let ids = set.usableEntries.map(\.id)
        queue = scheduler.studyOrder(entryIDs: ids, states: states, now: Date())
        position = 0
        isShowingBack = false
        knownThisSession = 0
        pickDirection()
        isLoaded = true
    }

    // MARK: - Display state

    public var isFinished: Bool { isLoaded && position >= queue.count }
    public var total: Int { queue.count }
    /// 1-based card number for "3 of 12".
    public var cardNumber: Int { min(position + 1, total) }

    public var currentEntry: VocabularyEntry? {
        guard position < queue.count else { return nil }
        return entriesByID[queue[position]]
    }

    /// The text on the front (prompt) of the current card.
    public var frontText: String { currentEntry?.prompt(for: direction) ?? "" }
    /// The text on the back (answer) of the current card.
    public var backText: String { currentEntry?.answer(for: direction) ?? "" }
    /// A pronunciation hint, shown with the answer when present.
    public var phonetic: String? { currentEntry?.phonetic }
    /// A native-script transcription of the foreign term, shown alongside it.
    public var transcription: String? { currentEntry?.transcription }
    /// An example sentence, shown with the answer when present.
    public var example: String? { currentEntry?.example }

    /// The foreign-language term for the current card — what the "listen" button
    /// voices, regardless of which side is the prompt.
    public var foreignTerm: String { currentEntry?.term ?? "" }
    /// The BCP-47 code used to pick a speech voice for the foreign term, or nil
    /// when the set didn't specify one (the synthesizer then uses its default).
    public var foreignLanguageCode: String? {
        self.set.foreignLanguage.code.isEmpty ? nil : self.set.foreignLanguage.code
    }
    /// Whether the foreign term is the side currently on screen — gates the
    /// transcription and the listen button so a recall card isn't given away early.
    public var isForeignSideVisible: Bool {
        direction == .foreignToNative ? !isShowingBack : isShowingBack
    }

    /// The language label for the side currently shown (for a subtle caption).
    public var frontLanguage: String {
        direction == .foreignToNative ? set.foreignLanguage.displayName : set.nativeLanguage.displayName
    }
    public var backLanguage: String {
        direction == .foreignToNative ? set.nativeLanguage.displayName : set.foreignLanguage.displayName
    }

    // MARK: - Intents

    /// Reveal the answer side.
    public func flip() { isShowingBack.toggle() }

    /// Record an answer for the current card, persist its new state, and advance.
    public func answer(_ answer: LeitnerScheduler.Answer) {
        guard let entry = currentEntry else { return }
        Task { await persist(answer, for: entry.id) }
        if answer == .known { knownThisSession += 1 }
        advance()
    }

    /// Restart the deck from the top (used by the finished screen).
    public func restart() {
        Task { await start() }
    }

    // MARK: - Implementation

    private func advance() {
        position += 1
        isShowingBack = false
        pickDirection()
    }

    private func pickDirection() {
        guard position < queue.count else { return }
        // Deterministic per-card direction; mixes both ways across the deck.
        direction = (generator.next() % 2 == 0) ? .foreignToNative : .nativeToForeign
    }

    private func persist(_ answer: LeitnerScheduler.Answer, for entryID: Int) async {
        let states = (try? await reviewRepository.states(forFile: fileID)) ?? []
        let current = states.first { $0.entryID == entryID } ?? CardReviewState(entryID: entryID)
        let updated = scheduler.apply(answer, to: current, now: Date())
        try? await reviewRepository.save(updated, forFile: fileID)
    }
}

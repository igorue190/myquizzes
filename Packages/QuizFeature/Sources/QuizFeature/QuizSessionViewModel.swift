//
//  QuizSessionViewModel.swift
//  QuizFeature
//
//  The one stateful object in the quiz runner. It owns a value-type `QuizSession`
//  from the engine, forwards user intents to it, and exposes display-ready state
//  (including the mapping from the domain model to DesignSystem's view enums).
//  Views read this and send intents — no quiz rules live in the view layer.
//

import Foundation
import Observation
import CoreModels
import QuizEngine
import MarkdownParser
import DesignSystem

@MainActor
@Observable
public final class QuizSessionViewModel {

    /// The live session. Mutating it (via the intent methods) is observed by
    /// SwiftUI because `@Observable` tracks this stored property.
    public private(set) var session: QuizSession

    /// Called once when the session is submitted, with the scored result. The
    /// app uses this to persist a `SessionRecord` (the feature stays free of any
    /// persistence dependency).
    @ObservationIgnored public var onFinish: ((SessionResult) -> Void)?

    /// Whether to fire haptic feedback on answer/submit (the Profile setting).
    @ObservationIgnored public var hapticsEnabled: Bool = false

    /// Injected AI-explanation call. nil ⇒ the feature is off and the "Ask AI"
    /// button stays hidden. The feature package stays free of any AI dependency.
    @ObservationIgnored public var onExplain: ((ExplanationRequest) async throws -> Explanation)?

    /// Injected local cache lookup. When set, a previously generated explanation is
    /// shown instantly and offline (the local-first promise) without a network call.
    /// nil ⇒ no cached display (e.g. the AI feature is disabled).
    @ObservationIgnored public var onCachedExplanation: ((ExplanationRequest) async -> Explanation?)?

    /// The language explanations should be written in — the learner's native
    /// language for translation quizzes, so the AI explains in the language they
    /// understand best rather than the answer's language. nil ⇒ the model uses the
    /// question's language (ordinary quizzes). Set at the composition root.
    @ObservationIgnored public var explanationLanguage: String?

    /// Per-question explanation state, keyed by `Question.id`.
    public private(set) var explanationPhases: [Int: ExplanationPhase] = [:]

    /// Seconds left on the exam clock (0 in Training, or when there's no limit).
    public private(set) var remaining: TimeInterval = 0
    @ObservationIgnored private var timerTask: Task<Void, Never>?

    public init(session: QuizSession, autostart: Bool = true) {
        self.session = session
        self.remaining = session.config.timeLimit ?? 0
        if autostart {
            self.session.start()
            beginTimerIfNeeded()
        }
    }

    /// Convenience: build a runnable session straight from Markdown (handy for
    /// previews and the app's "open a file" path).
    public static func make(
        fromMarkdown markdown: String,
        config: SessionConfig
    ) -> QuizSessionViewModel {
        let quiz = MarkdownQuizParser().parse(markdown)
        let session = SessionPlanner.makeSession(from: quiz.usableQuestions, config: config)
        return QuizSessionViewModel(session: session)
    }

    /// Build a session from an explicit set of questions — used by the "Review
    /// weak areas" flow, which assembles its pool from across the whole Library.
    /// Callers should hand in questions with unique ids.
    public static func make(
        fromQuestions questions: [Question],
        config: SessionConfig
    ) -> QuizSessionViewModel {
        let session = SessionPlanner.makeSession(from: questions, config: config)
        return QuizSessionViewModel(session: session)
    }

    // MARK: - Intents

    public func select(_ choiceID: Int, in questionID: Int) {
        session.select(choiceID: choiceID, in: questionID)
        if hapticsEnabled { Haptics.selection() }
    }
    public func toggleMark() { session.toggleMark() }
    public func goToNext() { session.next() }
    public func goToPrevious() { session.previous() }
    public func goto(_ index: Int) { session.goto(index: index) }
    public func submit() {
        timerTask?.cancel()
        timerTask = nil
        session.submit()
        if let result {
            if hapticsEnabled { Haptics.notify(result.passed ? .success : .error) }
            onFinish?(result)
        }
    }
    public func openReview() { session.openReview() }

    // MARK: - Exam timer

    public var totalTime: TimeInterval { session.config.timeLimit ?? 0 }
    public var hasTimer: Bool { mode == .exam && totalTime > 0 }

    /// Tick the exam clock down once per second; auto-submit at zero.
    private func beginTimerIfNeeded() {
        guard hasTimer else { return }
        remaining = totalTime
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard self.session.state == .inProgress else { return }
                if self.remaining <= 1 {
                    self.remaining = 0
                    self.submit()
                    return
                }
                self.remaining -= 1
            }
        }
    }

    // MARK: - Display state

    public var mode: SessionMode { session.config.mode }
    public var current: Question? { session.currentQuestion }
    public var count: Int { session.count }
    public var cursor: Int { session.cursor }
    public var isFirst: Bool { session.isFirst }
    public var isLast: Bool { session.isLast }
    public var answeredCount: Int { session.answeredCount }

    public var progressLabel: String { "Question \(session.cursor + 1) of \(session.count)" }

    /// Reviewing covers both "submitted" and "reviewing" — i.e. answers are now
    /// locked and correctness should be revealed.
    public var isReviewing: Bool {
        session.state == .submitted || session.state == .reviewing
    }

    public var isFinished: Bool { session.state == .submitted || session.state == .reviewing }

    /// Scored result, available once the session is submitted.
    public var result: SessionResult? {
        guard isFinished else { return nil }
        return Scorer.score(session)
    }

    // MARK: - Domain → DesignSystem mapping

    public func selectionStyle(for question: Question) -> ChoiceSelectionStyle {
        question.type == .multiple ? .multiple : .single
    }

    /// Map a choice to its DesignSystem visual state. During answering only
    /// selected/unselected are used (no feedback mid-exam); during review the
    /// correct/incorrect/missed states are revealed.
    public func choiceState(_ choice: Choice, in question: Question) -> ChoiceState {
        let isSelected = session.selection(for: question.id).contains(choice.id)
        guard isReviewing else {
            return isSelected ? .selected : .unselected
        }
        switch (choice.isCorrect, isSelected) {
        case (true, true):   return .correct
        case (true, false):  return .missedCorrect
        case (false, true):  return .incorrect
        case (false, false): return .unselected
        }
    }

    // MARK: - AI explanations

    /// Whether the "Ask AI" CTA (live generation) should appear.
    public var isAIEnabled: Bool { onExplain != nil }

    /// Whether the AI block should appear at all — true when we can either generate
    /// or show a cached explanation. Lets cached results show offline even when no
    /// API key is set (generation off, cache still readable).
    public var isAIVisible: Bool { onExplain != nil || onCachedExplanation != nil }

    public func explanationPhase(for questionID: Int) -> ExplanationPhase {
        explanationPhases[questionID] ?? .idle
    }

    /// Show a cached explanation for this question if one exists and nothing has
    /// been loaded yet. Cheap and offline; call on appear of each reviewed question.
    public func preloadExplanation(for question: Question) {
        guard let onCachedExplanation, explanationPhase(for: question.id) == .idle else { return }
        let request = Self.explanationRequest(for: question, selection: session.selection(for: question.id), language: explanationLanguage)
        Task {
            if explanationPhases[question.id] == nil || explanationPhases[question.id] == .idle,
               let cached = await onCachedExplanation(request) {
                explanationPhases[question.id] = .loaded(cached)
            }
        }
    }

    /// True when the user's answer to this question was wrong (drives the CTA).
    public func isAnswerCorrect(_ question: Question) -> Bool {
        session.selection(for: question.id) == question.correctChoiceIDs
    }

    /// Ask the injected service to explain a missed question; result lands in
    /// `explanationPhases[question.id]`.
    public func requestExplanation(for question: Question) {
        guard let onExplain else { return }
        let request = Self.explanationRequest(for: question, selection: session.selection(for: question.id), language: explanationLanguage)
        explanationPhases[question.id] = .loading
        Task {
            do {
                explanationPhases[question.id] = .loaded(try await onExplain(request))
            } catch {
                explanationPhases[question.id] = .failed(Self.explanationMessage(for: error))
            }
        }
    }

    static func explanationRequest(for question: Question, selection: Set<Int>, language: String? = nil) -> ExplanationRequest {
        ExplanationRequest(
            prompt: question.prompt,
            choices: question.choices.map { AttemptChoice(id: $0.id, text: $0.text, isCorrect: $0.isCorrect) },
            selectedChoiceIDs: selection,
            correctChoiceIDs: question.correctChoiceIDs,
            existingExplanation: question.explanation,
            explanationLanguage: language
        )
    }

    static func explanationMessage(for error: any Error) -> String {
        switch error as? ExplanationError {
        case .notConfigured: "AI explanations aren't set up. Add your API key in Profile."
        case .network:       "Couldn't reach the AI service. Check your connection."
        case .api(let reason): reason
        case .decoding, .none: "The AI response couldn't be read. Try again."
        }
    }

    // MARK: - Question palette (Exam)

    public enum PaletteCellState: Sendable, Equatable { case current, marked, answered, unanswered }

    /// State for the question-palette grid. Precedence: current → marked →
    /// answered → unanswered.
    public func paletteState(at index: Int) -> PaletteCellState {
        guard session.questions.indices.contains(index) else { return .unanswered }
        if index == session.cursor { return .current }
        let question = session.questions[index]
        if session.isMarked(question.id) { return .marked }
        if session.isAnswered(question.id) { return .answered }
        return .unanswered
    }

    public var isCurrentMarked: Bool {
        guard let question = current else { return false }
        return session.isMarked(question.id)
    }

    public func badge(for question: Question) -> TagChip? {
        guard let difficulty = question.difficulty else { return nil }
        let kind: TagChip.Kind = switch difficulty {
        case .beginner:     .difficulty(.beginner)
        case .intermediate: .difficulty(.intermediate)
        case .advanced:     .difficulty(.advanced)
        }
        return TagChip(difficulty.rawValue.capitalized, kind: kind)
    }
}

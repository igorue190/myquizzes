//
//  QuizSession.swift
//  QuizEngine
//
//  The session state machine. A value type with intent methods that transition
//  between the states from the plan's lifecycle diagram (§8.1):
//
//      Configured ──start()──▶ InProgress ──submit()/timeout──▶ Submitted
//                                                              └─openReview()─▶ Reviewing
//
//  Illegal transitions are no-ops (the UI shouldn't offer them, but the engine
//  stays total and crash-free regardless). The feature layer wraps this in an
//  @Observable view model; the engine itself is pure and Sendable.
//

import CoreModels

public struct QuizSession: Sendable, Equatable {

    public enum State: String, Sendable, Equatable {
        case configured     // built, not yet started
        case inProgress     // user is answering
        case submitted      // scored; awaiting review
        case reviewing      // walking the answered questions with feedback
    }

    public let config: SessionConfig
    /// Prepared questions in presentation order (already selected/shuffled).
    public let questions: [Question]

    public private(set) var state: State
    /// Index into `questions` of the currently visible question.
    public private(set) var cursor: Int
    /// questionID → chosen choice ids.
    public private(set) var selections: [Int: Set<Int>]
    /// questionIDs flagged "mark for review" (Exam mode).
    public private(set) var markedForReview: Set<Int>

    public init(config: SessionConfig, questions: [Question]) {
        self.config = config
        self.questions = questions
        self.state = .configured
        self.cursor = 0
        self.selections = [:]
        self.markedForReview = []
    }

    // MARK: - Derived state

    public var currentQuestion: Question? {
        questions.indices.contains(cursor) ? questions[cursor] : nil
    }

    public var count: Int { questions.count }

    public var isFirst: Bool { cursor == 0 }
    public var isLast: Bool { cursor >= questions.count - 1 }

    /// Questions with at least one selected choice.
    public var answeredCount: Int {
        questions.filter { !(selections[$0.id] ?? []).isEmpty }.count
    }

    public func selection(for questionID: Int) -> Set<Int> {
        selections[questionID] ?? []
    }

    public func isAnswered(_ questionID: Int) -> Bool {
        !(selections[questionID] ?? []).isEmpty
    }

    public func isMarked(_ questionID: Int) -> Bool {
        markedForReview.contains(questionID)
    }

    // MARK: - Transitions

    public mutating func start() {
        guard state == .configured else { return }
        state = .inProgress
    }

    /// Record a choice. Single/true-false replace any prior selection; multiple
    /// toggles membership. No-op outside `.inProgress`.
    public mutating func select(choiceID: Int, in questionID: Int) {
        guard state == .inProgress,
              let question = questions.first(where: { $0.id == questionID }),
              question.choices.contains(where: { $0.id == choiceID })
        else { return }

        switch question.type {
        case .single, .trueFalse:
            selections[questionID] = [choiceID]
        case .multiple:
            var current = selections[questionID] ?? []
            if current.contains(choiceID) {
                current.remove(choiceID)
            } else {
                current.insert(choiceID)
            }
            if current.isEmpty {
                selections[questionID] = nil
            } else {
                selections[questionID] = current
            }
        }
    }

    /// Clear a question's answer (Training "retry").
    public mutating func clearSelection(in questionID: Int) {
        guard state == .inProgress else { return }
        selections[questionID] = nil
    }

    public mutating func toggleMark() {
        guard state == .inProgress, let q = currentQuestion else { return }
        if markedForReview.contains(q.id) {
            markedForReview.remove(q.id)
        } else {
            markedForReview.insert(q.id)
        }
    }

    @discardableResult
    public mutating func next() -> Bool {
        guard state == .inProgress || state == .reviewing else { return false }
        guard cursor < questions.count - 1 else { return false }
        cursor += 1
        return true
    }

    @discardableResult
    public mutating func previous() -> Bool {
        guard state == .inProgress || state == .reviewing else { return false }
        guard cursor > 0 else { return false }
        cursor -= 1
        return true
    }

    /// Jump straight to a question (the Exam question-palette grid).
    public mutating func goto(index: Int) {
        guard state == .inProgress || state == .reviewing else { return }
        guard questions.indices.contains(index) else { return }
        cursor = index
    }

    public mutating func submit() {
        guard state == .inProgress else { return }
        state = .submitted
    }

    public mutating func openReview() {
        guard state == .submitted else { return }
        state = .reviewing
        cursor = 0
    }
}

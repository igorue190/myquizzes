//
//  QuizEngineTests.swift
//  QuizEngineTests
//

import Testing
import CoreModels
@testable import QuizEngine

// MARK: - Fixtures

private func choice(_ id: Int, _ text: String, _ correct: Bool) -> Choice {
    Choice(id: id, text: text, isCorrect: correct)
}

/// A pool of `n` single-answer questions where choice 0 is always correct.
private func pool(_ n: Int, tag: String? = nil) -> [Question] {
    (0..<n).map { i in
        Question(
            id: i,
            prompt: "Q\(i)",
            type: .single,
            choices: [choice(0, "right", true), choice(1, "wrong", false)],
            tags: tag.map { [$0] } ?? []
        )
    }
}

// MARK: - Selection & shuffling

@Suite("SessionPlanner selection and shuffling")
struct SessionPlannerTests {

    @Test("With no count and no shuffle, the session is the pool in order")
    func passthrough() {
        let session = SessionPlanner.makeSession(
            from: pool(5),
            config: SessionConfig(mode: .training)
        )
        #expect(session.questions.map(\.id) == [0, 1, 2, 3, 4])
        #expect(session.state == .configured)
    }

    @Test("A smaller count yields a subset of that size in original order")
    func subsetKeepsOrder() {
        let session = SessionPlanner.makeSession(
            from: pool(10),
            config: SessionConfig(mode: .exam, questionCount: 4, seed: 99)
        )
        #expect(session.count == 4)
        // shuffleQuestions is off → ids must be ascending (document order).
        #expect(session.questions.map(\.id) == session.questions.map(\.id).sorted())
    }

    @Test("Same seed reproduces the same selection; different seed differs")
    func seededSelectionIsReproducible() {
        func ids(seed: UInt64) -> [Int] {
            SessionPlanner.makeSession(
                from: pool(20),
                config: SessionConfig(mode: .exam, questionCount: 8,
                                      shuffleQuestions: true, seed: seed)
            ).questions.map(\.id)
        }
        #expect(ids(seed: 7) == ids(seed: 7))
        #expect(ids(seed: 7) != ids(seed: 8))
    }

    @Test("Shuffling answers preserves choice ids (scoring stays valid)")
    func shuffleAnswersPreservesIDs() {
        let q = Question(id: 0, prompt: "p", type: .multiple,
                         choices: [choice(0, "a", true), choice(1, "b", false),
                                   choice(2, "c", true), choice(3, "d", false)])
        let session = SessionPlanner.makeSession(
            from: [q],
            config: SessionConfig(mode: .training, shuffleAnswers: true, seed: 3)
        )
        let shuffled = session.questions[0]
        #expect(Set(shuffled.choices.map(\.id)) == [0, 1, 2, 3])
        #expect(shuffled.correctChoiceIDs == [0, 2])   // correctness tracked by id, not position
    }
}

// MARK: - State machine

@Suite("QuizSession state machine")
struct QuizSessionTests {

    @Test("start/submit/openReview follow the documented lifecycle")
    func lifecycle() {
        var s = SessionPlanner.makeSession(from: pool(3), config: SessionConfig(mode: .exam))
        #expect(s.state == .configured)
        s.openReview()                      // illegal before submit → no-op
        #expect(s.state == .configured)
        s.start()
        #expect(s.state == .inProgress)
        s.submit()
        #expect(s.state == .submitted)
        s.openReview()
        #expect(s.state == .reviewing)
    }

    @Test("Selecting before start is ignored")
    func selectRequiresInProgress() {
        var s = SessionPlanner.makeSession(from: pool(3), config: SessionConfig(mode: .training))
        s.select(choiceID: 0, in: 0)
        #expect(s.selection(for: 0).isEmpty)
    }

    @Test("Single-answer selection replaces; multiple toggles")
    func selectionSemantics() {
        let single = Question(id: 0, prompt: "s", type: .single,
                              choices: [choice(0, "a", true), choice(1, "b", false)])
        let multi = Question(id: 1, prompt: "m", type: .multiple,
                             choices: [choice(0, "a", true), choice(1, "b", true),
                                       choice(2, "c", false)])
        var s = SessionPlanner.makeSession(from: [single, multi], config: SessionConfig(mode: .training))
        s.start()

        s.select(choiceID: 0, in: 0)
        s.select(choiceID: 1, in: 0)        // single → replaces
        #expect(s.selection(for: 0) == [1])

        s.select(choiceID: 0, in: 1)
        s.select(choiceID: 1, in: 1)        // multiple → accumulates
        #expect(s.selection(for: 1) == [0, 1])
        s.select(choiceID: 0, in: 1)        // toggle off
        #expect(s.selection(for: 1) == [1])
    }

    @Test("Navigation respects bounds and mark-for-review toggles")
    func navigationAndMarks() {
        var s = SessionPlanner.makeSession(from: pool(3), config: SessionConfig(mode: .exam))
        s.start()
        #expect(s.isFirst)
        // Mutating methods can't be called inside #expect (the macro captures
        // the value immutably), so call them on their own line first.
        let beforeFirst = s.previous()      // can't go before first
        #expect(!beforeFirst)
        let movedForward = s.next()
        #expect(movedForward)
        #expect(s.cursor == 1)
        s.toggleMark()
        #expect(s.isMarked(s.currentQuestion!.id))
        s.toggleMark()
        #expect(!s.isMarked(s.currentQuestion!.id))
        s.goto(index: 2)
        #expect(s.isLast)
        let pastLast = s.next()             // can't go past last
        #expect(!pastLast)
    }
}

// MARK: - Scoring

@Suite("Scorer rules")
struct ScorerTests {

    @Test("Single/true-false score on exact match")
    func singleScoring() {
        #expect(Scorer.isCorrect(selected: [0], correct: [0]))
        #expect(!Scorer.isCorrect(selected: [1], correct: [0]))
        #expect(!Scorer.isCorrect(selected: [], correct: [0]))
    }

    @Test("Multiple is all-or-nothing: every correct, no incorrect")
    func multipleScoring() {
        #expect(Scorer.isCorrect(selected: [0, 2], correct: [0, 2]))   // exact
        #expect(!Scorer.isCorrect(selected: [0], correct: [0, 2]))      // partial → wrong
        #expect(!Scorer.isCorrect(selected: [0, 2, 3], correct: [0, 2]))// extra → wrong
        #expect(!Scorer.isCorrect(selected: [], correct: []))           // empty correct never passes
    }

    @Test("Scoring a session produces a pass at threshold")
    func sessionScore() {
        var s = SessionPlanner.makeSession(
            from: pool(10),
            config: SessionConfig(mode: .exam, passThreshold: 70)
        )
        s.start()
        // Answer 7 correctly (choice 0), 3 incorrectly (choice 1).
        for q in s.questions {
            s.select(choiceID: q.id < 7 ? 0 : 1, in: q.id)
        }
        s.submit()
        let result = Scorer.score(s)
        #expect(result.correctCount == 7)
        #expect(result.percentage == 70)
        #expect(result.passed)
        #expect(result.totalQuestions == 10)
    }

    @Test("Per-topic breakdown aggregates by tag")
    func breakdown() {
        var s = SessionPlanner.makeSession(
            from: pool(4, tag: "networking"),
            config: SessionConfig(mode: .training)
        )
        s.start()
        s.select(choiceID: 0, in: 0)   // correct
        s.select(choiceID: 0, in: 1)   // correct
        s.select(choiceID: 1, in: 2)   // wrong
        // q3 left unanswered → wrong
        s.submit()
        let result = Scorer.score(s)
        let net = result.topicBreakdown.first { $0.topic == "networking" }
        #expect(net?.total == 4)
        #expect(net?.correct == 2)
        #expect(net?.accuracy == 0.5)
    }
}

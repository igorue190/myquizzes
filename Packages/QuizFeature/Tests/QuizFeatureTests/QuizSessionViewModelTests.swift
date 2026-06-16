//
//  QuizSessionViewModelTests.swift
//  QuizFeatureTests
//

import Testing
import CoreModels
import DesignSystem
@testable import QuizFeature

@MainActor
@Suite("QuizSessionViewModel")
struct QuizSessionViewModelTests {

    private func makeModel(mode: SessionMode = .training) -> QuizSessionViewModel {
        let markdown = """
        ## Q1
        - [x] A
        - [ ] B

        ## Q2
        <!-- type: multiple -->
        - [x] A
        - [x] B
        - [ ] C
        """
        return QuizSessionViewModel.make(
            fromMarkdown: markdown,
            config: SessionConfig(mode: mode, passThreshold: 50, seed: 1)
        )
    }

    @Test("Starts in progress at the first question")
    func starts() {
        let model = makeModel()
        #expect(model.count == 2)
        #expect(model.cursor == 0)
        #expect(model.current?.prompt == "Q1")
        #expect(!model.isFinished)
        #expect(model.hapticsEnabled == false)   // off unless the app turns it on
    }

    @Test("Selecting then submitting scores and fires onFinish")
    func submitFiresOnFinish() {
        let model = makeModel(mode: .exam)
        var captured: SessionResult?
        model.onFinish = { captured = $0 }

        model.select(0, in: model.session.questions[0].id)   // Q1 correct
        model.goToNext()
        let q2 = model.session.questions[1]
        model.select(0, in: q2.id)
        model.select(1, in: q2.id)                            // Q2 fully correct
        model.submit()

        #expect(model.isFinished)
        #expect(captured?.correctCount == 2)
        #expect(captured?.passed == true)
    }

    @Test("Review reveals correct/incorrect/missed choice states")
    func reviewStates() {
        let model = makeModel()
        let q1 = model.session.questions[0]
        let a = q1.choices.first { $0.text == "A" }!   // correct
        let b = q1.choices.first { $0.text == "B" }!   // wrong
        model.select(b.id, in: q1.id)
        model.submit()

        #expect(model.isReviewing)
        #expect(model.choiceState(a, in: q1) == .missedCorrect)
        #expect(model.choiceState(b, in: q1) == .incorrect)
    }

    @Test("Palette reflects current / answered / unanswered")
    func palette() {
        let model = makeModel(mode: .exam)
        #expect(model.paletteState(at: 0) == .current)
        #expect(model.paletteState(at: 1) == .unanswered)
        model.select(0, in: model.session.questions[1].id)
        #expect(model.paletteState(at: 1) == .answered)
        model.goto(1)
        #expect(model.paletteState(at: 1) == .current)
    }
}

//
//  QuizExplanationTests.swift
//  QuizFeatureTests
//
//  Verifies the runner's "Ask AI" flow drives explanation state off the injected
//  service, and that the request is built from the live question + selection.
//

import Testing
import CoreModels
@testable import QuizFeature

@MainActor
@Suite("QuizSessionViewModel — AI explanations")
struct QuizExplanationTests {

    private func makeModel() -> QuizSessionViewModel {
        let markdown = """
        ## Capital of France?
        - [x] Paris
        - [ ] Rome
        """
        return QuizSessionViewModel.make(
            fromMarkdown: markdown,
            config: SessionConfig(mode: .training, passThreshold: 50, seed: 1)
        )
    }

    @Test("AI is disabled until onExplain is set")
    func disabledByDefault() {
        let model = makeModel()
        #expect(model.isAIEnabled == false)
        model.onExplain = { _ in Explanation(text: "x") }
        #expect(model.isAIEnabled == true)
    }

    @Test("requestExplanation loads the canned explanation into state")
    func loadsExplanation() async throws {
        let model = makeModel()
        let service = InMemoryExplanationService(canned: Explanation(text: "Paris is the capital."))
        model.onExplain = { try await service.explain($0) }

        let question = try #require(model.current)
        model.requestExplanation(for: question)

        // Drain the detached Task the view model spawned.
        try await Task.sleep(for: .milliseconds(50))

        guard case .loaded(let explanation) = model.explanationPhase(for: question.id) else {
            Issue.record("expected a loaded phase, got \(model.explanationPhase(for: question.id))")
            return
        }
        #expect(explanation.text == "Paris is the capital.")
    }

    @Test("explanationRequest carries prompt, selection, and correct ids")
    func buildsRequest() throws {
        let model = makeModel()
        let question = try #require(model.current)
        model.select(1, in: question.id)   // wrong answer (Rome)

        let request = QuizSessionViewModel.explanationRequest(
            for: question, selection: model.session.selection(for: question.id)
        )
        #expect(request.prompt == "Capital of France?")
        #expect(request.selectedChoiceIDs == [1])
        #expect(request.correctChoiceIDs == question.correctChoiceIDs)
        #expect(request.choices.count == 2)
    }
}

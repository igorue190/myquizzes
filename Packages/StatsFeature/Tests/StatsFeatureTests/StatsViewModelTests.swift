//
//  StatsViewModelTests.swift
//  StatsFeatureTests
//

import Testing
import Foundation
import CoreModels
@testable import StatsFeature

@MainActor
@Suite("StatsViewModel")
struct StatsViewModelTests {

    private func record(correct: Int, total: Int, topic: String) -> SessionRecord {
        let attempts = (0..<total).map {
            QuestionAttempt(questionID: $0, selectedChoiceIDs: [0],
                            correctChoiceIDs: [0], isCorrect: $0 < correct)
        }
        let result = SessionResult(
            mode: .exam, attempts: attempts, passThreshold: 70,
            topicBreakdown: [TopicScore(topic: topic, correct: correct, total: total)]
        )
        return SessionRecord(result: result)
    }

    @Test("Empty history yields the empty overview")
    func empty() async {
        let model = StatsViewModel(repository: InMemorySessionRepository())
        await model.load()
        #expect(model.overview.sessionCount == 0)
    }

    @Test("load aggregates saved records into the overview")
    func aggregates() async {
        let repo = InMemorySessionRepository()
        try! await repo.save(record(correct: 7, total: 10, topic: "Networking"))
        try! await repo.save(record(correct: 9, total: 10, topic: "Networking"))

        let model = StatsViewModel(repository: repo)
        await model.load()
        #expect(model.overview.sessionCount == 2)
        #expect(model.overview.totalCorrect == 16)
        #expect(model.overview.totalQuestions == 20)
        #expect(model.overview.topics.first?.topic == "Networking")
        #expect(model.overview.trend.count == 2)
    }
}

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

    private func record(
        correct: Int, total: Int, topic: String,
        mode: SessionMode = .exam, scope: String? = nil, daysAgo: Int = 0
    ) -> SessionRecord {
        let attempts = (0..<total).map {
            QuestionAttempt(questionID: $0, selectedChoiceIDs: [0],
                            correctChoiceIDs: [0], isCorrect: $0 < correct)
        }
        let result = SessionResult(
            mode: mode, attempts: attempts, passThreshold: 70,
            topicBreakdown: [TopicScore(topic: topic, correct: correct, total: total)]
        )
        return SessionRecord(
            finishedAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400)),
            scopeLabel: scope, result: result
        )
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

    // MARK: - Filtering

    @Test("Scope filter narrows the overview to one quiz")
    func filterByScope() async {
        let repo = InMemorySessionRepository()
        try! await repo.save(record(correct: 5, total: 10, topic: "A", scope: "Azure"))
        try! await repo.save(record(correct: 9, total: 10, topic: "B", scope: "AWS"))

        let model = StatsViewModel(repository: repo)
        await model.load()
        #expect(model.overview.sessionCount == 2)

        model.setScope("Azure")
        #expect(model.overview.sessionCount == 1)
        #expect(model.overview.totalCorrect == 5)
        #expect(model.isFiltered)

        model.setScope(nil)
        #expect(model.overview.sessionCount == 2)
    }

    @Test("Mode filter narrows the overview")
    func filterByMode() async {
        let repo = InMemorySessionRepository()
        try! await repo.save(record(correct: 5, total: 10, topic: "A", mode: .training))
        try! await repo.save(record(correct: 9, total: 10, topic: "B", mode: .exam))

        let model = StatsViewModel(repository: repo)
        await model.load()

        model.setMode(.training)
        #expect(model.overview.sessionCount == 1)
        #expect(model.overview.totalCorrect == 5)
    }

    @Test("Date range filter excludes older sessions")
    func filterByDate() async {
        let repo = InMemorySessionRepository()
        try! await repo.save(record(correct: 5, total: 10, topic: "A", daysAgo: 1))
        try! await repo.save(record(correct: 9, total: 10, topic: "B", daysAgo: 20))

        let model = StatsViewModel(repository: repo)
        await model.load()

        model.setDateRange(.last7)
        #expect(model.overview.sessionCount == 1)
        #expect(model.overview.totalCorrect == 5)
    }

    @Test("Available scopes and modes reflect history")
    func pickerOptions() async {
        let repo = InMemorySessionRepository()
        try! await repo.save(record(correct: 5, total: 10, topic: "A", mode: .training, scope: "Azure"))
        try! await repo.save(record(correct: 9, total: 10, topic: "B", mode: .exam, scope: "AWS"))

        let model = StatsViewModel(repository: repo)
        await model.load()
        #expect(model.availableScopes == ["AWS", "Azure"])
        #expect(model.availableModes == [.training, .exam])
    }

    // MARK: - Habits & review count

    @Test("dueCount reflects questions due for review")
    func dueCount() async {
        let repo = InMemorySessionRepository()
        let missed = QuestionAttempt(questionID: 0, selectedChoiceIDs: [1],
                                     correctChoiceIDs: [0], isCorrect: false, prompt: "Q1")
        try! await repo.save(SessionRecord(result: SessionResult(mode: .training, attempts: [missed], passThreshold: 70)))

        let model = StatsViewModel(repository: repo)
        await model.load()
        #expect(model.dueCount == 1)
    }

    @Test("habits are populated from loaded records")
    func habits() async {
        let repo = InMemorySessionRepository()
        try! await repo.save(record(correct: 5, total: 10, topic: "A"))
        let model = StatsViewModel(repository: repo)
        await model.load()
        #expect(model.habits.questionsAnswered == 10)
        #expect(model.habits.sessionsThisWeek == 1)
    }

    // MARK: - Action closures

    @Test("Injected action closures fire with the right payload")
    func actionClosures() async {
        let model = StatsViewModel(repository: InMemorySessionRepository())
        var reviewed = false
        var practicedTopic: String?
        var practicedMissed: String?
        model.onReviewWeakAreas = { reviewed = true }
        model.onPracticeTopic = { practicedTopic = $0 }
        model.onPracticeMissed = { practicedMissed = $0 }

        model.onReviewWeakAreas?()
        model.onPracticeTopic?("Networking")
        model.onPracticeMissed?("Q1")

        #expect(reviewed)
        #expect(practicedTopic == "Networking")
        #expect(practicedMissed == "Q1")
    }
}

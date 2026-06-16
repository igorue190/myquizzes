//
//  Results.swift
//  CoreModels
//
//  The scored outcome of a session. Produced by the QuizEngine, persisted by
//  the Statistics/Persistence layers, and rendered by ResultsFeature.
//

import Foundation

/// One question's outcome within a finished session.
public struct QuestionAttempt: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: Int { questionID }
    public let questionID: Int
    public let selectedChoiceIDs: Set<Int>
    public let correctChoiceIDs: Set<Int>
    public let isCorrect: Bool
    public let timeSpent: TimeInterval
    /// The question prompt, stored so statistics can surface most-missed
    /// questions across sessions by their text (a stable cross-file identity).
    public let prompt: String?

    public init(
        questionID: Int,
        selectedChoiceIDs: Set<Int>,
        correctChoiceIDs: Set<Int>,
        isCorrect: Bool,
        timeSpent: TimeInterval = 0,
        prompt: String? = nil
    ) {
        self.questionID = questionID
        self.selectedChoiceIDs = selectedChoiceIDs
        self.correctChoiceIDs = correctChoiceIDs
        self.isCorrect = isCorrect
        self.timeSpent = timeSpent
        self.prompt = prompt
    }
}

/// Accuracy for one tag/topic, used for the per-topic breakdown on the result
/// screen and as the raw input to the Statistics package.
public struct TopicScore: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: String { topic }
    public let topic: String
    public let correct: Int
    public let total: Int

    public init(topic: String, correct: Int, total: Int) {
        self.topic = topic
        self.correct = correct
        self.total = total
    }

    public var accuracy: Double {
        total == 0 ? 0 : Double(correct) / Double(total)
    }
}

/// The final, scored result of a session.
public struct SessionResult: Sendable, Equatable, Codable, Hashable {
    public let mode: SessionMode
    public let attempts: [QuestionAttempt]
    public let passThreshold: Int
    public let duration: TimeInterval
    public let topicBreakdown: [TopicScore]

    public init(
        mode: SessionMode,
        attempts: [QuestionAttempt],
        passThreshold: Int,
        duration: TimeInterval = 0,
        topicBreakdown: [TopicScore] = []
    ) {
        self.mode = mode
        self.attempts = attempts
        self.passThreshold = passThreshold
        self.duration = duration
        self.topicBreakdown = topicBreakdown
    }

    public var totalQuestions: Int { attempts.count }
    public var correctCount: Int { attempts.filter(\.isCorrect).count }

    /// 0...100, rounded for display by the caller.
    public var percentage: Double {
        totalQuestions == 0 ? 0 : Double(correctCount) / Double(totalQuestions) * 100
    }

    public var passed: Bool { percentage >= Double(passThreshold) }
}

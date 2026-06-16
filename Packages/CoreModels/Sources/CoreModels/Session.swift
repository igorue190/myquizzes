//
//  Session.swift
//  CoreModels
//
//  Configuration value types for a quiz session. The engine is pure and
//  deterministic given a seed, so `SessionConfig` carries the seed used to
//  shuffle and subset — reproducible sessions and reproducible tests.
//

import Foundation

/// Training (immediate feedback) vs. Exam (timed, feedback at the end).
public enum SessionMode: String, Sendable, Codable, Hashable, CaseIterable {
    case training
    case exam
}

/// Everything the user picks on the session-setup screen.
public struct SessionConfig: Sendable, Equatable, Codable, Hashable {
    public var mode: SessionMode
    /// nil = use every question in scope; otherwise take a seeded random subset.
    public var questionCount: Int?
    public var shuffleQuestions: Bool
    public var shuffleAnswers: Bool
    /// Percentage (0...100) required to pass.
    public var passThreshold: Int
    /// Exam only; nil in Training.
    public var timeLimit: TimeInterval?
    /// Seed for deterministic selection/shuffling.
    public var seed: UInt64

    public init(
        mode: SessionMode,
        questionCount: Int? = nil,
        shuffleQuestions: Bool = false,
        shuffleAnswers: Bool = false,
        passThreshold: Int = 70,
        timeLimit: TimeInterval? = nil,
        seed: UInt64 = 0
    ) {
        self.mode = mode
        self.questionCount = questionCount
        self.shuffleQuestions = shuffleQuestions
        self.shuffleAnswers = shuffleAnswers
        self.passThreshold = passThreshold
        self.timeLimit = timeLimit
        self.seed = seed
    }
}

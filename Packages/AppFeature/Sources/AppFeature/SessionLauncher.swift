//
//  SessionLauncher.swift
//  AppFeature
//
//  A tiny composition-root helper that builds a configured Training session from a
//  ready-made question pool. Both the Practice tab's "Review weak areas" button and
//  the Stats tab's review / topic / missed-question shortcuts assemble a pool and
//  hand it here, so the session wiring (config, haptics, AI explanation hooks, and
//  the save-on-finish closure) lives in exactly one place.
//

import Foundation
import CoreModels
import QuizFeature

@MainActor
enum SessionLauncher {
    /// Build a Training session over an explicit pool, wired to persist its result
    /// under `scope` and to use the injected AI-explanation hooks. The pool is taken
    /// as-is (callers do any capping); ids must already be unique.
    static func reviewSession(
        questions: [Question],
        scope: String,
        passThreshold: Int,
        hapticsEnabled: Bool,
        onExplain: ((ExplanationRequest) async throws -> Explanation)?,
        onCached: ((ExplanationRequest) async -> Explanation?)?,
        repository: any SessionRepository
    ) -> QuizSessionViewModel {
        let config = SessionConfig(
            mode: .training,
            questionCount: nil,
            shuffleAnswers: true,
            passThreshold: passThreshold,
            timeLimit: nil,
            seed: UInt64(Date().timeIntervalSince1970)
        )
        let model = QuizSessionViewModel.make(fromQuestions: questions, config: config)
        model.hapticsEnabled = hapticsEnabled
        model.onExplain = onExplain
        model.onCachedExplanation = onCached
        model.onFinish = { result in
            Task { try? await repository.save(SessionRecord(scopeLabel: scope, result: result)) }
        }
        return model
    }
}

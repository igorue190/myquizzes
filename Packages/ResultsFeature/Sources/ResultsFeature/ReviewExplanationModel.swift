//
//  ReviewExplanationModel.swift
//  ResultsFeature
//
//  The one stateful object behind the "Ask AI" buttons in the History review.
//  It owns per-question explanation state and forwards requests to an injected
//  `ExplanationService` closure (the feature stays free of any network/AI
//  dependency — AppFeature wires the concrete service in). One model per
//  SessionSummaryView; keyed by question id so each card tracks its own request.
//

import Foundation
import Observation
import CoreModels

/// The lifecycle of one question's explanation request.
enum ExplanationPhase: Equatable {
    case idle
    case loading
    case loaded(Explanation)
    case failed(String)
}

@MainActor
@Observable
final class ReviewExplanationModel {
    /// The injected generation call. nil ⇒ live generation is off (no "Ask AI").
    @ObservationIgnored
    var onExplain: ((ExplanationRequest) async throws -> Explanation)?

    /// Injected local cache lookup. When set, a previously generated explanation is
    /// shown instantly and offline without a network call. nil ⇒ no cached display.
    @ObservationIgnored
    var onCached: ((ExplanationRequest) async -> Explanation?)?

    /// Per-question state, keyed by `QuestionAttempt.id`.
    private(set) var phases: [Int: ExplanationPhase] = [:]

    /// Whether live generation (the "Ask AI"/"Regenerate" buttons) is available.
    var isEnabled: Bool { onExplain != nil }

    /// Whether the AI block should appear at all — generation or a cached result.
    var isVisible: Bool { onExplain != nil || onCached != nil }

    func phase(for id: Int) -> ExplanationPhase { phases[id] ?? .idle }

    /// Show a cached explanation for this question if one exists and nothing has
    /// loaded yet. Cheap and offline; call on appear of each reviewed question.
    func preload(_ request: ExplanationRequest, for id: Int) {
        guard let onCached, phase(for: id) == .idle else { return }
        Task {
            if phase(for: id) == .idle, let cached = await onCached(request) {
                phases[id] = .loaded(cached)
            }
        }
    }

    /// Fire a request for one question; results land back in `phases[id]`.
    func request(_ request: ExplanationRequest, for id: Int) {
        guard let onExplain else { return }
        phases[id] = .loading
        Task {
            do {
                phases[id] = .loaded(try await onExplain(request))
            } catch {
                phases[id] = .failed(Self.message(for: error))
            }
        }
    }

    static func message(for error: any Error) -> String {
        switch error as? ExplanationError {
        case .notConfigured:
            return "AI explanations aren't set up. Add your API key in Profile."
        case .network:
            return "Couldn't reach the AI service. Check your connection."
        case .api(let reason):
            return reason
        case .decoding, .none:
            return "The AI response couldn't be read. Try again."
        }
    }
}

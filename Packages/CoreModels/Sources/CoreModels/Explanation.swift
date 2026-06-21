//
//  Explanation.swift
//  CoreModels
//
//  The AI-explanation boundary: value types for asking an external model to
//  explain a missed question, and the `ExplanationService` protocol that the
//  feature layer talks to. Like the repository protocols, this lives in
//  CoreModels so features depend only on the abstraction; a concrete
//  Claude-backed actor lives in the `AIExplanation` package and is injected at
//  the AppFeature composition root. The optional, opt-in nature (a cloud call
//  with the user's own key) is a product decision documented in CLAUDE.md.
//

import Foundation

// MARK: - Request

/// Everything the model needs to explain why an answer was wrong. Built from a
/// persisted `QuestionAttempt` (History review) or a live `Question` + selection
/// (the quiz runner). A pure value type so it crosses the actor boundary freely.
public struct ExplanationRequest: Sendable, Equatable, Codable, Hashable {
    public let prompt: String
    public let choices: [AttemptChoice]
    public let selectedChoiceIDs: Set<Int>
    public let correctChoiceIDs: Set<Int>
    /// The author-provided explanation from the Markdown, if any — passed as
    /// context so the model can expand on it rather than contradict it.
    public let existingExplanation: String?
    /// The language the explanation should be written in (e.g. `"Russian"`). For a
    /// translation quiz this is the learner's native language, so the explanation
    /// lands in the language they understand best rather than the answer's
    /// language. When nil the model explains in the same language as the question
    /// (the default for ordinary quizzes).
    public let explanationLanguage: String?

    public init(
        prompt: String,
        choices: [AttemptChoice],
        selectedChoiceIDs: Set<Int>,
        correctChoiceIDs: Set<Int>,
        existingExplanation: String? = nil,
        explanationLanguage: String? = nil
    ) {
        self.prompt = prompt
        self.choices = choices
        self.selectedChoiceIDs = selectedChoiceIDs
        self.correctChoiceIDs = correctChoiceIDs
        self.existingExplanation = existingExplanation
        self.explanationLanguage = explanationLanguage
    }
}

// MARK: - Model choice

/// Which Claude model answers explanation requests. The raw value is the exact
/// Anthropic model id sent on the wire; the UI enumerates the cases in settings.
public enum AIModel: String, Sendable, Codable, CaseIterable, Hashable {
    case opus = "claude-opus-4-8"
    case sonnet = "claude-sonnet-4-6"
    case haiku = "claude-haiku-4-5"

    /// Shown in the Profile picker — names the model and its cost/quality niche.
    public var displayName: String {
        switch self {
        case .opus:   "Opus 4.8 — best, priciest"
        case .sonnet: "Sonnet 4.6 — balanced"
        case .haiku:  "Haiku 4.5 — cheapest"
        }
    }
}

// MARK: - Response

/// A reference the model cited. Surfaced in the UI with an "AI-generated, verify"
/// caveat — model-supplied URLs are not guaranteed correct.
public struct Source: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: String { url }
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// The model's explanation of a missed question.
public struct Explanation: Sendable, Equatable, Codable, Hashable {
    public let text: String
    public let sources: [Source]

    public init(text: String, sources: [Source] = []) {
        self.text = text
        self.sources = sources
    }
}

// MARK: - Caching

public extension ExplanationRequest {
    /// A stable, content-derived key for caching the generated explanation. Keyed
    /// on the question *identity* (prompt + choices + which are correct), NOT the
    /// user's selection, so the same question shares one cached explanation across
    /// sessions and replays. Deterministic FNV-1a (no CryptoKit — CoreModels stays
    /// Foundation-only).
    var cacheKey: String {
        var canonical = prompt + "\n"
        for choice in choices.sorted(by: { $0.id < $1.id }) {
            canonical += "\(choice.id)|\(choice.isCorrect ? 1 : 0)|\(choice.text)\n"
        }
        canonical += "correct:" + correctChoiceIDs.sorted().map(String.init).joined(separator: ",")
        return Self.fnv1a(canonical)
    }

    private static func fnv1a(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// A local store of generated explanations so review is instant and works offline
/// (the local-first promise). Declared here like the repository protocols; the
/// concrete SwiftData `ModelActor` lives in `Persistence`, with the `InMemory`
/// double below for previews/tests. Keyed by `ExplanationRequest.cacheKey`.
public protocol ExplanationCache: Sendable {
    /// The cached explanation for a question, or nil if none is stored.
    func explanation(forKey key: String) async -> Explanation?
    /// Store (or replace) the explanation for a question.
    func store(_ explanation: Explanation, forKey key: String) async
    /// Remove every cached explanation.
    func clear() async
}

/// An in-memory `ExplanationCache` for previews and tests.
public actor InMemoryExplanationCache: ExplanationCache {
    private var storage: [String: Explanation]

    public init(_ seed: [String: Explanation] = [:]) { self.storage = seed }

    public func explanation(forKey key: String) -> Explanation? { storage[key] }
    public func store(_ explanation: Explanation, forKey key: String) { storage[key] = explanation }
    public func clear() { storage.removeAll() }
}

// MARK: - Service boundary

/// What can go wrong producing an explanation. Surfaced to the UI as a friendly
/// message; never thrown for "feature disabled" (the caller hides the button then).
public enum ExplanationError: Error, Sendable, Equatable {
    /// No API key configured (or the feature is off). The UI should hide the CTA.
    case notConfigured
    /// A transport-level failure (offline, timeout).
    case network
    /// The response wasn't the structured shape we asked for.
    case decoding
    /// The API returned an error payload; the string is a human-readable reason.
    case api(String)
}

/// The abstraction features depend on. `Sendable` + `async throws`, mirroring the
/// repository protocols. Concrete implementations: `InMemoryExplanationService`
/// (here, for previews/tests) and `ClaudeExplanationService` (in `AIExplanation`).
public protocol ExplanationService: Sendable {
    func explain(_ request: ExplanationRequest) async throws -> Explanation
}

// MARK: - API key storage

/// Stores the user's API key for the AI feature. Declared here so the feature
/// layer (Profile settings) depends only on this abstraction; the concrete
/// Keychain-backed store lives in `AIExplanation` and is injected at the root.
/// Read-presence + write only — features never read the secret back.
public protocol APIKeyStore: Sendable {
    /// Whether a key is currently stored.
    var hasKey: Bool { get }
    /// Save (or, with an empty string, clear) the key.
    func setKey(_ key: String)
    /// Remove the stored key.
    func clearKey()
}

/// An in-memory `APIKeyStore` for previews and tests (no Keychain access).
public final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    public init(key: String? = nil) { self.key = key }

    public var hasKey: Bool {
        lock.lock(); defer { lock.unlock() }
        return !(key ?? "").isEmpty
    }
    public func setKey(_ key: String) {
        lock.lock(); defer { lock.unlock() }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = trimmed.isEmpty ? nil : trimmed
    }
    public func clearKey() {
        lock.lock(); defer { lock.unlock() }
        key = nil
    }
}

/// A dependency-free `ExplanationService` returning a fixed explanation. Used by
/// SwiftUI previews and tests so the feature layer is exercisable without network.
public actor InMemoryExplanationService: ExplanationService {
    private let canned: Explanation

    public init(canned: Explanation = Explanation(
        text: "The correct answer is the one that best matches the question. Review the highlighted option and the explanation below.",
        sources: []
    )) {
        self.canned = canned
    }

    public func explain(_ request: ExplanationRequest) async throws -> Explanation {
        canned
    }
}

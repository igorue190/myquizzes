//
//  Profile.swift
//  CoreModels
//
//  The local profile (no auth, no network — plan §4.1) and its repository
//  boundary. One active profile in v1; the repository shape allows more later.
//

import Foundation

/// Which visual identity the app uses. Maps to a DesignSystem `Theme` in the UI
/// layer (CoreModels stays free of SwiftUI).
public enum ThemeID: String, Sendable, Codable, CaseIterable, Hashable {
    case standard, aurora, violet

    public var displayName: String {
        switch self {
        case .standard: "Indigo"
        case .aurora:   "Aurora"
        case .violet:   "Violet (Light)"
        }
    }
}

public struct Profile: Sendable, Equatable, Codable, Hashable {
    public var displayName: String
    public var avatarSymbol: String          // an SF Symbol name (used when no photo)
    public var avatarImageData: Data?        // a user-supplied photo; nil = use the symbol
    public var themeID: ThemeID
    public var hapticsEnabled: Bool

    /// Opt-in: show the "Ask AI" button on missed questions. Off by default — it
    /// enables a cloud call (to Anthropic) using the user's own API key, which is
    /// a deliberate departure from the app's offline default. The key itself is
    /// stored in the Keychain, never here (this struct is exported in backups).
    public var aiExplanationsEnabled: Bool

    /// Which Claude model answers "Ask AI" requests. Defaults to the most capable
    /// Opus; the user can pick a cheaper model in Profile.
    public var aiModel: AIModel

    /// Whether the vocabulary feature (flashcards + translation quizzes, and its
    /// AI generation) is available. On by default; users who only want quizzes can
    /// turn it off in Settings ▸ Features to declutter the app. Toggled feature
    /// flags like this live here so they ride the profile's load/save/back-up path.
    public var vocabularyEnabled: Bool

    // Default session settings used when starting a quiz.
    public var defaultPassThreshold: Int     // percent
    public var defaultQuestionCount: Int?    // nil = all in scope
    public var defaultTimeLimit: TimeInterval?  // exam clock; nil = untimed

    public init(
        displayName: String = "Learner",
        avatarSymbol: String = "person.crop.circle.fill",
        avatarImageData: Data? = nil,
        themeID: ThemeID = .standard,
        hapticsEnabled: Bool = true,
        aiExplanationsEnabled: Bool = false,
        aiModel: AIModel = .opus,
        vocabularyEnabled: Bool = true,
        defaultPassThreshold: Int = 70,
        defaultQuestionCount: Int? = nil,
        defaultTimeLimit: TimeInterval? = 600
    ) {
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.avatarImageData = avatarImageData
        self.themeID = themeID
        self.hapticsEnabled = hapticsEnabled
        self.aiExplanationsEnabled = aiExplanationsEnabled
        self.aiModel = aiModel
        self.vocabularyEnabled = vocabularyEnabled
        self.defaultPassThreshold = defaultPassThreshold
        self.defaultQuestionCount = defaultQuestionCount
        self.defaultTimeLimit = defaultTimeLimit
    }

    // Custom decoding so profiles saved before `aiExplanationsEnabled` existed
    // still load (the new key defaults to false). Encoding stays synthesized.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarSymbol = try c.decode(String.self, forKey: .avatarSymbol)
        avatarImageData = try c.decodeIfPresent(Data.self, forKey: .avatarImageData)
        themeID = try c.decode(ThemeID.self, forKey: .themeID)
        hapticsEnabled = try c.decode(Bool.self, forKey: .hapticsEnabled)
        aiExplanationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .aiExplanationsEnabled) ?? false
        aiModel = try c.decodeIfPresent(AIModel.self, forKey: .aiModel) ?? .opus
        vocabularyEnabled = try c.decodeIfPresent(Bool.self, forKey: .vocabularyEnabled) ?? true
        defaultPassThreshold = try c.decode(Int.self, forKey: .defaultPassThreshold)
        defaultQuestionCount = try c.decodeIfPresent(Int.self, forKey: .defaultQuestionCount)
        defaultTimeLimit = try c.decodeIfPresent(TimeInterval.self, forKey: .defaultTimeLimit)
    }

    /// True when the user has chosen a photo (vs. the default SF Symbol avatar).
    public var hasPhoto: Bool { avatarImageData != nil }

    public static let `default` = Profile()

    /// SF Symbols offered in the avatar picker.
    public static let avatarOptions = [
        "person.crop.circle.fill", "graduationcap.fill", "brain.head.profile",
        "book.fill", "star.fill", "bolt.fill", "leaf.fill", "flame.fill"
    ]
}

/// The persistence boundary for the active profile.
public protocol ProfileRepository: Sendable {
    func load() async throws -> Profile
    func save(_ profile: Profile) async throws
}

public actor InMemoryProfileRepository: ProfileRepository {
    private var profile: Profile

    public init(profile: Profile = .default) {
        self.profile = profile
    }

    public func load() async throws -> Profile { profile }
    public func save(_ profile: Profile) async throws { self.profile = profile }
}

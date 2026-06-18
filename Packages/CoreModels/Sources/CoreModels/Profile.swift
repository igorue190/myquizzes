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
        defaultPassThreshold: Int = 70,
        defaultQuestionCount: Int? = nil,
        defaultTimeLimit: TimeInterval? = 600
    ) {
        self.displayName = displayName
        self.avatarSymbol = avatarSymbol
        self.avatarImageData = avatarImageData
        self.themeID = themeID
        self.hapticsEnabled = hapticsEnabled
        self.defaultPassThreshold = defaultPassThreshold
        self.defaultQuestionCount = defaultQuestionCount
        self.defaultTimeLimit = defaultTimeLimit
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

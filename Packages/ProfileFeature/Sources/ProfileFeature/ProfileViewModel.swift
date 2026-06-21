//
//  ProfileViewModel.swift
//  ProfileFeature
//
//  Holds the editable profile and persists changes. Also owns the "data
//  management" actions (export / delete history) via a SessionRepository.
//

import Foundation
import Observation
import UIKit
import CoreModels
import DesignSystem

@MainActor
@Observable
public final class ProfileViewModel {
    private let repository: any ProfileRepository
    private let sessionRepository: any SessionRepository
    private let libraryRepository: any LibraryRepository
    private let apiKeyStore: any APIKeyStore
    /// Local cache of AI explanations; nil in previews/tests. Lets the Data screen
    /// offer a "clear cache" action.
    private let explanationCache: (any ExplanationCache)?

    public var profile: Profile = .default

    /// A short summary of the most recent successful restore, for the result alert.
    public private(set) var lastRestoreSummary: String?

    /// Whether an Anthropic API key is stored (drives the settings UI). Kept in
    /// sync via `setAPIKey`/`clearAPIKey`; the secret itself is never held here.
    public private(set) var aiKeyPresent: Bool = false

    public init(
        repository: any ProfileRepository,
        sessionRepository: any SessionRepository,
        libraryRepository: any LibraryRepository,
        apiKeyStore: any APIKeyStore = InMemoryAPIKeyStore(),
        explanationCache: (any ExplanationCache)? = nil
    ) {
        self.repository = repository
        self.sessionRepository = sessionRepository
        self.libraryRepository = libraryRepository
        self.apiKeyStore = apiKeyStore
        self.explanationCache = explanationCache
        self.aiKeyPresent = apiKeyStore.hasKey
    }

    /// The DesignSystem theme for the current profile (so the app can re-tint).
    public var theme: Theme { profile.themeID.designTheme }

    public func load() async {
        profile = (try? await repository.load()) ?? .default
    }

    public func persist() async {
        try? await repository.save(profile)
    }

    // MARK: - AI explanations setting

    /// Toggle the opt-in AI feature and persist. Turning it on without a key is
    /// allowed (the UI then prompts for one); the CTA stays hidden until a key
    /// exists in the app's runner/results screens.
    public func setAIExplanationsEnabled(_ enabled: Bool) async {
        profile.aiExplanationsEnabled = enabled
        await persist()
    }

    /// Store the user's Anthropic API key in the Keychain and refresh presence.
    public func setAPIKey(_ key: String) {
        apiKeyStore.setKey(key)
        aiKeyPresent = apiKeyStore.hasKey
    }

    /// Remove the stored key.
    public func clearAPIKey() {
        apiKeyStore.clearKey()
        aiKeyPresent = apiKeyStore.hasKey
    }

    public func clearHistory() async {
        try? await sessionRepository.deleteAll()
    }

    /// Remove all cached AI explanations (they regenerate on demand).
    public func clearExplanationCache() async {
        await explanationCache?.clear()
    }

    /// Store a user-picked photo as the avatar (downscaled so the persisted
    /// profile stays small). Pass `nil` to clear it and fall back to the symbol.
    public func setPhoto(_ data: Data?) {
        guard let data else {
            profile.avatarImageData = nil
            return
        }
        profile.avatarImageData = Self.downscaledJPEG(from: data) ?? data
    }

    /// Resize to fit a square box and re-encode as JPEG to bound the stored size.
    private static func downscaledJPEG(from data: Data, maxDimension: CGFloat = 512) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
    }

    // MARK: - Backup / Restore

    /// Build a full backup (library + history + profile), write it to a temporary
    /// JSON file, and return its URL for a ShareLink. Returns nil on failure.
    public func exportBackup() async -> URL? {
        let service = BackupService(
            library: libraryRepository, sessions: sessionRepository, profiles: repository
        )
        guard let document = try? await service.export() else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(document) else { return nil }

        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Markwise-Backup-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Decode a backup file the user picked and restore it (additive). Returns
    /// false if the file can't be read or isn't a valid Markwise backup.
    public func restoreBackup(from url: URL) async -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(BackupDocument.self, from: data) else { return false }

        let service = BackupService(
            library: libraryRepository, sessions: sessionRepository, profiles: repository
        )
        do {
            try await service.restore(document)
            lastRestoreSummary = "Restored \(document.summaryLine)."
            await load()        // pick up the restored profile (theme, name, photo)
            return true
        } catch {
            return false
        }
    }

    /// A Markdown report of session history, for the export sheet / ShareLink.
    public func exportHistory() async -> String {
        let records = ((try? await sessionRepository.allRecords()) ?? []).reversed()
        var lines = ["# Markwise — Session History", ""]
        if records.isEmpty {
            lines.append("_No sessions yet._")
        } else {
            for record in records {
                let date = record.finishedAt.formatted(date: .abbreviated, time: .shortened)
                let scope = record.scopeLabel ?? "Quiz"
                let verdict = record.passed ? "pass" : "fail"
                lines.append("- \(date) — **\(scope)**: \(Int(record.percentage.rounded()))% (\(verdict))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

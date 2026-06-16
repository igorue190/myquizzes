//
//  ProfileViewModel.swift
//  ProfileFeature
//
//  Holds the editable profile and persists changes. Also owns the "data
//  management" actions (export / delete history) via a SessionRepository.
//

import Foundation
import Observation
import CoreModels
import DesignSystem

@MainActor
@Observable
public final class ProfileViewModel {
    private let repository: any ProfileRepository
    private let sessionRepository: any SessionRepository

    public var profile: Profile = .default

    public init(repository: any ProfileRepository, sessionRepository: any SessionRepository) {
        self.repository = repository
        self.sessionRepository = sessionRepository
    }

    /// The DesignSystem theme for the current profile (so the app can re-tint).
    public var theme: Theme { profile.themeID.designTheme }

    public func load() async {
        profile = (try? await repository.load()) ?? .default
    }

    public func persist() async {
        try? await repository.save(profile)
    }

    public func clearHistory() async {
        try? await sessionRepository.deleteAll()
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

//
//  SnapshotSmokeTests.swift
//  DesignSystemTests
//
//  Lightweight "does it render" smoke tests: each component is rendered to an
//  image via ImageRenderer and checked for non-empty output. This catches
//  layout/crash regressions without a snapshot-library dependency or baseline
//  images (those are the production upgrade — pointfree's swift-snapshot-testing).
//

import Testing
import SwiftUI
@testable import DesignSystem

@MainActor
@Suite("DesignSystem renders")
struct SnapshotSmokeTests {

    private func renders(_ view: some View) -> Bool {
        let renderer = ImageRenderer(
            content: view.frame(width: 320, height: 220).markwiseTheme(.standard)
        )
        renderer.scale = 2
        guard let image = renderer.uiImage else { return false }
        return image.size.width > 0 && image.size.height > 0
    }

    @Test("ChoiceRow renders in each state")
    func choiceRow() {
        for state in [ChoiceState.unselected, .selected, .correct, .incorrect, .missedCorrect] {
            #expect(renders(ChoiceRow(label: "**IaaS**", state: state) {}))
        }
    }

    @Test("QuestionCard renders") func questionCard() {
        #expect(renders(QuestionCard(prompt: "Which model?", progressLabel: "1 of 5") {
            ChoiceRow(label: "A", state: .selected) {}
            ChoiceRow(label: "B", state: .unselected) {}
        }))
    }

    @Test("ScoreRing renders") func scoreRing() {
        #expect(renders(ScoreRing(progress: 0.84, passed: true, caption: "42 / 50")))
    }

    @Test("TimerHUD renders (warning state too)") func timer() {
        #expect(renders(TimerHUD(remaining: 24, total: 600)))
        #expect(renders(TimerHUD(remaining: 600, total: 600)))
    }

    @Test("DiagnosticBanner renders each severity") func banner() {
        for severity in [DiagnosticBanner.Severity.info, .warning, .error] {
            #expect(renders(DiagnosticBanner(severity: severity, message: "Question 7 needs a fix")))
        }
    }

    @Test("EmptyStateView renders") func emptyState() {
        #expect(renders(EmptyStateView(icon: "tray", title: "Nothing yet", message: "Import a file.")))
    }

    @Test("TagChip renders for difficulty") func tagChip() {
        #expect(renders(TagChip("Beginner", kind: .difficulty(.beginner))))
    }
}

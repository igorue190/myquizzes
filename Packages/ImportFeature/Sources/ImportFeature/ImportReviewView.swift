//
//  ImportReviewView.swift
//  ImportFeature
//
//  The "parse summary → diagnostics → Add to library" review screen (plan §9.2,
//  screen 3). Shows the question count, any per-question diagnostics, and an
//  editable title. "Add" is disabled when nothing is usable.
//

import SwiftUI
import CoreModels
import MarkdownParser
import DesignSystem

public struct ImportReviewView: View {
    private let markdown: String
    private let quiz: ParsedQuiz
    private let onConfirm: (String) -> Void
    private let onCancel: () -> Void

    @State private var title: String

    public init(
        suggestedTitle: String,
        markdown: String,
        quiz: ParsedQuiz,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.markdown = markdown
        self.quiz = quiz
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: suggestedTitle)
    }

    /// Convenience that parses `markdown` itself (used for previews/deep-links).
    public init(
        suggestedTitle: String,
        markdown: String,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(
            suggestedTitle: suggestedTitle,
            markdown: markdown,
            quiz: MarkdownQuizParser().parse(markdown),
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    private var summary: ParseSummary { ParseSummary(quiz) }
    private var canAdd: Bool { !quiz.usableQuestions.isEmpty }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        GlassPanel {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Title").font(Typography.caption).foregroundStyle(.secondary)
                                TextField("Quiz title", text: $title)
                                    .font(Typography.headline)
                                    .textInputAutocapitalization(.words)
                            }
                        }

                        summaryCard

                        if quiz.diagnostics.isEmpty {
                            DiagnosticBanner(
                                severity: .info,
                                message: "No issues found. This quiz is ready to study."
                            )
                        } else {
                            ForEach(quiz.diagnostics) { diagnostic in
                                DiagnosticBanner(
                                    severity: bannerSeverity(diagnostic.severity),
                                    message: diagnostic.message
                                )
                            }
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Import quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onConfirm(title.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .disabled(!canAdd || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var summaryCard: some View {
        GlassCard {
            Label("Parse summary", systemImage: "doc.text.magnifyingglass")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                statRow("Questions", "\(summary.questionCount)")
                statRow("Usable", "\(quiz.usableQuestions.count)")
                if summary.warningCount > 0 {
                    statRow("Warnings", "\(summary.warningCount)", color: ColorTokens.warning)
                }
                if summary.errorCount > 0 {
                    statRow("Errors", "\(summary.errorCount)", color: ColorTokens.danger)
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(Typography.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(Typography.callout.weight(.semibold)).foregroundStyle(color)
        }
    }

    private func bannerSeverity(_ severity: Diagnostic.Severity) -> DiagnosticBanner.Severity {
        switch severity {
        case .info:    .info
        case .warning: .warning
        case .error:   .error
        }
    }
}

#Preview("Import review") {
    ImportReviewView(
        suggestedTitle: "AZ-900 Sample",
        markdown: """
        ## Which model gives the most control over the OS?
        <!-- type: single -->
        - [ ] SaaS
        - [x] IaaS

        ## Broken — no correct answer
        - [ ] A
        - [ ] B
        """,
        onConfirm: { _ in },
        onCancel: {}
    )
    .markwiseTheme(.standard)
}

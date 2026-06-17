//
//  SessionSummaryView.swift
//  ResultsFeature
//
//  A score report for one finished session: the pass/fail ring, the details
//  (when, what, mode), the per-topic breakdown, and — for sessions saved with
//  answer snapshots — a full per-question review (prompt, every option marked
//  correct/incorrect/chosen, and the explanation). Used as the History detail.
//

import SwiftUI
import Foundation
import CoreModels
import DesignSystem

public struct SessionSummaryView: View {
    private let record: SessionRecord

    public init(record: SessionRecord) {
        self.record = record
    }

    private var result: SessionResult { record.result }

    public var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.sm) {
                    ScoreRing(
                        progress: result.percentage / 100,
                        passed: result.passed,
                        caption: "\(result.correctCount) / \(result.totalQuestions) correct"
                    )
                    Text(result.passed ? "Passed" : "Keep practicing")
                        .font(Typography.title)
                        .foregroundStyle(result.passed ? ColorTokens.success : ColorTokens.danger)
                }
                .padding(.top, Spacing.lg)

                detailsCard

                if !result.topicBreakdown.isEmpty {
                    breakdownCard
                }

                if !reviewableAttempts.isEmpty {
                    reviewSection
                }
            }
            .padding(Spacing.lg)
        }
        .background(AppBackground())
        .navigationTitle(record.scopeLabel ?? "Result")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailsCard: some View {
        GlassCard {
            Label("Details", systemImage: "info.circle")
        } content: {
            VStack(spacing: Spacing.xs) {
                detailRow("Mode", record.mode == .exam ? "Exam" : "Training")
                detailRow("Date", record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                detailRow("Pass mark", "\(result.passThreshold)%")
            }
        }
    }

    private var breakdownCard: some View {
        GlassCard {
            Label("By topic", systemImage: "chart.bar.fill")
        } content: {
            VStack(spacing: Spacing.sm) {
                ForEach(result.topicBreakdown) { score in
                    HStack {
                        Text(score.topic).font(Typography.callout)
                        Spacer()
                        Text("\(score.correct)/\(score.total)")
                            .font(Typography.callout.weight(.semibold))
                            .foregroundStyle(score.accuracy >= 0.7 ? ColorTokens.success : ColorTokens.warning)
                    }
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Typography.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(Typography.callout.weight(.medium))
        }
    }

    // MARK: - Per-question review

    /// Attempts that carry an answer snapshot (older sessions have none).
    private var reviewableAttempts: [QuestionAttempt] {
        result.attempts.filter { !$0.choices.isEmpty }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label("Review", systemImage: "list.bullet.rectangle")
                .font(Typography.headline)
                .padding(.horizontal, Spacing.xs)

            ForEach(reviewableAttempts) { attempt in
                QuestionCard(
                    prompt: attempt.prompt ?? "Question",
                    badge: TagChip(
                        attempt.isCorrect ? "Correct" : "Incorrect",
                        kind: .semantic(attempt.isCorrect ? ColorTokens.success : ColorTokens.danger)
                    )
                ) {
                    ForEach(attempt.choices) { choice in
                        ChoiceRow(
                            label: choice.text,
                            state: state(of: choice, in: attempt),
                            style: style(for: attempt),
                            isEnabled: false
                        ) {}
                    }
                    if let explanation = attempt.explanation, !explanation.isEmpty {
                        MarkdownText(explanation)
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func style(for attempt: QuestionAttempt) -> ChoiceSelectionStyle {
        attempt.choices.filter(\.isCorrect).count > 1 ? .multiple : .single
    }

    private func state(of choice: AttemptChoice, in attempt: QuestionAttempt) -> ChoiceState {
        let selected = attempt.selectedChoiceIDs.contains(choice.id)
        switch (choice.isCorrect, selected) {
        case (true, true):   return .correct
        case (true, false):  return .missedCorrect
        case (false, true):  return .incorrect
        case (false, false): return .unselected
        }
    }
}

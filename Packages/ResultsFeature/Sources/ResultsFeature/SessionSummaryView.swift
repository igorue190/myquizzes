//
//  SessionSummaryView.swift
//  ResultsFeature
//
//  A score report for one finished session: the pass/fail ring, the details
//  (when, what, mode), and the per-topic breakdown. Used as the History detail.
//  (The just-finished per-question review lives in QuizFeature, which still has
//  the live questions.)
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
}

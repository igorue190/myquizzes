//
//  StatsView.swift
//  StatsFeature
//
//  The Stats tab: a summary, an accuracy-over-time chart (Swift Charts), and a
//  per-topic mastery list (weakest first). Driven entirely by StatsViewModel.
//

import SwiftUI
import Charts
import CoreModels
import Statistics
import DesignSystem

public struct StatsView: View {
    @State private var model: StatsViewModel

    public init(model: StatsViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            AppBackground()
            if model.overview.sessionCount == 0 {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No stats yet",
                    message: "Take a few quizzes and your mastery and trends will show up here."
                )
            } else {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        summary
                        trendCard
                        masteryCard
                        if !model.overview.mostMissed.isEmpty {
                            mostMissedCard
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
        .task { await model.load() }
    }

    // MARK: - Summary tiles

    private var summary: some View {
        HStack(spacing: Spacing.md) {
            statTile(value: "\(model.overview.sessionCount)", label: "Sessions")
            statTile(
                value: "\(Int((model.overview.overallAccuracy * 100).rounded()))%",
                label: "Accuracy"
            )
        }
    }

    private func statTile(value: String, label: String) -> some View {
        GlassPanel {
            VStack(spacing: Spacing.xxs) {
                Text(value).font(Typography.displayLarge)
                Text(label).font(Typography.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Trend chart

    private var trendCard: some View {
        GlassCard {
            Label("Accuracy over time", systemImage: "chart.xyaxis.line")
        } content: {
            Chart(model.overview.trend) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.percentage)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(ColorTokens.brand)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Score", point.percentage)
                )
                .foregroundStyle(point.passed ? ColorTokens.success : ColorTokens.danger)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .frame(height: 180)
        }
    }

    // MARK: - Topic mastery

    private var masteryCard: some View {
        GlassCard {
            Label("Mastery by topic", systemImage: "target")
        } content: {
            VStack(spacing: Spacing.md) {
                ForEach(model.overview.topics) { topic in
                    masteryRow(topic)
                }
            }
        }
    }

    private func masteryRow(_ topic: TopicMastery) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(topic.topic).font(Typography.callout)
                Spacer()
                TagChip(topic.level.label, kind: .semantic(color(for: topic.level)))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ColorTokens.hairline)
                    Capsule()
                        .fill(color(for: topic.level))
                        .frame(width: max(6, geo.size.width * topic.accuracy))
                }
            }
            .frame(height: 8)
            Text("\(topic.correct)/\(topic.total) correct")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var mostMissedCard: some View {
        GlassCard {
            Label("Most missed", systemImage: "exclamationmark.triangle.fill")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(model.overview.mostMissed) { question in
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        MarkdownText(question.prompt)
                            .font(Typography.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Missed \(question.misses) of \(question.attempts) · \(Int((question.missRate * 100).rounded()))%")
                            .font(Typography.caption)
                            .foregroundStyle(ColorTokens.danger)
                    }
                }
            }
        }
    }

    private func color(for level: MasteryLevel) -> Color {
        switch level {
        case .mastered:   ColorTokens.success
        case .proficient: ColorTokens.brand
        case .developing: ColorTokens.warning
        case .novice:     ColorTokens.danger
        }
    }
}

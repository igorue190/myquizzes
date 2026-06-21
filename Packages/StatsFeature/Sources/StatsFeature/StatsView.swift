//
//  StatsView.swift
//  StatsFeature
//
//  The Stats tab, reframed as a study coach rather than a passive dashboard. It
//  leads with what to do next (a spaced-review call to action and habit signals),
//  lets the user scope the numbers by quiz / mode / date, then shows the trend and
//  per-topic mastery — every weak spot tappable to launch practice. All logic is
//  in StatsViewModel + the Statistics package; this view only renders and forwards
//  intents through the model's injected action closures.
//

import SwiftUI
import CoreModels
import Statistics
import DesignSystem

public struct StatsView: View {
    @State private var model: StatsViewModel
    @State private var showClearConfirm = false
    @State private var showAllTopics = false

    public init(model: StatsViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            AppBackground()
            if model.records.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No stats yet",
                    message: "Take a few quizzes and your mastery and trends will show up here."
                )
            } else {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        if model.dueCount > 0, model.onReviewWeakAreas != nil {
                            upNextCard
                        }
                        habitStrip
                        scopeControls
                        if model.overview.sessionCount > 0 {
                            masteryCard
                            if !model.overview.mostMissed.isEmpty {
                                mostMissedCard
                            }
                        } else {
                            noMatchNote
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
        .toolbar {
            if !model.records.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) { showClearConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .tint(ColorTokens.danger)
                }
            }
        }
        .alert("Clear all stats?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) { Task { await model.clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes every saved session — stats and history. It can't be undone.")
        }
        .task { await model.load() }
    }

    // MARK: - Up next (spaced review CTA)

    private var upNextCard: some View {
        GlassCard {
            Label("Up next", systemImage: "sparkles")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("^[\(model.dueCount) question](inflect: true) due for review")
                    .font(Typography.body)
                Text("Re-quizzes what you miss most, in Training. Answer one correctly twice and it graduates out.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                Button {
                    model.onReviewWeakAreas?()
                } label: {
                    Label("Review now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary)
            }
        }
    }

    // MARK: - Habit strip

    private var habitStrip: some View {
        HStack(spacing: Spacing.md) {
            habitTile(
                value: "\(model.habits.studyStreakDays)",
                label: "day streak",
                systemImage: "flame.fill",
                tint: model.habits.studyStreakDays > 0 ? ColorTokens.warning : .secondary
            )
            habitTile(
                value: "\(model.habits.questionsAnswered)",
                label: "answered",
                systemImage: "checklist",
                tint: ColorTokens.brand
            )
            habitTile(
                value: "\(model.habits.sessionsThisWeek)",
                label: "this week",
                systemImage: "calendar",
                tint: ColorTokens.info
            )
        }
    }

    private func habitTile(value: String, label: String, systemImage: String, tint: Color) -> some View {
        GlassPanel(padding: Spacing.md) {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: systemImage).font(.title3).foregroundStyle(tint)
                Text(value).font(Typography.title)
                Text(label).font(Typography.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Scope controls

    @ViewBuilder private var scopeControls: some View {
        if model.availableScopes.count > 1 || model.availableModes.count > 1 {
            GlassPanel(padding: Spacing.md) {
                VStack(spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        if model.availableScopes.count > 1 {
                            Picker("Quiz", selection: scopeBinding) {
                                Text("All quizzes").tag(String?.none)
                                ForEach(model.availableScopes, id: \.self) { scope in
                                    Text(scope).tag(String?.some(scope))
                                }
                            }
                        }
                        if model.availableModes.count > 1 {
                            Picker("Mode", selection: modeBinding) {
                                Text("All modes").tag(SessionMode?.none)
                                ForEach(model.availableModes, id: \.self) { mode in
                                    Text(label(for: mode)).tag(SessionMode?.some(mode))
                                }
                            }
                        }
                        Spacer()
                    }
                    .pickerStyle(.menu)
                    .font(Typography.callout)

                    Picker("Range", selection: dateBinding) {
                        ForEach(StatsDateRange.allCases, id: \.self) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    private var noMatchNote: some View {
        GlassPanel {
            VStack(spacing: Spacing.xs) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title2).foregroundStyle(.secondary)
                Text("No sessions match these filters.")
                    .font(Typography.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Topic mastery

    private var masteryCard: some View {
        GlassCard {
            HStack {
                Label("Mastery by topic", systemImage: "target")
                Spacer()
                if model.overview.topics.count > shownTopics.count {
                    Button(showAllTopics ? "Show less" : "Show all") {
                        withAnimation(Motion.quick) { showAllTopics.toggle() }
                    }
                    .font(Typography.caption)
                }
            }
        } content: {
            VStack(spacing: Spacing.md) {
                ForEach(shownTopics) { topic in
                    masteryRow(topic)
                }
            }
        }
    }

    /// Weakest-first, hiding small-sample noise until the user asks for all.
    private var shownTopics: [TopicMastery] {
        showAllTopics ? model.overview.topics : model.overview.weakestTopics(limit: 5)
    }

    @ViewBuilder
    private func masteryRow(_ topic: TopicMastery) -> some View {
        let actionable = model.onPracticeTopic != nil
        Button {
            model.onPracticeTopic?(topic.topic)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text(topic.topic).font(Typography.callout)
                    Spacer()
                    TagChip(topic.level.label, kind: .semantic(color(for: topic.level)))
                    if actionable {
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actionable)
    }

    private var mostMissedCard: some View {
        GlassCard {
            Label("Most missed", systemImage: "exclamationmark.triangle.fill")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(model.overview.mostMissed) { question in
                    missedRow(question)
                }
            }
        }
    }

    @ViewBuilder
    private func missedRow(_ question: MissedQuestion) -> some View {
        let actionable = model.onPracticeMissed != nil
        Button {
            model.onPracticeMissed?(question.prompt)
        } label: {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    MarkdownText(question.prompt)
                        .font(Typography.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Missed \(question.misses) of \(question.attempts) · \(Int((question.missRate * 100).rounded()))%")
                        .font(Typography.caption)
                        .foregroundStyle(ColorTokens.danger)
                }
                if actionable {
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.top, Spacing.xxs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actionable)
    }

    // MARK: - Filter bindings (mutate the model only through its intents)

    private var scopeBinding: Binding<String?> {
        Binding(get: { model.selectedScope }, set: { model.setScope($0) })
    }
    private var modeBinding: Binding<SessionMode?> {
        Binding(get: { model.selectedMode }, set: { model.setMode($0) })
    }
    private var dateBinding: Binding<StatsDateRange> {
        Binding(get: { model.dateRange }, set: { model.setDateRange($0) })
    }

    // MARK: - Domain → DesignSystem mapping

    private func color(for level: MasteryLevel) -> Color {
        switch level {
        case .mastered:   ColorTokens.success
        case .proficient: ColorTokens.brand
        case .developing: ColorTokens.warning
        case .novice:     ColorTokens.danger
        }
    }

    private func label(for mode: SessionMode) -> String {
        switch mode {
        case .training: "Training"
        case .exam:     "Exam"
        }
    }
}

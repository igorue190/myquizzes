//
//  QuizRunnerView.swift
//  QuizFeature
//
//  The screen that runs a session. While in progress it shows the current
//  QuestionCard with tappable ChoiceRows (+ a timer/nav in Exam mode); once
//  submitted it shows the score + per-question review. Entirely driven by
//  QuizSessionViewModel — this view holds no quiz logic.
//

import SwiftUI
import CoreModels
import DesignSystem

public struct QuizRunnerView: View {
    @State private var model: QuizSessionViewModel
    @State private var showPalette = false

    public init(model: QuizSessionViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            AppBackground()
            if model.isFinished {
                ResultView(model: model)
            } else {
                runner
            }
        }
    }

    // MARK: - Answering

    private var runner: some View {
        VStack(spacing: Spacing.lg) {
            if model.mode == .exam {
                examBar
                    .padding(.horizontal, Spacing.lg)
            }

            ScrollView {
                if let question = model.current {
                    QuestionCard(
                        prompt: question.prompt,
                        progressLabel: model.mode == .training ? model.progressLabel : nil,
                        badge: model.badge(for: question)
                    ) {
                        ForEach(question.choices) { choice in
                            ChoiceRow(
                                label: choice.text,
                                state: model.choiceState(choice, in: question),
                                style: model.selectionStyle(for: question)
                            ) {
                                model.select(choice.id, in: question.id)
                            }
                        }
                    }
                    .padding(Spacing.lg)
                } else {
                    EmptyStateView(
                        icon: "questionmark.folder",
                        title: "No questions",
                        message: "This quiz has no usable questions yet."
                    )
                }
            }

            navigationBar
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.sm)
        }
        .sheet(isPresented: $showPalette) {
            QuestionPaletteView(model: model) { showPalette = false }
                .markwiseTheme(.standard)
        }
    }

    // Exam toolbar: countdown timer, question palette, and mark-for-review.
    private var examBar: some View {
        HStack(spacing: Spacing.md) {
            if model.hasTimer {
                TimerHUD(remaining: model.remaining, total: model.totalTime)
            }
            Text(model.progressLabel)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button { showPalette = true } label: {
                Image(systemName: "square.grid.3x3.fill")
            }
            .tint(ColorTokens.brand)
            Button { model.toggleMark() } label: {
                Image(systemName: markImageName)
            }
            .tint(ColorTokens.warning)
        }
    }

    @ViewBuilder
    private var navigationBar: some View {
        HStack(spacing: Spacing.md) {
            if !model.isFirst {
                Button("Back") { model.goToPrevious() }
                    .buttonStyle(.glassSecondary)
            }

            if model.isLast {
                Button("Submit") { model.submit() }
                    .buttonStyle(.glassPrimary)
            } else {
                Button("Next") { model.goToNext() }
                    .buttonStyle(.glassPrimary)
            }
        }
    }

    private var markImageName: String {
        model.isCurrentMarked ? "flag.fill" : "flag"
    }
}

// MARK: - Result

struct ResultView: View {
    let model: QuizSessionViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                if let result = model.result {
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
                    .padding(.top, Spacing.xl)

                    if !result.topicBreakdown.isEmpty {
                        topicBreakdown(result.topicBreakdown)
                    }

                    ForEach(reviewItems, id: \.question.id) { item in
                        QuestionCard(prompt: item.question.prompt) {
                            ForEach(item.question.choices) { choice in
                                ChoiceRow(
                                    label: choice.text,
                                    state: model.choiceState(choice, in: item.question),
                                    style: model.selectionStyle(for: item.question),
                                    isEnabled: false
                                ) {}
                            }
                            if let explanation = item.question.explanation {
                                MarkdownText(explanation)
                                    .font(Typography.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .onAppear { model.openReview() }
    }

    private func topicBreakdown(_ scores: [TopicScore]) -> some View {
        GlassCard {
            Label("By topic", systemImage: "chart.bar.fill")
        } content: {
            VStack(spacing: Spacing.sm) {
                ForEach(scores) { score in
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

    private var reviewItems: [(question: Question, attempt: QuestionAttempt)] {
        guard let result = model.result else { return [] }
        return result.attempts.compactMap { attempt in
            model.session.questions.first { $0.id == attempt.questionID }
                .map { (question: $0, attempt: attempt) }
        }
    }
}

#Preview("Quiz runner") {
    let markdown = """
    ## Which cloud service model gives the most control over the OS?
    <!-- type: single -->
    - [ ] SaaS
    - [ ] PaaS
    - [x] IaaS
    - [ ] FaaS

    > **Explanation:** IaaS exposes the VM and OS to the customer.

    ## Which are characteristics of elasticity? (Choose two.)
    <!-- type: multiple -->
    - [x] Scales out automatically
    - [x] Pay only for what you use
    - [ ] Fixed capacity
    """
    let model = QuizSessionViewModel.make(
        fromMarkdown: markdown,
        config: SessionConfig(mode: .training, passThreshold: 70, seed: 1)
    )
    return QuizRunnerView(model: model)
        .markwiseTheme(.standard)
}

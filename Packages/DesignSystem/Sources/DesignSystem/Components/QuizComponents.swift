//
//  QuizComponents.swift
//  DesignSystem
//
//  The interaction surfaces of the quiz runner. State is driven entirely by the
//  caller (the QuizEngine via a view model) — these views are pure and dumb.
//

import SwiftUI

// MARK: - Markdown text

/// Renders inline Markdown (bold, italic, code, links) from a dynamic string.
/// Used for prompts and answer labels so quiz content keeps its formatting.
public struct MarkdownText: View {
    private let raw: String
    public init(_ raw: String) { self.raw = raw }

    public var body: some View { Text(attributed) }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }
}

// MARK: - Tag chip

/// A small pill for tags and difficulty badges.
public struct TagChip: View {
    public enum Kind: Sendable, Equatable {
        case neutral
        case difficulty(Difficulty)
        case semantic(Color)
    }
    public enum Difficulty: String, Sendable, CaseIterable {
        case beginner, intermediate, advanced
    }

    private let text: String
    private let kind: Kind

    public init(_ text: String, kind: Kind = .neutral) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        HStack(spacing: Spacing.xxs) {
            if let dot = dotColor {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            Text(text)
                .font(Typography.caption.weight(.semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs)
        .glassCapsule(role)
    }

    private var role: GlassRole {
        switch kind {
        case .neutral:                 .regular
        case .semantic(let c):         .tinted(c)
        case .difficulty(let d):       .tinted(d.color)
        }
    }

    /// The label text uses the system label color so it stays legible on the
    /// translucent tinted capsule (the earlier same-color-as-tint text read as a
    /// blank color blob). The semantic color is carried by a small leading dot.
    private var foreground: Color {
        switch kind {
        case .neutral:    .secondary
        case .semantic, .difficulty: .primary
        }
    }

    private var dotColor: Color? {
        switch kind {
        case .neutral:           nil
        case .semantic(let c):   c
        case .difficulty(let d): d.color
        }
    }
}

extension TagChip.Difficulty {
    var color: Color {
        switch self {
        case .beginner:     ColorTokens.success
        case .intermediate: ColorTokens.warning
        case .advanced:     ColorTokens.danger
        }
    }
}

// MARK: - Choice row

/// Visual state of an answer row. The first two are answering states; the last
/// three are review states shown after a session ends.
public enum ChoiceState: Sendable, Equatable {
    case unselected
    case selected
    case correct        // user picked it and it was right
    case incorrect      // user picked it and it was wrong
    case missedCorrect  // correct answer the user did NOT pick
}

public enum ChoiceSelectionStyle: Sendable { case single, multiple }

/// A single selectable answer. Single-choice uses a circular indicator,
/// multiple-choice a square one — matching Microsoft-exam conventions.
public struct ChoiceRow: View {
    private let label: String
    private let state: ChoiceState
    private let style: ChoiceSelectionStyle
    private let isEnabled: Bool
    private let onTap: () -> Void

    public init(
        label: String,
        state: ChoiceState,
        style: ChoiceSelectionStyle = .single,
        isEnabled: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.label = label
        self.state = state
        self.style = style
        self.isEnabled = isEnabled
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.md) {
                indicator
                MarkdownText(label)
                    .font(Typography.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                stateIcon
            }
            .padding(Spacing.md)
            .frame(minHeight: 44, alignment: .center)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .glassSurface(glassRole, cornerRadius: Radius.md, interactive: isInteractive)
        .overlay {
            // In review, outline the row in its result color instead of tinting
            // the whole surface — keeps the answer text and indicators legible.
            if let reviewColor {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(reviewColor, lineWidth: 2)
            }
        }
        .animation(Motion.snappy, value: state)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(accessibilityHint)
    }

    // Leading selection indicator: a circle for single-choice (a radio), a
    // rounded square for multiple-choice (a checkbox). Selected = a solid fill
    // with a high-contrast white glyph, so the chosen answer is unmistakable.
    @ViewBuilder
    private var indicator: some View {
        let isCircle = style == .single
        let shape = RoundedRectangle(cornerRadius: isCircle ? 13 : 7, style: .continuous)
        ZStack {
            shape.fill(isFilled ? indicatorColor : Color.clear)
            shape.strokeBorder(indicatorColor, lineWidth: 2)
            if isFilled {
                if isCircle {
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: 26, height: 26)
    }

    // Trailing result icon (review only).
    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .correct, .missedCorrect:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(ColorTokens.success)
                .contentTransition(.symbolEffect(.replace))
        case .incorrect:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(ColorTokens.danger)
                .contentTransition(.symbolEffect(.replace))
        case .selected, .unselected:
            EmptyView()
        }
    }

    private var isSelected: Bool { state == .selected || state == .correct || state == .incorrect }
    private var isInteractive: Bool { isEnabled && (state == .unselected || state == .selected) }

    /// The indicator shows a solid fill (with a white glyph) whenever it's chosen
    /// *or* being revealed in review — so the correct answer the user missed still
    /// has a clearly visible, filled radio/checkbox rather than a faint outline.
    private var isFilled: Bool {
        switch state {
        case .unselected:                                false
        case .selected, .correct, .incorrect, .missedCorrect: true
        }
    }

    private var indicatorColor: Color {
        switch state {
        case .unselected:               .secondary
        case .selected:                 ColorTokens.brand
        case .correct, .missedCorrect:  ColorTokens.success
        case .incorrect:                ColorTokens.danger
        }
    }

    /// Review-only outline color for the whole row (nil while answering, so the
    /// surface stays neutral and the text/indicator keep full contrast).
    private var reviewColor: Color? {
        switch state {
        case .correct, .missedCorrect: ColorTokens.success
        case .incorrect:               ColorTokens.danger
        case .selected, .unselected:   nil
        }
    }

    private var glassRole: GlassRole {
        switch state {
        case .unselected:                            .regular
        case .selected:                              .prominent
        case .correct, .missedCorrect, .incorrect:   .regular
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .correct:        "Correct answer, selected"
        case .incorrect:      "Incorrect answer, selected"
        case .missedCorrect:  "Correct answer, not selected"
        case .selected:       "Selected"
        case .unselected:     "Double-tap to select"
        }
    }
}

// MARK: - Question card

/// Wraps a question prompt with an optional progress label and type badge,
/// then a slot for its answer rows.
public struct QuestionCard<Choices: View>: View {
    private let prompt: String
    private let bodyMarkdown: String?
    private let progressLabel: String?
    private let badge: TagChip?
    private let choices: Choices

    public init(
        prompt: String,
        body: String? = nil,
        progressLabel: String? = nil,
        badge: TagChip? = nil,
        @ViewBuilder choices: () -> Choices
    ) {
        self.prompt = prompt
        self.bodyMarkdown = body
        self.progressLabel = progressLabel
        self.badge = badge
        self.choices = choices()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if progressLabel != nil || badge != nil {
                HStack {
                    if let progressLabel {
                        Text(progressLabel)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    badge
                }
            }
            RichText(prompt, baseFont: Typography.title)
                .fixedSize(horizontal: false, vertical: true)

            if let bodyMarkdown, !bodyMarkdown.isEmpty {
                RichText(bodyMarkdown, baseFont: Typography.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Spacing.sm) { choices }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.xl)
        .glassSurface(.regular, cornerRadius: Radius.xxl)
    }
}

// MARK: - Score ring

/// Animated circular score indicator for the result screen. Green when passed,
/// red when not. Respects Reduce Motion.
public struct ScoreRing: View {
    private let progress: Double      // 0...1
    private let passed: Bool
    private let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    public init(progress: Double, passed: Bool, caption: String) {
        self.progress = min(max(progress, 0), 1)
        self.passed = passed
        self.caption = caption
    }

    public var body: some View {
        ZStack {
            Circle().stroke(ColorTokens.hairline, lineWidth: 14)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: Spacing.xxs) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(Typography.displayLarge)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, height: 180)
        .onAppear {
            if reduceMotion { animated = progress }
            else { withAnimation(Motion.smooth.delay(0.1)) { animated = progress } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent. \(passed ? "Passed." : "Not passed.")")
    }

    private var ringColor: Color { passed ? ColorTokens.success : ColorTokens.danger }
}

// MARK: - Timer HUD

/// A compact glass capsule for the exam countdown. Turns to the danger tint in
/// the final stretch.
public struct TimerHUD: View {
    private let remaining: TimeInterval
    private let total: TimeInterval

    public init(remaining: TimeInterval, total: TimeInterval) {
        self.remaining = max(remaining, 0)
        self.total = total
    }

    public var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "timer")
            Text(formatted)
                .font(Typography.timer)
                .monospacedDigit()
        }
        .foregroundStyle(isWarning ? ColorTokens.danger : .primary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .glassCapsule(isWarning ? .tinted(ColorTokens.danger) : .clear)
        .animation(Motion.snappy, value: isWarning)
        .accessibilityLabel("Time remaining \(formatted)")
    }

    private var isWarning: Bool { total > 0 && remaining <= max(30, total * 0.1) }

    private var formatted: String {
        let total = Int(remaining.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview("Quiz components") {
    ZStack {
        AppBackground()
        ScrollView {
            VStack(spacing: Spacing.lg) {
                HStack { Spacer(); TimerHUD(remaining: 24, total: 600) }
                QuestionCard(
                    prompt: "Which service model gives the **most control** over the OS?",
                    progressLabel: "Question 3 of 50",
                    badge: TagChip("Beginner", kind: .difficulty(.beginner))
                ) {
                    ChoiceRow(label: "SaaS", state: .unselected) {}
                    ChoiceRow(label: "PaaS", state: .incorrect) {}
                    ChoiceRow(label: "**IaaS**", state: .missedCorrect) {}
                    ChoiceRow(label: "FaaS", state: .selected) {}
                }
                ScoreRing(progress: 0.84, passed: true, caption: "42 / 50 correct")
            }
            .padding()
        }
    }
    .markwiseTheme(.standard)
}

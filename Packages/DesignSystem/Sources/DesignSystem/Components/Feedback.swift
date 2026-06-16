//
//  Feedback.swift
//  DesignSystem
//
//  Empty states and diagnostics. Copy here is part of the design: an empty
//  screen invites action, and a diagnostic says what happened and how to fix it.
//

import SwiftUI

// MARK: - Empty state

/// A friendly empty state with an animated symbol, guidance copy, and an
/// optional primary action. Use for an empty library, no results, etc.
public struct EmptyStateView: View {
    private let icon: String
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        icon: String,
        title: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 46))
                .foregroundStyle(ColorTokens.brandGradient)
                .symbolEffect(.bounce, options: .nonRepeating)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(Typography.title)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.glassPrimary)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 360)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Diagnostic banner

/// Inline banner for parser results. Severity drives color and icon. Copy
/// should be concrete ("Question 7 has no correct answer marked"), never vague.
public struct DiagnosticBanner: View {
    public enum Severity: Sendable {
        case info, warning, error

        var color: Color {
            switch self {
            case .info:    ColorTokens.info
            case .warning: ColorTokens.warning
            case .error:   ColorTokens.danger
            }
        }
        var icon: String {
            switch self {
            case .info:    "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error:   "xmark.octagon.fill"
            }
        }
    }

    private let severity: Severity
    private let message: String
    private let count: Int?

    public init(severity: Severity, message: String, count: Int? = nil) {
        self.severity = severity
        self.message = message
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: severity.icon)
                .foregroundStyle(severity.color)
            VStack(alignment: .leading, spacing: 2) {
                if let count {
                    // Automatic grammatical agreement: "1 issue" / "3 issues".
                    Text("^[\(count) issue](inflect: true)")
                        .font(Typography.caption.weight(.semibold))
                }
                MarkdownText(message)
                    .font(Typography.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .glassSurface(.tinted(severity.color), cornerRadius: Radius.md)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Feedback") {
    ZStack {
        AppBackground()
        VStack(spacing: Spacing.xl) {
            DiagnosticBanner(
                severity: .warning,
                message: "Question 7 has no correct answer marked. It will be skipped until fixed.",
                count: 2
            )
            EmptyStateView(
                icon: "tray.and.arrow.down",
                title: "No quizzes yet",
                message: "Import a Markdown file to turn your notes into a quiz.",
                actionTitle: "Import a file"
            ) {}
        }
        .padding()
    }
    .markwiseTheme(.standard)
}

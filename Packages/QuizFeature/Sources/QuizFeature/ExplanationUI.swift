//
//  ExplanationUI.swift
//  QuizFeature
//
//  The "Ask AI" presentation pieces for the quiz runner's review state: the
//  per-question phase enum the view model exposes, and the card that renders a
//  returned `Explanation` (with an AI-generated caveat). Pure presentation — the
//  request logic lives in QuizSessionViewModel.
//

import SwiftUI
import CoreModels
import DesignSystem

/// The lifecycle of one question's explanation request.
public enum ExplanationPhase: Equatable, Sendable {
    case idle
    case loading
    case loaded(Explanation)
    case failed(String)
}

/// Renders an AI-generated `Explanation` (text + sources) with a verify caveat.
struct ExplanationCard: View {
    let explanation: Explanation

    var body: some View {
        GlassCard {
            Label("AI explanation", systemImage: "sparkles")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                RichText(explanation.text, baseFont: Typography.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !explanation.sources.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Sources").font(Typography.caption).foregroundStyle(.secondary)
                        ForEach(explanation.sources) { source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    Label(source.title, systemImage: "link").font(Typography.callout)
                                }
                            } else {
                                Label(source.title, systemImage: "link").font(Typography.callout)
                            }
                        }
                    }
                }

                Text("AI-generated — verify important facts and sources.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

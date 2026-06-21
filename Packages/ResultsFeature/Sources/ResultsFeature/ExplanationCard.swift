//
//  ExplanationCard.swift
//  ResultsFeature
//
//  Renders an AI-generated `Explanation` (text + cited sources) inside a glass
//  card, with an explicit "AI-generated, verify" caveat — model-supplied URLs
//  are not guaranteed correct. A small presentation view; no logic.
//

import SwiftUI
import CoreModels
import DesignSystem

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
                                    Label(source.title, systemImage: "link")
                                        .font(Typography.callout)
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

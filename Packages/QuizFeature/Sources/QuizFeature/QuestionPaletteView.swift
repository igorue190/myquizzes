//
//  QuestionPaletteView.swift
//  QuizFeature
//
//  The exam question-palette grid: every question as a numbered glass cell,
//  colored by state (current / marked / answered / unanswered). Tapping jumps to
//  that question. Microsoft-exam navigation parity (plan §9.3).
//

import SwiftUI
import DesignSystem

struct QuestionPaletteView: View {
    let model: QuizSessionViewModel
    let onDismiss: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 54), spacing: Spacing.sm)]

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        LazyVGrid(columns: columns, spacing: Spacing.sm) {
                            ForEach(0..<model.count, id: \.self) { index in
                                Button {
                                    model.goto(index)
                                    onDismiss()
                                } label: {
                                    cell(index)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        legend
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    private func cell(_ index: Int) -> some View {
        let state = model.paletteState(at: index)
        return Text("\(index + 1)")
            .font(Typography.button)
            .foregroundStyle(foreground(state))
            .frame(width: 54, height: 54)
            .glassSurface(role(state), cornerRadius: Radius.md)
    }

    private var legend: some View {
        HStack(spacing: Spacing.lg) {
            legendItem(.answered, "Answered")
            legendItem(.marked, "Marked")
            legendItem(.unanswered, "Skipped")
        }
        .font(Typography.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ state: QuizSessionViewModel.PaletteCellState, _ label: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(tint(state)).frame(width: 10, height: 10)
            Text(label)
        }
    }

    // MARK: - State → style

    private func role(_ state: QuizSessionViewModel.PaletteCellState) -> GlassRole {
        switch state {
        case .current:    .prominent
        case .marked:     .tinted(ColorTokens.warning)
        case .answered:   .tinted(ColorTokens.success)
        case .unanswered: .regular
        }
    }

    private func foreground(_ state: QuizSessionViewModel.PaletteCellState) -> Color {
        switch state {
        case .current:    .white
        case .marked:     ColorTokens.warning
        case .answered:   ColorTokens.success
        case .unanswered: .secondary
        }
    }

    private func tint(_ state: QuizSessionViewModel.PaletteCellState) -> Color {
        switch state {
        case .current:    ColorTokens.brand
        case .marked:     ColorTokens.warning
        case .answered:   ColorTokens.success
        case .unanswered: ColorTokens.hairline
        }
    }
}

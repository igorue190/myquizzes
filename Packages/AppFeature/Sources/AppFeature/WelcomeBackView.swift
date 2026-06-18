//
//  WelcomeBackView.swift
//  AppFeature
//
//  A brief, self-dismissing greeting shown to returning (already-onboarded) users
//  on a cold launch: their avatar and name, reinforcing the personal, on-device
//  feel. New users get OnboardingView instead; `RootView` decides which to show.
//

import SwiftUI
import DesignSystem

struct WelcomeBackView: View {
    let name: String
    let imageData: Data?
    let symbol: String
    /// Called when the greeting should dismiss (auto after a beat, or on tap).
    var onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    /// Live downward drag, so the greeting follows the finger and can be flicked
    /// away — dismissal otherwise happens automatically after a couple of seconds.
    @State private var dragOffset: CGFloat = 0

    private var greetingName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "there" : trimmed
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: Spacing.lg) {
                Spacer()
                ProfileAvatar(imageData: imageData, symbolName: symbol, size: 120)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: Spacing.xs) {
                    Text("Welcome back")
                        .font(Typography.title)
                        .foregroundStyle(.secondary)
                    Text(greetingName)
                        .font(Typography.displayLarge)
                        .foregroundStyle(ColorTokens.brandGradient)
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared ? 1 : 0)
                Spacer()
                Text("Swipe down or tap to continue")
                    .font(Typography.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, Spacing.xl)
            }
            .padding(.horizontal, Spacing.xl)
        }
        .offset(y: dragOffset)
        .contentShape(Rectangle())
        .onTapGesture { onContinue() }
        .gesture(
            DragGesture()
                .onChanged { dragOffset = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 120 {
                        onContinue()
                    } else {
                        withAnimation(Motion.snappy) { dragOffset = 0 }
                    }
                }
        )
        .task {
            withAnimation(reduceMotion ? nil : Motion.smooth) { appeared = true }
            try? await Task.sleep(for: .seconds(2))
            onContinue()
        }
    }
}

#Preview("Welcome back") {
    WelcomeBackView(name: "Ihor", imageData: nil, symbol: "graduationcap.fill") {}
        .markwiseTheme(.standard)
}

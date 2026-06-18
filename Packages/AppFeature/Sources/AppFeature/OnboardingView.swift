//
//  OnboardingView.swift
//  AppFeature
//
//  A short first-run intro (plan §9.2): a few paged panes that explain what
//  Markwise does and reinforce the offline / on-device privacy promise, ending
//  with a name field. Shown once; `RootView` records completion via @AppStorage.
//

import SwiftUI
import DesignSystem

struct OnboardingView: View {
    /// Called when the user taps "Get Started". Passes the (possibly empty)
    /// display name they entered.
    var onFinish: (String) -> Void

    @State private var page = 0
    @State private var name = ""

    private let panes: [Pane] = [
        Pane(icon: "graduationcap.fill",
             title: "Welcome to Markwise",
             message: "Turn your Markdown study notes into interactive quizzes — no account, no internet required."),
        Pane(icon: "doc.text.magnifyingglass",
             title: "Import & Practice",
             message: "Bring in any .md file. Learn at your own pace in Training, or take a timed, exam-style test."),
        Pane(icon: "lock.shield.fill",
             title: "Yours, on this device",
             message: "Your files, results, and profile never leave your iPhone. Everything stays private and offline.")
    ]

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: Spacing.lg) {
                TabView(selection: $page) {
                    ForEach(panes.indices, id: \.self) { index in
                        paneView(panes[index], showsNameField: index == lastIndex)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(Motion.smooth, value: page)

                Button(isLastPage ? "Get Started" : "Continue") {
                    if isLastPage {
                        onFinish(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        withAnimation(Motion.smooth) { page += 1 }
                    }
                }
                .buttonStyle(.glassPrimary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
        }
    }

    private func paneView(_ pane: Pane, showsNameField: Bool) -> some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: pane.icon)
                .font(.system(size: 76))
                .foregroundStyle(ColorTokens.brandGradient)
                .symbolEffect(.bounce, value: page)
            Text(pane.title)
                .font(Typography.displayLarge)
                .multilineTextAlignment(.center)
            Text(pane.message)
                .font(Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsNameField {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .frame(maxWidth: 260)
                    .padding(.top, Spacing.md)
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
    }

    private var lastIndex: Int { panes.count - 1 }
    private var isLastPage: Bool { page == lastIndex }

    private struct Pane {
        let icon: String
        let title: String
        let message: String
    }
}

#Preview("Onboarding") {
    OnboardingView { _ in }
        .markwiseTheme(.standard)
}

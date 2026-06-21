//
//  FeaturesSettingsView.swift
//  ProfileFeature
//
//  The "Features" sub-settings screen, pushed from the Profile form. A home for
//  optional-feature on/off switches so users can tailor the app to what they
//  actually use — vocabulary, AI explanations, and haptics. Each toggle flips a
//  flag on `model.profile`, which the parent ProfileView observes and persists.
//  Gating elsewhere (Library entries, the AI-features screen, openers, the quiz
//  runner) reads the same flags.
//

import SwiftUI
import CoreModels
import DesignSystem

struct FeaturesSettingsView: View {
    @Bindable var model: ProfileViewModel

    var body: some View {
        Form {
            vocabularySection
            aiSection
            feedbackSection
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Features")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var vocabularySection: some View {
        Section {
            Toggle("Vocabulary", isOn: $model.profile.vocabularyEnabled)
        } header: {
            Text("Vocabulary")
        } footer: {
            Text("Bilingual word sets you study as flashcards and translation quizzes, separate from your regular quizzes. Turning this off hides vocabulary creation; any sets you've already saved stay in your Library.")
        }
    }

    private var aiSection: some View {
        Section {
            Toggle("AI explanations", isOn: $model.profile.aiExplanationsEnabled)
        } header: {
            Text("AI explanations")
        } footer: {
            Text("Powers the “Ask AI” button on missed questions and “Generate with AI” in the Library. This is the one feature that leaves your device: text is sent to Anthropic using your own API key. Off by default — pick a model and add your key under AI features.")
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle("Haptics", isOn: $model.profile.hapticsEnabled)
        } header: {
            Text("Haptics")
        } footer: {
            Text("Subtle vibration feedback when you answer and when a session ends.")
        }
    }
}

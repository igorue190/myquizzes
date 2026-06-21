//
//  AISettingsView.swift
//  ProfileFeature
//
//  The "AI features" sub-settings screen, pushed from the Profile form. Configures
//  the AI features once they're enabled in the Features screen: the model picker,
//  API-key management, and the copy-paste quiz/vocabulary prompts. Mutating
//  `model.profile` here is observed by the parent ProfileView, which persists it.
//

import SwiftUI
import UIKit
import CoreModels
import DesignSystem

struct AISettingsView: View {
    @Bindable var model: ProfileViewModel

    @State private var apiKeyDraft = ""
    @State private var activePrompt: PromptKind?

    /// Which copy-paste prompt the sheet is showing.
    private enum PromptKind: String, Identifiable {
        case quiz, vocabulary
        var id: String { rawValue }

        var navigationTitle: String {
            switch self {
            case .quiz: "Quiz prompt"
            case .vocabulary: "Vocabulary prompt"
            }
        }
        var text: String {
            switch self {
            case .quiz: QuizPromptTemplate.text
            case .vocabulary: VocabularyPromptTemplate.text
            }
        }
    }

    var body: some View {
        Form {
            aiSection
            createSection
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("AI features")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activePrompt) { promptSheet($0) }
    }

    // MARK: - Sections

    @ViewBuilder private var aiSection: some View {
        if model.profile.aiExplanationsEnabled {
            Section {
                Picker("Model", selection: $model.profile.aiModel) {
                    ForEach(AIModel.allCases, id: \.self) { aiModel in
                        Text(aiModel.displayName).tag(aiModel)
                    }
                }

                if model.aiKeyPresent {
                    Label("API key saved", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(ColorTokens.success)
                    Button(role: .destructive) {
                        model.clearAPIKey()
                        apiKeyDraft = ""
                    } label: {
                        Label("Remove API key", systemImage: "trash")
                            .foregroundStyle(ColorTokens.danger)
                    }
                } else {
                    SecureField("Anthropic API key (sk-ant-…)", text: $apiKeyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        model.setAPIKey(apiKeyDraft)
                        apiKeyDraft = ""
                    } label: {
                        Label("Save API key", systemImage: "key.fill")
                    }
                    .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Model & API key")
            } footer: {
                Text("Your key is sent to Anthropic only when you use an AI feature, and is stored only in the Keychain — never included in backups.")
            }
        } else {
            Section {
                Label("AI explanations are off", systemImage: "sparkles")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Turn on AI explanations in Features to pick a model and add your API key.")
            }
        }
    }

    private var createSection: some View {
        Section {
            Button { activePrompt = .quiz } label: {
                Label("AI quiz-creation prompt", systemImage: "sparkles")
            }
            if model.profile.vocabularyEnabled {
                Button { activePrompt = .vocabulary } label: {
                    Label("AI vocabulary prompt", systemImage: "character.book.closed")
                }
            }
        } header: {
            Text("Create content")
        } footer: {
            Text("Prefer another assistant? Paste a prompt into any AI with your study material to generate a file you can import — a quiz, or a vocabulary set (turned into flashcards and translation quizzes).")
        }
    }

    // MARK: - Copy-paste prompt sheet

    private func promptSheet(_ kind: PromptKind) -> some View {
        NavigationStack {
            ScrollView {
                Text(kind.text)
                    .font(Typography.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Spacing.lg)
            }
            .navigationTitle(kind.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { activePrompt = nil }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = kind.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: kind.text)
                }
            }
        }
    }
}

//
//  VocabularyStudyView.swift
//  VocabularyFeature
//
//  The vocabulary study hub: the screen you land on when opening a vocab file from
//  the Library. Shows the language pair and mastery progress, then two ways to
//  study — Flashcards (pushed in-place) and a translation Quiz (handed to the host
//  via `onStartQuiz`, so the existing quiz runner stays in QuizFeature). The view
//  holds a `@State` view model, reads it, and sends intents; all logic lives in the
//  view model / VocabularyKit.
//

import SwiftUI
import CoreModels
import DesignSystem

public struct VocabularyStudyView: View {
    @State private var model: VocabularyStudyViewModel
    private let onStartQuiz: (ParsedQuiz) -> Void
    private let onClose: () -> Void

    @State private var showDeck = false

    public init(
        set: VocabularySet,
        fileID: UUID,
        reviewRepository: any VocabReviewRepository,
        onStartQuiz: @escaping (ParsedQuiz) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: VocabularyStudyViewModel(
            set: set, fileID: fileID, reviewRepository: reviewRepository
        ))
        self.onStartQuiz = onStartQuiz
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        progressCard
                        actionsCard
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle(model.vocabulary.title.isEmpty ? "Vocabulary" : model.vocabulary.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
            .navigationDestination(isPresented: $showDeck) {
                FlashcardDeckView(model: model.makeDeck())
            }
        }
        .task { await model.load() }
        .onChange(of: showDeck) { _, isShowing in
            // Refresh progress when returning from the deck.
            if !isShowing { Task { await model.load() } }
        }
    }

    // MARK: - Cards

    private var progressCard: some View {
        GlassCard {
            Label(languagePair, systemImage: "character.book.closed")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ProgressView(value: model.masteryFraction) {
                    HStack {
                        Text("Mastery").font(Typography.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.masteredCount)/\(model.entryCount)")
                            .font(Typography.caption.weight(.semibold))
                    }
                }
                .tint(ColorTokens.success)

                HStack(spacing: Spacing.lg) {
                    stat("\(model.dueCount)", "Due")
                    stat("\(model.learningCount)", "Learning")
                    stat("\(model.newCount)", "New")
                }
            }
        }
    }

    private var actionsCard: some View {
        VStack(spacing: Spacing.md) {
            Button {
                showDeck = true
            } label: {
                Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassPrimary)
            .disabled(!model.canStudy)

            Button {
                onStartQuiz(model.makeQuiz())
            } label: {
                Label("Take a quiz", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassSecondary)
            .disabled(!model.canQuiz)

            if !model.canQuiz {
                Text("Add at least two words to build a quiz.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Text(value).font(Typography.title.weight(.bold)).foregroundStyle(ColorTokens.brand)
            Text(label).font(Typography.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var languagePair: String {
        "\(model.vocabulary.foreignLanguage.displayName) ⇄ \(model.vocabulary.nativeLanguage.displayName)"
    }
}

//
//  FlashcardDeckView.swift
//  VocabularyFeature
//
//  The flashcard runner: one card at a time, tap to flip between the prompt and
//  the answer, then rate recall with Again / Known — which steps the card's Leitner
//  box (via the view model) and schedules its next review. Direction is mixed per
//  card. The flip uses a 3D rotation that's disabled under Reduce Motion. The view
//  is dumb: it reads the view model and sends intents.
//

import SwiftUI
import CoreModels
import DesignSystem

public struct FlashcardDeckView: View {
    @State private var model: FlashcardDeckViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: FlashcardDeckViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            AppBackground()
            if model.isFinished {
                finishedView
            } else {
                VStack(spacing: Spacing.xl) {
                    progressHeader
                    Spacer(minLength: 0)
                    card
                    listenRow
                    Spacer(minLength: 0)
                    controls
                }
                .padding(Spacing.lg)
            }
        }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !model.isLoaded { await model.start() } }
    }

    // MARK: - Header

    private var progressHeader: some View {
        VStack(spacing: Spacing.xs) {
            Text("\(model.cardNumber) of \(model.total)")
                .font(Typography.caption).foregroundStyle(.secondary)
            ProgressView(value: Double(model.position), total: Double(max(model.total, 1)))
                .tint(ColorTokens.brand)
        }
    }

    // MARK: - Card

    private var card: some View {
        Button {
            flipCard()
        } label: {
            VStack(spacing: Spacing.md) {
                Text(model.isShowingBack ? model.backLanguage : model.frontLanguage)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(model.isShowingBack ? model.backText : model.frontText)
                    .font(Typography.displayLarge)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)

                // Native-script transcription of the foreign term, shown only while
                // the foreign side is face-up (so a recall card isn't given away).
                if model.isForeignSideVisible, let transcription = model.transcription, !transcription.isEmpty {
                    Text(transcription)
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                }

                if model.isShowingBack {
                    if let phonetic = model.phonetic, !phonetic.isEmpty {
                        Text(phonetic).font(Typography.callout).foregroundStyle(.secondary)
                    }
                    if let example = model.example, !example.isEmpty {
                        Text(example)
                            .font(Typography.body)
                            .italic()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    Text("Tap to reveal")
                        .font(Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .padding(Spacing.xl)
            .glassSurface(.regular, cornerRadius: Radius.xl)
            // A cross-fade between the two sides; the id change drives the
            // transition. Disabled content motion under Reduce Motion.
            .id(model.isShowingBack)
            .transition(.opacity)
        }
        .buttonStyle(.plain)
    }

    private func flipCard() {
        withAnimation(reduceMotion ? nil : Motion.snappy) { model.flip() }
    }

    // MARK: - Listen

    /// The "listen" affordance: voices the foreign term aloud. Shown only when the
    /// foreign side is visible, and kept outside the flip button so tapping it
    /// doesn't also flip the card.
    @ViewBuilder
    private var listenRow: some View {
        if model.isForeignSideVisible && !model.foreignTerm.isEmpty {
            SpeakButton(text: model.foreignTerm, languageCode: model.foreignLanguageCode)
                .transition(.opacity)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if model.isShowingBack {
            HStack(spacing: Spacing.md) {
                Button {
                    model.answer(.again)
                } label: {
                    Label("Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassSecondary)
                .tint(ColorTokens.warning)

                Button {
                    model.answer(.known)
                } label: {
                    Label("Known", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary)
            }
        } else {
            Button {
                flipCard()
            } label: {
                Label("Reveal", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassPrimary)
        }
    }

    // MARK: - Finished

    private var finishedView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(ColorTokens.success)
            Text("Deck complete")
                .font(Typography.title)
            Text("You knew \(model.knownThisSession) of \(model.total) this round.")
                .font(Typography.callout)
                .foregroundStyle(.secondary)
            Button {
                model.restart()
            } label: {
                Label("Study again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassPrimary)
            .padding(.top, Spacing.md)
        }
        .padding(Spacing.xl)
    }
}

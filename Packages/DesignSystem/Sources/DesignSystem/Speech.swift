//
//  Speech.swift
//  DesignSystem
//
//  Text-to-speech for reading a foreign word aloud — the "listen" affordance the
//  vocabulary cards use to voice a term's pronunciation. Lives in DesignSystem (the
//  shared SwiftUI/iOS layer) so any feature can drop in a `SpeakButton` without
//  reaching for AVFoundation itself or re-inventing the synthesizer lifecycle.
//  `SpeechPronouncer` wraps a single `AVSpeechSynthesizer`, picks a voice from a
//  BCP-47 language code, and tracks whether it is currently speaking; the synthesizer
//  and its delegate callbacks are main-actor isolated to stay Sendable-clean.
//

import SwiftUI
import AVFoundation

// MARK: - Pronouncer

/// Speaks short text aloud via the system speech synthesizer, choosing a voice for
/// the given language. Owns one `AVSpeechSynthesizer` for its lifetime and exposes
/// `isSpeaking` so a button can reflect playback state. Tapping again while speaking
/// stops the current utterance (toggle behaviour).
@MainActor
@Observable
public final class SpeechPronouncer: NSObject, AVSpeechSynthesizerDelegate {
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    /// Whether an utterance is currently being spoken; drives the button's icon.
    public private(set) var isSpeaking = false

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak `text` in the voice for `languageCode` (a BCP-47 tag like "hr" or
    /// "ru"). A no-op for blank text. If already speaking, this stops playback
    /// instead — so a single button both starts and stops.
    public func speak(_ text: String, languageCode: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        if let voice = Self.voice(for: languageCode) {
            utterance.voice = voice
        }
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Resolve a voice for a language code, tolerating both bare codes ("hr") and
    /// full identifiers ("hr-HR"); falls back to the system default when none match.
    private static func voice(for languageCode: String?) -> AVSpeechSynthesisVoice? {
        guard let code = languageCode?.trimmingCharacters(in: .whitespaces), !code.isEmpty else {
            return nil
        }
        if let exact = AVSpeechSynthesisVoice(language: code) {
            return exact
        }
        // Match a more specific installed voice by language prefix ("hr" → "hr-HR").
        let prefix = code.lowercased()
        return AVSpeechSynthesisVoice.speechVoices().first {
            $0.language.lowercased().hasPrefix(prefix)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

// MARK: - Button

/// A reusable "listen" button: a speaker icon that reads `text` aloud in the voice
/// for `languageCode`. Owns its own `SpeechPronouncer`, so callers just supply what
/// to say. The icon animates to a filled speaker while speaking (skipped under
/// Reduce Motion).
public struct SpeakButton: View {
    private let text: String
    private let languageCode: String?

    @State private var pronouncer = SpeechPronouncer()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(text: String, languageCode: String? = nil) {
        self.text = text
        self.languageCode = languageCode
    }

    public var body: some View {
        Button {
            pronouncer.speak(text, languageCode: languageCode)
        } label: {
            Image(systemName: pronouncer.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                .font(Typography.headline)
                .foregroundStyle(ColorTokens.brand)
                .frame(width: 44, height: 44)
                .contentTransition(.symbolEffect(.replace))
        }
        .glassCapsule(.regular, interactive: true)
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : Motion.snappy, value: pronouncer.isSpeaking)
        .accessibilityLabel(Text("Listen to pronunciation"))
    }
}

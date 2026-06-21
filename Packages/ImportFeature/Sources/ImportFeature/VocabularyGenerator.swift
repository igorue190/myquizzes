//
//  VocabularyGenerator.swift
//  ImportFeature
//
//  The "paste a word list / pick a file → AI structures it into clean pairs →
//  review" flow for vocabulary. The sibling of `QuizGenerator`: a reusable view
//  modifier (`.vocabularyGenerator(isPresented:generate:onImport:)`) that gathers
//  source material plus the two languages, calls an injected generation closure
//  (the AI service lives behind `VocabularyGenerationService` in CoreModels, so
//  this feature stays dependency-free), then shows the parsed pairs before handing
//  the generated Markdown to the caller, which persists it like any imported file.
//  The app then builds flashcards and quizzes from the set offline.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreModels
import MarkdownParser
import DesignSystem

public extension View {
    /// Present the AI vocabulary-generation flow. `generate` turns a request into
    /// Markdown in the app's vocab format; `onImport` is called with the final
    /// title, that Markdown, and its summary once the user taps "Add".
    func vocabularyGenerator(
        isPresented: Binding<Bool>,
        generate: @escaping (VocabularyGenerationRequest) async throws -> String,
        onImport: @escaping (_ title: String, _ markdown: String, _ summary: ParseSummary) -> Void
    ) -> some View {
        modifier(VocabularyGeneratorModifier(isPresented: isPresented, generate: generate, onImport: onImport))
    }
}

struct VocabularyGeneratorModifier: ViewModifier {
    @Binding var isPresented: Bool
    let generate: (VocabularyGenerationRequest) async throws -> String
    let onImport: (String, String, ParseSummary) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            GenerateVocabularyView(generate: generate, onImport: { title, markdown, summary in
                onImport(title, markdown, summary)
                isPresented = false
            }, onCancel: { isPresented = false })
        }
    }
}

// MARK: - Generation form

struct GenerateVocabularyView: View {
    let generate: (VocabularyGenerationRequest) async throws -> String
    let onImport: (String, String, ParseSummary) -> Void
    let onCancel: () -> Void

    @State private var sourceText = ""
    @State private var title = ""
    @State private var foreignLabel = Language.croatian.label
    @State private var nativeLabel = Language.english.label
    @State private var maxEntries = 30
    @State private var phase: Phase = .idle
    @State private var review: VocabReviewPayload?
    @State private var showFileImporter = false
    @State private var fileError: String?
    @FocusState private var sourceFocused: Bool

    private enum Phase: Equatable {
        case idle
        case generating
        case failed(String)
    }

    private var isGenerating: Bool { phase == .generating }
    private var canGenerate: Bool {
        !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isGenerating
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        sourceCard
                        optionsCard
                        if case let .failed(message) = phase {
                            DiagnosticBanner(severity: .error, message: message)
                        }
                        generateButton
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Generate vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: Self.contentTypes,
                allowsMultipleSelection: false
            ) { result in
                loadFile(result)
            }
            .alert(
                "Couldn't read file",
                isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(fileError ?? "")
            }
            .sheet(item: $review) { payload in
                VocabularyReviewView(
                    suggestedTitle: payload.suggestedTitle,
                    markdown: payload.markdown,
                    set: payload.set,
                    onConfirm: { confirmedTitle in
                        onImport(confirmedTitle, payload.markdown, ParseSummary(payload.set))
                        review = nil
                    },
                    onCancel: { review = nil }
                )
            }
        }
    }

    // MARK: - Cards

    private var sourceCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Word list / notes")
                        .font(Typography.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { showFileImporter = true } label: {
                        Label("Load from file…", systemImage: "doc.text")
                            .font(Typography.caption)
                    }
                    .tint(ColorTokens.brand)
                }
                TextEditor(text: $sourceText)
                    .font(Typography.body)
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .focused($sourceFocused)
                    .overlay(alignment: .topLeading) {
                        // Hide the placeholder as soon as the editor is focused, not
                        // only once text is typed — tapping in clears the prompt.
                        if sourceText.isEmpty && !sourceFocused {
                            Text("Paste pairs, a glossary, or any bilingual text…")
                                .font(Typography.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, Spacing.xs)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    private var optionsCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Title (optional)").font(Typography.caption).foregroundStyle(.secondary)
                    TextField("Set title", text: $title)
                        .font(Typography.headline)
                        .textInputAutocapitalization(.words)
                }
                languageField("Foreign (learning)", label: $foreignLabel)
                languageField("Native (translation)", label: $nativeLabel)
                Stepper(value: $maxEntries, in: 5...100, step: 5) {
                    HStack {
                        Text("Max words").font(Typography.callout)
                        Spacer()
                        Text("\(maxEntries)")
                            .font(Typography.callout.weight(.semibold))
                            .foregroundStyle(ColorTokens.brand)
                    }
                }
            }
        }
    }

    /// A free-text language field with a menu of common languages to prefill it.
    private func languageField(_ caption: String, label: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(caption).font(Typography.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Language", text: label)
                    .font(Typography.callout)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                Menu {
                    ForEach(Language.common, id: \.code) { language in
                        Button(language.displayName) { label.wrappedValue = language.label }
                    }
                } label: {
                    Image(systemName: "globe").foregroundStyle(ColorTokens.brand)
                }
            }
        }
    }

    @ViewBuilder
    private var generateButton: some View {
        if isGenerating {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Structuring vocabulary…").font(Typography.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        } else {
            Button { runGeneration() } label: {
                Label("Generate vocabulary", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassPrimary)
            .disabled(!canGenerate)
        }
    }

    // MARK: - Actions

    private func runGeneration() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = VocabularyGenerationRequest(
            sourceText: sourceText,
            foreignLanguage: Language(label: foreignLabel),
            nativeLanguage: Language(label: nativeLabel),
            maxEntries: maxEntries,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle
        )
        phase = .generating
        Task {
            do {
                let markdown = try await generate(request)
                guard let set = VocabularyParser().parse(markdown) else {
                    phase = .failed("The AI response wasn't a valid vocabulary set. Try again.")
                    return
                }
                phase = .idle
                review = VocabReviewPayload(
                    suggestedTitle: trimmedTitle.isEmpty ? (set.title.isEmpty ? "Vocabulary" : set.title) : trimmedTitle,
                    markdown: markdown,
                    set: set
                )
            } catch {
                phase = .failed(Self.message(for: error))
            }
        }
    }

    private func loadFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            sourceText = try String(contentsOf: url, encoding: .utf8)
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            fileError = "The file couldn't be read as text."
        }
    }

    static var contentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        return types
    }

    static func message(for error: any Error) -> String {
        switch error as? VocabularyGenerationError {
        case .notConfigured: "AI generation isn't set up. Add your API key in Profile."
        case .emptySource:   "Add some source text first."
        case .network:       "Couldn't reach the AI service. Check your connection."
        case .api(let reason): reason
        case .decoding, .none: "The AI response couldn't be read. Try again."
        }
    }
}

// MARK: - Review payload

/// `Identifiable` payload so the review sheet can present the parsed set.
struct VocabReviewPayload: Identifiable {
    let id = UUID()
    let suggestedTitle: String
    let markdown: String
    let set: VocabularySet
}

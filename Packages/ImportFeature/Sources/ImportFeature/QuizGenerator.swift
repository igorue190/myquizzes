//
//  QuizGenerator.swift
//  ImportFeature
//
//  The "paste text / pick a file → AI generates a quiz → review" flow. A reusable
//  view modifier (`.quizGenerator(isPresented:generate:onImport:)`) that mirrors
//  `.quizImporter`: it gathers source material, calls an injected generation
//  closure (the AI service lives behind `QuizGenerationService` in CoreModels, so
//  this feature stays dependency-free), then hands the generated Markdown to the
//  same `ImportReviewView` the file importer uses before yielding the result.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreModels
import MarkdownParser
import DesignSystem

public extension View {
    /// Present the AI quiz-generation flow. `generate` turns a request into
    /// Markdown in the app's quiz format; `onImport` is called with the final
    /// title, that Markdown, and its parse summary once the user taps "Add".
    func quizGenerator(
        isPresented: Binding<Bool>,
        generate: @escaping (QuizGenerationRequest) async throws -> String,
        onImport: @escaping (_ title: String, _ markdown: String, _ summary: ParseSummary) -> Void
    ) -> some View {
        modifier(QuizGeneratorModifier(isPresented: isPresented, generate: generate, onImport: onImport))
    }
}

struct QuizGeneratorModifier: ViewModifier {
    @Binding var isPresented: Bool
    let generate: (QuizGenerationRequest) async throws -> String
    let onImport: (String, String, ParseSummary) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            GenerateQuizView(generate: generate, onImport: { title, markdown, summary in
                onImport(title, markdown, summary)
                isPresented = false
            }, onCancel: { isPresented = false })
        }
    }
}

// MARK: - Generation form

struct GenerateQuizView: View {
    let generate: (QuizGenerationRequest) async throws -> String
    let onImport: (String, String, ParseSummary) -> Void
    let onCancel: () -> Void

    @State private var sourceText = ""
    @State private var title = ""
    @State private var questionCount = 10
    @State private var phase: Phase = .idle
    @State private var review: ReviewPayload?
    @State private var showFileImporter = false
    @State private var fileError: String?
    @FocusState private var sourceFocused: Bool

    /// The lifecycle of the generation request.
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
            .navigationTitle("Generate quiz")
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
                ImportReviewView(
                    suggestedTitle: payload.suggestedTitle,
                    markdown: payload.markdown,
                    quiz: payload.quiz,
                    onConfirm: { confirmedTitle in
                        onImport(confirmedTitle, payload.markdown, ParseSummary(payload.quiz))
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
                    Text("Source material")
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
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .focused($sourceFocused)
                    .overlay(alignment: .topLeading) {
                        // Hide the placeholder on focus, not only once text is typed.
                        if sourceText.isEmpty && !sourceFocused {
                            Text("Paste notes, an article, or any study text…")
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
                    TextField("Quiz title", text: $title)
                        .font(Typography.headline)
                        .textInputAutocapitalization(.words)
                }
                Stepper(value: $questionCount, in: 3...30) {
                    HStack {
                        Text("Questions").font(Typography.callout)
                        Spacer()
                        Text("\(questionCount)")
                            .font(Typography.callout.weight(.semibold))
                            .foregroundStyle(ColorTokens.brand)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var generateButton: some View {
        if isGenerating {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Generating quiz…").font(Typography.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
        } else {
            Button { runGeneration() } label: {
                Label("Generate quiz", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassPrimary)
            .disabled(!canGenerate)
        }
    }

    // MARK: - Actions

    private func runGeneration() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = QuizGenerationRequest(
            sourceText: sourceText,
            questionCount: questionCount,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle
        )
        phase = .generating
        Task {
            do {
                let markdown = try await generate(request)
                let quiz = MarkdownQuizParser().parse(markdown)
                phase = .idle
                review = ReviewPayload(
                    suggestedTitle: trimmedTitle.isEmpty ? (quiz.metadata.title ?? "Generated Quiz") : trimmedTitle,
                    markdown: markdown,
                    quiz: quiz
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
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        if let daringfireball = UTType("net.daringfireball.markdown") { types.append(daringfireball) }
        return types
    }

    static func message(for error: any Error) -> String {
        switch error as? QuizGenerationError {
        case .notConfigured: "AI quiz generation isn't set up. Add your API key in Profile."
        case .emptySource:   "Add some source text first."
        case .network:       "Couldn't reach the AI service. Check your connection."
        case .api(let reason): reason
        case .decoding, .none: "The AI response couldn't be read. Try again."
        }
    }
}

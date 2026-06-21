//
//  QuizImporter.swift
//  ImportFeature
//
//  A reusable view modifier that drives the whole import flow: present the
//  system file picker, read the chosen .md (security-scoped), parse it, show a
//  review sheet with diagnostics, and on confirm hand back the reviewed content.
//  Attach with `.quizImporter(isPresented:onImport:)`.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreModels
import MarkdownParser

public extension View {
    /// Present the quiz import flow. `onImport` is called with the final title,
    /// the raw Markdown, and its parse summary once the user taps "Add".
    func quizImporter(
        isPresented: Binding<Bool>,
        onImport: @escaping (_ title: String, _ markdown: String, _ summary: ParseSummary) -> Void
    ) -> some View {
        modifier(QuizImporterModifier(isPresented: isPresented, onImport: onImport))
    }
}

struct QuizImporterModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onImport: (String, String, ParseSummary) -> Void

    @State private var review: ReviewPayload?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: Self.contentTypes,
                allowsMultipleSelection: false
            ) { result in
                handle(result)
            }
            .sheet(item: $review) { payload in
                ImportReviewView(
                    suggestedTitle: payload.suggestedTitle,
                    markdown: payload.markdown,
                    quiz: payload.quiz,
                    onConfirm: { title in
                        // Classify by content so a vocabulary file dropped into the
                        // quiz importer is still stored with the right kind.
                        let summary: ParseSummary
                        if VocabularyParser.isVocabulary(payload.markdown),
                           let set = VocabularyParser().parse(payload.markdown) {
                            summary = ParseSummary(set)
                        } else {
                            summary = ParseSummary(payload.quiz)
                        }
                        onImport(title, payload.markdown, summary)
                        review = nil
                    },
                    onCancel: { review = nil }
                )
            }
            .alert(
                "Couldn't import file",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    /// The content types the picker allows. Markdown is frequently typed as
    /// plain text, so we accept that plus the `.md` extension type.
    static var contentTypes: [UTType] {
        var types: [UTType] = [.plainText, .text]
        if let markdown = UTType(filenameExtension: "md") { types.append(markdown) }
        if let daringfireball = UTType("net.daringfireball.markdown") { types.append(daringfireball) }
        return types
    }

    private func handle(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else {
            // A cancelled picker reports failure; treat as a no-op, not an error.
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let quiz = MarkdownQuizParser().parse(markdown)
            review = ReviewPayload(
                suggestedTitle: url.deletingPathExtension().lastPathComponent,
                markdown: markdown,
                quiz: quiz
            )
        } catch {
            errorMessage = "The file couldn't be read as text."
        }
    }
}

/// Internal carrier for the review sheet (Identifiable for `.sheet(item:)`).
struct ReviewPayload: Identifiable {
    let id = UUID()
    let suggestedTitle: String
    let markdown: String
    let quiz: ParsedQuiz
}

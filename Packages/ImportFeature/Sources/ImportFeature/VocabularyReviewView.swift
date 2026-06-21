//
//  VocabularyReviewView.swift
//  ImportFeature
//
//  The vocabulary counterpart of `ImportReviewView`: shows the parsed pairs and an
//  editable title before the caller persists the set. "Add" is disabled when no
//  entry is usable (both sides filled). The caller saves the same Markdown via its
//  library repository, exactly like a quiz import.
//

import SwiftUI
import CoreModels
import MarkdownParser
import DesignSystem

public struct VocabularyReviewView: View {
    private let markdown: String
    private let vocabulary: VocabularySet
    private let onConfirm: (String) -> Void
    private let onCancel: () -> Void

    @State private var title: String

    public init(
        suggestedTitle: String,
        markdown: String,
        set: VocabularySet,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.markdown = markdown
        self.vocabulary = set
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _title = State(initialValue: suggestedTitle)
    }

    /// Convenience that parses `markdown` itself (used for previews/deep-links).
    public init?(
        suggestedTitle: String,
        markdown: String,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let set = VocabularyParser().parse(markdown) else { return nil }
        self.init(
            suggestedTitle: suggestedTitle,
            markdown: markdown,
            set: set,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    private var usableCount: Int { vocabulary.usableEntries.count }
    private var canAdd: Bool { usableCount > 0 }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        titleCard
                        summaryCard
                        entriesCard
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Import vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onConfirm(title.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .disabled(!canAdd || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Cards

    private var titleCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Title").font(Typography.caption).foregroundStyle(.secondary)
                TextField("Set title", text: $title)
                    .font(Typography.headline)
                    .textInputAutocapitalization(.words)
            }
        }
    }

    private var summaryCard: some View {
        GlassCard {
            Label("Vocabulary set", systemImage: "character.book.closed")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                statRow("Direction", "\(vocabulary.foreignLanguage.displayName) ⇄ \(vocabulary.nativeLanguage.displayName)")
                statRow("Words & phrases", "\(vocabulary.entries.count)")
                statRow("Usable", "\(usableCount)")
                if usableCount < vocabulary.entries.count {
                    statRow("Incomplete rows", "\(vocabulary.entries.count - usableCount)", color: ColorTokens.warning)
                }
            }
        }
    }

    private var entriesCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Preview").font(Typography.caption).foregroundStyle(.secondary)
                ForEach(vocabulary.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                        Text(entry.term.isEmpty ? "—" : entry.term)
                            .font(Typography.callout.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.translation.isEmpty ? "—" : entry.translation)
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if entry.id != vocabulary.entries.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(Typography.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(Typography.callout.weight(.semibold)).foregroundStyle(color)
        }
    }
}

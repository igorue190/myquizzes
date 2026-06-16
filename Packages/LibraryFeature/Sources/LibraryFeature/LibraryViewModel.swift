//
//  LibraryViewModel.swift
//  LibraryFeature
//
//  Holds the loaded content tree and forwards intents to an injected
//  LibraryRepository. Parsing on import happens here (the feature depends on
//  MarkdownParser); the repository stays persistence-only and parser-agnostic.
//

import Foundation
import Observation
import CoreModels
import MarkdownParser

@MainActor
@Observable
public final class LibraryViewModel {

    /// A category together with its topics, ready for the outline view.
    public struct CategoryNode: Identifiable, Sendable, Equatable {
        public let category: CoreModels.Category
        public var topics: [Topic]
        public var id: UUID { category.id }
    }

    private let repository: any LibraryRepository

    public private(set) var nodes: [CategoryNode] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    public init(repository: any LibraryRepository) {
        self.repository = repository
    }

    // MARK: - Loading

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let categories = try await repository.categories()
            var result: [CategoryNode] = []
            for category in categories {
                let topics = try await repository.topics(in: category.id)
                result.append(CategoryNode(category: category, topics: topics))
            }
            nodes = result
        } catch {
            errorMessage = "Couldn't load your library."
        }
    }

    public func markdown(for file: QuizFileRef) async -> String? {
        try? await repository.markdown(for: file.id)
    }

    // MARK: - Container queries (a "container" is a topic root or a folder)

    public func folders(inTopic topicID: UUID, parent: Folder?) async -> [Folder] {
        (try? await repository.folders(in: topicID, parent: parent?.id)) ?? []
    }

    public func files(inTopic topicID: UUID, folder: Folder?) async -> [QuizFileRef] {
        if let folder {
            return (try? await repository.files(inFolder: folder.id)) ?? []
        }
        return (try? await repository.files(in: topicID)) ?? []
    }

    // MARK: - Mutations

    public func addCategory(name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.createCategory(name: trimmed)
        await load()
    }

    public func addTopic(name: String, to category: CoreModels.Category) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.createTopic(name: trimmed, in: category.id)
        await load()
    }

    public func addFolder(name: String, topicID: UUID, parent: Folder?) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.createFolder(name: trimmed, in: topicID, parent: parent?.id)
    }

    /// Parse + store at a topic's root (used by the app's first-launch seed).
    public func importMarkdown(title: String, markdown: String, into topic: Topic) async {
        let quiz = MarkdownQuizParser().parse(markdown)
        try? await repository.importFile(
            title: title, markdown: markdown, summary: ParseSummary(quiz),
            into: topic.id, folder: nil
        )
    }

    /// Store an already-parsed import (summary from the import review screen)
    /// into a container (topic root when `folder == nil`).
    public func add(title: String, markdown: String, summary: ParseSummary,
                    topicID: UUID, folder: Folder?) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.importFile(
            title: trimmed, markdown: markdown, summary: summary,
            into: topicID, folder: folder?.id
        )
    }

    /// The Library's "Add sample file" action, into the current container.
    public func addSample(topicID: UUID, folder: Folder?) async {
        let quiz = MarkdownQuizParser().parse(LibrarySample.markdown)
        try? await repository.importFile(
            title: "AZ-900 Sample", markdown: LibrarySample.markdown, summary: ParseSummary(quiz),
            into: topicID, folder: folder?.id
        )
    }

    // MARK: - Rename

    public func rename(category: CoreModels.Category, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.rename(category: category.id, to: trimmed)
        await load()
    }
    public func rename(topic: Topic, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.rename(topic: topic.id, to: trimmed)
        await load()
    }
    public func rename(folder: Folder, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.rename(folder: folder.id, to: trimmed)
    }
    public func rename(file: QuizFileRef, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await repository.rename(file: file.id, to: trimmed)
    }

    // MARK: - Reorder

    public func reorderTopics(in category: CoreModels.Category, _ orderedIDs: [UUID]) async {
        try? await repository.reorderTopics(in: category.id, orderedIDs)
        await load()
    }
    public func reorderFolders(topicID: UUID, parent: Folder?, _ orderedIDs: [UUID]) async {
        try? await repository.reorderFolders(in: topicID, parent: parent?.id, orderedIDs)
    }

    // MARK: - Search

    public struct SearchResults: Sendable, Equatable {
        public var topics: [Topic]
        public var files: [QuizFileRef]
        public var isEmpty: Bool { topics.isEmpty && files.isEmpty }
    }

    public func search(_ query: String) async -> SearchResults {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return SearchResults(topics: [], files: []) }
        let topics = nodes.flatMap(\.topics).filter { $0.name.lowercased().contains(needle) }
        let files = ((try? await repository.allFiles()) ?? []).filter { $0.title.lowercased().contains(needle) }
        return SearchResults(topics: topics, files: files)
    }

    // MARK: - Delete

    public func delete(category: CoreModels.Category) async {
        try? await repository.deleteCategory(category.id)
        await load()
    }

    public func delete(topic: Topic) async {
        try? await repository.deleteTopic(topic.id)
        await load()
    }

    public func delete(folder: Folder) async {
        try? await repository.deleteFolder(folder.id)
    }

    public func delete(file: QuizFileRef) async {
        try? await repository.deleteFile(file.id)
    }

    public func isEmpty() -> Bool { nodes.isEmpty }
}

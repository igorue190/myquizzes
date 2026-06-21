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
    /// A flat list of every stored file, refreshed on `load()`. The Practice tab
    /// observes this so imported quizzes are runnable without browsing the tree.
    public private(set) var files: [QuizFileRef] = []
    public private(set) var isLoading = false
    public var errorMessage: String?

    /// Guards the one-time content-kind heal so it runs at most once per session.
    @ObservationIgnored private var didReconcileKinds = false

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
            files = (try? await repository.allFiles()) ?? []
            await reconcileFileKinds()
        } catch {
            errorMessage = "Couldn't load your library."
        }
    }

    /// Heal file kinds lost when `kind` was first persisted: files saved before
    /// that migration were backfilled with a default `.quiz` kind regardless of
    /// content, so vocabulary sets showed up as quizzes. Re-derive each file's kind
    /// from its markdown (the authoritative source the openers already trust) and
    /// correct the stored summary. Runs once per session and only writes when a
    /// kind actually changed, so it's cheap and idempotent.
    private func reconcileFileKinds() async {
        guard !didReconcileKinds else { return }
        didReconcileKinds = true

        var changed = false
        for file in files {
            guard let markdown = try? await repository.markdown(for: file.id) else { continue }
            let corrected = Self.summary(for: markdown)
            guard corrected.kind != file.summary.kind else { continue }
            try? await repository.updateSummary(file: file.id, to: corrected)
            changed = true
        }
        if changed { files = (try? await repository.allFiles()) ?? files }
    }

    /// The correct parse summary for a markdown file, classifying vocabulary vs
    /// quiz from its content so the stored `kind` is authoritative. Vocabulary is
    /// detected first (front matter), since a vocab file isn't a valid quiz.
    static func summary(for markdown: String) -> ParseSummary {
        if VocabularyParser.isVocabulary(markdown), let set = VocabularyParser().parse(markdown) {
            return ParseSummary(set)
        }
        return ParseSummary(MarkdownQuizParser().parse(markdown))
    }

    public func markdown(for file: QuizFileRef) async -> String? {
        try? await repository.markdown(for: file.id)
    }

    /// Reconstruct real questions (with their choices) for a list of prompts —
    /// the bridge that lets "Review weak areas" re-quiz from history, since
    /// history only records prompts, not answer options. Parses every stored
    /// file, matches by trimmed prompt in the given priority order, caps at
    /// `limit`, and renumbers ids so the combined pool forms a valid session.
    public func reviewQuestions(forPrompts prompts: [String], limit: Int) async -> [Question] {
        guard limit > 0, !prompts.isEmpty else { return [] }

        var byPrompt: [String: Question] = [:]
        for file in files {
            guard let markdown = try? await repository.markdown(for: file.id) else { continue }
            for question in MarkdownQuizParser().parse(markdown).usableQuestions {
                let key = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if byPrompt[key] == nil { byPrompt[key] = question }
            }
        }

        var pool: [Question] = []
        var used = Set<String>()
        for prompt in prompts {
            let key = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !used.contains(key), let question = byPrompt[key] else { continue }
            used.insert(key)
            pool.append(question)
            if pool.count >= limit { break }
        }

        return pool.enumerated().map { index, q in
            Question(
                id: index, prompt: q.prompt, body: q.body, type: q.type, choices: q.choices,
                explanation: q.explanation, reference: q.reference, tags: q.tags,
                difficulty: q.difficulty
            )
        }
    }

    /// Reconstruct questions carrying a given topic tag, across every stored file —
    /// the bridge that lets the Stats screen launch a focused "practice this topic"
    /// session from a weak-topic row. Matches case-insensitively on `tags`, caps at
    /// `limit`, de-duplicates by prompt, and renumbers ids into a valid pool.
    public func questions(forTag tag: String, limit: Int) async -> [Question] {
        guard limit > 0, !tag.isEmpty else { return [] }
        let needle = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var pool: [Question] = []
        var used = Set<String>()
        for file in files {
            guard let markdown = try? await repository.markdown(for: file.id) else { continue }
            for question in MarkdownQuizParser().parse(markdown).usableQuestions {
                guard question.tags.contains(where: { $0.lowercased() == needle }) else { continue }
                let key = question.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !used.contains(key) else { continue }
                used.insert(key)
                pool.append(question)
                if pool.count >= limit { break }
            }
            if pool.count >= limit { break }
        }

        return pool.enumerated().map { index, q in
            Question(
                id: index, prompt: q.prompt, body: q.body, type: q.type, choices: q.choices,
                explanation: q.explanation, reference: q.reference, tags: q.tags,
                difficulty: q.difficulty
            )
        }
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
        try? await repository.importFile(
            title: title, markdown: markdown, summary: Self.summary(for: markdown),
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

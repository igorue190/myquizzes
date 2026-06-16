//
//  InMemoryLibraryRepository.swift
//  CoreModels
//
//  A dependency-free LibraryRepository backed by dictionaries. Used by tests
//  (to verify the repository contract without SwiftData) and SwiftUI previews.
//  An actor, so it's Sendable and free of data races by construction.
//

import Foundation

public actor InMemoryLibraryRepository: LibraryRepository {
    private var categoriesByID: [UUID: Category] = [:]
    private var topicsByID: [UUID: Topic] = [:]
    private var foldersByID: [UUID: Folder] = [:]
    private var filesByID: [UUID: QuizFileRef] = [:]
    private var markdownByFile: [UUID: String] = [:]

    public init() {}

    public func categories() async throws -> [Category] {
        categoriesByID.values.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    public func topics(in categoryID: UUID) async throws -> [Topic] {
        topicsByID.values
            .filter { $0.categoryID == categoryID }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    public func folders(in topicID: UUID, parent parentFolderID: UUID?) async throws -> [Folder] {
        foldersByID.values
            .filter { $0.topicID == topicID && $0.parentFolderID == parentFolderID }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    public func files(in topicID: UUID) async throws -> [QuizFileRef] {
        filesByID.values
            .filter { $0.topicID == topicID && $0.folderID == nil }
            .sorted { $0.importedAt < $1.importedAt }
    }

    public func files(inFolder folderID: UUID) async throws -> [QuizFileRef] {
        filesByID.values
            .filter { $0.folderID == folderID }
            .sorted { $0.importedAt < $1.importedAt }
    }

    @discardableResult
    public func createCategory(name: String) async throws -> Category {
        let category = Category(name: name, order: categoriesByID.count)
        categoriesByID[category.id] = category
        return category
    }

    @discardableResult
    public func createTopic(name: String, in categoryID: UUID) async throws -> Topic {
        guard categoriesByID[categoryID] != nil else { throw LibraryError.notFound }
        let siblings = topicsByID.values.filter { $0.categoryID == categoryID }.count
        let topic = Topic(name: name, order: siblings, categoryID: categoryID)
        topicsByID[topic.id] = topic
        return topic
    }

    @discardableResult
    public func createFolder(name: String, in topicID: UUID, parent parentFolderID: UUID?) async throws -> Folder {
        guard topicsByID[topicID] != nil else { throw LibraryError.notFound }
        if let parentFolderID, foldersByID[parentFolderID] == nil { throw LibraryError.notFound }
        let siblings = foldersByID.values.filter {
            $0.topicID == topicID && $0.parentFolderID == parentFolderID
        }.count
        let folder = Folder(name: name, order: siblings, topicID: topicID, parentFolderID: parentFolderID)
        foldersByID[folder.id] = folder
        return folder
    }

    @discardableResult
    public func importFile(
        title: String,
        markdown: String,
        summary: ParseSummary,
        into topicID: UUID,
        folder folderID: UUID?
    ) async throws -> QuizFileRef {
        guard topicsByID[topicID] != nil else { throw LibraryError.notFound }
        if let folderID, foldersByID[folderID] == nil { throw LibraryError.notFound }
        let id = UUID()
        let file = QuizFileRef(
            id: id,
            title: title,
            storedFileName: "\(id.uuidString).md",
            topicID: topicID,
            folderID: folderID,
            summary: summary
        )
        filesByID[id] = file
        markdownByFile[id] = markdown
        return file
    }

    public func markdown(for fileID: UUID) async throws -> String {
        guard let markdown = markdownByFile[fileID] else { throw LibraryError.fileMissing }
        return markdown
    }

    public func allFiles() async throws -> [QuizFileRef] {
        filesByID.values.sorted { $0.title < $1.title }
    }

    // MARK: - Rename

    public func rename(category id: UUID, to name: String) async throws {
        categoriesByID[id]?.name = name
    }
    public func rename(topic id: UUID, to name: String) async throws {
        topicsByID[id]?.name = name
    }
    public func rename(folder id: UUID, to name: String) async throws {
        foldersByID[id]?.name = name
    }
    public func rename(file id: UUID, to title: String) async throws {
        filesByID[id]?.title = title
    }

    // MARK: - Reorder (each id's order becomes its index)

    public func reorderTopics(in categoryID: UUID, _ orderedIDs: [UUID]) async throws {
        for (index, id) in orderedIDs.enumerated() where topicsByID[id]?.categoryID == categoryID {
            topicsByID[id]?.order = index
        }
    }
    public func reorderFolders(in topicID: UUID, parent parentFolderID: UUID?, _ orderedIDs: [UUID]) async throws {
        for (index, id) in orderedIDs.enumerated()
        where foldersByID[id]?.topicID == topicID && foldersByID[id]?.parentFolderID == parentFolderID {
            foldersByID[id]?.order = index
        }
    }

    public func deleteCategory(_ id: UUID) async throws {
        for topic in topicsByID.values where topic.categoryID == id {
            try await deleteTopic(topic.id)
        }
        categoriesByID[id] = nil
    }

    public func deleteTopic(_ id: UUID) async throws {
        for folder in foldersByID.values where folder.topicID == id {
            foldersByID[folder.id] = nil
        }
        for file in filesByID.values where file.topicID == id {
            try await deleteFile(file.id)
        }
        topicsByID[id] = nil
    }

    public func deleteFolder(_ id: UUID) async throws {
        // Cascade to subfolders and files.
        for subfolder in foldersByID.values where subfolder.parentFolderID == id {
            try await deleteFolder(subfolder.id)
        }
        for file in filesByID.values where file.folderID == id {
            try await deleteFile(file.id)
        }
        foldersByID[id] = nil
    }

    public func deleteFile(_ id: UUID) async throws {
        filesByID[id] = nil
        markdownByFile[id] = nil
    }

    public func isEmpty() async throws -> Bool {
        categoriesByID.isEmpty && topicsByID.isEmpty && filesByID.isEmpty && foldersByID.isEmpty
    }
}

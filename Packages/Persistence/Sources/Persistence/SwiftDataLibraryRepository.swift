//
//  SwiftDataLibraryRepository.swift
//  Persistence
//
//  The SwiftData implementation of CoreModels.LibraryRepository. A ModelActor so
//  all SwiftData access is serialized on its own executor (Swift 6 safe). Maps
//  @Model entities ↔ value types and keeps the FileStore in sync with the DB.
//

import Foundation
import SwiftData
import CoreModels

public actor SwiftDataLibraryRepository: ModelActor, LibraryRepository {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private let fileStore: FileStore

    public init(modelContainer: ModelContainer, fileStore: FileStore) {
        self.modelContainer = modelContainer
        let context = ModelContext(modelContainer)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.fileStore = fileStore
    }

    // MARK: - Reads

    public func categories() throws -> [CoreModels.Category] {
        try modelContext.fetch(
            FetchDescriptor<CategoryEntity>(
                sortBy: [SortDescriptor(\.order), SortDescriptor(\.name)]
            )
        ).map(\.value)
    }

    public func topics(in categoryID: UUID) throws -> [Topic] {
        guard let category = try fetchCategory(categoryID) else { return [] }
        return category.topics
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            .map(\.value)
    }

    public func folders(in topicID: UUID, parent parentFolderID: UUID?) throws -> [CoreModels.Folder] {
        guard let topic = try fetchTopic(topicID) else { return [] }
        return topic.folders
            .filter { $0.parentFolderID == parentFolderID }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
            .map(\.value)
    }

    public func files(in topicID: UUID) throws -> [QuizFileRef] {
        guard let topic = try fetchTopic(topicID) else { return [] }
        return topic.files
            .filter { $0.folder == nil }
            .sorted { $0.importedAt < $1.importedAt }
            .map(\.value)
    }

    public func files(inFolder folderID: UUID) throws -> [QuizFileRef] {
        guard let folder = try fetchFolder(folderID) else { return [] }
        return folder.files
            .sorted { $0.importedAt < $1.importedAt }
            .map(\.value)
    }

    // MARK: - Writes

    @discardableResult
    public func createCategory(name: String) throws -> CoreModels.Category {
        let order = try modelContext.fetchCount(FetchDescriptor<CategoryEntity>())
        let entity = CategoryEntity(name: name, order: order)
        modelContext.insert(entity)
        try modelContext.save()
        return entity.value
    }

    @discardableResult
    public func createTopic(name: String, in categoryID: UUID) throws -> Topic {
        guard let category = try fetchCategory(categoryID) else { throw LibraryError.notFound }
        let entity = TopicEntity(name: name, order: category.topics.count, category: category)
        modelContext.insert(entity)
        try modelContext.save()
        return entity.value
    }

    @discardableResult
    public func createFolder(name: String, in topicID: UUID, parent parentFolderID: UUID?) throws -> CoreModels.Folder {
        guard let topic = try fetchTopic(topicID) else { throw LibraryError.notFound }
        if let parentFolderID, try fetchFolder(parentFolderID) == nil { throw LibraryError.notFound }
        let order = topic.folders.filter { $0.parentFolderID == parentFolderID }.count
        let entity = FolderEntity(name: name, order: order, topic: topic, parentFolderID: parentFolderID)
        modelContext.insert(entity)
        try modelContext.save()
        return entity.value
    }

    @discardableResult
    public func importFile(
        title: String,
        markdown: String,
        summary: ParseSummary,
        into topicID: UUID,
        folder folderID: UUID?
    ) throws -> QuizFileRef {
        guard let topic = try fetchTopic(topicID) else { throw LibraryError.notFound }
        var folderEntity: FolderEntity?
        if let folderID {
            guard let folder = try fetchFolder(folderID) else { throw LibraryError.notFound }
            folderEntity = folder
        }
        let id = UUID()
        let name = "\(id.uuidString).md"
        try fileStore.write(markdown, name: name)
        let entity = QuizFileEntity(
            id: id, title: title, storedFileName: name, summary: summary,
            topic: topic, folder: folderEntity
        )
        modelContext.insert(entity)
        try modelContext.save()
        return entity.value
    }

    public func markdown(for fileID: UUID) throws -> String {
        guard let file = try fetchFile(fileID) else { throw LibraryError.notFound }
        do {
            return try fileStore.read(name: file.storedFileName)
        } catch {
            throw LibraryError.fileMissing
        }
    }

    public func allFiles() throws -> [QuizFileRef] {
        try modelContext.fetch(
            FetchDescriptor<QuizFileEntity>(sortBy: [SortDescriptor(\.title)])
        ).map(\.value)
    }

    // MARK: - Rename

    public func rename(category id: UUID, to name: String) throws {
        try fetchCategory(id)?.name = name
        try modelContext.save()
    }
    public func rename(topic id: UUID, to name: String) throws {
        try fetchTopic(id)?.name = name
        try modelContext.save()
    }
    public func rename(folder id: UUID, to name: String) throws {
        try fetchFolder(id)?.name = name
        try modelContext.save()
    }
    public func rename(file id: UUID, to title: String) throws {
        try fetchFile(id)?.title = title
        try modelContext.save()
    }

    public func updateSummary(file id: UUID, to summary: ParseSummary) throws {
        guard let entity = try fetchFile(id) else { return }
        entity.questionCount = summary.questionCount
        entity.warningCount = summary.warningCount
        entity.errorCount = summary.errorCount
        entity.kindRaw = summary.kind.rawValue
        try modelContext.save()
    }

    // MARK: - Reorder

    public func reorderTopics(in categoryID: UUID, _ orderedIDs: [UUID]) throws {
        guard let category = try fetchCategory(categoryID) else { return }
        let byID = Dictionary(uniqueKeysWithValues: category.topics.map { ($0.id, $0) })
        for (index, id) in orderedIDs.enumerated() { byID[id]?.order = index }
        try modelContext.save()
    }
    public func reorderFolders(in topicID: UUID, parent parentFolderID: UUID?, _ orderedIDs: [UUID]) throws {
        guard let topic = try fetchTopic(topicID) else { return }
        let byID = Dictionary(uniqueKeysWithValues:
            topic.folders.filter { $0.parentFolderID == parentFolderID }.map { ($0.id, $0) })
        for (index, id) in orderedIDs.enumerated() { byID[id]?.order = index }
        try modelContext.save()
    }

    // MARK: - Deletes (clean up the FileStore before the DB cascade)

    public func deleteCategory(_ id: UUID) throws {
        guard let category = try fetchCategory(id) else { return }
        for topic in category.topics {
            for file in topic.files { fileStore.delete(name: file.storedFileName) }
        }
        modelContext.delete(category)
        try modelContext.save()
    }

    public func deleteTopic(_ id: UUID) throws {
        guard let topic = try fetchTopic(id) else { return }
        for file in topic.files { fileStore.delete(name: file.storedFileName) }
        modelContext.delete(topic)
        try modelContext.save()
    }

    public func deleteFolder(_ id: UUID) throws {
        guard let folder = try fetchFolder(id) else { return }
        let allFolders = try modelContext.fetch(FetchDescriptor<FolderEntity>())
        deleteFolderTree(folder, allFolders: allFolders)
        try modelContext.save()
    }

    /// Manually cascade: delete subfolders (recursively) and stored bytes, then
    /// the folder itself (its `files` cascade is handled by SwiftData).
    private func deleteFolderTree(_ folder: FolderEntity, allFolders: [FolderEntity]) {
        for subfolder in allFolders where subfolder.parentFolderID == folder.id {
            deleteFolderTree(subfolder, allFolders: allFolders)
        }
        for file in folder.files { fileStore.delete(name: file.storedFileName) }
        modelContext.delete(folder)
    }

    public func deleteFile(_ id: UUID) throws {
        guard let file = try fetchFile(id) else { return }
        fileStore.delete(name: file.storedFileName)
        modelContext.delete(file)
        try modelContext.save()
    }

    public func isEmpty() throws -> Bool {
        try modelContext.fetchCount(FetchDescriptor<CategoryEntity>()) == 0
    }

    // MARK: - Entity lookups (fetch + filter; the tree is small)

    private func fetchCategory(_ id: UUID) throws -> CategoryEntity? {
        try modelContext.fetch(FetchDescriptor<CategoryEntity>()).first { $0.id == id }
    }

    private func fetchTopic(_ id: UUID) throws -> TopicEntity? {
        try modelContext.fetch(FetchDescriptor<TopicEntity>()).first { $0.id == id }
    }

    private func fetchFolder(_ id: UUID) throws -> FolderEntity? {
        try modelContext.fetch(FetchDescriptor<FolderEntity>()).first { $0.id == id }
    }

    private func fetchFile(_ id: UUID) throws -> QuizFileEntity? {
        try modelContext.fetch(FetchDescriptor<QuizFileEntity>()).first { $0.id == id }
    }
}

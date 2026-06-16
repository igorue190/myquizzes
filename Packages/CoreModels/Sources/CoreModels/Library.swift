//
//  Library.swift
//  CoreModels
//
//  The user's content tree as pure value types, plus the repository boundary.
//  Features depend on `LibraryRepository` (a protocol) and these structs — never
//  on a persistence framework — so SwiftData can be swapped for CloudKit later
//  by replacing only the implementation (plan §6.2, §11).
//
//  Models Category → Topic → (nested Folders) → QuizFile (plan §4.2). A file
//  lives directly under a topic (folderID == nil) or inside a folder; folders
//  nest via parentFolderID.
//

import Foundation

// MARK: - Tree value types

public struct Category: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var order: Int

    public init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}

public struct Topic: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var order: Int
    public var categoryID: UUID

    public init(id: UUID = UUID(), name: String, order: Int = 0, categoryID: UUID) {
        self.id = id
        self.name = name
        self.order = order
        self.categoryID = categoryID
    }
}

/// An optional nested container inside a topic. `parentFolderID == nil` means
/// it sits at the topic's root; otherwise it nests inside another folder.
public struct Folder: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var order: Int
    public var topicID: UUID
    public var parentFolderID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        order: Int = 0,
        topicID: UUID,
        parentFolderID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.topicID = topicID
        self.parentFolderID = parentFolderID
    }
}

/// A reference to an imported `.md` file plus its cached parse summary. The raw
/// bytes live in the file store (keyed by `storedFileName`), never in the DB.
public struct QuizFileRef: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var title: String
    public var storedFileName: String
    public var topicID: UUID
    /// nil = directly under the topic; otherwise the containing folder.
    public var folderID: UUID?
    public var summary: ParseSummary
    public var importedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        storedFileName: String,
        topicID: UUID,
        folderID: UUID? = nil,
        summary: ParseSummary,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.storedFileName = storedFileName
        self.topicID = topicID
        self.folderID = folderID
        self.summary = summary
        self.importedAt = importedAt
    }
}

// MARK: - Parse summary / validation

/// Cached, displayable result of parsing a file (so the Library can show a
/// "12 questions · 2 warnings" badge without re-parsing).
public struct ParseSummary: Sendable, Equatable, Codable, Hashable {
    public var questionCount: Int
    public var warningCount: Int
    public var errorCount: Int

    public init(questionCount: Int = 0, warningCount: Int = 0, errorCount: Int = 0) {
        self.questionCount = questionCount
        self.warningCount = warningCount
        self.errorCount = errorCount
    }

    /// Derive a summary from a parsed quiz.
    public init(_ quiz: ParsedQuiz) {
        self.questionCount = quiz.questions.count
        self.warningCount = quiz.diagnostics.filter { $0.severity == .warning }.count
        self.errorCount = quiz.diagnostics.filter { $0.severity == .error }.count
    }

    public enum Status: String, Sendable, Codable { case ok, warnings, errors }

    public var status: Status {
        if errorCount > 0 { return .errors }
        if warningCount > 0 { return .warnings }
        return .ok
    }
}

// MARK: - Repository boundary

public enum LibraryError: Error, Sendable, Equatable {
    case notFound
    case fileMissing
}

/// The persistence boundary for the content tree. Implemented by SwiftData in
/// the Persistence package and by `InMemoryLibraryRepository` for tests/previews.
public protocol LibraryRepository: Sendable {
    func categories() async throws -> [Category]
    func topics(in categoryID: UUID) async throws -> [Topic]

    /// Folders at one level of a topic. `parent == nil` → the topic's root.
    func folders(in topicID: UUID, parent parentFolderID: UUID?) async throws -> [Folder]
    /// Files directly under a topic (not in any folder).
    func files(in topicID: UUID) async throws -> [QuizFileRef]
    /// Files inside a specific folder.
    func files(inFolder folderID: UUID) async throws -> [QuizFileRef]

    @discardableResult func createCategory(name: String) async throws -> Category
    @discardableResult func createTopic(name: String, in categoryID: UUID) async throws -> Topic
    @discardableResult
    func createFolder(name: String, in topicID: UUID, parent parentFolderID: UUID?) async throws -> Folder

    /// Copy `markdown` into the managed store and record a file referencing it.
    /// `folder == nil` places the file at the topic's root.
    @discardableResult
    func importFile(
        title: String,
        markdown: String,
        summary: ParseSummary,
        into topicID: UUID,
        folder folderID: UUID?
    ) async throws -> QuizFileRef

    /// The raw Markdown for a stored file.
    func markdown(for fileID: UUID) async throws -> String

    /// Every file across the whole library (for search).
    func allFiles() async throws -> [QuizFileRef]

    func rename(category id: UUID, to name: String) async throws
    func rename(topic id: UUID, to name: String) async throws
    func rename(folder id: UUID, to name: String) async throws
    func rename(file id: UUID, to title: String) async throws

    /// Persist a new order for siblings (each id's `order` becomes its index).
    func reorderTopics(in categoryID: UUID, _ orderedIDs: [UUID]) async throws
    func reorderFolders(in topicID: UUID, parent parentFolderID: UUID?, _ orderedIDs: [UUID]) async throws

    func deleteCategory(_ id: UUID) async throws
    func deleteTopic(_ id: UUID) async throws
    func deleteFolder(_ id: UUID) async throws
    func deleteFile(_ id: UUID) async throws

    func isEmpty() async throws -> Bool
}

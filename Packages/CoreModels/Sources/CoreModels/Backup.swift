//
//  Backup.swift
//  CoreModels
//
//  A self-contained, offline backup of everything the user owns: the content
//  tree (categories → topics → folders → files + their Markdown), session
//  history, and the profile. `BackupService` walks the repository protocols to
//  produce one `BackupDocument` and restores it into any repository set, so
//  backup/restore stays persistence-agnostic (SwiftData today, CloudKit later).
//

import Foundation

// MARK: - Document

/// One portable backup. Codable so the app can write it to a single JSON file
/// the user shares/saves and re-imports — no backend, no account.
public struct BackupDocument: Sendable, Codable, Equatable {

    /// A stored file together with its raw Markdown (the bytes that normally live
    /// in the file store, inlined here so the backup is fully self-contained).
    public struct FileEntry: Sendable, Codable, Equatable {
        public var ref: QuizFileRef
        public var markdown: String
        public init(ref: QuizFileRef, markdown: String) {
            self.ref = ref
            self.markdown = markdown
        }
    }

    /// Bumped if the shape changes so a restore can refuse an unknown format.
    public var version: Int
    public var createdAt: Date
    public var profile: Profile
    public var categories: [Category]
    public var topics: [Topic]
    public var folders: [Folder]
    public var files: [FileEntry]
    public var sessions: [SessionRecord]

    public static let currentVersion = 1

    public init(
        version: Int = BackupDocument.currentVersion,
        createdAt: Date = Date(),
        profile: Profile = .default,
        categories: [Category] = [],
        topics: [Topic] = [],
        folders: [Folder] = [],
        files: [FileEntry] = [],
        sessions: [SessionRecord] = []
    ) {
        self.version = version
        self.createdAt = createdAt
        self.profile = profile
        self.categories = categories
        self.topics = topics
        self.folders = folders
        self.files = files
        self.sessions = sessions
    }

    /// A short human summary for confirmation UI ("12 quizzes · 30 sessions").
    public var summaryLine: String {
        "\(files.count) quiz\(files.count == 1 ? "" : "zes") · \(sessions.count) session\(sessions.count == 1 ? "" : "s")"
    }
}

public enum BackupError: Error, Sendable, Equatable {
    case unsupportedVersion(Int)
}

// MARK: - Service

/// Produces and restores `BackupDocument`s over the repository protocols. Pure:
/// it owns no storage of its own, just orchestrates the three repositories.
public struct BackupService: Sendable {
    private let library: any LibraryRepository
    private let sessions: any SessionRepository
    private let profiles: any ProfileRepository

    public init(
        library: any LibraryRepository,
        sessions: any SessionRepository,
        profiles: any ProfileRepository
    ) {
        self.library = library
        self.sessions = sessions
        self.profiles = profiles
    }

    // MARK: Export

    public func export() async throws -> BackupDocument {
        let categories = try await library.categories()
        var topics: [Topic] = []
        var folders: [Folder] = []
        var files: [BackupDocument.FileEntry] = []

        for category in categories {
            let topicsInCategory = try await library.topics(in: category.id)
            topics += topicsInCategory

            for topic in topicsInCategory {
                let topicFolders = try await allFolders(inTopic: topic.id)
                folders += topicFolders

                // Files at the topic root, then inside each folder.
                files += try await fileEntries(library.files(in: topic.id))
                for folder in topicFolders {
                    files += try await fileEntries(library.files(inFolder: folder.id))
                }
            }
        }

        let profile = (try? await profiles.load()) ?? .default
        let records = (try? await sessions.allRecords()) ?? []

        return BackupDocument(
            profile: profile,
            categories: categories,
            topics: topics,
            folders: folders,
            files: files,
            sessions: records
        )
    }

    private func fileEntries(_ refs: [QuizFileRef]) async throws -> [BackupDocument.FileEntry] {
        var entries: [BackupDocument.FileEntry] = []
        for ref in refs {
            let markdown = (try? await library.markdown(for: ref.id)) ?? ""
            entries.append(.init(ref: ref, markdown: markdown))
        }
        return entries
    }

    /// Breadth-first walk of every folder under a topic (all nesting levels).
    private func allFolders(inTopic topicID: UUID) async throws -> [Folder] {
        var result: [Folder] = []
        var queue: [UUID?] = [nil]
        while !queue.isEmpty {
            let parent = queue.removeFirst()
            let level = try await library.folders(in: topicID, parent: parent)
            result += level
            queue += level.map { Optional($0.id) }
        }
        return result
    }

    // MARK: Restore

    /// Restore a document by *adding* its content (new categories/topics/folders/
    /// files are created with fresh ids, sessions are saved, the profile is
    /// overwritten). On a fresh install this is a clean restore; on a populated
    /// device it merges rather than deletes, so nothing is lost.
    public func restore(_ doc: BackupDocument) async throws {
        guard doc.version <= BackupDocument.currentVersion else {
            throw BackupError.unsupportedVersion(doc.version)
        }

        // Old id → newly created id, so parent relationships survive the rebuild.
        var categoryMap: [UUID: UUID] = [:]
        for category in doc.categories.sorted(by: { $0.order < $1.order }) {
            let created = try await library.createCategory(name: category.name)
            categoryMap[category.id] = created.id
        }

        var topicMap: [UUID: UUID] = [:]
        for topic in doc.topics.sorted(by: { $0.order < $1.order }) {
            guard let newCategory = categoryMap[topic.categoryID] else { continue }
            let created = try await library.createTopic(name: topic.name, in: newCategory)
            topicMap[topic.id] = created.id
        }

        // Folders, parents before children: keep retrying until no progress.
        var folderMap: [UUID: UUID] = [:]
        var pending = doc.folders.sorted(by: { $0.order < $1.order })
        while !pending.isEmpty {
            var madeProgress = false
            var stillPending: [Folder] = []
            for folder in pending {
                guard let newTopic = topicMap[folder.topicID] else { continue } // orphan: skip
                if let parentOld = folder.parentFolderID {
                    guard let newParent = folderMap[parentOld] else {
                        stillPending.append(folder)      // parent not created yet
                        continue
                    }
                    let created = try await library.createFolder(name: folder.name, in: newTopic, parent: newParent)
                    folderMap[folder.id] = created.id
                } else {
                    let created = try await library.createFolder(name: folder.name, in: newTopic, parent: nil)
                    folderMap[folder.id] = created.id
                }
                madeProgress = true
            }
            pending = stillPending
            if !madeProgress { break }   // remaining folders reference missing parents
        }

        for entry in doc.files {
            guard let newTopic = topicMap[entry.ref.topicID] else { continue }
            let newFolder = entry.ref.folderID.flatMap { folderMap[$0] }
            try await library.importFile(
                title: entry.ref.title,
                markdown: entry.markdown,
                summary: entry.ref.summary,
                into: newTopic,
                folder: newFolder
            )
        }

        for record in doc.sessions {
            try? await sessions.save(record)
        }

        try await profiles.save(doc.profile)
    }
}

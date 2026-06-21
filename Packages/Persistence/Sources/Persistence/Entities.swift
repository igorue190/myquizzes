//
//  Entities.swift
//  Persistence
//
//  SwiftData @Model classes for the content tree. These are persistence details
//  kept private to this package — the rest of the app only sees the CoreModels
//  value types they map to. The DB stores relationships and the cached parse
//  summary; the raw .md bytes live in the FileStore (plan §7 storage split).
//

import Foundation
import SwiftData
import CoreModels

@Model
final class CategoryEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    @Relationship(deleteRule: .cascade, inverse: \TopicEntity.category)
    var topics: [TopicEntity]

    init(id: UUID = UUID(), name: String, order: Int) {
        self.id = id
        self.name = name
        self.order = order
        self.topics = []
    }

    var value: CoreModels.Category { CoreModels.Category(id: id, name: name, order: order) }
}

@Model
final class TopicEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var category: CategoryEntity?
    @Relationship(deleteRule: .cascade, inverse: \FolderEntity.topic)
    var folders: [FolderEntity]
    @Relationship(deleteRule: .cascade, inverse: \QuizFileEntity.topic)
    var files: [QuizFileEntity]

    init(id: UUID = UUID(), name: String, order: Int, category: CategoryEntity?) {
        self.id = id
        self.name = name
        self.order = order
        self.category = category
        self.folders = []
        self.files = []
    }

    var value: Topic {
        Topic(id: id, name: name, order: order, categoryID: category?.id ?? id)
    }
}

@Model
final class FolderEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var topic: TopicEntity?
    // Parent is a plain id (not a SwiftData self-relationship — those crash the
    // model container). The subfolder cascade is handled manually in the repo.
    var parentFolderID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \QuizFileEntity.folder)
    var files: [QuizFileEntity]

    init(
        id: UUID = UUID(), name: String, order: Int,
        topic: TopicEntity?, parentFolderID: UUID?
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.topic = topic
        self.parentFolderID = parentFolderID
        self.files = []
    }

    var value: CoreModels.Folder {
        CoreModels.Folder(
            id: id, name: name, order: order,
            topicID: topic?.id ?? id, parentFolderID: parentFolderID
        )
    }
}

@Model
final class QuizFileEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var storedFileName: String
    var questionCount: Int
    var warningCount: Int
    var errorCount: Int
    /// Whether this file is a quiz or a vocabulary set. Stored as the raw value so
    /// SwiftData lightweight migration adds the column with a `.quiz` default for
    /// files saved before the vocabulary feature existed.
    var kindRaw: String = ContentKind.quiz.rawValue
    var importedAt: Date
    var topic: TopicEntity?
    var folder: FolderEntity?

    init(
        id: UUID = UUID(),
        title: String,
        storedFileName: String,
        summary: ParseSummary,
        importedAt: Date = Date(),
        topic: TopicEntity?,
        folder: FolderEntity? = nil
    ) {
        self.id = id
        self.title = title
        self.storedFileName = storedFileName
        self.questionCount = summary.questionCount
        self.warningCount = summary.warningCount
        self.errorCount = summary.errorCount
        self.kindRaw = summary.kind.rawValue
        self.importedAt = importedAt
        self.topic = topic
        self.folder = folder
    }

    var value: QuizFileRef {
        QuizFileRef(
            id: id,
            title: title,
            storedFileName: storedFileName,
            topicID: topic?.id ?? id,
            folderID: folder?.id,
            summary: ParseSummary(
                questionCount: questionCount,
                warningCount: warningCount,
                errorCount: errorCount,
                kind: ContentKind(rawValue: kindRaw) ?? .quiz
            ),
            importedAt: importedAt
        )
    }
}

//
//  LibraryRepositoryTests.swift
//  CoreModelsTests
//
//  Contract tests for LibraryRepository, run against the in-memory
//  implementation. The SwiftData implementation in Persistence is expected to
//  satisfy the same behaviors.
//

import Testing
import Foundation
@testable import CoreModels

@Suite("LibraryRepository contract (in-memory)")
struct LibraryRepositoryTests {

    @Test("A fresh repository is empty")
    func startsEmpty() async throws {
        let repo = InMemoryLibraryRepository()
        #expect(try await repo.isEmpty())
        #expect(try await repo.categories().isEmpty)
    }

    @Test("Creating categories and topics builds an ordered tree")
    func createTree() async throws {
        let repo = InMemoryLibraryRepository()
        let azure = try await repo.createCategory(name: "Microsoft Azure")
        let aws = try await repo.createCategory(name: "AWS")
        #expect(try await repo.categories().map(\.name) == ["Microsoft Azure", "AWS"]) // creation order

        let cloud = try await repo.createTopic(name: "Cloud Concepts", in: azure.id)
        _ = try await repo.createTopic(name: "Security", in: azure.id)
        let topics = try await repo.topics(in: azure.id)
        #expect(topics.map(\.name) == ["Cloud Concepts", "Security"])
        #expect(try await repo.topics(in: aws.id).isEmpty)
        #expect(cloud.categoryID == azure.id)
    }

    @Test("Creating a topic under a missing category throws")
    func topicRequiresCategory() async throws {
        let repo = InMemoryLibraryRepository()
        await #expect(throws: LibraryError.notFound) {
            try await repo.createTopic(name: "Orphan", in: UUID())
        }
    }

    @Test("Importing a file stores its markdown and summary")
    func importFile() async throws {
        let repo = InMemoryLibraryRepository()
        let cat = try await repo.createCategory(name: "C")
        let topic = try await repo.createTopic(name: "T", in: cat.id)
        let md = "## Q\n- [x] A\n- [ ] B\n"
        let file = try await repo.importFile(
            title: "Quiz",
            markdown: md,
            summary: ParseSummary(questionCount: 1, warningCount: 0, errorCount: 0),
            into: topic.id,
            folder: nil
        )
        #expect(file.summary.questionCount == 1)
        #expect(file.summary.status == .ok)
        #expect(try await repo.files(in: topic.id).count == 1)
        #expect(try await repo.markdown(for: file.id) == md)
        #expect(try await !repo.isEmpty())
    }

    @Test("Deleting a category cascades to its topics and files")
    func cascadingDelete() async throws {
        let repo = InMemoryLibraryRepository()
        let cat = try await repo.createCategory(name: "C")
        let topic = try await repo.createTopic(name: "T", in: cat.id)
        let file = try await repo.importFile(
            title: "Q", markdown: "## Q\n- [x] A\n- [ ] B\n",
            summary: ParseSummary(questionCount: 1), into: topic.id, folder: nil
        )

        try await repo.deleteCategory(cat.id)
        #expect(try await repo.isEmpty())
        await #expect(throws: LibraryError.fileMissing) {
            try await repo.markdown(for: file.id)
        }
    }

    @Test("Folders nest and scope files; deleting a folder cascades")
    func folders() async throws {
        let repo = InMemoryLibraryRepository()
        let cat = try await repo.createCategory(name: "Azure")
        let topic = try await repo.createTopic(name: "Cloud", in: cat.id)

        // A root folder and a nested subfolder.
        let chapter1 = try await repo.createFolder(name: "Chapter 1", in: topic.id, parent: nil)
        let section = try await repo.createFolder(name: "Section A", in: topic.id, parent: chapter1.id)

        #expect(try await repo.folders(in: topic.id, parent: nil).map(\.name) == ["Chapter 1"])
        #expect(try await repo.folders(in: topic.id, parent: chapter1.id).map(\.name) == ["Section A"])

        // A file in the topic root vs. one inside the subfolder.
        let summary = ParseSummary(questionCount: 1)
        _ = try await repo.importFile(title: "Root", markdown: "## Q\n- [x] A\n- [ ] B\n",
                                      summary: summary, into: topic.id, folder: nil)
        let nested = try await repo.importFile(title: "Nested", markdown: "## Q\n- [x] A\n- [ ] B\n",
                                               summary: summary, into: topic.id, folder: section.id)

        #expect(try await repo.files(in: topic.id).map(\.title) == ["Root"])
        #expect(try await repo.files(inFolder: section.id).map(\.title) == ["Nested"])
        #expect(nested.folderID == section.id)

        // Deleting Chapter 1 removes Section A and its file.
        try await repo.deleteFolder(chapter1.id)
        #expect(try await repo.folders(in: topic.id, parent: nil).isEmpty)
        await #expect(throws: LibraryError.fileMissing) { try await repo.markdown(for: nested.id) }
        #expect(try await repo.files(in: topic.id).map(\.title) == ["Root"])   // root file survives
    }

    @Test("Rename, reorder, and search")
    func renameReorderSearch() async throws {
        let repo = InMemoryLibraryRepository()
        let cat = try await repo.createCategory(name: "Old")
        try await repo.rename(category: cat.id, to: "Azure")
        #expect(try await repo.categories().first?.name == "Azure")

        let t1 = try await repo.createTopic(name: "Networking", in: cat.id)
        let t2 = try await repo.createTopic(name: "Security", in: cat.id)
        #expect(try await repo.topics(in: cat.id).map(\.name) == ["Networking", "Security"])
        try await repo.reorderTopics(in: cat.id, [t2.id, t1.id])
        #expect(try await repo.topics(in: cat.id).map(\.name) == ["Security", "Networking"])

        _ = try await repo.importFile(title: "AZ-900 Notes", markdown: "## Q\n- [x] A\n- [ ] B\n",
                                      summary: ParseSummary(questionCount: 1), into: t1.id, folder: nil)
        let all = try await repo.allFiles()
        #expect(all.map(\.title) == ["AZ-900 Notes"])
        try await repo.rename(file: all[0].id, to: "Renamed Notes")
        #expect(try await repo.allFiles().first?.title == "Renamed Notes")
    }

    @Test("ParseSummary derives status from diagnostics")
    func parseSummaryStatus() {
        #expect(ParseSummary(questionCount: 3).status == .ok)
        #expect(ParseSummary(questionCount: 3, warningCount: 1).status == .warnings)
        #expect(ParseSummary(questionCount: 3, warningCount: 1, errorCount: 2).status == .errors)
    }
}

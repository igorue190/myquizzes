//
//  SwiftDataLibraryRepositoryTests.swift
//  PersistenceTests
//
//  The SwiftData repository must satisfy the same contract as the in-memory
//  one (CoreModelsTests/LibraryRepositoryTests). These run against an in-memory
//  ModelContainer + a temporary FileStore, so nothing touches the real device
//  store.
//

import Testing
import Foundation
@testable import Persistence
import CoreModels

@Suite("SwiftDataLibraryRepository contract")
struct SwiftDataLibraryRepositoryTests {

    private func makeRepo() throws -> SwiftDataLibraryRepository {
        try PersistenceStack.makeRepository(inMemory: true)
    }

    @Test("A fresh store is empty")
    func startsEmpty() async throws {
        let repo = try makeRepo()
        #expect(try await repo.isEmpty())
    }

    @Test("Create tree, import a file, read it back")
    func roundTrip() async throws {
        let repo = try makeRepo()
        let azure = try await repo.createCategory(name: "Microsoft Azure")
        let topic = try await repo.createTopic(name: "Cloud Concepts", in: azure.id)
        let md = "## Q\n- [x] A\n- [ ] B\n"

        let file = try await repo.importFile(
            title: "AZ-900",
            markdown: md,
            summary: ParseSummary(questionCount: 1, warningCount: 0, errorCount: 0),
            into: topic.id,
            folder: nil
        )

        #expect(try await repo.categories().map(\.name) == ["Microsoft Azure"])
        #expect(try await repo.topics(in: azure.id).map(\.name) == ["Cloud Concepts"])
        #expect(try await repo.files(in: topic.id).map(\.title) == ["AZ-900"])
        #expect(try await repo.markdown(for: file.id) == md)
        #expect(try await !repo.isEmpty())
    }

    @Test("ParseSummary.kind survives the round trip so vocab files route correctly")
    func summaryKindPersists() async throws {
        let repo = try makeRepo()
        let category = try await repo.createCategory(name: "Languages")
        let topic = try await repo.createTopic(name: "Croatian", in: category.id)

        _ = try await repo.importFile(
            title: "Quiz", markdown: "## Q\n- [x] A\n- [ ] B\n",
            summary: ParseSummary(questionCount: 1, kind: .quiz),
            into: topic.id, folder: nil
        )
        _ = try await repo.importFile(
            title: "Vocab", markdown: "---\nkind: vocabulary\n---\n",
            summary: ParseSummary(questionCount: 5, kind: .vocabulary),
            into: topic.id, folder: nil
        )

        let files = try await repo.files(in: topic.id)
        let byTitle = Dictionary(uniqueKeysWithValues: files.map { ($0.title, $0.summary.kind) })
        #expect(byTitle["Quiz"] == .quiz)
        #expect(byTitle["Vocab"] == .vocabulary)
    }

    @Test("Deleting a category cascades to topics, files, and stored bytes")
    func cascadingDelete() async throws {
        let repo = try makeRepo()
        let cat = try await repo.createCategory(name: "C")
        let topic = try await repo.createTopic(name: "T", in: cat.id)
        let file = try await repo.importFile(
            title: "Q", markdown: "## Q\n- [x] A\n- [ ] B\n",
            summary: ParseSummary(questionCount: 1), into: topic.id, folder: nil
        )

        try await repo.deleteCategory(cat.id)
        #expect(try await repo.isEmpty())
        await #expect(throws: LibraryError.self) {
            try await repo.markdown(for: file.id)
        }
    }

    @Test("Importing under a missing topic throws notFound")
    func importRequiresTopic() async throws {
        let repo = try makeRepo()
        await #expect(throws: LibraryError.notFound) {
            try await repo.importFile(
                title: "x", markdown: "## Q\n- [x] A\n- [ ] B\n",
                summary: ParseSummary(), into: UUID(), folder: nil
            )
        }
    }

    @Test("Folders nest, scope files, and cascade on delete")
    func folders() async throws {
        let repo = try makeRepo()
        let cat = try await repo.createCategory(name: "Azure")
        let topic = try await repo.createTopic(name: "Cloud", in: cat.id)
        let chapter = try await repo.createFolder(name: "Chapter 1", in: topic.id, parent: nil)
        let section = try await repo.createFolder(name: "Section A", in: topic.id, parent: chapter.id)

        let summary = ParseSummary(questionCount: 1)
        _ = try await repo.importFile(title: "Root", markdown: "## Q\n- [x] A\n- [ ] B\n",
                                      summary: summary, into: topic.id, folder: nil)
        let nested = try await repo.importFile(title: "Nested", markdown: "## Q\n- [x] A\n- [ ] B\n",
                                               summary: summary, into: topic.id, folder: section.id)

        #expect(try await repo.folders(in: topic.id, parent: nil).map(\.name) == ["Chapter 1"])
        #expect(try await repo.folders(in: topic.id, parent: chapter.id).map(\.name) == ["Section A"])
        #expect(try await repo.files(in: topic.id).map(\.title) == ["Root"])
        #expect(try await repo.files(inFolder: section.id).map(\.title) == ["Nested"])
        #expect(nested.folderID == section.id)

        try await repo.deleteFolder(chapter.id)
        #expect(try await repo.folders(in: topic.id, parent: nil).isEmpty)
        #expect(try await repo.files(in: topic.id).map(\.title) == ["Root"])
        await #expect(throws: LibraryError.self) { try await repo.markdown(for: nested.id) }
    }
}

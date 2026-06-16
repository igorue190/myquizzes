//
//  LibraryViewModelTests.swift
//  LibraryFeatureTests
//

import Testing
import CoreModels
@testable import LibraryFeature

@MainActor
@Suite("LibraryViewModel")
struct LibraryViewModelTests {

    @Test("load builds the category/topic tree")
    func loadTree() async {
        let repo = InMemoryLibraryRepository()
        let category = try! await repo.createCategory(name: "Azure")
        _ = try! await repo.createTopic(name: "Cloud", in: category.id)

        let model = LibraryViewModel(repository: repo)
        await model.load()
        #expect(model.nodes.count == 1)
        #expect(model.nodes.first?.category.name == "Azure")
        #expect(model.nodes.first?.topics.map(\.name) == ["Cloud"])
    }

    @Test("addCategory / addTopic mutate and reload")
    func add() async {
        let model = LibraryViewModel(repository: InMemoryLibraryRepository())
        await model.addCategory(name: "AWS")
        #expect(model.nodes.map(\.category.name) == ["AWS"])
        await model.addTopic(name: "EC2", to: model.nodes[0].category)
        #expect(model.nodes[0].topics.map(\.name) == ["EC2"])
    }

    @Test("import then delete a file")
    func importDelete() async {
        let model = LibraryViewModel(repository: InMemoryLibraryRepository())
        await model.addCategory(name: "C")
        await model.addTopic(name: "T", to: model.nodes[0].category)
        let topic = model.nodes[0].topics[0]

        await model.importMarkdown(title: "Quiz", markdown: "## Q\n- [x] A\n- [ ] B\n", into: topic)
        var files = await model.files(inTopic: topic.id, folder: nil)
        #expect(files.count == 1)
        #expect(files[0].summary.questionCount == 1)

        await model.delete(file: files[0])
        files = await model.files(inTopic: topic.id, folder: nil)
        #expect(files.isEmpty)
    }

    @Test("empty repository reports empty")
    func empty() async {
        let model = LibraryViewModel(repository: InMemoryLibraryRepository())
        await model.load()
        #expect(model.isEmpty())
    }

    @Test("folders nest and scope files")
    func folders() async {
        let model = LibraryViewModel(repository: InMemoryLibraryRepository())
        await model.addCategory(name: "Azure")
        await model.addTopic(name: "Cloud", to: model.nodes[0].category)
        let topicID = model.nodes[0].topics[0].id

        await model.addFolder(name: "Chapter 1", topicID: topicID, parent: nil)
        let roots = await model.folders(inTopic: topicID, parent: nil)
        #expect(roots.map(\.name) == ["Chapter 1"])

        await model.add(title: "Nested", markdown: "## Q\n- [x] A\n- [ ] B\n",
                        summary: ParseSummary(questionCount: 1), topicID: topicID, folder: roots[0])
        #expect(await model.files(inTopic: topicID, folder: roots[0]).map(\.title) == ["Nested"])
        #expect(await model.files(inTopic: topicID, folder: nil).isEmpty)   // not at topic root
    }
}

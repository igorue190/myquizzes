//
//  LibraryView.swift
//  LibraryFeature
//
//  The content tree: categories (sections) → topics → (nested folders) → files.
//  Create, rename (context menu), reorder (Edit + drag), delete (swipe), and
//  search across topics/files. Reads a LibraryViewModel; holds no persistence
//  logic.
//

import SwiftUI
import Foundation
import CoreModels
import DesignSystem
import ImportFeature

public struct LibraryView: View {
    @State private var model: LibraryViewModel
    private let onPlay: (QuizFileRef, String) -> Void

    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var addTopicTarget: CoreModels.Category?
    @State private var newTopicName = ""
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var searchText = ""
    @State private var searchResults = LibraryViewModel.SearchResults(topics: [], files: [])

    enum RenameTarget: Identifiable {
        case category(CoreModels.Category), topic(Topic)
        var id: UUID { switch self { case .category(let c): c.id; case .topic(let t): t.id } }
        var currentName: String { switch self { case .category(let c): c.name; case .topic(let t): t.name } }
    }

    public init(
        model: LibraryViewModel,
        onPlay: @escaping (QuizFileRef, String) -> Void = { _, _ in }
    ) {
        _model = State(initialValue: model)
        self.onPlay = onPlay
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                if !searchText.isEmpty {
                    searchResultsView
                } else if model.nodes.isEmpty {
                    EmptyStateView(
                        icon: "tray.and.arrow.down",
                        title: "No quizzes yet",
                        message: "Create a category to start organizing your study material.",
                        actionTitle: "New category"
                    ) { showAddCategory = true }
                } else {
                    tree
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button { newCategoryName = ""; showAddCategory = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search topics and files")
            .navigationDestination(for: Topic.self) { topic in
                LibraryContainerView(model: model, topicID: topic.id, title: topic.name,
                                     folder: nil, onPlay: onPlay)
            }
            .navigationDestination(for: CoreModels.Folder.self) { folder in
                LibraryContainerView(model: model, topicID: folder.topicID, title: folder.name,
                                     folder: folder, onPlay: onPlay)
            }
            .alert("New category", isPresented: $showAddCategory) {
                TextField("Name", text: $newCategoryName)
                Button("Add") { commitCategory() }
                Button("Cancel", role: .cancel) { newCategoryName = "" }
            }
            .alert(
                "New topic",
                isPresented: Binding(
                    get: { addTopicTarget != nil },
                    set: { if !$0 { addTopicTarget = nil; newTopicName = "" } }
                )
            ) {
                TextField("Name", text: $newTopicName)
                Button("Add") { commitTopic() }
                Button("Cancel", role: .cancel) { addTopicTarget = nil; newTopicName = "" }
            }
            .alert("Rename", isPresented: renamePresented) {
                TextField("Name", text: $renameText)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .task { await model.load() }
            .onChange(of: searchText) {
                Task { searchResults = await model.search(searchText) }
            }
        }
    }

    private var tree: some View {
        List {
            ForEach(model.nodes) { node in
                Section {
                    ForEach(node.topics) { topic in
                        NavigationLink(value: topic) {
                            Label(topic.name, systemImage: "folder").font(Typography.body)
                        }
                        .listRowBackground(rowBackground)
                        .contextMenu {
                            Button { beginRename(.topic(topic)) } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) {
                                Task { await model.delete(topic: topic) }
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .onMove { from, to in
                        var ids = node.topics.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        Task { await model.reorderTopics(in: node.category, ids) }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { node.topics[$0] }
                        Task { for topic in targets { await model.delete(topic: topic) } }
                    }
                    Button { newTopicName = ""; addTopicTarget = node.category } label: {
                        Label("Add topic", systemImage: "plus").font(Typography.callout)
                    }
                    .listRowBackground(rowBackground)
                } header: {
                    HStack {
                        Text(node.category.name)
                        Spacer()
                        Menu {
                            Button { beginRename(.category(node.category)) } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) {
                                Task { await model.delete(category: node.category) }
                            } label: { Label("Delete", systemImage: "trash") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var searchResultsView: some View {
        List {
            if searchResults.isEmpty {
                Text("No matches.")
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            if !searchResults.topics.isEmpty {
                Section("Topics") {
                    ForEach(searchResults.topics) { topic in
                        NavigationLink(value: topic) {
                            Label(topic.name, systemImage: "folder").font(Typography.body)
                        }
                        .listRowBackground(rowBackground)
                    }
                }
            }
            if !searchResults.files.isEmpty {
                Section("Files") {
                    ForEach(searchResults.files) { file in
                        Button { playFile(file) } label: { FileRow(file: file) }
                            .listRowBackground(rowBackground)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var rowBackground: Color { Color(.systemBackground).opacity(0.5) }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func beginRename(_ target: RenameTarget) {
        renameText = target.currentName
        renameTarget = target
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let name = renameText
        renameTarget = nil
        Task {
            switch target {
            case .category(let category): await model.rename(category: category, to: name)
            case .topic(let topic):       await model.rename(topic: topic, to: name)
            }
        }
    }

    private func playFile(_ file: QuizFileRef) {
        Task { if let markdown = await model.markdown(for: file) { onPlay(file, markdown) } }
    }

    private func commitCategory() {
        let name = newCategoryName
        newCategoryName = ""
        Task { await model.addCategory(name: name) }
    }

    private func commitTopic() {
        guard let target = addTopicTarget else { return }
        let name = newTopicName
        newTopicName = ""
        addTopicTarget = nil
        Task { await model.addTopic(name: name, to: target) }
    }
}

// MARK: - Container (a topic root or a folder) — folders + files, recursive

struct LibraryContainerView: View {
    let model: LibraryViewModel
    let topicID: UUID
    let title: String
    let folder: CoreModels.Folder?
    let onPlay: (QuizFileRef, String) -> Void

    @State private var folders: [CoreModels.Folder] = []
    @State private var files: [QuizFileRef] = []
    @State private var showImporter = false
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""

    enum RenameTarget: Identifiable {
        case folder(CoreModels.Folder), file(QuizFileRef)
        var id: UUID { switch self { case .folder(let f): f.id; case .file(let f): f.id } }
        var currentName: String { switch self { case .folder(let f): f.name; case .file(let f): f.title } }
    }

    var body: some View {
        ZStack {
            AppBackground()
            List {
                if folders.isEmpty && files.isEmpty {
                    Text("Empty. Add a folder, import a file, or add the sample.")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                if !folders.isEmpty {
                    Section {
                        ForEach(folders) { folder in
                            NavigationLink(value: folder) {
                                Label(folder.name, systemImage: "folder.fill").font(Typography.body)
                            }
                            .listRowBackground(rowBackground)
                            .contextMenu {
                                Button { beginRename(.folder(folder)) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    Task { await model.delete(folder: folder); await reload() }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        .onMove { from, to in
                            var ids = folders.map(\.id)
                            ids.move(fromOffsets: from, toOffset: to)
                            Task { await model.reorderFolders(topicID: topicID, parent: folder, ids); await reload() }
                        }
                        .onDelete { offsets in
                            let targets = offsets.map { folders[$0] }
                            Task { for folder in targets { await model.delete(folder: folder) }; await reload() }
                        }
                    } header: { Text("Folders") }
                }
                Section {
                    ForEach(files) { file in
                        Button { play(file) } label: { FileRow(file: file) }
                            .listRowBackground(rowBackground)
                            .contextMenu {
                                Button { beginRename(.file(file)) } label: { Label("Rename", systemImage: "pencil") }
                            }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { files[$0] }
                        Task { for file in targets { await model.delete(file: file) }; await reload() }
                    }
                    Button { showImporter = true } label: {
                        Label("Import file…", systemImage: "square.and.arrow.down").font(Typography.callout)
                    }
                    .listRowBackground(rowBackground)
                    Button {
                        Task { await model.addSample(topicID: topicID, folder: folder); await reload() }
                    } label: {
                        Label("Add sample file", systemImage: "doc.badge.plus").font(Typography.callout)
                    }
                    .listRowBackground(rowBackground)
                } header: { Text("Files") }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .primaryAction) {
                Button { newFolderName = ""; showAddFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .quizImporter(isPresented: $showImporter) { title, markdown, summary in
            Task {
                await model.add(title: title, markdown: markdown, summary: summary,
                                topicID: topicID, folder: folder)
                await reload()
            }
        }
        .alert("New folder", isPresented: $showAddFolder) {
            TextField("Name", text: $newFolderName)
            Button("Add") {
                let name = newFolderName
                newFolderName = ""
                Task { await model.addFolder(name: name, topicID: topicID, parent: folder); await reload() }
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename", isPresented: renamePresented) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .task { await reload() }
    }

    private var rowBackground: Color { Color(.systemBackground).opacity(0.5) }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private func beginRename(_ target: RenameTarget) {
        renameText = target.currentName
        renameTarget = target
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let name = renameText
        renameTarget = nil
        Task {
            switch target {
            case .folder(let folder): await model.rename(folder: folder, to: name)
            case .file(let file):     await model.rename(file: file, to: name)
            }
            await reload()
        }
    }

    private func reload() async {
        folders = await model.folders(inTopic: topicID, parent: folder)
        files = await model.files(inTopic: topicID, folder: folder)
    }

    private func play(_ file: QuizFileRef) {
        Task {
            if let markdown = await model.markdown(for: file) {
                onPlay(file, markdown)
            }
        }
    }
}

private struct FileRow: View {
    let file: QuizFileRef

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "doc.text")
                .foregroundStyle(ColorTokens.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.title).font(Typography.body)
                Text("^[\(file.summary.questionCount) question](inflect: true)")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusChip
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch file.summary.status {
        case .ok:
            TagChip("Ready", kind: .semantic(ColorTokens.success))
        case .warnings:
            TagChip("\(file.summary.warningCount) warning", kind: .semantic(ColorTokens.warning))
        case .errors:
            TagChip("\(file.summary.errorCount) error", kind: .semantic(ColorTokens.danger))
        }
    }
}

// MARK: - Sample

/// A small bundled quiz used by the "Add sample file" action so the Library is
/// usable before real file import lands.
enum LibrarySample {
    static let markdown = """
    ---
    title: AZ-900 Sample
    topic: Cloud Concepts
    difficulty: beginner
    ---

    ## Which cloud service model gives the most control over the OS?
    <!-- type: single -->
    - [ ] SaaS
    - [ ] PaaS
    - [x] IaaS
    - [ ] FaaS

    > **Explanation:** IaaS exposes the VM and OS to the customer.

    ## Which are characteristics of cloud elasticity? (Choose two.)
    <!-- type: multiple -->
    - [x] Resources scale out automatically under load
    - [x] You pay only for what you consume
    - [ ] Capacity is fixed at provisioning time

    ## Azure Availability Zones protect against a full region outage.
    <!-- type: truefalse -->
    - [ ] True
    - [x] False
    """
}

#Preview("Library") {
    let model = LibraryViewModel(repository: InMemoryLibraryRepository())
    return LibraryView(model: model)
        .markwiseTheme(.standard)
}

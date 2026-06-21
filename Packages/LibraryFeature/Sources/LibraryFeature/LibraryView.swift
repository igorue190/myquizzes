//
//  LibraryView.swift
//  LibraryFeature
//
//  The content "home": categories become section headers over a 2-column grid of
//  colorful, square topic tiles (a game-like picker), drilling into
//  LibraryContainerView for folders/files. Create, rename and delete via each
//  tile's context menu; search across topics/files. Reads a LibraryViewModel;
//  holds no persistence logic.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import CoreModels
import DesignSystem
import ImportFeature

public struct LibraryView: View {
    @State private var model: LibraryViewModel
    private let onPlay: (QuizFileRef, String) -> Void
    /// Injected AI quiz-generation call. nil ⇒ the feature is off and the
    /// "Generate with AI" entry stays hidden (mirrors the "Ask AI" gating).
    private let generate: ((QuizGenerationRequest) async throws -> String)?
    /// Injected AI vocabulary-structuring call. nil ⇒ the "Generate vocabulary"
    /// entry stays hidden, same gating as `generate`.
    private let generateVocabulary: ((VocabularyGenerationRequest) async throws -> String)?

    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var addTopicTarget: CoreModels.Category?
    @State private var newTopicName = ""
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var searchText = ""
    @State private var searchResults = LibraryViewModel.SearchResults(topics: [], files: [])
    /// A local, drag-mutable mirror of `model.nodes` so tiles can reorder live
    /// before the move is persisted. Kept in sync with the model below.
    @State private var localNodes: [LibraryViewModel.CategoryNode] = []
    @State private var draggingTopic: Topic?

    enum RenameTarget: Identifiable {
        case category(CoreModels.Category), topic(Topic)
        var id: UUID { switch self { case .category(let c): c.id; case .topic(let t): t.id } }
        var currentName: String { switch self { case .category(let c): c.name; case .topic(let t): t.name } }
    }

    public init(
        model: LibraryViewModel,
        onPlay: @escaping (QuizFileRef, String) -> Void = { _, _ in },
        generate: ((QuizGenerationRequest) async throws -> String)? = nil,
        generateVocabulary: ((VocabularyGenerationRequest) async throws -> String)? = nil
    ) {
        _model = State(initialValue: model)
        self.onPlay = onPlay
        self.generate = generate
        self.generateVocabulary = generateVocabulary
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
                ToolbarItem(placement: .primaryAction) {
                    Button { newCategoryName = ""; showAddCategory = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search topics and files")
            .navigationDestination(for: Topic.self) { topic in
                LibraryContainerView(model: model, topicID: topic.id, title: topic.name,
                                     folder: nil, onPlay: onPlay, generate: generate,
                                     generateVocabulary: generateVocabulary)
            }
            .navigationDestination(for: CoreModels.Folder.self) { folder in
                LibraryContainerView(model: model, topicID: folder.topicID, title: folder.name,
                                     folder: folder, onPlay: onPlay, generate: generate,
                                     generateVocabulary: generateVocabulary)
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
            .task {
                await model.load()
                localNodes = model.nodes
            }
            .onChange(of: model.nodes) { _, nodes in localNodes = nodes }
            .onChange(of: searchText) {
                Task { searchResults = await model.search(searchText) }
            }
        }
    }

    /// Two equal, flexible columns — the "two square tiles per row" grid.
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)]
    }

    private var tree: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach($localNodes) { $node in
                    Section {
                        ForEach(node.topics) { topic in
                            NavigationLink(value: topic) {
                                TopicTile(
                                    topic: topic,
                                    quizCount: quizCount(for: topic),
                                    gradient: ColorTokens.tileGradient(seed: tileSeed(topic.id)),
                                    icon: tileIcon(topic.id)
                                )
                                .opacity(draggingTopic?.id == topic.id ? 0.4 : 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { beginRename(.topic(topic)) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    Task { await model.delete(topic: topic) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .onDrag {
                                draggingTopic = topic
                                return NSItemProvider(object: topic.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: TileDropDelegate(
                                item: topic,
                                items: $node.topics,
                                dragging: $draggingTopic,
                                commit: { ordered in
                                    let category = node.category
                                    Task { await model.reorderTopics(in: category, ordered.map(\.id)) }
                                }
                            ))
                        }
                        AddTile(title: "Add topic") {
                            newTopicName = ""; addTopicTarget = node.category
                        }
                    } header: {
                        categoryHeader(node)
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
            .animation(Motion.snappy, value: localNodes)
        }
    }

    private func categoryHeader(_ node: LibraryViewModel.CategoryNode) -> some View {
        HStack {
            Text(node.category.name)
                .font(Typography.title)
                .foregroundStyle(.primary)
            Spacer()
            Menu {
                Button { beginRename(.category(node.category)) } label: { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive) {
                    Task { await model.delete(category: node.category) }
                } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xs)
    }

    /// Number of quizzes filed directly or nested under a topic, for the tile badge.
    private func quizCount(for topic: Topic) -> Int {
        model.files.filter { $0.topicID == topic.id }.count
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
    let generate: ((QuizGenerationRequest) async throws -> String)?
    let generateVocabulary: ((VocabularyGenerationRequest) async throws -> String)?

    @State private var folders: [CoreModels.Folder] = []
    @State private var files: [QuizFileRef] = []
    @State private var showImporter = false
    @State private var showGenerator = false
    @State private var showVocabGenerator = false
    @State private var showAddFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: RenameTarget?
    @State private var renameText = ""
    @State private var draggingFolder: CoreModels.Folder?

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)]
    }

    enum RenameTarget: Identifiable {
        case folder(CoreModels.Folder), file(QuizFileRef)
        var id: UUID { switch self { case .folder(let f): f.id; case .file(let f): f.id } }
        var currentName: String { switch self { case .folder(let f): f.name; case .file(let f): f.title } }
    }

    var body: some View {
        ZStack {
            AppBackground()
            if folders.isEmpty && files.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "Nothing here yet",
                    message: "Add a folder, import a file, generate one with AI, or add the sample.",
                    actionTitle: "Add sample file"
                ) {
                    Task { await model.addSample(topicID: topicID, folder: folder); await reload() }
                }
            } else {
                grid
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newFolderName = ""; showAddFolder = true } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
                    }
                    Button { showImporter = true } label: {
                        Label("Import file…", systemImage: "square.and.arrow.down")
                    }
                    if generate != nil {
                        Button { showGenerator = true } label: {
                            Label("Generate quiz with AI…", systemImage: "sparkles")
                        }
                    }
                    if generateVocabulary != nil {
                        Button { showVocabGenerator = true } label: {
                            Label("Generate vocabulary with AI…", systemImage: "character.book.closed")
                        }
                    }
                    Button {
                        Task { await model.addSample(topicID: topicID, folder: folder); await reload() }
                    } label: {
                        Label("Add sample file", systemImage: "doc.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
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
        .quizGenerator(
            isPresented: $showGenerator,
            generate: generate ?? { _ in throw QuizGenerationError.notConfigured }
        ) { title, markdown, summary in
            Task {
                await model.add(title: title, markdown: markdown, summary: summary,
                                topicID: topicID, folder: folder)
                await reload()
            }
        }
        .vocabularyGenerator(
            isPresented: $showVocabGenerator,
            generate: generateVocabulary ?? { _ in throw VocabularyGenerationError.notConfigured }
        ) { title, markdown, summary in
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

    // MARK: - Tile grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                if !folders.isEmpty {
                    Section {
                        ForEach(folders) { folder in
                            NavigationLink(value: folder) {
                                FolderTile(folder: folder)
                                    .opacity(draggingFolder?.id == folder.id ? 0.4 : 1)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { beginRename(.folder(folder)) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    Task { await model.delete(folder: folder); await reload() }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .onDrag {
                                draggingFolder = folder
                                return NSItemProvider(object: folder.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: TileDropDelegate(
                                item: folder,
                                items: $folders,
                                dragging: $draggingFolder,
                                commit: { ordered in
                                    Task { await model.reorderFolders(topicID: topicID, parent: self.folder, ordered.map(\.id)) }
                                }
                            ))
                        }
                    } header: { sectionHeader("Folders") }
                }
                Section {
                    ForEach(files) { file in
                        Button { play(file) } label: { FileTile(file: file) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { beginRename(.file(file)) } label: { Label("Rename", systemImage: "pencil") }
                                Button(role: .destructive) {
                                    Task { await model.delete(file: file); await reload() }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                } header: { sectionHeader("Files") }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
            .animation(Motion.snappy, value: folders)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(Typography.headline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xs)
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

// MARK: - Tile helpers

/// A deterministic seed from a UUID so a tile keeps its color/icon across launches
/// (`UUID.hashValue` is randomized per process, so we hash the text instead).
func tileSeed(_ id: UUID) -> Int {
    id.uuidString.unicodeScalars.reduce(into: 0) { $0 = $0 &* 31 &+ Int($1.value) }
}

/// Playful, study-themed SF Symbols cycled by seed for topic-tile variety.
private let topicTileIcons = [
    "brain.head.profile", "graduationcap.fill", "lightbulb.fill",
    "books.vertical.fill", "puzzlepiece.fill", "star.fill",
    "flag.checkered", "trophy.fill"
]
func tileIcon(_ id: UUID) -> String {
    topicTileIcons[abs(tileSeed(id)) % topicTileIcons.count]
}

// MARK: - Tiles

/// A square, game-like topic tile: a colorful gradient icon badge over the topic
/// name and a quiz count, on a glass surface. Tapping navigates into the topic.
private struct TopicTile: View {
    let topic: Topic
    let quizCount: Int
    let gradient: LinearGradient
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                Circle().fill(gradient)
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            Spacer(minLength: Spacing.sm)

            Text(topic.name)
                .font(Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("^[\(quizCount) quiz](inflect: true)")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        // Make the whole tile tappable, not just the icon/text — the spacer gaps
        // between them aren't hit-testable without an explicit content shape.
        .contentShape(Rectangle())
        .glassSurface(.regular, cornerRadius: Radius.xl, interactive: true)
    }
}

/// A square "add" tile with a dashed outline, matching the topic tile footprint.
private struct AddTile: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: "plus")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(ColorTokens.brand)
                Text(title)
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(
                        ColorTokens.brand.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// A square folder tile mirroring `TopicTile`'s footprint. Tapping navigates in.
private struct FolderTile: View {
    let folder: CoreModels.Folder

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ZStack {
                Circle().fill(ColorTokens.tileGradient(seed: tileSeed(folder.id)))
                Image(systemName: "folder.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            Spacer(minLength: Spacing.sm)

            Text(folder.name)
                .font(Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("Folder")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .glassSurface(.regular, cornerRadius: Radius.xl, interactive: true)
    }
}

/// A square content-file tile: gradient badge, title, item count, and a status
/// chip. Vocabulary sets carry a distinct icon, accent, and "N words" label so
/// they read clearly apart from quizzes. Tapping opens the file.
private struct FileTile: View {
    let file: QuizFileRef

    private var isVocab: Bool { file.summary.kind == .vocabulary }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                ZStack {
                    Circle().fill(ColorTokens.tileGradient(seed: tileSeed(file.id)))
                    Image(systemName: isVocab ? "character.book.closed.fill" : "doc.text.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                Spacer()
                statusChip
            }

            Spacer(minLength: Spacing.sm)

            TagChip(isVocab ? "Vocabulary" : "Quiz", kind: .semantic(isVocab ? ColorTokens.info : ColorTokens.brand))
            Text(file.title)
                .font(Typography.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(isVocab
                 ? "^[\(file.summary.questionCount) word](inflect: true)"
                 : "^[\(file.summary.questionCount) question](inflect: true)")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .glassSurface(.regular, cornerRadius: Radius.xl, interactive: true)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch file.summary.status {
        case .ok:
            Image(systemName: "checkmark.seal.fill").foregroundStyle(ColorTokens.success)
        case .warnings:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ColorTokens.warning)
        case .errors:
            Image(systemName: "xmark.octagon.fill").foregroundStyle(ColorTokens.danger)
        }
    }
}

// MARK: - Drag-to-reorder

/// A generic drop delegate that reorders a list of tiles live as one is dragged
/// over another, then persists the final order via `commit`. Shared by topics,
/// folders, and files. Moves only within one `items` array (a drag from another
/// section/array is a no-op because its id won't be found here).
private struct TileDropDelegate<Item: Identifiable & Equatable>: DropDelegate {
    let item: Item
    @Binding var items: [Item]
    @Binding var dragging: Item?
    let commit: ([Item]) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id,
              let from = items.firstIndex(where: { $0.id == dragging.id }),
              let to = items.firstIndex(where: { $0.id == item.id })
        else { return }
        withAnimation(Motion.snappy) {
            items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let ordered = items
        dragging = nil
        commit(ordered)
        return true
    }
}

private struct FileRow: View {
    let file: QuizFileRef

    private var isVocab: Bool { file.summary.kind == .vocabulary }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: isVocab ? "character.book.closed" : "doc.text")
                .foregroundStyle(isVocab ? ColorTokens.info : ColorTokens.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.title).font(Typography.body)
                Text(isVocab
                     ? "^[\(file.summary.questionCount) word](inflect: true)"
                     : "^[\(file.summary.questionCount) question](inflect: true)")
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

//
//  ProfileView.swift
//  ProfileFeature
//
//  The settings form: identity, appearance (theme), default exam settings,
//  haptics, and data management. Edits persist automatically (on change).
//

import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import CoreModels
import DesignSystem

public struct ProfileView: View {
    @Bindable private var model: ProfileViewModel

    @State private var showDeleteConfirm = false
    @State private var exportItem: ExportItem?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPrompt = false
    @State private var backupShare: BackupShare?
    @State private var showRestorePicker = false
    @State private var restoreResult: RestoreResult?
    @State private var isWorking = false

    public init(model: ProfileViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Form {
                identitySection
                appearanceSection
                examDefaultsSection
                feedbackSection
                createSection
                backupSection
                dataSection
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Profile")
        }
        .task { await model.load() }
        .onChange(of: model.profile) { Task { await model.persist() } }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    model.setPhoto(data)
                }
                photoItem = nil
            }
        }
        .alert("Delete all history?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await model.clearHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved session result. It can't be undone.")
        }
        .sheet(item: $exportItem) { item in
            exportSheet(item.text)
        }
        .sheet(isPresented: $showPrompt) {
            promptSheet
        }
        .sheet(item: $backupShare) { share in
            backupShareSheet(share.url)
        }
        .fileImporter(
            isPresented: $showRestorePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            isWorking = true
            Task {
                let ok = await model.restoreBackup(from: url)
                isWorking = false
                restoreResult = ok ? .success(model.lastRestoreSummary) : .failure
            }
        }
        .alert(item: $restoreResult) { result in
            switch result {
            case .success(let summary):
                Alert(title: Text("Restore complete"),
                      message: Text(summary ?? "Your backup was restored."),
                      dismissButton: .default(Text("OK")))
            case .failure:
                Alert(title: Text("Couldn't restore"),
                      message: Text("That file isn't a valid Markwise backup."),
                      dismissButton: .default(Text("OK")))
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Profile") {
            VStack(spacing: Spacing.md) {
                ProfileAvatar(
                    imageData: model.profile.avatarImageData,
                    symbolName: model.profile.avatarSymbol,
                    size: 96
                )
                HStack(spacing: Spacing.lg) {
                    PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                        Label(model.profile.hasPhoto ? "Change photo" : "Upload photo",
                              systemImage: "photo.on.rectangle")
                    }
                    if model.profile.hasPhoto {
                        Button(role: .destructive) { model.setPhoto(nil) } label: {
                            Label("Remove", systemImage: "trash")
                                .foregroundStyle(ColorTokens.danger)
                        }
                    }
                }
                .font(Typography.callout)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)

            // The SF Symbol avatars are the fallback when no photo is set.
            if !model.profile.hasPhoto {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(Profile.avatarOptions, id: \.self) { symbol in
                            Button { model.profile.avatarSymbol = symbol } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .foregroundStyle(model.profile.avatarSymbol == symbol ? ColorTokens.brand : .secondary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle().fill(
                                            model.profile.avatarSymbol == symbol
                                                ? ColorTokens.brand.opacity(0.18) : .clear
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            TextField("Display name", text: $model.profile.displayName)
                .textInputAutocapitalization(.words)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $model.profile.themeID) {
                ForEach(ThemeID.allCases, id: \.self) { theme in
                    Text(theme.displayName).tag(theme)
                }
            }
        }
    }

    private var examDefaultsSection: some View {
        Section("Exam defaults") {
            Stepper(
                "Pass mark: \(model.profile.defaultPassThreshold)%",
                value: $model.profile.defaultPassThreshold,
                in: 50...100, step: 5
            )
            Picker("Time limit", selection: timeLimitMinutes) {
                Text("Untimed").tag(0)
                ForEach([15, 30, 45, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
            }
            Picker("Questions", selection: questionCount) {
                Text("All").tag(0)
                ForEach([10, 15, 25, 50], id: \.self) { Text("\($0)").tag($0) }
            }
        }
    }

    private var feedbackSection: some View {
        Section("Feedback") {
            Toggle("Haptics", isOn: $model.profile.hapticsEnabled)
        }
    }

    private var createSection: some View {
        Section {
            Button { showPrompt = true } label: {
                Label("AI quiz-creation prompt", systemImage: "sparkles")
            }
        } header: {
            Text("Create quizzes")
        } footer: {
            Text("Paste this prompt into any AI assistant with your study material to generate a quiz file you can import.")
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                isWorking = true
                Task {
                    let url = await model.exportBackup()
                    isWorking = false
                    if let url { backupShare = BackupShare(url: url) }
                }
            } label: {
                HStack {
                    Label("Back up all data", systemImage: "arrow.up.doc")
                    if isWorking { Spacer(); ProgressView() }
                }
            }
            .disabled(isWorking)

            Button {
                showRestorePicker = true
            } label: {
                Label("Restore from backup", systemImage: "arrow.down.doc")
            }
            .disabled(isWorking)
        } header: {
            Text("Backup")
        } footer: {
            Text("Saves your quizzes, history, and profile to one file you can store in Files or iCloud Drive and re-import on a new device. Restoring adds the backup's content; it won't erase what's already here.")
        }
    }

    private var dataSection: some View {
        Section {
            Button {
                Task { exportItem = ExportItem(text: await model.exportHistory()) }
            } label: {
                Label("Export history", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete all history", systemImage: "trash")
                    .foregroundStyle(ColorTokens.danger)
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything stays on this device — no account, no network.")
        }
    }

    // MARK: - Quiz-creation prompt sheet

    private var promptSheet: some View {
        NavigationStack {
            ScrollView {
                Text(QuizPromptTemplate.text)
                    .font(Typography.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Spacing.lg)
            }
            .navigationTitle("Quiz prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showPrompt = false }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = QuizPromptTemplate.text
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: QuizPromptTemplate.text)
                }
            }
        }
    }

    // MARK: - Backup share sheet

    private func backupShareSheet(_ url: URL) -> some View {
        NavigationStack {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(ColorTokens.success)
                Text("Backup ready")
                    .font(Typography.title)
                Text("Save it to Files or iCloud Drive, or send it to yourself. Keep it safe — it contains all your quizzes and history.")
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Label("Share / Save backup", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glassPrimary)
            }
            .padding(Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground())
            .navigationTitle("Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { backupShare = nil }
                }
            }
        }
    }

    // MARK: - Export sheet

    private func exportSheet(_ text: String) -> some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(Typography.mono)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(Spacing.lg)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { ShareLink(item: text) }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { exportItem = nil }
                }
            }
        }
    }

    // MARK: - Bindings for optional/derived settings

    private var timeLimitMinutes: Binding<Int> {
        Binding(
            get: { Int((model.profile.defaultTimeLimit ?? 0) / 60) },
            set: { model.profile.defaultTimeLimit = $0 == 0 ? nil : TimeInterval($0 * 60) }
        )
    }

    private var questionCount: Binding<Int> {
        Binding(
            get: { model.profile.defaultQuestionCount ?? 0 },
            set: { model.profile.defaultQuestionCount = $0 == 0 ? nil : $0 }
        )
    }
}

private struct ExportItem: Identifiable {
    let id = UUID()
    let text: String
}

private struct BackupShare: Identifiable {
    let id = UUID()
    let url: URL
}

private enum RestoreResult: Identifiable {
    case success(String?)
    case failure
    var id: String {
        switch self {
        case .success: "success"
        case .failure: "failure"
        }
    }
}

/// The copy-paste prompt that teaches another AI assistant to emit a quiz file in
/// exactly the Markdown shape the importer accepts. Kept in sync with the parser
/// (front matter keys, `##` prompts, `- [x]` task lists, type/tags comments,
/// explanation/reference blockquotes).
enum QuizPromptTemplate {
    static let text = """
    You are a quiz-authoring assistant. Produce a single Markdown (.md) file of \
    quiz questions in the EXACT format below. It will be imported by an iOS quiz \
    app called Markwise; if you deviate from the format, questions are dropped.

    ===================  SOURCE MATERIAL  ===================
    Create the quiz from this material / topic:

    <<< PASTE YOUR TEXT, TOPIC, OR LEARNING OBJECTIVES HERE >>>

    Number of questions: <<< e.g. 15 >>>
    Mix: mostly single-answer, some multiple-answer, a few true/false.
    =========================================================

    -----------------------  FORMAT  ------------------------
    1. OPTIONAL front matter at the very top, fenced by `---` lines, as flat
       `key: value` pairs. Allowed keys (all optional):
         title:            string
         category:         string  (broad subject, e.g. "Microsoft Azure")
         topic:            string  (sub-topic, e.g. "Cloud Concepts")
         difficulty:       beginner | intermediate | advanced
         passThreshold:    integer percent to pass, e.g. 70
         shuffleQuestions: true | false
         shuffleAnswers:   true | false

    2. EACH QUESTION is:
       a) A heading starting with `## ` — the question prompt.
       b) OPTIONAL comment directives on their own lines after the heading:
            <!-- type: single -->     (one correct answer)
            <!-- type: multiple -->   (two or more correct answers)
            <!-- type: truefalse -->  (a True/False question)
            <!-- tags: tag-one, tag-two -->
       c) The ANSWERS as a Markdown task list, one per line:
            - [x] correct answer
            - [ ] wrong answer
       d) OPTIONAL explanation blockquote right after the answers:
            > **Explanation:** why the correct answer is correct.
            > **Reference:** https://example.com/optional-source

    3. HARD REQUIREMENTS (a question is discarded if broken):
       - Non-empty prompt; at least 2 answers; at least one `- [x]`.
       - Do NOT mark every answer correct; no duplicate answer text.
       - single => exactly one `- [x]`; multiple => two or more `- [x]`.
       - truefalse => exactly two options "True" and "False", one correct.
       - Separate every question and blockquote with a blank line.

    4. OUTPUT: only the Markdown file content — no commentary before or after.

    -------------------  EXAMPLE  ---------------------------
    ---
    title: AZ-900 — Azure Fundamentals
    category: Microsoft Azure
    topic: Cloud Concepts
    difficulty: beginner
    passThreshold: 70
    ---

    ## Which cloud service model gives the most control over the operating system?
    <!-- type: single -->
    <!-- tags: cloud-concepts -->

    - [ ] SaaS
    - [ ] PaaS
    - [x] IaaS
    - [ ] FaaS

    > **Explanation:** IaaS exposes the VM and OS to the customer.
    > **Reference:** https://learn.microsoft.com/azure/

    ## Which are characteristics of cloud elasticity? (Choose two.)
    <!-- type: multiple -->

    - [x] Resources scale out automatically under load
    - [x] You pay only for what you consume
    - [ ] Capacity is fixed at provisioning time

    > **Explanation:** Elasticity means automatic scale-out/in with usage billing.
    ---------------------------------------------------------
    Now generate the full .md file for the SOURCE MATERIAL above.
    """
}

#Preview("Profile") {
    ProfileView(
        model: ProfileViewModel(
            repository: InMemoryProfileRepository(),
            sessionRepository: InMemorySessionRepository(),
            libraryRepository: InMemoryLibraryRepository()
        )
    )
    .markwiseTheme(.standard)
}

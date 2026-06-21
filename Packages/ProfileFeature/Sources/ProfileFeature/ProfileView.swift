//
//  ProfileView.swift
//  ProfileFeature
//
//  The settings form: identity, appearance (theme), and default exam settings,
//  plus links into three focused sub-screens — "Features", "AI features", and
//  "Data & backup" (see FeaturesSettingsView / AISettingsView / DataSettingsView).
//  Edits persist automatically (on change of the observed profile).
//

import SwiftUI
import PhotosUI
import UIKit
import CoreModels
import DesignSystem

public struct ProfileView: View {
    @Bindable private var model: ProfileViewModel

    @State private var photoItem: PhotosPickerItem?

    public init(model: ProfileViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Form {
                identitySection
                appearanceSection
                examDefaultsSection
                managementSection
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

    /// Links into the three focused sub-settings screens.
    private var managementSection: some View {
        Section("Settings") {
            NavigationLink {
                FeaturesSettingsView(model: model)
            } label: {
                Label("Features", systemImage: "switch.2")
            }
            NavigationLink {
                AISettingsView(model: model)
            } label: {
                Label("AI features", systemImage: "sparkles")
            }
            NavigationLink {
                DataSettingsView(model: model)
            } label: {
                Label("Data & backup", systemImage: "externaldrive")
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

/// The copy-paste prompt that teaches another AI assistant to emit a quiz file in
/// exactly the Markdown shape the importer accepts. Kept in sync with the parser
/// (front matter keys, `##` prompts, `- [x]` task lists, type/tags comments,
/// explanation/reference blockquotes). Used by AISettingsView.
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

/// The copy-paste prompt that teaches another AI assistant to emit a *vocabulary*
/// file in exactly the Markdown shape the importer accepts. Kept in sync with
/// `VocabularyParser` (front matter `kind: vocabulary` + the Term/Translation
/// table). Used by AISettingsView; the app builds flashcards and quizzes from the
/// imported set.
enum VocabularyPromptTemplate {
    static let text = """
    You are a vocabulary assistant. Produce a single Markdown (.md) file of \
    bilingual word/phrase pairs in the EXACT format below. It will be imported by \
    an iOS app called Markwise, which turns it into flashcards and translation \
    quizzes; if you deviate from the format, rows are dropped.

    ===================  SOURCE MATERIAL  ===================
    Foreign language (the word being learned): <<< e.g. Croatian (hr) >>>
    Native language (your translation):        <<< e.g. English (en) >>>

    Extract the vocabulary from this material / topic:

    <<< PASTE YOUR WORD LIST, NOTES, OR TOPIC HERE >>>
    =========================================================

    -----------------------  FORMAT  ------------------------
    1. REQUIRED front matter at the very top, fenced by `---` lines:
         kind: vocabulary            (must be exactly this)
         title:   string             (e.g. "Croatian — Travel Basics")
         foreign: Name (code)        (the `Term` language, e.g. "Croatian (hr)")
         native:  Name (code)        (the `Translation` language, e.g. "English (en)")

    2. THEN a Markdown table with this exact header:
         | Term | Translation | Pronunciation | Transcription | Example |
         |------|-------------|---------------|---------------|---------|
       One row per pair:
         - Term:          the foreign word/phrase being learned.
         - Translation:   its meaning in the native language.
         - Pronunciation: optional Latin/IPA-style hint (leave blank if unsure).
         - Transcription: optional spelling of the foreign term in the NATIVE
                          language's own script (e.g. "хвала"); blank when the
                          native language already uses the Latin alphabet.
         - Example:       optional short sentence in the foreign language.

    3. HARD REQUIREMENTS (a row is discarded if broken):
       - Every row needs a non-empty Term AND Translation.
       - Keep multi-word phrases intact; one pair per row.
       - Do NOT invent words the source doesn't contain. No duplicates.
       - If a cell contains a `|`, escape it as `\\|`.

    4. OUTPUT: only the Markdown file content — no commentary before or after.

    -------------------  EXAMPLE  ---------------------------
    ---
    kind: vocabulary
    title: Croatian — Travel Basics
    foreign: Croatian (hr)
    native: English (en)
    ---

    | Term | Translation | Pronunciation | Transcription | Example |
    |------|-------------|---------------|---------------|---------|
    | dobar dan | good day | DOH-bar dahn | добар дан | Dobar dan, kako ste? |
    | hvala | thank you | HVAH-lah | хвала | Hvala lijepa! |
    | molim | please | MOH-leem | молим |  |
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

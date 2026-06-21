//
//  RootView.swift
//  AppFeature
//
//  The app's root navigation: a TabView for Library · Practice · Stats · Profile
//  (the four sections from the plan §9.1). This is also the composition root: it
//  stands up the SwiftData-backed repositories (one shared container) and injects
//  them into the features. The active profile drives the app theme; finished
//  sessions persist via `onFinish` and surface on the Stats/History screens.
//

import SwiftUI
import Foundation
import CoreModels
import DesignSystem
import LibraryFeature
import QuizFeature
import ImportFeature
import StatsFeature
import Statistics
import ResultsFeature
import ProfileFeature
import VocabularyFeature
import MarkdownParser
import Persistence
import AIExplanation

public enum AppTab: Hashable { case library, practice, stats, profile }

/// Launch-time options, driven by environment variables so UI/snapshot tests
/// (and `simctl launch`) can deep-link into a screen. Harmless in normal use.
enum LaunchOptions {
    private static var screen: String? {
        ProcessInfo.processInfo.environment["MARKWISE_UITEST_SCREEN"]
    }
    static var initialTab: AppTab {
        switch screen {
        case "practice", "runner", "exam": .practice
        case "stats", "history":           .stats
        case "profile":                    .profile
        default:                           .library
        }
    }
    static var autostartRunner: Bool { screen == "runner" }
    static var autostartExam: Bool { screen == "exam" }
    static var showImportReview: Bool { screen == "import" }
    static var showHistory: Bool { screen == "history" }
    /// Deep-linking into a screen skips the first-run onboarding overlay.
    static var skipOnboarding: Bool { screen != nil }
}

public struct RootView: View {
    @State private var selection: AppTab
    @State private var library: LibraryViewModel
    @State private var stats: StatsViewModel
    @State private var profile: ProfileViewModel
    @State private var activeQuiz: QuizSessionViewModel?
    /// The vocabulary set currently open in the study hub (nil = none).
    @State private var activeVocab: VocabStudyPayload?
    @State private var showImportReview: Bool
    @State private var showHistory: Bool
    @State private var showWelcomeBack: Bool

    @AppStorage("markwise.hasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

    private let libraryRepository: any LibraryRepository
    private let sessionRepository: any SessionRepository
    /// Local store of generated AI explanations so review is instant and offline.
    private let explanationCache: any ExplanationCache
    /// Per-card flashcard review state for vocabulary sets.
    private let vocabReviewRepository: any VocabReviewRepository

    /// Keychain-backed store for the user's API key (presence-gated by `explain`).
    private let apiKeyStore = KeychainAPIKeyStore()

    public init() {
        // Composition root: prefer the on-disk SwiftData store (one container for
        // all repositories); fall back to in-memory if it can't be created.
        let repos = try? PersistenceStack.makeAppRepositories()
        let libraryRepo: any LibraryRepository = repos?.library ?? InMemoryLibraryRepository()
        let sessionRepo: any SessionRepository = repos?.session ?? InMemorySessionRepository()
        let profileRepo: any ProfileRepository = repos?.profile ?? InMemoryProfileRepository()
        self.libraryRepository = libraryRepo
        self.sessionRepository = sessionRepo
        self.explanationCache = repos?.explanationCache ?? InMemoryExplanationCache()
        self.vocabReviewRepository = repos?.vocabReview ?? InMemoryVocabReviewRepository()
        _library = State(initialValue: LibraryViewModel(repository: libraryRepo))
        _stats = State(initialValue: StatsViewModel(repository: sessionRepo))
        _profile = State(initialValue: ProfileViewModel(repository: profileRepo, sessionRepository: sessionRepo, libraryRepository: libraryRepo, apiKeyStore: KeychainAPIKeyStore(), explanationCache: repos?.explanationCache))
        _selection = State(initialValue: LaunchOptions.initialTab)
        _showImportReview = State(initialValue: LaunchOptions.showImportReview)
        _showHistory = State(initialValue: LaunchOptions.showHistory)
        // Greet returning users on a cold launch; first-run users see onboarding
        // instead, and UITest deep-links skip the greeting.
        let onboarded = UserDefaults.standard.bool(forKey: "markwise.hasOnboarded")
        _showWelcomeBack = State(initialValue: onboarded && !LaunchOptions.skipOnboarding)
    }

    /// The current theme, derived from the profile — re-tints the whole app when
    /// the user switches it in settings.
    private var theme: Theme { profile.theme }

    /// The injected explanation call, or nil when the feature is off or no key is
    /// stored (callers hide the "Ask AI" CTA then). Recomputed in `body`, so it
    /// reacts to the profile toggle and key changes.
    private var explain: ((ExplanationRequest) async throws -> Explanation)? {
        guard profile.profile.aiExplanationsEnabled, apiKeyStore.hasKey else { return nil }
        // Build per-call so the Profile model picker takes effect immediately.
        let modelID = profile.profile.aiModel.rawValue
        let service = ClaudeExplanationService(modelProvider: { modelID })
        let cache = explanationCache
        // Generate live, then persist so the next review is instant and offline.
        return { request in
            let explanation = try await service.explain(request)
            await cache.store(explanation, forKey: request.cacheKey)
            return explanation
        }
    }

    /// A local, offline cache lookup for an already-generated explanation. Gated on
    /// the AI toggle only (not the key) so previously generated explanations still
    /// show offline even without a key; nil when the feature is off.
    private var cachedExplanation: ((ExplanationRequest) async -> Explanation?)? {
        guard profile.profile.aiExplanationsEnabled else { return nil }
        let cache = explanationCache
        return { await cache.explanation(forKey: $0.cacheKey) }
    }

    /// The injected quiz-generation call, or nil when the feature is off or no key
    /// is stored (LibraryView hides the "Generate with AI" entry then). Reuses the
    /// same AI toggle + key as explanations. Recomputed in `body` so it reacts to
    /// the profile toggle and key changes.
    private var generateQuiz: ((QuizGenerationRequest) async throws -> String)? {
        guard profile.profile.aiExplanationsEnabled, apiKeyStore.hasKey else { return nil }
        let modelID = profile.profile.aiModel.rawValue
        let service = ClaudeQuizGenerationService(modelProvider: { modelID })
        return { try await service.generate($0) }
    }

    /// The injected vocabulary-structuring call, or nil when the feature is off or
    /// no key is stored (LibraryView hides the "Generate vocabulary" entry then).
    /// Reuses the same AI toggle + key + model as the other AI features.
    private var generateVocabulary: ((VocabularyGenerationRequest) async throws -> String)? {
        guard profile.profile.vocabularyEnabled else { return nil }
        guard profile.profile.aiExplanationsEnabled, apiKeyStore.hasKey else { return nil }
        let modelID = profile.profile.aiModel.rawValue
        let service = ClaudeVocabularyService(modelProvider: { modelID })
        return { try await service.generate($0) }
    }

    public var body: some View {
        TabView(selection: $selection) {
            LibraryView(
                model: library,
                onPlay: { file, markdown in
                    openFile(file, markdown: markdown)
                },
                generate: generateQuiz,
                generateVocabulary: generateVocabulary
            )
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppTab.library)

            PracticeView(
                sessionRepository: sessionRepository,
                profile: profile,
                library: library,
                onExplain: explain,
                onCached: cachedExplanation,
                onOpenVocabulary: { file in
                    Task {
                        if let markdown = await library.markdown(for: file) {
                            openFile(file, markdown: markdown)
                        }
                    }
                }
            )
            .tabItem { Label("Practice", systemImage: "play.circle") }
            .tag(AppTab.practice)

            statsTab()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(AppTab.stats)

            ProfileView(model: profile)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .markwiseTheme(theme)
        .fullScreenCover(
            isPresented: Binding(get: { activeQuiz != nil }, set: { if !$0 { activeQuiz = nil } })
        ) {
            if let activeQuiz {
                NavigationStack {
                    QuizRunnerView(model: activeQuiz)
                        .navigationTitle("Training")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { self.activeQuiz = nil }
                            }
                        }
                }
                .markwiseTheme(theme)
            }
        }
        .fullScreenCover(item: $activeVocab) { payload in
            // The study hub presents its translation quiz from a *nested* cover
            // (inside this one) rather than swapping two covers at this level,
            // which SwiftUI would drop — so the quiz reliably appears.
            VocabStudyContainer(
                payload: payload,
                reviewRepository: vocabReviewRepository,
                theme: theme,
                makeQuiz: { questions, scope, language in
                    makeQuiz(fromQuestions: questions, scope: scope, explanationLanguage: language)
                },
                onClose: { activeVocab = nil }
            )
            .markwiseTheme(theme)
        }
        .sheet(isPresented: $showImportReview) {
            ImportReviewView(
                suggestedTitle: "AZ-900 Sample",
                markdown: SampleQuiz.markdown,
                onConfirm: { _ in showImportReview = false },
                onCancel: { showImportReview = false }
            )
            .markwiseTheme(theme)
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                HistoryView(repository: sessionRepository, onExplain: explain)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showHistory = false }
                        }
                    }
            }
            .markwiseTheme(theme)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasOnboarded && !LaunchOptions.skipOnboarding },
            set: { presented in if !presented { hasOnboarded = true } }
        )) {
            OnboardingView { name in
                if !name.isEmpty {
                    profile.profile.displayName = name
                    Task { await profile.persist() }
                }
                hasOnboarded = true
            }
            .markwiseTheme(theme)
        }
        .fullScreenCover(isPresented: $showWelcomeBack) {
            WelcomeBackView(
                name: profile.profile.displayName,
                imageData: profile.profile.avatarImageData,
                symbol: profile.profile.avatarSymbol
            ) { showWelcomeBack = false }
            .markwiseTheme(theme)
        }
        .task { await seedIfNeeded() }
        .task {
            // TEMP: simulate opening a vocab file whose cached kind is .quiz (an
            // import saved before `kind` was persisted) to prove markdown routing.
            if ProcessInfo.processInfo.environment["MARKWISE_UITEST_SCREEN"] == "vocabopen" {
                let ref = QuizFileRef(
                    title: "Demo Vocab", storedFileName: "x", topicID: UUID(),
                    summary: ParseSummary(questionCount: 8, kind: .quiz)
                )
                openFile(ref, markdown: SampleVocab.markdown)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await importSharedFiles() } }
        }
        .onChange(of: selection) { _, tab in
            // Refresh the flat file list so newly imported quizzes appear in Practice.
            if tab == .practice { Task { await library.load() } }
        }
    }

    /// Drain any `.md` files the Share extension dropped into the App Group inbox,
    /// importing each into an "Imported › Shared" topic.
    private func importSharedFiles() async {
        let inbox = SharedInbox.shared()
        let pending = inbox.pendingFiles()
        guard !pending.isEmpty else { return }
        do {
            let topic = try await importedTopic()
            for file in pending {
                await library.importMarkdown(title: file.title, markdown: file.markdown, into: topic)
                inbox.remove(file)
            }
            await library.load()
        } catch {
            // Non-fatal: files remain in the inbox for the next foreground.
        }
    }

    /// Find (or create) the "Imported › Shared" destination for shared files.
    private func importedTopic() async throws -> Topic {
        let categories = try await libraryRepository.categories()
        let category: CoreModels.Category
        if let existing = categories.first(where: { $0.name == "Imported" }) {
            category = existing
        } else {
            category = try await libraryRepository.createCategory(name: "Imported")
        }
        let topics = try await libraryRepository.topics(in: category.id)
        if let existing = topics.first(where: { $0.name == "Shared" }) {
            return existing
        }
        return try await libraryRepository.createTopic(name: "Shared", in: category.id)
    }

    /// Open a tapped library file: vocabulary sets go to the study hub, quizzes
    /// straight into the runner. Falls back to the quiz path if a file tagged
    /// vocabulary can't be parsed as one.
    private func openFile(_ file: QuizFileRef, markdown: String) {
        // Route on the markdown itself (authoritative), not just the cached kind —
        // so files imported before `kind` was persisted still open as vocabulary.
        let isVocab = file.summary.kind == .vocabulary || VocabularyParser.isVocabulary(markdown)
        if isVocab, let set = VocabularyParser().parse(markdown) {
            activeVocab = VocabStudyPayload(fileID: file.id, title: file.title, set: set)
        } else {
            activeQuiz = makeQuiz(markdown: markdown, scope: file.title)
        }
    }

    /// Build a quiz view model that uses the profile's defaults and persists its
    /// result when submitted.
    private func makeQuiz(markdown: String, scope: String, mode: SessionMode = .training) -> QuizSessionViewModel {
        let model = QuizSessionViewModel.make(fromMarkdown: markdown, config: quizConfig(mode: mode))
        return configureQuiz(model, scope: scope)
    }

    /// Build a quiz view model from already-parsed questions (used for the
    /// translation quizzes derived from a vocabulary set). `explanationLanguage`
    /// is the learner's native language, so AI explanations come back in it.
    private func makeQuiz(fromQuestions questions: [Question], scope: String, mode: SessionMode = .training, explanationLanguage: String? = nil) -> QuizSessionViewModel {
        let model = QuizSessionViewModel.make(fromQuestions: questions, config: quizConfig(mode: mode))
        return configureQuiz(model, scope: scope, explanationLanguage: explanationLanguage)
    }

    private func quizConfig(mode: SessionMode) -> SessionConfig {
        let defaults = profile.profile
        return SessionConfig(
            mode: mode,
            questionCount: defaults.defaultQuestionCount,
            shuffleAnswers: true,
            passThreshold: defaults.defaultPassThreshold,
            timeLimit: mode == .exam ? defaults.defaultTimeLimit : nil,
            seed: 7
        )
    }

    /// Apply the profile defaults, AI hooks, and result-persistence to a quiz model.
    private func configureQuiz(_ model: QuizSessionViewModel, scope: String, explanationLanguage: String? = nil) -> QuizSessionViewModel {
        model.hapticsEnabled = profile.profile.hapticsEnabled
        model.onExplain = explain
        model.onCachedExplanation = cachedExplanation
        model.explanationLanguage = explanationLanguage
        let repo = sessionRepository
        model.onFinish = { result in
            Task { try? await repo.save(SessionRecord(scopeLabel: scope, result: result)) }
        }
        return model
    }

    // MARK: - Stats tab + its practice shortcuts

    /// The Stats tab, wired so its review / topic / missed shortcuts launch a
    /// Training session. The action closures are assigned here (not in `init`)
    /// because they depend on the live profile and AI hooks, which are recomputed
    /// per render; they're `@ObservationIgnored` on the model, so re-assigning them
    /// during body evaluation doesn't trigger a re-render.
    private func statsTab() -> some View {
        stats.onReviewWeakAreas = { startReviewSession() }
        stats.onPracticeTopic = { startTopicSession($0) }
        stats.onPracticeMissed = { startMissedSession($0) }
        return NavigationStack {
            StatsView(model: stats)
                .navigationTitle("Stats")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            HistoryView(repository: sessionRepository, onExplain: explain, onCached: cachedExplanation)
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                }
        }
    }

    /// Re-quiz the spaced-review queue (the same pool the Practice tab builds).
    private func startReviewSession() {
        Task {
            await library.load()
            let records = (try? await sessionRepository.allRecords()) ?? []
            let due = Statistics.dueForReview(from: records)
            let pool = await library.reviewQuestions(forPrompts: due, limit: 200)
            launchReview(pool: pool, scope: "Weak areas review")
        }
    }

    /// Practice every question tagged with a weak topic.
    private func startTopicSession(_ topic: String) {
        Task {
            await library.load()
            let pool = await library.questions(forTag: topic, limit: 200)
            launchReview(pool: pool, scope: "\(topic) practice")
        }
    }

    /// Re-quiz a single missed question by its prompt.
    private func startMissedSession(_ prompt: String) {
        Task {
            await library.load()
            let pool = await library.reviewQuestions(forPrompts: [prompt], limit: 50)
            launchReview(pool: pool, scope: "Review")
        }
    }

    private func launchReview(pool: [Question], scope: String) {
        guard !pool.isEmpty else { return }
        let defaults = profile.profile
        activeQuiz = SessionLauncher.reviewSession(
            questions: pool,
            scope: scope,
            passThreshold: defaults.defaultPassThreshold,
            hapticsEnabled: defaults.hapticsEnabled,
            onExplain: explain,
            onCached: cachedExplanation,
            repository: sessionRepository
        )
    }

    /// On first launch, seed one category/topic + the sample and a handful of
    /// sample sessions so the Library and Stats tabs have something to show.
    private func seedIfNeeded() async {
        await profile.load()
        do {
            if try await libraryRepository.isEmpty() {
                let category = try await libraryRepository.createCategory(name: "Microsoft Azure")
                let topic = try await libraryRepository.createTopic(name: "Cloud Concepts", in: category.id)
                await library.importMarkdown(
                    title: "AZ-900 Sample", markdown: SampleQuiz.markdown, into: topic
                )

                // Seed a sample vocabulary set so the foreign-words feature is
                // discoverable (parses through the normal vocab path, no AI needed).
                let languages = try await libraryRepository.createCategory(name: "Languages")
                let croatian = try await libraryRepository.createTopic(name: "Croatian", in: languages.id)
                if let set = VocabularyParser().parse(SampleVocab.markdown) {
                    await library.add(
                        title: SampleVocab.title, markdown: SampleVocab.markdown,
                        summary: ParseSummary(set), topicID: croatian.id, folder: nil
                    )
                }
            }
            if try await sessionRepository.allRecords().isEmpty {
                for record in SampleSessions.make() { try await sessionRepository.save(record) }
            }
        } catch {
            // Non-fatal: tabs simply show their empty states.
        }
        await library.load()
        await stats.load()
    }
}

/// Identifiable payload for presenting the vocabulary study hub over a tapped file.
struct VocabStudyPayload: Identifiable {
    var id: UUID { fileID }
    let fileID: UUID
    let title: String
    let set: VocabularySet
}

/// Hosts the vocabulary study hub and presents its translation quiz from a nested
/// full-screen cover. Keeping the quiz cover *inside* the study cover (rather than
/// swapping two covers at the root) is what makes the quiz reliably appear — and
/// dismissing it returns to the hub, where progress refreshes.
private struct VocabStudyContainer: View {
    let payload: VocabStudyPayload
    let reviewRepository: any VocabReviewRepository
    let theme: Theme
    let makeQuiz: ([Question], String, String?) -> QuizSessionViewModel
    let onClose: () -> Void

    @State private var quiz: QuizSessionViewModel?

    /// The learner's native language, passed to the quiz so AI explanations are
    /// written in it. nil when the set didn't name one.
    private var nativeLanguage: String? {
        let name = payload.set.nativeLanguage.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    var body: some View {
        VocabularyStudyView(
            set: payload.set,
            fileID: payload.fileID,
            reviewRepository: reviewRepository,
            onStartQuiz: { parsed in
                quiz = makeQuiz(parsed.questions, payload.title, nativeLanguage)
            },
            onClose: onClose
        )
        .fullScreenCover(
            isPresented: Binding(get: { quiz != nil }, set: { if !$0 { quiz = nil } })
        ) {
            if let quiz {
                NavigationStack {
                    QuizRunnerView(model: quiz)
                        .navigationTitle("Quiz")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { self.quiz = nil }
                            }
                        }
                }
                .markwiseTheme(theme)
            }
        }
    }
}

/// A small bundled vocabulary set, seeded on first launch so the feature is
/// discoverable without an API key (it parses through the normal import path).
enum SampleVocab {
    static let title = "Croatian — Travel Basics"
    static let markdown = """
    ---
    kind: vocabulary
    title: Croatian — Travel Basics
    foreign: Croatian (hr)
    native: English (en)
    ---

    | Term | Translation | Pronunciation | Example |
    |------|-------------|---------------|---------|
    | dobar dan | good day | DOH-bar dahn | Dobar dan, kako ste? |
    | hvala | thank you | HVAH-lah | Hvala lijepa! |
    | molim | please | MOH-leem | Molim vas. |
    | da | yes | dah |  |
    | ne | no | neh |  |
    | gdje je | where is | g-DYEH yeh | Gdje je kolodvor? |
    | koliko košta | how much is it | KOH-lee-koh KOSH-ta | Koliko košta ovo? |
    | molim vas | excuse me / please | MOH-leem vahs |  |
    """
}

#Preview("Root") {
    RootView()
}

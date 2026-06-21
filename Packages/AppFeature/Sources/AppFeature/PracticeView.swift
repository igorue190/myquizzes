//
//  PracticeView.swift
//  AppFeature
//
//  The practice launcher: choose Training vs Exam, then pick a quiz to run —
//  either one of the user's imported Library files or the bundled sample — and
//  run it through the real parser + engine, rendered by QuizFeature's runner.
//  Imported quizzes appear here because the view observes the LibraryViewModel's
//  flat `files` list (refreshed whenever the Library loads).
//
//  Visually it speaks the same glass language as Library and Stats: an
//  `AppBackground` under a `ScrollView` of glass cards (the review CTA and the
//  session options) above a 2-column `LazyVGrid` of square launch tiles — one
//  per quiz / vocabulary set / sample. No List, no flat rows.
//

import SwiftUI
import CoreModels
import QuizFeature
import ProfileFeature
import LibraryFeature
import Statistics
import DesignSystem

struct PracticeView: View {
    let sessionRepository: any SessionRepository
    let profile: ProfileViewModel
    let library: LibraryViewModel
    /// Injected AI-explanation call, gated/built by RootView. nil ⇒ no "Ask AI"
    /// button. Set on every quiz model this view launches.
    var onExplain: ((ExplanationRequest) async throws -> Explanation)? = nil
    /// Injected local cache lookup (offline). Set on every quiz model launched.
    var onCached: ((ExplanationRequest) async -> Explanation?)? = nil
    /// Open a tapped vocabulary set in the study hub. Wired by RootView (which owns
    /// the study-hub presentation); nil ⇒ the Vocabulary section is hidden.
    var onOpenVocabulary: ((QuizFileRef) -> Void)? = nil

    @State private var runningModel: QuizSessionViewModel?
    @State private var isRunning = false
    @State private var mode: SessionMode = .training
    /// 0 = all questions in the quiz; otherwise a fixed count. Seeded from the
    /// profile default on first appearance, then user-adjustable per session.
    @State private var questionCount = 0
    @State private var initializedCount = false
    @State private var shuffleQuestions = false
    /// Questions currently due for spaced review, rebuilt from history + library
    /// each time the tab appears or a session finishes.
    @State private var reviewPool: [Question] = []

    /// Two equal, flexible columns — the "two square tiles per row" grid, matching
    /// Library's launcher footprint.
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Spacing.md), GridItem(.flexible(), spacing: Spacing.md)]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        reviewCard
                        optionsCard
                        quizzesSection
                        vocabularySection
                        sampleSection
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationTitle("Practice")
            .navigationDestination(isPresented: $isRunning) {
                if let runningModel {
                    QuizRunnerView(model: runningModel)
                        .navigationTitle(runningModel.mode == .exam ? "Exam" : "Training")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .task {
                if !initializedCount {
                    questionCount = profile.profile.defaultQuestionCount ?? 0
                    initializedCount = true
                }
                await loadReview()
                // Deep-link for UI/snapshot tests: jump straight into a session.
                guard !isRunning else { return }
                if LaunchOptions.autostartExam {
                    startSample(.exam)
                } else if LaunchOptions.autostartRunner {
                    startSample(.training)
                }
            }
            .onChange(of: isRunning) { _, running in
                // A finished session changes what's weak — refresh on return.
                if !running { Task { await loadReview() } }
            }
        }
    }

    // MARK: - Sections

    /// Smart-review call to action — mirrors Stats' "Up next" card. Always shown so
    /// the affordance is discoverable; the button is disabled until something is due.
    private var reviewCard: some View {
        GlassCard {
            Label("Smart review", systemImage: "sparkles")
        } content: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(reviewPool.isEmpty
                     ? "Nothing due yet — take a few quizzes first."
                     : "^[\(reviewPool.count) question](inflect: true) due for review")
                    .font(Typography.body)
                Text("Re-quizzes the questions you miss most, in Training mode. Answer one correctly twice and it graduates out of review.")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                Button { startReview() } label: {
                    Label("Review now", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary)
                .disabled(reviewPool.isEmpty)
            }
        }
    }

    /// Session options — mode, question count, and shuffle — grouped on one glass
    /// panel, the way Stats groups its scope controls.
    private var optionsCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Picker("Mode", selection: $mode) {
                    Text("Training").tag(SessionMode.training)
                    Text("Exam").tag(SessionMode.exam)
                }
                .pickerStyle(.segmented)

                Picker("Questions", selection: $questionCount) {
                    Text("All").tag(0)
                    ForEach([5, 10, 15, 25, 50], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.menu)

                Toggle("Shuffle questions", isOn: $shuffleQuestions)
                    .font(Typography.callout)

                Text(mode == .training
                     ? "Training reveals correctness as you answer."
                     : "Exam hides feedback and scores at the end (timed if set in Profile).")
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Imported quizzes (vocabulary sets are listed separately, in their own section).
    private var quizFiles: [QuizFileRef] {
        library.files.filter { $0.summary.kind != .vocabulary }
    }

    /// Imported vocabulary sets, surfaced only when the feature is enabled.
    private var vocabFiles: [QuizFileRef] {
        library.files.filter { $0.summary.kind == .vocabulary }
    }

    private var quizzesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Your quizzes")
            if quizFiles.isEmpty {
                GlassPanel {
                    Text("No quizzes yet. Import one from the Library tab and it'll show up here to practice.")
                        .font(Typography.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(quizFiles) { file in
                        LaunchTile(
                            title: file.title,
                            subtitle: pluralized(file.summary.questionCount, "question"),
                            badge: "Quiz",
                            badgeColor: ColorTokens.brand,
                            icon: "doc.text.fill",
                            seed: tileSeed(file.id)
                        ) { startFile(file) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var vocabularySection: some View {
        if profile.profile.vocabularyEnabled, onOpenVocabulary != nil, !vocabFiles.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionHeader("Vocabulary")
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(vocabFiles) { file in
                        LaunchTile(
                            title: file.title,
                            subtitle: pluralized(file.summary.questionCount, "word"),
                            badge: "Vocabulary",
                            badgeColor: ColorTokens.info,
                            icon: "character.book.closed.fill",
                            seed: tileSeed(file.id)
                        ) { onOpenVocabulary?(file) }
                    }
                }
            }
        }
    }

    private var sampleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Sample")
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                LaunchTile(
                    title: "AZ-900 — Cloud Concepts",
                    subtitle: "4-question built-in sample",
                    badge: "Quiz",
                    badgeColor: ColorTokens.brand,
                    icon: "doc.text.fill",
                    seed: sampleTileSeed
                ) { startSample(mode) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(Typography.title)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.top, Spacing.xs)
    }

    /// Manual pluralization. The `^[…](inflect:)` markup only resolves when SwiftUI
    /// renders a `LocalizedStringKey`; these subtitles travel as plain `String`s into
    /// the row builders, so we pluralize here instead of relying on that markup.
    private func pluralized(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: - Smart review

    /// Rebuild the review pool: ask Statistics which prompts are due, then have
    /// the Library reconstruct the matching questions (with their choices).
    private func loadReview() async {
        await library.load()
        let records = (try? await sessionRepository.allRecords()) ?? []
        let due = Statistics.dueForReview(from: records)
        reviewPool = await library.reviewQuestions(forPrompts: due, limit: 200)
    }

    private func startReview() {
        guard !reviewPool.isEmpty else { return }
        let pool = questionCount == 0 ? reviewPool : Array(reviewPool.prefix(questionCount))
        let defaults = profile.profile
        runningModel = SessionLauncher.reviewSession(
            questions: pool,
            scope: "Weak areas review",
            passThreshold: defaults.defaultPassThreshold,
            hapticsEnabled: defaults.hapticsEnabled,
            onExplain: onExplain,
            onCached: onCached,
            repository: sessionRepository
        )
        isRunning = true
    }

    // MARK: - Launch

    private func startFile(_ file: QuizFileRef) {
        Task {
            guard let markdown = await library.markdown(for: file) else { return }
            run(markdown: markdown, scope: file.title)
        }
    }

    /// Run the bundled sample. An optional `forcedMode` lets the UITest deep-link
    /// pick the mode without touching the segmented control.
    private func startSample(_ forcedMode: SessionMode? = nil) {
        if let forcedMode { mode = forcedMode }
        run(markdown: SampleQuiz.markdown, scope: "AZ-900 Sample")
    }

    private func run(markdown: String, scope: String) {
        let defaults = profile.profile
        let config = SessionConfig(
            mode: mode,
            questionCount: questionCount == 0 ? nil : questionCount,
            shuffleQuestions: shuffleQuestions,
            shuffleAnswers: true,
            passThreshold: defaults.defaultPassThreshold,
            timeLimit: mode == .exam ? defaults.defaultTimeLimit : nil,
            seed: UInt64(Date().timeIntervalSince1970)
        )
        let model = QuizSessionViewModel.make(fromMarkdown: markdown, config: config)
        model.hapticsEnabled = defaults.hapticsEnabled
        model.onExplain = onExplain
        model.onCachedExplanation = onCached
        let repo = sessionRepository
        model.onFinish = { result in
            Task { try? await repo.save(SessionRecord(scopeLabel: scope, result: result)) }
        }
        runningModel = model
        isRunning = true
    }
}

// MARK: - Launch tile

/// A square, game-like tile that starts a session when tapped — the Practice-tab
/// counterpart to Library's `FileTile`: a gradient icon badge with a "play" glyph,
/// a kind chip, the title, and an item count, all on an interactive glass surface.
private struct LaunchTile: View {
    let title: String
    let subtitle: String
    let badge: String
    let badgeColor: Color
    let icon: String
    let seed: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    ZStack {
                        Circle().fill(ColorTokens.tileGradient(seed: seed))
                        Image(systemName: icon)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 52, height: 52)
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(ColorTokens.brand)
                }

                Spacer(minLength: Spacing.sm)

                TagChip(badge, kind: .semantic(badgeColor))
                Text(title)
                    .font(Typography.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .aspectRatio(1, contentMode: .fit)
            // Make the whole tile tappable, not just the icon/text.
            .contentShape(Rectangle())
            .glassSurface(.regular, cornerRadius: Radius.xl, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

/// A deterministic seed from a UUID so a tile keeps its gradient across launches
/// (`UUID.hashValue` is randomized per process, so we hash the text instead).
private func tileSeed(_ id: UUID) -> Int {
    id.uuidString.unicodeScalars.reduce(into: 0) { $0 = $0 &* 31 &+ Int($1.value) }
}

/// A fixed seed for the bundled sample tile, which has no persisted id.
private let sampleTileSeed = 0xA2900

/// The bundled sample, embedded so the Practice tab works with no file import.
enum SampleQuiz {
    static let markdown = """
    ---
    title: AZ-900 — Azure Fundamentals
    topic: Cloud Concepts
    difficulty: beginner
    passThreshold: 70
    ---

    ## Which cloud service model gives the most control over the operating system?
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

    > **Explanation:** Elasticity means automatic scale-out/in with consumption-based billing.

    ## Azure Availability Zones protect against a full region outage.
    <!-- type: truefalse -->
    - [ ] True
    - [x] False

    > **Explanation:** Availability Zones protect against datacenter-level failures within a region, not a full region outage.

    ## A resource group is a logical container for related Azure resources.
    - [x] True
    - [ ] False

    > **Explanation:** Resource groups hold resources that share the same lifecycle.
    """
}

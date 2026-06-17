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

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    reviewSection
                    modeSection
                    librarySection
                    sampleSection
                }
                .scrollContentBackground(.hidden)
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

    private var reviewSection: some View {
        Section {
            Button { startReview() } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title3)
                        .foregroundStyle(ColorTokens.brandGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Review weak areas").font(Typography.body).foregroundStyle(.primary)
                        Text(reviewPool.isEmpty
                             ? "Nothing due yet — take a few quizzes first"
                             : "^[\(reviewPool.count) question](inflect: true) to review")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .disabled(reviewPool.isEmpty)
            .listRowBackground(rowBackground)
        } header: {
            Text("Smart review")
        } footer: {
            Text("Re-quizzes the questions you miss most, in Training mode. Answer one correctly twice and it graduates out of review.")
        }
    }

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $mode) {
                Text("Training").tag(SessionMode.training)
                Text("Exam").tag(SessionMode.exam)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Picker("Questions", selection: $questionCount) {
                Text("All").tag(0)
                ForEach([5, 10, 15, 25, 50], id: \.self) { Text("\($0)").tag($0) }
            }

            Toggle("Shuffle questions", isOn: $shuffleQuestions)
        } footer: {
            Text(mode == .training
                 ? "Training reveals correctness as you answer."
                 : "Exam hides feedback and scores at the end (timed if set in Profile).")
        }
    }

    private var librarySection: some View {
        Section("Your quizzes") {
            if library.files.isEmpty {
                Text("Imported quizzes show up here. Add one from the Library tab, then pick it to practice.")
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(library.files) { file in
                Button { startFile(file) } label: {
                    quizRow(title: file.title,
                            subtitle: "^[\(file.summary.questionCount) question](inflect: true)")
                }
                .listRowBackground(rowBackground)
            }
        }
    }

    private var sampleSection: some View {
        Section("Sample") {
            Button { startSample(mode) } label: {
                quizRow(title: "AZ-900 — Cloud Concepts",
                        subtitle: "4-question built-in sample")
            }
            .listRowBackground(rowBackground)
        }
    }

    private func quizRow(title: String, subtitle: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundStyle(ColorTokens.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.body).foregroundStyle(.primary)
                Text(subtitle).font(Typography.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var rowBackground: Color { Color(.systemBackground).opacity(0.5) }

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
        let config = SessionConfig(
            mode: .training,
            questionCount: nil,
            shuffleAnswers: true,
            passThreshold: defaults.defaultPassThreshold,
            timeLimit: nil,
            seed: UInt64(Date().timeIntervalSince1970)
        )
        let model = QuizSessionViewModel.make(fromQuestions: pool, config: config)
        model.hapticsEnabled = defaults.hapticsEnabled
        let repo = sessionRepository
        model.onFinish = { result in
            Task { try? await repo.save(SessionRecord(scopeLabel: "Weak areas review", result: result)) }
        }
        runningModel = model
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
        let repo = sessionRepository
        model.onFinish = { result in
            Task { try? await repo.save(SessionRecord(scopeLabel: scope, result: result)) }
        }
        runningModel = model
        isRunning = true
    }
}

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

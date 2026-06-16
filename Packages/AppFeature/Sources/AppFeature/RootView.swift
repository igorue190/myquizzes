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
import ResultsFeature
import ProfileFeature
import Persistence

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
}

public struct RootView: View {
    @State private var selection: AppTab
    @State private var library: LibraryViewModel
    @State private var stats: StatsViewModel
    @State private var profile: ProfileViewModel
    @State private var activeQuiz: QuizSessionViewModel?
    @State private var showImportReview: Bool
    @State private var showHistory: Bool

    private let libraryRepository: any LibraryRepository
    private let sessionRepository: any SessionRepository

    public init() {
        // Composition root: prefer the on-disk SwiftData store (one container for
        // all repositories); fall back to in-memory if it can't be created.
        let repos = try? PersistenceStack.makeAppRepositories()
        let libraryRepo: any LibraryRepository = repos?.library ?? InMemoryLibraryRepository()
        let sessionRepo: any SessionRepository = repos?.session ?? InMemorySessionRepository()
        let profileRepo: any ProfileRepository = repos?.profile ?? InMemoryProfileRepository()
        self.libraryRepository = libraryRepo
        self.sessionRepository = sessionRepo
        _library = State(initialValue: LibraryViewModel(repository: libraryRepo))
        _stats = State(initialValue: StatsViewModel(repository: sessionRepo))
        _profile = State(initialValue: ProfileViewModel(repository: profileRepo, sessionRepository: sessionRepo))
        _selection = State(initialValue: LaunchOptions.initialTab)
        _showImportReview = State(initialValue: LaunchOptions.showImportReview)
        _showHistory = State(initialValue: LaunchOptions.showHistory)
    }

    /// The current theme, derived from the profile — re-tints the whole app when
    /// the user switches it in settings.
    private var theme: Theme { profile.theme }

    public var body: some View {
        TabView(selection: $selection) {
            LibraryView(model: library) { file, markdown in
                activeQuiz = makeQuiz(markdown: markdown, scope: file.title)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(AppTab.library)

            PracticeView(sessionRepository: sessionRepository, profile: profile)
                .tabItem { Label("Practice", systemImage: "play.circle") }
                .tag(AppTab.practice)

            NavigationStack {
                StatsView(model: stats)
                    .navigationTitle("Stats")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink {
                                HistoryView(repository: sessionRepository)
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                    }
            }
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
                HistoryView(repository: sessionRepository)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showHistory = false }
                        }
                    }
            }
            .markwiseTheme(theme)
        }
        .task { await seedIfNeeded() }
    }

    /// Build a quiz view model that uses the profile's defaults and persists its
    /// result when submitted.
    private func makeQuiz(markdown: String, scope: String, mode: SessionMode = .training) -> QuizSessionViewModel {
        let defaults = profile.profile
        let config = SessionConfig(
            mode: mode,
            questionCount: defaults.defaultQuestionCount,
            shuffleAnswers: true,
            passThreshold: defaults.defaultPassThreshold,
            timeLimit: mode == .exam ? defaults.defaultTimeLimit : nil,
            seed: 7
        )
        let model = QuizSessionViewModel.make(fromMarkdown: markdown, config: config)
        model.hapticsEnabled = defaults.hapticsEnabled
        let repo = sessionRepository
        model.onFinish = { result in
            Task { try? await repo.save(SessionRecord(scopeLabel: scope, result: result)) }
        }
        return model
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

#Preview("Root") {
    RootView()
}

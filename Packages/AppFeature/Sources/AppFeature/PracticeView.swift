//
//  PracticeView.swift
//  AppFeature
//
//  The working vertical slice: pick a mode, and run the bundled sample quiz
//  through the real parser + engine, rendered by QuizFeature's runner. This is
//  the end-to-end proof that parser → engine → view model → Liquid Glass UI all
//  compose. A later phase swaps the embedded sample for the user's Library.
//

import SwiftUI
import CoreModels
import QuizFeature
import ProfileFeature
import DesignSystem

struct PracticeView: View {
    let sessionRepository: any SessionRepository
    let profile: ProfileViewModel

    @State private var runningModel: QuizSessionViewModel?
    @State private var isRunning = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: Spacing.xl) {
                    GlassCard {
                        Label("AZ-900 — Cloud Concepts", systemImage: "cloud.fill")
                    } content: {
                        Text("A 4-question sample parsed from Markdown. Training gives feedback as you go; Exam scores at the end.")
                            .font(Typography.callout)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: Spacing.md) {
                        Button("Start training") { start(.training) }
                            .buttonStyle(.glassPrimary)
                        Button("Start exam") { start(.exam) }
                            .buttonStyle(.glassSecondary)
                    }
                }
                .padding(Spacing.lg)
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
                // Deep-link for UI/snapshot tests: jump straight into a session.
                guard !isRunning else { return }
                if LaunchOptions.autostartExam {
                    start(.exam)
                } else if LaunchOptions.autostartRunner {
                    start(.training)
                }
            }
        }
    }

    private func start(_ mode: SessionMode) {
        let defaults = profile.profile
        let config = SessionConfig(
            mode: mode,
            questionCount: defaults.defaultQuestionCount,
            shuffleAnswers: true,
            passThreshold: defaults.defaultPassThreshold,
            timeLimit: mode == .exam ? defaults.defaultTimeLimit : nil,
            seed: 2026
        )
        let model = QuizSessionViewModel.make(fromMarkdown: SampleQuiz.markdown, config: config)
        model.hapticsEnabled = defaults.hapticsEnabled
        let repo = sessionRepository
        model.onFinish = { result in
            Task { try? await repo.save(SessionRecord(scopeLabel: "AZ-900 Sample", result: result)) }
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

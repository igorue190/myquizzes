//
//  ProfileView.swift
//  ProfileFeature
//
//  The settings form: identity, appearance (theme), default exam settings,
//  haptics, and data management. Edits persist automatically (on change).
//

import SwiftUI
import CoreModels
import DesignSystem

public struct ProfileView: View {
    @Bindable private var model: ProfileViewModel

    @State private var showDeleteConfirm = false
    @State private var exportItem: ExportItem?

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
                dataSection
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Profile")
        }
        .task { await model.load() }
        .onChange(of: model.profile) { Task { await model.persist() } }
        .alert("Delete all history?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await model.clearHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved session result. It can't be undone.")
        }
        .sheet(item: $exportItem) { item in
            exportSheet(item.text)
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Profile") {
            HStack {
                Spacer()
                Image(systemName: model.profile.avatarSymbol)
                    .font(.system(size: 56))
                    .foregroundStyle(ColorTokens.brandGradient)
                    .symbolEffect(.bounce, value: model.profile.avatarSymbol)
                Spacer()
            }
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
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Everything stays on this device — no account, no network.")
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

#Preview("Profile") {
    ProfileView(
        model: ProfileViewModel(
            repository: InMemoryProfileRepository(),
            sessionRepository: InMemorySessionRepository()
        )
    )
    .markwiseTheme(.standard)
}

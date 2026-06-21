//
//  DataSettingsView.swift
//  ProfileFeature
//
//  The "Data & backup" sub-settings screen, pushed from the Profile form. Groups
//  all data management: full backup/restore (one portable file) and history
//  export/clear. Everything stays on device; the only output is files the user
//  explicitly shares.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreModels
import DesignSystem

struct DataSettingsView: View {
    @Bindable var model: ProfileViewModel

    @State private var showDeleteConfirm = false
    @State private var exportItem: ExportItem?
    @State private var backupShare: BackupShare?
    @State private var showRestorePicker = false
    @State private var restoreResult: RestoreResult?
    @State private var isWorking = false
    @State private var cacheCleared = false

    var body: some View {
        Form {
            backupSection
            dataSection
            cacheSection
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Data & backup")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete all history?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await model.clearHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved session result. It can't be undone.")
        }
        .sheet(item: $exportItem) { item in exportSheet(item.text) }
        .sheet(item: $backupShare) { share in backupShareSheet(share.url) }
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
            Text("History")
        } footer: {
            Text("Everything stays on this device — no account, no network.")
        }
    }

    private var cacheSection: some View {
        Section {
            Button {
                Task {
                    await model.clearExplanationCache()
                    cacheCleared = true
                }
            } label: {
                Label(cacheCleared ? "Cache cleared" : "Clear AI explanation cache",
                      systemImage: cacheCleared ? "checkmark.circle" : "sparkles.rectangle.stack")
            }
            .disabled(cacheCleared)
        } header: {
            Text("AI cache")
        } footer: {
            Text("Removes saved AI explanations from this device. They're regenerated on demand the next time you ask — nothing else is affected.")
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
}

// MARK: - Sheet item carriers

struct ExportItem: Identifiable {
    let id = UUID()
    let text: String
}

struct BackupShare: Identifiable {
    let id = UUID()
    let url: URL
}

enum RestoreResult: Identifiable {
    case success(String?)
    case failure
    var id: String {
        switch self {
        case .success: "success"
        case .failure: "failure"
        }
    }
}

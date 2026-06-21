//
//  HistoryView.swift
//  ResultsFeature
//
//  The list of past sessions (newest first). Tapping one opens its summary.
//  Must be hosted inside a NavigationStack by the caller.
//

import SwiftUI
import Foundation
import Observation
import CoreModels
import DesignSystem

@MainActor
@Observable
public final class HistoryViewModel {
    private let repository: any SessionRepository
    public private(set) var records: [SessionRecord] = []

    public init(repository: any SessionRepository) {
        self.repository = repository
    }

    public func load() async {
        let all = (try? await repository.allRecords()) ?? []
        records = all.reversed()   // newest first
    }
}

public struct HistoryView: View {
    @State private var model: HistoryViewModel
    private let onExplain: ((ExplanationRequest) async throws -> Explanation)?
    private let onCached: ((ExplanationRequest) async -> Explanation?)?

    public init(
        model: HistoryViewModel,
        onExplain: ((ExplanationRequest) async throws -> Explanation)? = nil,
        onCached: ((ExplanationRequest) async -> Explanation?)? = nil
    ) {
        _model = State(initialValue: model)
        self.onExplain = onExplain
        self.onCached = onCached
    }

    public init(
        repository: any SessionRepository,
        onExplain: ((ExplanationRequest) async throws -> Explanation)? = nil,
        onCached: ((ExplanationRequest) async -> Explanation?)? = nil
    ) {
        _model = State(initialValue: HistoryViewModel(repository: repository))
        self.onExplain = onExplain
        self.onCached = onCached
    }

    public var body: some View {
        ZStack {
            AppBackground()
            if model.records.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No history yet",
                    message: "Finish a quiz and it'll appear here."
                )
            } else {
                List {
                    ForEach(model.records) { record in
                        NavigationLink {
                            SessionSummaryView(record: record, onExplain: onExplain, onCached: onCached)
                        } label: {
                            HistoryRow(record: record)
                        }
                        .listRowBackground(Color(.systemBackground).opacity(0.5))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("History")
        .task { await model.load() }
    }
}

private struct HistoryRow: View {
    let record: SessionRecord

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.scopeLabel ?? "Quiz").font(Typography.body)
                Text(record.finishedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(record.percentage.rounded()))%")
                .font(Typography.headline)
                .foregroundStyle(record.passed ? ColorTokens.success : ColorTokens.danger)
            TagChip(
                record.passed ? "Pass" : "Fail",
                kind: .semantic(record.passed ? ColorTokens.success : ColorTokens.danger)
            )
        }
    }
}

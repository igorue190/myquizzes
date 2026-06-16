//
//  SessionHistory.swift
//  CoreModels
//
//  Persisted history of finished sessions, plus its repository boundary. A
//  `SessionRecord` wraps the engine's pure `SessionResult` with the metadata
//  history needs (when it finished, what it covered). The Statistics package
//  aggregates `[SessionRecord]`; Persistence stores them.
//

import Foundation

/// One finished session, persisted for history and statistics (plan §7).
public struct SessionRecord: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: UUID
    public let finishedAt: Date
    /// Human label for what was studied (file/topic name), for the history list.
    public let scopeLabel: String?
    public let result: SessionResult

    public init(
        id: UUID = UUID(),
        finishedAt: Date = Date(),
        scopeLabel: String? = nil,
        result: SessionResult
    ) {
        self.id = id
        self.finishedAt = finishedAt
        self.scopeLabel = scopeLabel
        self.result = result
    }

    public var mode: SessionMode { result.mode }
    public var percentage: Double { result.percentage }
    public var passed: Bool { result.passed }
    public var correctCount: Int { result.correctCount }
    public var totalQuestions: Int { result.totalQuestions }
}

/// The persistence boundary for session history. Implemented by SwiftData in
/// Persistence and by `InMemorySessionRepository` for tests/previews.
public protocol SessionRepository: Sendable {
    func save(_ record: SessionRecord) async throws
    /// All records, oldest first (chronological — convenient for trend charts).
    func allRecords() async throws -> [SessionRecord]
    func deleteAll() async throws
}

public actor InMemorySessionRepository: SessionRepository {
    private var records: [UUID: SessionRecord] = [:]

    public init() {}

    public func save(_ record: SessionRecord) async throws {
        records[record.id] = record
    }

    public func allRecords() async throws -> [SessionRecord] {
        records.values.sorted { $0.finishedAt < $1.finishedAt }
    }

    public func deleteAll() async throws {
        records.removeAll()
    }
}

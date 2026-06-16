//
//  SessionRecordEntity.swift
//  Persistence
//
//  Stores a finished session. The full `SessionRecord` (Codable) is kept as a
//  JSON payload; `finishedAt` is denormalized as a column so history can be
//  fetched in chronological order without decoding every row.
//

import Foundation
import SwiftData

@Model
final class SessionRecordEntity {
    @Attribute(.unique) var id: UUID
    var finishedAt: Date
    var payload: Data

    init(id: UUID, finishedAt: Date, payload: Data) {
        self.id = id
        self.finishedAt = finishedAt
        self.payload = payload
    }
}

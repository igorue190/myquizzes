//
//  VocabReviewEntity.swift
//  Persistence
//
//  Stores one flashcard's spaced-repetition state, scoped to its vocab file. The
//  `CardReviewState` value is kept as a JSON payload (the domain model stays the
//  source of truth) while `fileID` is a queryable column so a whole file's states
//  load in one fetch, and `key` ("<fileID>:<entryID>") gives an upsert identity.
//

import Foundation
import SwiftData

@Model
final class VocabReviewEntity {
    @Attribute(.unique) var key: String
    var fileID: UUID
    var payload: Data

    init(key: String, fileID: UUID, payload: Data) {
        self.key = key
        self.fileID = fileID
        self.payload = payload
    }

    static func key(file fileID: UUID, entry entryID: Int) -> String {
        "\(fileID.uuidString):\(entryID)"
    }
}

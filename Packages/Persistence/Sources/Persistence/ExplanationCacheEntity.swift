//
//  ExplanationCacheEntity.swift
//  Persistence
//
//  Caches one AI-generated explanation, keyed by a content hash of the question
//  (`ExplanationRequest.cacheKey`). The `Explanation` value is stored as a JSON
//  payload; `createdAt` records when it was generated so a future cleanup/expiry
//  pass has something to sort on.
//

import Foundation
import SwiftData

@Model
final class ExplanationCacheEntity {
    @Attribute(.unique) var key: String
    var payload: Data
    var createdAt: Date

    init(key: String, payload: Data, createdAt: Date) {
        self.key = key
        self.payload = payload
        self.createdAt = createdAt
    }
}

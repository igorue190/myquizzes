//
//  ProfileEntity.swift
//  Persistence
//
//  Stores the single active profile as a JSON payload under a fixed key.
//

import Foundation
import SwiftData

@Model
final class ProfileEntity {
    @Attribute(.unique) var id: String   // always "active" in v1
    var payload: Data

    init(id: String = "active", payload: Data) {
        self.id = id
        self.payload = payload
    }
}

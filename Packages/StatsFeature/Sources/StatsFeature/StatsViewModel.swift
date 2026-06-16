//
//  StatsViewModel.swift
//  StatsFeature
//
//  Loads session history through a SessionRepository and aggregates it into a
//  StatsOverview. UI reads `overview`; no quiz/stat logic lives in the view.
//

import Observation
import CoreModels
import Statistics

@MainActor
@Observable
public final class StatsViewModel {
    private let repository: any SessionRepository

    public private(set) var overview: StatsOverview = .empty

    public init(repository: any SessionRepository) {
        self.repository = repository
    }

    public func load() async {
        let records = (try? await repository.allRecords()) ?? []
        overview = Statistics.overview(from: records)
    }
}

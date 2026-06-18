//
//  ThemeMapping.swift
//  ProfileFeature
//
//  Bridges the pure `ThemeID` (CoreModels) to a DesignSystem `Theme`. Lives here
//  because it's the seam where the domain meets the UI toolkit.
//

import CoreModels
import DesignSystem

public extension ThemeID {
    var designTheme: Theme {
        switch self {
        case .standard: .standard
        case .aurora:   .aurora
        case .violet:   .violet
        }
    }
}

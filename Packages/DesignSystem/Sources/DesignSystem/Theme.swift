//
//  Theme.swift
//  DesignSystem
//
//  A small, Sendable theme value injected through the environment. Swapping the
//  theme (e.g. from Profile settings) re-tints the whole app from one place.
//

import SwiftUI

public struct Theme: Sendable, Equatable {
    public var accent: Color
    public var accentSecondary: Color
    public var cornerStyle: RoundedCornerStyle

    public init(
        accent: Color = ColorTokens.brand,
        accentSecondary: Color = ColorTokens.brandSecondary,
        cornerStyle: RoundedCornerStyle = .continuous
    ) {
        self.accent = accent
        self.accentSecondary = accentSecondary
        self.cornerStyle = cornerStyle
    }

    /// Default indigo–violet identity.
    public static let standard = Theme()

    /// An alternate teal–indigo identity the user can pick in settings.
    public static let aurora = Theme(
        accent: Color(light: 0x0EA5A4, dark: 0x2DD4BF),
        accentSecondary: Color(light: 0x6366F1, dark: 0x818CF8)
    )
}

public extension EnvironmentValues {
    @Entry var theme: Theme = .standard
}

public extension View {
    /// Inject a theme and set the SwiftUI `.tint` to match in one call.
    /// Apply once near the app root: `RootView().markwiseTheme(.standard)`.
    func markwiseTheme(_ theme: Theme) -> some View {
        environment(\.theme, theme)
            .tint(theme.accent)
    }
}

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
    /// Forces a color scheme for this theme (`nil` = follow the system). Used by
    /// the light "Violet" identity to pin white surfaces + black text.
    public var preferredColorScheme: ColorScheme?

    public init(
        accent: Color = ColorTokens.brand,
        accentSecondary: Color = ColorTokens.brandSecondary,
        cornerStyle: RoundedCornerStyle = .continuous,
        preferredColorScheme: ColorScheme? = nil
    ) {
        self.accent = accent
        self.accentSecondary = accentSecondary
        self.cornerStyle = cornerStyle
        self.preferredColorScheme = preferredColorScheme
    }

    /// Default indigo–violet identity.
    public static let standard = Theme()

    /// An alternate teal–indigo identity the user can pick in settings.
    public static let aurora = Theme(
        accent: Color(light: 0x0EA5A4, dark: 0x2DD4BF),
        accentSecondary: Color(light: 0x6366F1, dark: 0x818CF8)
    )

    /// A light, white-and-purple identity: purple accents on white surfaces with
    /// black text. Pinned to light mode so the look is consistent.
    public static let violet = Theme(
        accent: Color(light: 0x7C3AED, dark: 0x7C3AED),
        accentSecondary: Color(light: 0xC084FC, dark: 0xC084FC),
        preferredColorScheme: .light
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
            .preferredColorScheme(theme.preferredColorScheme)
    }
}

//
//  Tokens.swift
//  DesignSystem
//
//  The single source of truth for every primitive value in the UI.
//  Components must reference these tokens — never hard-coded numbers or colors.
//

import SwiftUI
import UIKit

// MARK: - Spacing (4pt grid)

/// Spacing scale on a 4pt grid. Use these for padding, stacks, and gaps.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs:  CGFloat = 4
    public static let sm:  CGFloat = 8
    public static let md:  CGFloat = 12
    public static let lg:  CGFloat = 16
    public static let xl:  CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

// MARK: - Corner radius

/// Corner radii tuned for concentricity — nest a smaller radius inside a larger
/// one (e.g. a `Radius.md` control inside a `Radius.xl` card) so glass shapes
/// stay visually concentric, as Apple's HIG recommends.
public enum Radius {
    public static let sm:   CGFloat = 8
    public static let md:   CGFloat = 12
    public static let lg:   CGFloat = 16
    public static let xl:   CGFloat = 22
    public static let xxl:  CGFloat = 28
    public static let pill: CGFloat = 999
}

// MARK: - Typography

/// Semantic type ramp. Every face is built on a Dynamic Type text style, so the
/// whole app scales with the user's accessibility text-size setting for free.
/// The rounded design gives Markwise a friendly, study-app voice.
public enum Typography {
    public static let displayLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)
    public static let title        = Font.system(.title2,     design: .rounded, weight: .semibold)
    public static let headline     = Font.system(.headline,   design: .rounded, weight: .semibold)
    public static let body         = Font.system(.body,       design: .rounded)
    public static let callout      = Font.system(.callout,    design: .rounded)
    public static let caption      = Font.system(.caption,    design: .rounded, weight: .medium)
    public static let button       = Font.system(.body,       design: .rounded, weight: .semibold)
    public static let mono         = Font.system(.body,       design: .monospaced)
    public static let timer        = Font.system(.title3,     design: .monospaced, weight: .semibold)
}

// MARK: - Color tokens

/// Semantic colors. Brand and surface colors adapt to light/dark automatically.
/// Text uses the system `.primary` / `.secondary` for guaranteed contrast.
public enum ColorTokens {

    // Brand — a considered indigo–violet pair (deliberately not an "AI-default" palette).
    public static let brand          = Color(light: 0x4F46E5, dark: 0x7C7BFF)
    public static let brandSecondary = Color(light: 0x9333EA, dark: 0xC084FC)

    /// Brand gradient for accent fills and icon tints. Computed (not stored) so
    /// it stays concurrency-safe under Swift 6 strict concurrency.
    public static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brand, brandSecondary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    /// A playful, light/dark-adaptive palette for tile accents (e.g. the Library
    /// topic tiles). Each entry is a two-color gradient pair. Computed (not stored)
    /// to stay concurrency-safe, mirroring `brandGradient`.
    static var tilePalette: [[Color]] {
        [
            [Color(light: 0x4F46E5, dark: 0x7C7BFF), Color(light: 0x9333EA, dark: 0xC084FC)], // indigo → violet
            [Color(light: 0x0EA5E9, dark: 0x38BDF8), Color(light: 0x2563EB, dark: 0x60A5FA)], // sky → blue
            [Color(light: 0x059669, dark: 0x34D399), Color(light: 0x0D9488, dark: 0x2DD4BF)], // emerald → teal
            [Color(light: 0xF59E0B, dark: 0xFBBF24), Color(light: 0xEA580C, dark: 0xFB923C)], // amber → orange
            [Color(light: 0xE11D48, dark: 0xFB7185), Color(light: 0xDB2777, dark: 0xF472B6)], // rose → pink
            [Color(light: 0x7C3AED, dark: 0xA78BFA), Color(light: 0x4338CA, dark: 0x818CF8)]  // violet → indigo
        ]
    }

    /// A stable, vivid gradient for a tile, chosen by `seed` so a given item keeps
    /// its color across launches. Use a deterministic seed (not `UUID.hashValue`,
    /// which is randomized per process).
    public static func tileGradient(seed: Int) -> LinearGradient {
        let palette = tilePalette
        let pair = palette[abs(seed) % palette.count]
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Semantic state colors — used *only* when they carry meaning. Tuned so the
    // light values clear WCAG AA (≥4.5:1) as text on the light surface and the
    // dark values do the same on the dark surface, while toning down the neon
    // green/yellow that read poorly over translucent glass.
    public static let success = Color(light: 0x0F7A34, dark: 0x52D17E)
    public static let warning = Color(light: 0x8A5300, dark: 0xE2A92B)
    public static let danger  = Color(light: 0xC02626, dark: 0xF1736F)
    public static let info    = Color(light: 0x1A4FD0, dark: 0x6BA6FA)

    // Surfaces & lines
    /// Opaque surface used as the fallback when Reduce Transparency is on.
    public static let surfaceOpaque = Color(light: 0xF7F7FB, dark: 0x16161D)
    public static let hairline      = Color.primary.opacity(0.12)
    public static let scrim         = Color.black.opacity(0.28)
}

// MARK: - Motion

/// Standard animation curves. Prefer these over ad-hoc `.easeInOut` calls so
/// motion feels consistent across the app. Honor Reduce Motion at call sites.
public enum Motion {
    public static let quick:  Animation = .easeOut(duration: 0.18)
    public static let snappy: Animation = .snappy(duration: 0.28)
    public static let smooth: Animation = .smooth(duration: 0.35)
    public static let bouncy: Animation = .bouncy(duration: 0.40)
}

// MARK: - Color hex helpers

public extension Color {
    /// Build a color that resolves differently in light vs dark mode.
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Build a color from a 24-bit RGB hex value (e.g. `0x4F46E5`).
    init(hex: UInt) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}

private extension UIColor {
    convenience init(hex: UInt) {
        self.init(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue:  CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

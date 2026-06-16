//
//  Glass.swift
//  DesignSystem
//
//  The ONE place that knows about iOS 26 Liquid Glass. Every surface in the app
//  goes through `glassSurface(_:)`. This keeps three concerns in a single file:
//
//    1. iOS 26 `.glassEffect()` when available.
//    2. A graceful `Material` fallback on iOS 18–25 (APIs compile under the
//       iOS 26 SDK but only run on 26+).
//    3. Accessibility: Reduce Transparency → opaque fills; Reduce Motion →
//       no interactive bounce. Handled here so no component repeats the logic.
//

import SwiftUI

// MARK: - Semantic glass roles

/// Describe a surface by *meaning*, not by raw glass parameters. The modifier
/// maps each role to the right `Glass` value (or fallback) and tints only when
/// the tint carries meaning — per Apple's guidance ("tint with meaning").
public enum GlassRole: Sendable, Equatable {
    /// Default elevated surface — panels, cards, bars.
    case regular
    /// Small surface floating over rich content/media; pair with a dimming scrim.
    case clear
    /// Primary emphasis — tinted with the theme accent (e.g. the main CTA).
    case prominent
    /// Explicit semantic tint for state surfaces (success / warning / danger).
    case tinted(Color)
}

// MARK: - Public API

public extension View {

    /// Apply a Liquid Glass surface clipped to a rounded rectangle.
    /// - Note: Apply this *last* in a modifier chain, after padding.
    func glassSurface(
        _ role: GlassRole = .regular,
        cornerRadius: CGFloat = Radius.lg,
        interactive: Bool = false
    ) -> some View {
        glassSurface(
            role,
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            interactive: interactive
        )
    }

    /// Apply a Liquid Glass surface clipped to any shape.
    func glassSurface(
        _ role: GlassRole = .regular,
        in shape: some Shape,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassSurfaceModifier(role: role, shape: AnyShape(shape), interactive: interactive))
    }

    /// Convenience for capsule-shaped controls (chips, HUDs, pills).
    func glassCapsule(_ role: GlassRole = .regular, interactive: Bool = false) -> some View {
        glassSurface(role, in: Capsule(), interactive: interactive)
    }
}

// MARK: - Implementation

struct GlassSurfaceModifier: ViewModifier {
    let role: GlassRole
    let shape: AnyShape
    let interactive: Bool

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            opaqueFallback(content)                     // no translucency at all
        } else if #available(iOS 26.0, *) {
            content.glassEffect(resolvedGlass, in: shape)   // the real thing
        } else {
            materialFallback(content)                   // iOS 18–25 approximation
        }
    }

    // The native iOS 26 path.
    @available(iOS 26.0, *)
    private var resolvedGlass: Glass {
        var glass: Glass
        switch role {
        case .regular:       glass = .regular
        case .clear:         glass = .clear
        case .prominent:     glass = .regular.tint(theme.accent)
        case .tinted(let c): glass = .regular.tint(c)
        }
        // Interactive bounce/shimmer only on tappable surfaces, and never when
        // the user has asked for reduced motion.
        if interactive && !reduceMotion {
            glass = glass.interactive()
        }
        return glass
    }

    // iOS 18–25: blurred system materials read closest to glass.
    @ViewBuilder
    private func materialFallback(_ content: Content) -> some View {
        switch role {
        case .prominent:
            content.background { shape.fill(theme.accent) }
        case .tinted(let c):
            content
                .background {
                    shape.fill(.regularMaterial)
                    shape.fill(c.opacity(0.16))
                }
                .overlay(border)
        case .regular:
            content.background { shape.fill(.regularMaterial) }.overlay(border)
        case .clear:
            content.background { shape.fill(.ultraThinMaterial) }.overlay(border)
        }
    }

    // Reduce Transparency: solid, fully legible fills.
    @ViewBuilder
    private func opaqueFallback(_ content: Content) -> some View {
        switch role {
        case .prominent:
            content.background { shape.fill(theme.accent) }
        case .tinted(let c):
            content
                .background {
                    shape.fill(ColorTokens.surfaceOpaque)
                    shape.fill(c.opacity(0.18))
                }
                .overlay(border)
        case .regular, .clear:
            content.background { shape.fill(ColorTokens.surfaceOpaque) }.overlay(border)
        }
    }

    private var border: some View {
        shape.stroke(ColorTokens.hairline, lineWidth: 0.5)
    }
}

// MARK: - Glass button styles

/// Primary call-to-action. On iOS 26 this is tinted, interactive glass; on older
/// systems it falls back to a solid accent fill. (You may also use the native
/// `.buttonStyle(.glassProminent)` directly on iOS 26 where appropriate.)
public struct PrimaryGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            .foregroundStyle(.white)
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.xl)
            .glassSurface(.prominent, in: Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : Motion.snappy, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Secondary action — neutral glass.
public struct SecondaryGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.button)
            .foregroundStyle(.primary)
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.xl)
            .glassSurface(.regular, in: Capsule(), interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : Motion.snappy, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

public extension ButtonStyle where Self == PrimaryGlassButtonStyle {
    /// `Button("Start") { }.buttonStyle(.glassPrimary)`
    static var glassPrimary: PrimaryGlassButtonStyle { .init() }
}

public extension ButtonStyle where Self == SecondaryGlassButtonStyle {
    /// `Button("Cancel") { }.buttonStyle(.glassSecondary)`
    static var glassSecondary: SecondaryGlassButtonStyle { .init() }
}

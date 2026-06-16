//
//  Surfaces.swift
//  DesignSystem
//
//  Container surfaces. Liquid Glass reads best over rich content, so the app
//  background provides depth for glass to refract.
//

import SwiftUI
import UIKit

// MARK: - App background

/// A soft, brand-tinted gradient backdrop. Place behind your root content so
/// glass surfaces have something to sample. Falls back to a solid color when
/// Reduce Transparency is on.
public struct AppBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        Group {
            if reduceTransparency {
                ColorTokens.surfaceOpaque
            } else if #available(iOS 18.0, *) {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
                        SIMD2<Float>(0, 0.5), SIMD2<Float>(0.5, 0.5), SIMD2<Float>(1, 0.5),
                        SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1)
                    ],
                    colors: meshColors
                )
                .overlay(Color(.systemBackground).opacity(0.55))
            } else {
                LinearGradient(
                    colors: [theme.accent.opacity(0.18), theme.accentSecondary.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay(Color(.systemBackground).opacity(0.55))
            }
        }
        .ignoresSafeArea()
    }

    private var meshColors: [Color] {
        let a = theme.accent, b = theme.accentSecondary
        return [
            a.opacity(0.32), b.opacity(0.24), a.opacity(0.30),
            b.opacity(0.20), Color(.systemBackground), a.opacity(0.18),
            a.opacity(0.22), b.opacity(0.28), b.opacity(0.20)
        ]
    }
}

// MARK: - Glass panel

/// A glass container around arbitrary content. The everyday building block for
/// grouped UI (a question, a settings group, a stat tile).
public struct GlassPanel<Content: View>: View {
    private let role: GlassRole
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(
        role: GlassRole = .regular,
        cornerRadius: CGFloat = Radius.lg,
        padding: CGFloat = Spacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .glassSurface(role, cornerRadius: cornerRadius)
    }
}

// MARK: - Glass card

/// A titled glass card with a header row and body — used for result summaries,
/// library rows, and grouped lists.
public struct GlassCard<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    public init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            header.font(Typography.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .glassSurface(.regular, cornerRadius: Radius.xl)
    }
}

#Preview("Surfaces") {
    ZStack {
        AppBackground()
        VStack(spacing: Spacing.lg) {
            GlassPanel {
                Text("Glass panel").font(Typography.headline)
            }
            GlassCard {
                Label("Cloud Concepts", systemImage: "cloud.fill")
            } content: {
                Text("12 questions · last studied 2 days ago")
                    .font(Typography.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .markwiseTheme(.standard)
}

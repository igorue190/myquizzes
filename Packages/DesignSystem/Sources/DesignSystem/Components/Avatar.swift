//
//  Avatar.swift
//  DesignSystem
//
//  A circular profile avatar. Shows a user-supplied photo when one exists,
//  otherwise an SF Symbol glyph in the brand gradient. Pure and stateless —
//  the caller owns the data. Used by the Profile screen and onboarding.
//

import SwiftUI
import UIKit

public struct ProfileAvatar: View {
    private let imageData: Data?
    private let symbolName: String
    private let size: CGFloat

    public init(imageData: Data?, symbolName: String, size: CGFloat = 96) {
        self.imageData = imageData
        self.symbolName = symbolName
        self.size = size
    }

    public var body: some View {
        Group {
            if let imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(ColorTokens.brandGradient)
                    .symbolEffect(.bounce, value: symbolName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ColorTokens.brand.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ColorTokens.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

#Preview("Avatar") {
    HStack(spacing: 24) {
        ProfileAvatar(imageData: nil, symbolName: "graduationcap.fill")
        ProfileAvatar(imageData: nil, symbolName: "brain.head.profile", size: 56)
    }
    .padding()
}

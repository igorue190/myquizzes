//
//  Haptics.swift
//  DesignSystem
//
//  A thin wrapper over UIKit feedback generators. Call sites gate these on the
//  user's haptics preference (Profile setting). Main-actor isolated because the
//  feedback generators are.
//

import UIKit

@MainActor
public enum Haptics {
    /// A light tap — e.g. selecting an answer.
    public static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    /// A success/warning/error notification — e.g. pass/fail on submit.
    public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    public static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

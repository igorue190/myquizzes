//
//  MarkwiseApp.swift
//  Markwise
//
//  The @main entry point — a thin shell. All composition lives in AppFeature's
//  RootView (which also injects the theme), so the app target stays trivial and
//  the real UI is exercised as a compile-checked package.
//

import SwiftUI
import AppFeature

@main
struct MarkwiseApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

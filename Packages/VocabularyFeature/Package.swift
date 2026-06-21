// swift-tools-version: 6.1
import PackageDescription

// VocabularyFeature: the SwiftUI surfaces for studying a vocabulary set — the
// study hub (flashcards vs. quiz) and the flashcard deck with its Leitner spaced
// review. Views are dumb; an @Observable view model owns the state and forwards
// intents to VocabularyKit (the quiz builder + scheduler) and persists review
// state through CoreModels' `VocabReviewRepository`. Launching a translation quiz
// is surfaced as an `onStartQuiz(ParsedQuiz)` closure so this feature never
// depends on QuizFeature — AppFeature wires it to the existing runner. Depends on
// the core packages + DesignSystem; never on another feature.
let package = Package(
    name: "VocabularyFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "VocabularyFeature", targets: ["VocabularyFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../VocabularyKit"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "VocabularyFeature",
            dependencies: ["CoreModels", "VocabularyKit", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VocabularyFeatureTests",
            dependencies: ["VocabularyFeature", "CoreModels", "VocabularyKit"]
        )
    ]
)

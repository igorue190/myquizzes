// swift-tools-version: 6.1
import PackageDescription

// QuizFeature: the SwiftUI quiz runner (Training + Exam) and result/review
// screens. This is the integration layer where the pure engine meets the
// Liquid Glass design system — views are dumb, an @Observable view model holds
// state and forwards intents to the QuizEngine (the plan's unidirectional flow,
// §6.2). Depends on the core packages + DesignSystem; never on another feature.
let package = Package(
    name: "QuizFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "QuizFeature", targets: ["QuizFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../QuizEngine"),
        .package(path: "../MarkdownParser"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "QuizFeature",
            dependencies: ["CoreModels", "QuizEngine", "MarkdownParser", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "QuizFeatureTests",
            dependencies: ["QuizFeature", "CoreModels", "QuizEngine", "DesignSystem"]
        )
    ]
)

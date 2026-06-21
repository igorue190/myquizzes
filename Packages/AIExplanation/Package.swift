// swift-tools-version: 6.1
import PackageDescription

// AIExplanation: a core-layer package implementing CoreModels' `ExplanationService`
// against Anthropic's Messages API over raw URLSession (no third-party SDK — the
// product stays dependency-light). It also owns the Keychain storage for the
// user's API key. Like Persistence, it implements a CoreModels abstraction and is
// injected at the AppFeature composition root; features never depend on it.
let package = Package(
    name: "AIExplanation",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "AIExplanation", targets: ["AIExplanation"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        // Test-only: lets the vocab-service test parse its own rendered Markdown
        // back, guarding against drift between the renderer and the parser. The
        // production target stays dependency-light (CoreModels only).
        .package(path: "../MarkdownParser")
    ],
    targets: [
        .target(
            name: "AIExplanation",
            dependencies: ["CoreModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AIExplanationTests",
            dependencies: ["AIExplanation", "CoreModels", "MarkdownParser"]
        )
    ]
)

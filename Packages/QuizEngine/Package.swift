// swift-tools-version: 6.1
import PackageDescription

// QuizEngine: the pure session state machine, seeded question selection, and
// scoring rules. No UI, no IO — depends only on CoreModels. This is half of the
// product's correctness-critical core (the other half is MarkdownParser) and is
// where the heaviest unit-test coverage lives.
let package = Package(
    name: "QuizEngine",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "QuizEngine", targets: ["QuizEngine"])
    ],
    dependencies: [
        .package(path: "../CoreModels")
    ],
    targets: [
        .target(name: "QuizEngine", dependencies: ["CoreModels"]),
        .testTarget(name: "QuizEngineTests", dependencies: ["QuizEngine", "CoreModels"])
    ]
)

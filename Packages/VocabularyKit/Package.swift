// swift-tools-version: 6.1
import PackageDescription

// VocabularyKit: the pure logic that turns a `VocabularySet` into study material.
// `VocabularyQuizBuilder` derives a `ParsedQuiz` (so translation quizzes flow
// through the existing QuizEngine/runner unchanged) and `LeitnerScheduler` steps
// flashcard spaced-repetition state. Foundation + CoreModels only — no UI, no IO
// — so it builds and `swift test`s on a plain toolchain alongside the other pure
// core packages, and carries the heavy determinism coverage.
let package = Package(
    name: "VocabularyKit",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "VocabularyKit", targets: ["VocabularyKit"])
    ],
    dependencies: [
        .package(path: "../CoreModels")
    ],
    targets: [
        .target(
            name: "VocabularyKit",
            dependencies: ["CoreModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "VocabularyKitTests",
            dependencies: ["VocabularyKit", "CoreModels"]
        )
    ]
)

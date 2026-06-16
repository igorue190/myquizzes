// swift-tools-version: 6.1
import PackageDescription

// ResultsFeature: the session summary (score ring + per-topic breakdown) and the
// History list of past sessions (plan §4.7, §9.2 screen 7). Reads session
// history through a `SessionRepository`; UI only.
let package = Package(
    name: "ResultsFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ResultsFeature", targets: ["ResultsFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "ResultsFeature",
            dependencies: ["CoreModels", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

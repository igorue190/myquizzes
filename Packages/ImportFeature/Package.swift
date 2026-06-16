// swift-tools-version: 6.1
import PackageDescription

// ImportFeature: the pick → parse → review flow for bringing a .md file into the
// library (plan §4.3, §9.2 screen 3). Self-contained UI that yields a reviewed
// (title, markdown, summary); the caller persists it via its repository. Depends
// only on CoreModels + MarkdownParser + DesignSystem — never on another feature.
let package = Package(
    name: "ImportFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ImportFeature", targets: ["ImportFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../MarkdownParser"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "ImportFeature",
            dependencies: ["CoreModels", "MarkdownParser", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

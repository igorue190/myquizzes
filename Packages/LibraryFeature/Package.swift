// swift-tools-version: 6.1
import PackageDescription

// LibraryFeature: the content-tree UI (categories → topics → files), create /
// import / delete. It is injected a `LibraryRepository` (the protocol from
// CoreModels) and parses imported files via MarkdownParser to cache a summary.
// It does NOT depend on Persistence — the app wires the SwiftData implementation
// in at the composition root.
let package = Package(
    name: "LibraryFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "LibraryFeature", targets: ["LibraryFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../MarkdownParser"),
        .package(path: "../DesignSystem"),
        .package(path: "../ImportFeature")
    ],
    targets: [
        .target(
            name: "LibraryFeature",
            dependencies: ["CoreModels", "MarkdownParser", "DesignSystem", "ImportFeature"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LibraryFeatureTests",
            dependencies: ["LibraryFeature", "CoreModels"]
        )
    ]
)

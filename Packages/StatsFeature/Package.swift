// swift-tools-version: 6.1
import PackageDescription

// StatsFeature: the Stats tab — accuracy trend (Swift Charts) and per-topic
// mastery. Reads session history through a `SessionRepository` and aggregates
// it via the Statistics package. UI only; no persistence dependency.
let package = Package(
    name: "StatsFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "StatsFeature", targets: ["StatsFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../Statistics"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "StatsFeature",
            dependencies: ["CoreModels", "Statistics", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "StatsFeatureTests",
            dependencies: ["StatsFeature", "CoreModels", "Statistics"]
        )
    ]
)

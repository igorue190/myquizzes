// swift-tools-version: 6.1
import PackageDescription

// Statistics: pure aggregation of session history into per-topic mastery and an
// accuracy trend (plan §4.7, §7 TopicStat). No UI, no IO — depends only on
// CoreModels, so it's deterministic and unit-tested on the command line.
let package = Package(
    name: "Statistics",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Statistics", targets: ["Statistics"])
    ],
    dependencies: [
        .package(path: "../CoreModels")
    ],
    targets: [
        .target(name: "Statistics", dependencies: ["CoreModels"]),
        .testTarget(name: "StatisticsTests", dependencies: ["Statistics", "CoreModels"])
    ]
)

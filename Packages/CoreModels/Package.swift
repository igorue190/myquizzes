// swift-tools-version: 6.1
import PackageDescription

// CoreModels: the domain entities and value types shared across the app.
// Pure Swift + Foundation only — no UI, no persistence framework — so it builds
// and tests on any platform (including this command-line toolchain).
let package = Package(
    name: "CoreModels",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "CoreModels", targets: ["CoreModels"])
    ],
    targets: [
        .target(name: "CoreModels"),
        .testTarget(name: "CoreModelsTests", dependencies: ["CoreModels"])
    ]
)

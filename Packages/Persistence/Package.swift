// swift-tools-version: 6.1
import PackageDescription

// Persistence: the SwiftData stack + on-disk file store + the SwiftData-backed
// LibraryRepository. This is the ONLY package that imports SwiftData; features
// depend on the `LibraryRepository` protocol in CoreModels, so swapping in
// CloudKit later touches only this package (plan §6.2). macOS is declared
// alongside iOS so the store is unit-testable on the command line.
let package = Package(
    name: "Persistence",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(path: "../CoreModels")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: ["CoreModels"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "CoreModels"]
        )
    ]
)

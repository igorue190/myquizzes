// swift-tools-version: 6.1
import PackageDescription

// AppFeature: the app's composition root as a library — the root TabView and the
// glue that assembles features into screens. Keeping it in a package means the
// whole UI shell is compile-checked independently; the actual @main app target
// (in the Xcode project) is a thin shell that just presents `RootView`.
let package = Package(
    name: "AppFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "AppFeature", targets: ["AppFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../DesignSystem"),
        .package(path: "../QuizFeature"),
        .package(path: "../LibraryFeature"),
        .package(path: "../ImportFeature"),
        .package(path: "../StatsFeature"),
        .package(path: "../ResultsFeature"),
        .package(path: "../ProfileFeature"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "AppFeature",
            dependencies: ["CoreModels", "DesignSystem", "QuizFeature", "LibraryFeature", "ImportFeature", "StatsFeature", "ResultsFeature", "ProfileFeature", "Persistence"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

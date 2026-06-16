// swift-tools-version: 6.1
import PackageDescription

// Root package: the `myquizzes` command-line demo that exercises the pure core
// (parse a .md → run a quiz session → print a scored report). It depends on the
// local packages under Packages/. The iOS app, DesignSystem, and feature
// modules live in their own packages and are built with Xcode 26 (they require
// the iOS SDK); this executable is what runs on a plain macOS toolchain.
let package = Package(
    name: "myquizzes",
    platforms: [.macOS(.v14), .iOS(.v18)],
    dependencies: [
        .package(path: "Packages/CoreModels"),
        .package(path: "Packages/MarkdownParser"),
        .package(path: "Packages/QuizEngine")
    ],
    targets: [
        .executableTarget(
            name: "myquizzes",
            dependencies: ["CoreModels", "MarkdownParser", "QuizEngine"]
        )
    ]
)

// swift-tools-version: 6.1
import PackageDescription

// MarkdownParser: turns a .md file into a `ParsedQuiz` + diagnostics. AST-based
// via apple/swift-markdown (never regex), as the plan mandates (§5). Pure: no
// UI, no IO beyond being handed a String. Depends on CoreModels.
let package = Package(
    name: "MarkdownParser",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "MarkdownParser", targets: ["MarkdownParser"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "MarkdownParser",
            dependencies: [
                "CoreModels",
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .testTarget(
            name: "MarkdownParserTests",
            dependencies: ["MarkdownParser", "CoreModels"]
        )
    ]
)

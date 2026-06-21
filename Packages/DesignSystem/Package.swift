// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [
        // Deployment target iOS 18. Build with the iOS 26 SDK (Xcode 26).
        // Liquid Glass APIs are gated at runtime with `if #available(iOS 26, *)`.
        .iOS(.v18)
    ],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        // The rich-content renderer parses Markdown for display (code, tables,
        // lists, images, inline). Same vetted Apple parser the MarkdownParser
        // package uses — kept to the one allowed external dependency.
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            resources: [
                // Bundled KaTeX (CSS/JS/woff2 fonts) so math renders fully offline.
                .copy("Resources/KaTeX")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ]
)

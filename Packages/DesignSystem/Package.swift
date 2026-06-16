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
    targets: [
        .target(
            name: "DesignSystem",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ]
)

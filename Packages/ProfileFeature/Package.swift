// swift-tools-version: 6.1
import PackageDescription

// ProfileFeature: the local profile/settings screen (plan §4.1, §9.2 screen 9).
// Name/avatar, theme, default exam settings, haptics, and data management
// (export/delete history). Injected a ProfileRepository + SessionRepository.
let package = Package(
    name: "ProfileFeature",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "ProfileFeature", targets: ["ProfileFeature"])
    ],
    dependencies: [
        .package(path: "../CoreModels"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "ProfileFeature",
            dependencies: ["CoreModels", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ProfileFeatureTests",
            dependencies: ["ProfileFeature", "CoreModels", "DesignSystem"]
        )
    ]
)

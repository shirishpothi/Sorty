// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sorty",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "SortyLib",
            targets: ["SortyLib"]),
        .executable(
            name: "SortyApp",
            targets: ["SortyApp"]),
        .executable(
            name: "learnings",
            targets: ["LearningsCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "SortyLib",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/SortyLib",
            resources: [
                // NOTE: Assets.xcassets is managed by Xcode project for proper .car compilation
                // SPM only handles the Images directory as PNG fallbacks
                .copy("Resources/Images")
            ],
            swiftSettings: [
                // Debug: Fast build, no optimization
                .unsafeFlags(["-Onone", "-enable-batch-mode"], .when(configuration: .debug)),
                // Release: Full optimization with whole-module
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release)),
                // Common settings for both
                .unsafeFlags(["-suppress-warnings"]),
            ],
            linkerSettings: []
        ),
        .executableTarget(
            name: "SortyApp",
            dependencies: ["SortyLib"],
            path: "Sources/SortyApp",
            swiftSettings: [
                .unsafeFlags(["-Onone", "-enable-batch-mode"], .when(configuration: .debug)),
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release)),
            ],
            linkerSettings: []
        ),
        .testTarget(
            name: "SortyTests",
            dependencies: ["SortyLib"],
            path: "Tests/SortyTests",
            swiftSettings: [
                // Tests: Fast build with debug info
                .unsafeFlags(["-Onone", "-enable-batch-mode"]),
                .unsafeFlags(["-g"]), // Debug symbols for test debugging
            ]
        ),
        .executableTarget(
            name: "LearningsCLI",
            dependencies: ["SortyLib"],
            path: "Sources/LearningsCLI",
            swiftSettings: [
                .unsafeFlags(["-Onone", "-enable-batch-mode"], .when(configuration: .debug)),
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release)),
            ],
            linkerSettings: []
        )
    ]
)

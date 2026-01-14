// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sorty",
    platforms: [
        .macOS(.v14)
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
    dependencies: [],
    targets: [
        .target(
            name: "SortyLib",
            path: "Sources/SortyLib",
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/Images")
            ]
        ),
        .executableTarget(
            name: "SortyApp",
            dependencies: ["SortyLib"],
            path: "Sources/SortyApp"
        ),
        .testTarget(
            name: "SortyTests",
            dependencies: ["SortyLib"],
            path: "Tests/SortyTests"
        ),
        .executableTarget(
            name: "LearningsCLI",
            dependencies: ["SortyLib"],
            path: "Sources/LearningsCLI"
        )
    ]
)


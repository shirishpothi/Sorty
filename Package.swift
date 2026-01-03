// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileOrganizer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FileOrganizerLib",
            targets: ["FileOrganizerLib"]),
        .executable(
            name: "FileOrganizerApp",
            targets: ["FileOrganizerApp"]),
        .executable(
            name: "learnings",
            targets: ["LearningsCLI"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FileOrganizerLib",
            path: "Sources/FileOrganizerLib"
        ),
        .executableTarget(
            name: "FileOrganizerApp",
            dependencies: ["FileOrganizerLib"],
            path: "Sources/FileOrganizerApp"
        ),
        .testTarget(
            name: "FileOrganizerTests",
            dependencies: ["FileOrganizerLib"],
            path: "Tests/FileOrganizerTests"
        ),
        .executableTarget(
            name: "LearningsCLI",
            dependencies: ["FileOrganizerLib"],
            path: "Sources/LearningsCLI"
        )
    ]
)


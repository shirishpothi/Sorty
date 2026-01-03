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
    targets: [
        // Target for the core logic (Models, AI, Organizer, etc.)
        .target(
            name: "FileOrganizerLib",
            path: ".",
            exclude: [
                "FileOrganizerApp.swift",
                "Tests",
                "FinderExtension/FileOrganizerActionExtension.swift",
                "build.sh",
                "Makefile",
                "README.md",
                "HELP.md",
                "LICENSE",
                "SECURITY.md",
                "CONTRIBUTING.md",
                "AppCoordinator.swift",
                "Info.plist",
                "FileOrganizer.app",
                ".git",
                ".gitignore",
                "Resources/commit.txt",
                "Assets",
                "Logs",
                "TestResults.xcresult"
            ],

            sources: [
                "AI",
                "FileSystem",
                "Learnings",
                "Models",
                "Organizer",
                "Utilities",
                "ViewModels",
                "Views",
                "FinderExtension"
            ]
        ),
        // Target for the App (contains Views and App entry)
        .executableTarget(
            name: "FileOrganizerApp",
            dependencies: ["FileOrganizerLib"],
            path: ".",
            exclude: [
                "Tests",
                "FinderExtension",
                "AI", "FileSystem", "Models", "Organizer", "Utilities", "ViewModels", "Views",
                "build.sh",
                "Makefile",
                "README.md",
                "HELP.md",
                "LICENSE",
                "SECURITY.md",
                "CONTRIBUTING.md",
                "Info.plist",
                "FileOrganizer.app",
                ".git",
                ".gitignore",
                "Resources/commit.txt",
                "Assets",
                "Logs",
                "TestResults.xcresult"
            ],

            sources: [
                "FileOrganizerApp.swift",
                "AppCoordinator.swift"
            ]
        ),
        .testTarget(
            name: "FileOrganizerTests",
            dependencies: ["FileOrganizerLib"],
            path: "Tests"
        ),
        // CLI tool for The Learnings feature
        .executableTarget(
            name: "LearningsCLI",
            dependencies: ["FileOrganizerLib"],
            path: "CLI",
            sources: ["LearningsCLI.swift"]
        )
    ]
)


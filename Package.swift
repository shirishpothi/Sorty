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
            name: "SortyQuality",
            targets: ["SortyQuality"])
    ],
    dependencies: [
        // Upstream Permiso currently targets macOS 26, so Sorty vendors a local
        // package variant that preserves the same overlay UI on macOS 15.
        .package(path: "Packages/Permiso"),
        // Beam 0.1.0 is vendored so its shader loader can resolve SwiftPM
        // resources from a signed macOS app's Contents/Resources directory.
        .package(path: "Packages/Beam"),
        .package(
            url: "https://github.com/PostHog/posthog-ios.git",
            exact: "3.68.2"
        ),
        .package(
            url: "https://github.com/getsentry/sentry-cocoa.git",
            exact: "9.23.0"
        ),
        .package(
            url: "https://github.com/krzysztofzablocki/Inject.git",
            exact: "1.6.0"
        ),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "SortyLib",
            dependencies: [
                .product(name: "Permiso", package: "Permiso"),
                .product(name: "Beam", package: "beam"),
                .product(name: "PostHog", package: "posthog-ios"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "Inject", package: "Inject"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/SortyLib",
            resources: [
                // NOTE: Assets.xcassets is managed by Xcode project for proper .car compilation
                // SPM only handles the Images directory as PNG fallbacks
                .copy("Resources/Images"),
                .copy("Resources/AppIcons"),
                .copy("Resources/Shaders"),
                .copy("Resources/whats-new-design-system-1.png"),
                .copy("Resources/whats-new-design-system-2.png"),
                .copy("Resources/whats-new-design-system-3.png"),
                .copy("Resources/whats-new-design-system-4.png"),
                .copy("Resources/whats-new-design-system-5.png"),
                .copy("Resources/whats-new-preview.png"),
                .copy("Resources/SortyAppRepair.entitlements"),
                .process("Resources/Localizable.xcstrings"),
                .process("Resources/automation-demo.mp4"),
                .process("Resources/files-and-folders-demo.mp4"),
                .process("Resources/full-disk-access-demo.mp4"),
                .process("Resources/SortyMascotTemplate.svg"),
                .process("Resources/OnboardingSound.wav"),
                .process("Resources/Final Onboarding.wav")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                // Debug: Fast incremental build (SPM manages incremental builds internally)
                .unsafeFlags(["-enable-batch-mode"], .when(configuration: .debug)),
                // Release: Full optimization with whole-module
                .unsafeFlags(["-whole-module-optimization"], .when(configuration: .release)),
                // Batched builds otherwise repeat the same diagnostics for many
                // primary files, producing megabytes of low-value output.
                .unsafeFlags(["-suppress-warnings"]),
                // Swift 6 strict concurrency - minimal checking to reduce type-check cost
                .unsafeFlags(["-strict-concurrency=minimal"]),
            ],
            linkerSettings: [
                // Skip deduplication in debug for faster linking
                .unsafeFlags(["-Xlinker", "-no_deduplicate"], .when(configuration: .debug)),
                // InjectionNext interposes updated implementations in Debug builds.
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "SortyApp",
            dependencies: ["SortyLib"],
            path: "Sources/SortyApp",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .unsafeFlags(["-enable-batch-mode"], .when(configuration: .debug)),
                .unsafeFlags(["-whole-module-optimization"], .when(configuration: .release)),
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-no_deduplicate"], .when(configuration: .debug)),
                .unsafeFlags(["-Xlinker", "-interposable"], .when(configuration: .debug)),
            ]
        ),
        .executableTarget(
            name: "SortyQuality",
            dependencies: ["SortyLib"],
            path: "Sources/SortyQuality"
        ),
        .testTarget(
            name: "SortyTests",
            dependencies: ["SortyLib"],
            path: "Tests/SortyTests",
            swiftSettings: [
                .unsafeFlags(["-enable-batch-mode"]),
            ]
        )
    ]
)

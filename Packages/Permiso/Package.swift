// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Permiso",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Permiso",
            targets: ["Permiso"]
        )
    ],
    targets: [
        .target(
            name: "Permiso"
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Beam",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(name: "Beam", targets: ["Beam"]),
  ],
  targets: [
    .target(
      name: "Beam",
      resources: [
        .process("Shaders/Medium.metal"),
        .process("Shaders/Small.metal"),
        .process("Shaders/Line.metal"),
        .process("Shaders/Comet.metal"),
        .process("Shaders/Lens.metal"),
        .process("Shaders/GlyphFill.metal"),
      ]
    ),
  ]
)

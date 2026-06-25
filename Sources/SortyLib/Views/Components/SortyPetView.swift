//
//  SortyPetView.swift
//  Sorty
//

import AppKit
import SwiftUI

enum SortyPetAnimationState: String, CaseIterable {
    case idle
    case ready
    case organizing
    case renaming
    case scanning
    case duplicates
    case reviewing
    case applying
    case completed
    case failed
    case waiting
}

struct SortyPetView: View {
    let state: SortyPetAnimationState
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let manifest = SortyPetAssetProvider.shared.manifest,
           let spriteSheet = SortyPetAssetProvider.shared.spriteSheet {
            SwiftUI.TimelineView(.animation(minimumInterval: frameInterval(for: manifest))) { context in
                let frameIndex = reduceMotion ? 0 : frameIndex(for: context.date, manifest: manifest)
                if let image = SortyPetAssetProvider.shared.frameImage(
                    for: state,
                    frameIndex: frameIndex,
                    manifest: manifest,
                    spriteSheet: spriteSheet
                ) {
                    Image(nsImage: image)
                        .renderingMode(.original)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func frameInterval(for manifest: SortyPetManifest) -> TimeInterval {
        1.0 / Double(max(manifest.atlas.framesPerSecond, 1))
    }

    private func frameIndex(for date: Date, manifest: SortyPetManifest) -> Int {
        let frames = manifest.atlas.states[state.rawValue]?.frames ?? manifest.atlas.framesPerState
        let frameCount = max(frames, 1)
        let elapsed = date.timeIntervalSinceReferenceDate
        return Int(elapsed * Double(max(manifest.atlas.framesPerSecond, 1))) % frameCount
    }
}

@MainActor
final class SortyPetAssetProvider {
    static let shared = SortyPetAssetProvider()
    nonisolated static let animatedMascotEnabledKey = "animatedMascotEnabled"

    let manifest: SortyPetManifest?
    let spriteSheet: NSImage?

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        manifest = Self.loadManifest()
        spriteSheet = Self.loadSpriteSheet(manifest: manifest)
        cache.countLimit = 96
    }

    func frameImage(
        for state: SortyPetAnimationState,
        frameIndex: Int,
        manifest: SortyPetManifest,
        spriteSheet: NSImage
    ) -> NSImage? {
        guard let stateInfo = manifest.atlas.states[state.rawValue] else { return nil }

        let boundedFrame = min(max(frameIndex, 0), max(stateInfo.frames - 1, 0))
        let key = "\(state.rawValue)-\(boundedFrame)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        guard let cgImage = spriteSheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / CGFloat(manifest.atlas.columns)
        let scaleY = CGFloat(cgImage.height) / CGFloat(manifest.atlas.rowCount)
        let cropRect = CGRect(
            x: CGFloat(boundedFrame) * scaleX,
            y: CGFloat(stateInfo.row) * scaleY,
            width: scaleX,
            height: scaleY
        ).integral

        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }

        let image = NSImage(cgImage: cropped, size: CGSize(
            width: manifest.atlas.cellWidth,
            height: manifest.atlas.cellHeight
        ))
        cache.setObject(image, forKey: key)
        return image
    }

    private static func loadManifest() -> SortyPetManifest? {
        guard let url = petResourceURL(fileName: "pet", extension: "json", petName: "Sorty"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(SortyPetManifest.self, from: data)
    }

    private static func loadSpriteSheet(manifest: SortyPetManifest?) -> NSImage? {
        let imageName = manifest?.atlas.imageName ?? "spritesheet.png"
        let splitName = (imageName as NSString)
        guard let url = petResourceURL(
            fileName: splitName.deletingPathExtension,
            extension: splitName.pathExtension.isEmpty ? "png" : splitName.pathExtension,
            petName: manifest?.displayName ?? "Sorty"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private static func petResourceURL(fileName: String, extension ext: String, petName: String) -> URL? {
        let subdirectory = "Pets/\(petName)"
        let bundles = [SortyResources.bundle, Bundle.main]

        for bundle in bundles {
            if let url = bundle.url(forResource: fileName, withExtension: ext, subdirectory: subdirectory) {
                return url
            }

            if let resourceURL = bundle.resourceURL {
                let directURL = resourceURL
                    .appendingPathComponent(subdirectory)
                    .appendingPathComponent("\(fileName).\(ext)")
                if FileManager.default.fileExists(atPath: directURL.path) {
                    return directURL
                }
            }
        }

        let sourceURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/SortyLib/Resources")
            .appendingPathComponent(subdirectory)
            .appendingPathComponent("\(fileName).\(ext)")
        if FileManager.default.fileExists(atPath: sourceURL.path) {
            return sourceURL
        }

        return nil
    }
}

struct SortyPetManifest: Decodable {
    let id: String
    let displayName: String
    let version: Int
    let states: [String]
    let atlas: SortyPetAtlas
}

struct SortyPetAtlas: Decodable {
    let imageName: String
    let cellWidth: Int
    let cellHeight: Int
    let framesPerState: Int
    let framesPerSecond: Int
    let states: [String: SortyPetStateInfo]

    var columns: Int {
        let maxFrames = states.values.map(\.frames).max() ?? framesPerState
        return max(maxFrames, framesPerState, 1)
    }

    var rowCount: Int {
        let maxRow = states.values.map(\.row).max() ?? 0
        return max(maxRow + 1, 1)
    }
}

struct SortyPetStateInfo: Decodable {
    let row: Int
    let frames: Int
}

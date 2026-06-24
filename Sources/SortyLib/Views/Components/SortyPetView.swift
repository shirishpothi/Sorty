//
//  SortyPetView.swift
//  Sorty
//

import AppKit
import SwiftUI

public enum SortyPetAnimationState: String, CaseIterable, Codable, Sendable {
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

    var staticAssetName: String {
        switch self {
        case .failed:
            return "SadSortyMascot"
        case .waiting, .reviewing:
            return "UnorganizedSortyMascot"
        case .ready, .idle, .organizing, .renaming, .scanning, .duplicates, .applying, .completed:
            return "ReadyToOrganizeIcon"
        }
    }
}

public enum SortyPetAtlasAnimation: String, CaseIterable, Codable, Sendable {
    case idle
    case runningRight = "running-right"
    case runningLeft = "running-left"
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review
}

public struct SortyPetManifest: Decodable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let version: Int?
    public let states: [String]
    public let spritesheetPath: String?
    public let atlas: SortyPetAtlas?
}

public struct SortyPetAtlas: Decodable, Equatable, Sendable {
    public let imageName: String?
    public let cellWidth: Int
    public let cellHeight: Int
    public let framesPerState: Int
    public let framesPerSecond: Double
    public let states: [String: SortyPetAtlasState]

    public func state(_ animation: SortyPetAtlasAnimation) -> SortyPetAtlasState? {
        states[animation.rawValue]
    }
}

public struct SortyPetAtlasState: Decodable, Equatable, Sendable {
    public let row: Int
    public let frames: Int
}

@MainActor
public enum SortyPetAssetProvider {
    public static let animatedMascotEnabledKey = "sortyPet.animatedMascotEnabled"

    private static let fallbackManifest = SortyPetManifest(
        id: "sorty",
        displayName: "Sorty",
        description: "A focused Sorty companion for folder organization workflows.",
        version: nil,
        states: SortyPetAtlasAnimation.allCases.map(\.rawValue),
        spritesheetPath: nil,
        atlas: nil
    )

    public static var bundledManifest: SortyPetManifest {
        guard let url = SortyResources.bundle.url(
            forResource: "pet",
            withExtension: "json",
            subdirectory: "Pets/Sorty"
        ),
            let data = try? Data(contentsOf: url),
            let manifest = try? JSONDecoder().decode(SortyPetManifest.self, from: data),
            !manifest.states.isEmpty
        else {
            return fallbackManifest
        }

        return manifest
    }

    public static func hasAnimation(for state: SortyPetAnimationState) -> Bool {
        atlasState(for: state) != nil
    }

    public static func atlasState(for state: SortyPetAnimationState) -> SortyPetAtlasState? {
        guard let atlas = bundledManifest.atlas else {
            return nil
        }
        return atlas.state(state.atlasAnimation)
    }

    public static func atlasFrame(for state: SortyPetAnimationState, frameIndex: Int) -> NSImage? {
        guard let atlas = bundledManifest.atlas,
              let atlasState = atlas.state(state.atlasAnimation),
              atlasState.frames > 0,
              atlas.cellWidth > 0,
              atlas.cellHeight > 0,
              let spritesheetName = bundledManifest.resolvedSpritesheetName,
              let spritesheet = spritesheet(named: spritesheetName)
        else {
            return nil
        }

        let normalizedIndex = frameIndex % atlasState.frames
        let cacheKey = "atlas-\(spritesheetName)-\(state.rawValue)-\(normalizedIndex)" as NSString
        if let cached = frameCache.object(forKey: cacheKey) {
            return cached
        }

        guard let cgImage = spritesheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / max(spritesheet.size.width, 1)
        let scaleY = CGFloat(cgImage.height) / max(spritesheet.size.height, 1)
        let rect = CGRect(
            x: CGFloat(normalizedIndex * atlas.cellWidth) * scaleX,
            y: CGFloat(atlasState.row * atlas.cellHeight) * scaleY,
            width: CGFloat(atlas.cellWidth) * scaleX,
            height: CGFloat(atlas.cellHeight) * scaleY
        ).integral

        guard let cropped = cgImage.cropping(to: rect) else {
            return nil
        }

        let image = NSImage(cgImage: cropped, size: NSSize(width: atlas.cellWidth, height: atlas.cellHeight))
        frameCache.setObject(image, forKey: cacheKey, cost: atlas.cellWidth * atlas.cellHeight * 4)
        return image
    }

    public static func staticImage(for state: SortyPetAnimationState) -> NSImage? {
        SortyResources.image(named: state.staticAssetName)
            ?? SortyResources.image(named: "SortyMascot")
            ?? SortyResources.image(named: "SortyMascotTemplate")
    }

    private static let frameCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        return cache
    }()

    private static let spritesheetCache = NSCache<NSString, NSImage>()

    private static func spritesheet(named imageName: String) -> NSImage? {
        let cacheKey = imageName as NSString
        if let cached = spritesheetCache.object(forKey: cacheKey) {
            return cached
        }

        let resourceName = (imageName as NSString).deletingPathExtension
        let resourceExtension = (imageName as NSString).pathExtension
        guard !resourceName.isEmpty,
              !resourceExtension.isEmpty,
              let url = SortyResources.bundle.url(
                  forResource: resourceName,
                  withExtension: resourceExtension,
                  subdirectory: "Pets/Sorty"
              ),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }

        spritesheetCache.setObject(image, forKey: cacheKey)
        return image
    }
}

private extension SortyPetManifest {
    var resolvedSpritesheetName: String? {
        if let spritesheetPath, !spritesheetPath.isEmpty {
            return spritesheetPath
        }
        return atlas?.imageName
    }
}

public struct SortyPetView: View {
    let state: SortyPetAnimationState
    let size: CGFloat
    let accessibilityLabel: String
    let fallbackAssetName: String?

    @AppStorage(SortyPetAssetProvider.animatedMascotEnabledKey) private var animatedMascotEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        state: SortyPetAnimationState,
        size: CGFloat,
        accessibilityLabel: String = "Sorty mascot",
        fallbackAssetName: String? = nil
    ) {
        self.state = state
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.fallbackAssetName = fallbackAssetName
    }

    public var body: some View {
        Group {
            if animatedMascotEnabled,
               !reduceMotion,
               SortyPetAssetProvider.hasAnimation(for: state),
               SortyPetAssetProvider.atlasState(for: state) != nil,
               let image = resolvedImage {
                animatedPet(image: image)
            } else {
                staticPet
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var resolvedImage: NSImage? {
        if let fallbackAssetName,
           let image = SortyResources.image(named: fallbackAssetName) {
            return image
        }
        return SortyPetAssetProvider.staticImage(for: state)
    }

    private var staticPet: some View {
        Group {
            if let image = resolvedImage {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: max(16, size * 0.34), weight: .semibold))
                    .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
            }
        }
        .frame(width: size, height: size)
    }

    private func animatedPet(image: NSImage) -> some View {
        SwiftUI.TimelineView(.animation(minimumInterval: frameInterval)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let atlasFrame = SortyPetAssetProvider.atlasFrame(
                for: state,
                frameIndex: atlasFrameIndex(at: time)
            )

            Image(nsImage: atlasFrame ?? image)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)
            .frame(width: size, height: size)
        }
    }

    private func atlasFrameIndex(at time: TimeInterval) -> Int {
        let framesPerSecond = SortyPetAssetProvider.bundledManifest.atlas?.framesPerSecond ?? 8
        return Int((time * framesPerSecond).rounded(.down))
    }

    private var imageSize: CGFloat {
        switch state {
        case .reviewing, .waiting, .failed:
            return size
        default:
            return size * 0.96
        }
    }

    private var frameInterval: TimeInterval {
        1.0 / 30.0
    }
}

private extension SortyPetAnimationState {
    var atlasAnimation: SortyPetAtlasAnimation {
        switch self {
        case .idle:
            return .idle
        case .ready:
            return .waving
        case .organizing, .renaming, .scanning, .duplicates, .applying:
            return .running
        case .completed:
            return .jumping
        case .failed:
            return .failed
        case .waiting:
            return .waiting
        case .reviewing:
            return .review
        }
    }
}

public extension SortyPetAnimationState {
    static func organizationState(_ state: OrganizationState, mode: OrganizationMode) -> SortyPetAnimationState {
        switch state {
        case .idle:
            return mode == .renameOnly ? .renaming : .ready
        case .scanning:
            return .scanning
        case .organizing:
            return mode == .renameOnly ? .renaming : .organizing
        case .ready:
            return .reviewing
        case .applying:
            return .applying
        case .completed:
            return .completed
        case .error:
            return .failed
        }
    }

    static func duplicateState(_ state: DuplicateScanState) -> SortyPetAnimationState {
        switch state {
        case .idle:
            return .ready
        case .preparing, .scanning:
            return .duplicates
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }
}

#Preview("Sorty Pet States") {
    HStack(spacing: 18) {
        SortyPetView(state: .ready, size: 96)
        SortyPetView(state: .organizing, size: 96)
        SortyPetView(state: .renaming, size: 96)
        SortyPetView(state: .failed, size: 96)
    }
    .padding()
}

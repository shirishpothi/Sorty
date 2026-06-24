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

public struct SortyPetManifest: Decodable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let version: Int
    public let states: [SortyPetAnimationState]
    public let atlas: SortyPetAtlas?
}

public struct SortyPetAtlas: Decodable, Equatable, Sendable {
    public let imageName: String
    public let cellWidth: Int
    public let cellHeight: Int
    public let framesPerState: Int
    public let framesPerSecond: Double
    public let states: [String: SortyPetAtlasState]

    public func state(_ animationState: SortyPetAnimationState) -> SortyPetAtlasState? {
        states[animationState.rawValue]
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
        version: 1,
        states: SortyPetAnimationState.allCases,
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
        bundledManifest.states.contains(state)
    }

    public static func atlasState(for state: SortyPetAnimationState) -> SortyPetAtlasState? {
        guard let atlas = bundledManifest.atlas else {
            return nil
        }
        return atlas.state(state)
    }

    public static func atlasFrame(for state: SortyPetAnimationState, frameIndex: Int) -> NSImage? {
        guard let atlas = bundledManifest.atlas,
              let atlasState = atlas.state(state),
              atlasState.frames > 0,
              atlas.cellWidth > 0,
              atlas.cellHeight > 0,
              let spritesheet = spritesheet(named: atlas.imageName)
        else {
            return nil
        }

        let normalizedIndex = frameIndex % atlasState.frames
        let cacheKey = "atlas-\(atlas.imageName)-\(state.rawValue)-\(normalizedIndex)" as NSString
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

public struct SortyPetView: View {
    let state: SortyPetAnimationState
    let size: CGFloat
    let accessibilityLabel: String
    let fallbackAssetName: String?

    @AppStorage(SortyPetAssetProvider.animatedMascotEnabledKey) private var animatedMascotEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationPhase = Double.random(in: 0..<12)

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

            ZStack {
                if atlasFrame == nil, showsAura {
                    aura(time: time)
                }

                Image(nsImage: atlasFrame ?? image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: imageSize, height: imageSize)
                    .scaleEffect(atlasFrame == nil ? scale(at: time) : 1)
                    .offset(atlasFrame == nil ? offset(at: time) : .zero)
                    .rotationEffect(.degrees(atlasFrame == nil ? rotation(at: time) : 0))

                if atlasFrame == nil, showsProgressDots {
                    progressDots(time: time)
                }
            }
            .frame(width: size, height: size)
        }
    }

    private func atlasFrameIndex(at time: TimeInterval) -> Int {
        let frames = SortyPetAssetProvider.atlasState(for: state)?.frames ?? 1
        guard frames > 1 else {
            return 0
        }

        let timeOffset = time + animationPhase + state.phaseOffset
        let rawFrame = Int((timeOffset * state.framesPerSecond).rounded(.down))
        return state.usesPingPongPlayback ? pingPongFrame(rawFrame, frameCount: frames) : rawFrame
    }

    private func pingPongFrame(_ rawFrame: Int, frameCount: Int) -> Int {
        let cycleLength = max((frameCount * 2) - 2, 1)
        let cycleIndex = rawFrame % cycleLength
        if cycleIndex < frameCount {
            return cycleIndex
        }
        return cycleLength - cycleIndex
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
        switch state {
        case .idle, .ready, .completed:
            return 1.0 / 18.0
        default:
            return 1.0 / 30.0
        }
    }

    private var showsAura: Bool {
        switch state {
        case .organizing, .renaming, .scanning, .duplicates, .applying, .completed:
            return true
        case .idle, .ready, .reviewing, .failed, .waiting:
            return false
        }
    }

    private var showsProgressDots: Bool {
        switch state {
        case .organizing, .renaming, .scanning, .duplicates, .applying:
            return size >= 44
        case .idle, .ready, .reviewing, .completed, .failed, .waiting:
            return false
        }
    }

    private func scale(at time: TimeInterval) -> CGFloat {
        let pulse = sin(time * state.rhythm)
        switch state {
        case .idle:
            return 1 + CGFloat(pulse) * 0.018
        case .ready:
            return 1 + CGFloat(pulse) * 0.024
        case .organizing, .renaming:
            return 1 + CGFloat(pulse) * 0.04
        case .scanning, .duplicates, .reviewing:
            return 1 + CGFloat(pulse) * 0.028
        case .applying:
            return 1 + CGFloat(pulse) * 0.034
        case .completed:
            return 1 + CGFloat(abs(pulse)) * 0.045
        case .failed:
            return 0.99 + CGFloat(pulse) * 0.012
        case .waiting:
            return 1 + CGFloat(pulse) * 0.02
        }
    }

    private func offset(at time: TimeInterval) -> CGSize {
        switch state {
        case .organizing:
            return CGSize(width: sin(time * 4.1) * 2.2, height: cos(time * 5.2) * 1.7)
        case .renaming:
            return CGSize(width: sin(time * 5.4) * 3.0, height: cos(time * 2.4) * 1.0)
        case .scanning, .duplicates:
            return CGSize(width: sin(time * 2.2) * 1.5, height: cos(time * 3.0) * 1.5)
        case .applying:
            return CGSize(width: sin(time * 4.8) * 3.2, height: 0)
        case .completed:
            return CGSize(width: 0, height: -abs(sin(time * 4.0)) * 4.0)
        case .failed:
            return CGSize(width: sin(time * 8.0) * 0.8, height: 0)
        case .waiting:
            return CGSize(width: 0, height: sin(time * 2.0) * 1.8)
        case .idle, .ready, .reviewing:
            return CGSize(width: 0, height: sin(time * 1.8) * 1.2)
        }
    }

    private func rotation(at time: TimeInterval) -> Double {
        switch state {
        case .renaming:
            return sin(time * 4.4) * 4
        case .organizing, .applying:
            return sin(time * 3.4) * 3
        case .scanning, .duplicates, .reviewing:
            return sin(time * 1.9) * 2.6
        case .completed:
            return sin(time * 4.0) * 5
        case .failed:
            return sin(time * 5.6) * 1.8
        case .idle, .ready, .waiting:
            return sin(time * 1.6) * 1.4
        }
    }

    private func aura(time: TimeInterval) -> some View {
        let pulse = (sin(time * state.rhythm) + 1) / 2
        let color = state.accentColor

        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.12 + pulse * 0.12),
                        color.opacity(0.05),
                        .clear
                    ],
                    center: .center,
                    startRadius: size * 0.18,
                    endRadius: size * 0.48
                )
            )
            .frame(width: size, height: size)
    }

    private func progressDots(time: TimeInterval) -> some View {
        HStack(spacing: max(3, size * 0.035)) {
            ForEach(0..<3, id: \.self) { index in
                let phase = time * 4 + Double(index) * 0.7
                Circle()
                    .fill(state.accentColor.opacity(0.45 + ((sin(phase) + 1) / 2) * 0.45))
                    .frame(width: max(3, size * 0.045), height: max(3, size * 0.045))
                    .offset(y: -abs(sin(phase)) * max(2, size * 0.04))
            }
        }
        .offset(y: size * 0.34)
        .accessibilityHidden(true)
    }
}

private extension SortyPetAnimationState {
    var framesPerSecond: Double {
        switch self {
        case .idle, .waiting:
            return 4.5
        case .ready, .reviewing:
            return 5.5
        case .completed:
            return 6.5
        case .failed:
            return 5.0
        case .organizing, .renaming, .scanning, .duplicates, .applying:
            return 7.0
        }
    }

    var phaseOffset: Double {
        switch self {
        case .idle:
            return 0
        case .ready:
            return 0.7
        case .organizing:
            return 1.3
        case .renaming:
            return 1.9
        case .scanning:
            return 2.6
        case .duplicates:
            return 3.1
        case .reviewing:
            return 3.8
        case .applying:
            return 4.4
        case .completed:
            return 5.2
        case .failed:
            return 6.1
        case .waiting:
            return 6.8
        }
    }

    var usesPingPongPlayback: Bool {
        switch self {
        case .organizing, .renaming, .scanning, .duplicates, .applying:
            return false
        case .idle, .ready, .reviewing, .completed, .failed, .waiting:
            return true
        }
    }

    var rhythm: Double {
        switch self {
        case .idle, .ready:
            return 2.0
        case .organizing, .renaming, .applying:
            return 4.2
        case .scanning, .duplicates, .reviewing:
            return 3.0
        case .completed:
            return 4.8
        case .failed:
            return 2.6
        case .waiting:
            return 2.2
        }
    }

    var accentColor: Color {
        switch self {
        case .completed:
            return SortyDesignSystem.Colors.success
        case .failed:
            return SortyDesignSystem.Colors.error
        case .duplicates:
            return .purple
        case .scanning, .reviewing:
            return SortyDesignSystem.Colors.info
        case .waiting:
            return SortyDesignSystem.Colors.warning
        case .idle, .ready, .organizing, .renaming, .applying:
            return SortyDesignSystem.Colors.resolvedAccent
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

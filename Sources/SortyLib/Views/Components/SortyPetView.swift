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
}

@MainActor
public enum SortyPetAssetProvider {
    public static let animatedMascotEnabledKey = "sortyPet.animatedMascotEnabled"

    private static let fallbackManifest = SortyPetManifest(
        id: "sorty",
        displayName: "Sorty",
        version: 1,
        states: SortyPetAnimationState.allCases
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

    public static func staticImage(for state: SortyPetAnimationState) -> NSImage? {
        SortyResources.image(named: state.staticAssetName)
            ?? SortyResources.image(named: "SortyMascot")
            ?? SortyResources.image(named: "SortyMascotTemplate")
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

            ZStack {
                if showsAura {
                    aura(time: time)
                }

                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .frame(width: imageSize, height: imageSize)
                    .scaleEffect(scale(at: time))
                    .offset(offset(at: time))
                    .rotationEffect(.degrees(rotation(at: time)))

                if showsProgressDots {
                    progressDots(time: time)
                }
            }
            .frame(width: size, height: size)
        }
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

//
//  SortingLabView.swift
//  Sorty
//
//  Immersive spatial visualization of the AI-powered file organization pipeline.
//  Composes lab components: grid background, AI portal, folder nodes, file particles, and console.
//

import SwiftUI

struct SortingLabView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @Binding var isCompactMode: Bool

    @StateObject private var animationManager = LabAnimationManager()
    @StateObject private var refreshManager = AnalysisRefreshManager()
    @AppStorage("analysis.liveInsightsEnabled") private var liveInsightsEnabled = true

    @State private var mouseLocation: CGPoint? = nil
    @State private var lastMoveCount = 0
    @State private var lastInsightCount = 0
    @State private var lastScannedFileCount = 0

    private static let folderAccentColors: [Color] = [
        .cyan, .orange, .purple, .green, .pink, .yellow, .mint, .indigo
    ]

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            ZStack {
                LabGridBackground(isActive: animationManager.isActive, mouseLocation: mouseLocation)

                GeometryReader { geo in
                    let size = geo.size

                    // Source hopper indicator
                    sourceHopperView
                        .position(x: 60, y: 60)

                    // Folder nodes arranged radially
                    ForEach(Array(animationManager.folderNodes.enumerated()), id: \.element.id) { index, node in
                        let pos = folderNodePosition(for: node, in: size)
                        let color = Self.folderAccentColors[index % Self.folderAccentColors.count]
                        LabFolderNode(
                            folderName: node.name,
                            fileCount: node.fileCount,
                            isLoading: node.isLoading,
                            isReceivingFile: node.isReceivingFile,
                            accentColor: color
                        )
                        .position(pos)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // File particles
                    ForEach(animationManager.particles) { particle in
                        let pos = particlePosition(for: particle, in: size)
                        LabFileParticle(
                            fileName: particle.fileName,
                            isActive: particle.phase != .arrived
                        )
                        .position(pos)
                        .opacity(particle.phase == .arrived ? 0 : 1)
                        .animation(.easeInOut(duration: 0.15), value: particle.normalizedProgress)
                    }

                    // Central AI portal
                    AIPortalView(
                        isProcessing: organizer.state == .organizing || organizer.state == .scanning,
                        fileReceivedPulse: animationManager.portalReceivedFilePulse,
                        portalSize: min(size.width, size.height) * 0.18
                    )
                    .position(x: size.width / 2, y: size.height / 2)
                }

                // Console overlay at bottom
                VStack {
                    Spacer()
                    AIConsoleView(
                        isStreaming: organizer.isStreaming,
                        insights: organizer.getCachedInsights(),
                        funnyMessage: refreshManager.currentFunnyMessage,
                        funnyMessageOpacity: refreshManager.funnyMessageOpacity,
                        liveOrganizationMoves: organizer.liveOrganizationMoves,
                        liveInsightsEnabled: $liveInsightsEnabled
                    )
                    .frame(maxWidth: 550)
                    .padding(.bottom, 16)
                }

                // Progress badge top-right
                if organizer.state.isOperationInProgress {
                    VStack {
                        HStack {
                            Spacer()
                            progressBadge
                                .padding(.top, 12)
                                .padding(.trailing, 12)
                        }
                        Spacer()
                    }
                }

                // Compact mode toggle top-left
                VStack {
                    HStack {
                        compactModeToggle
                            .padding(.top, 12)
                            .padding(.leading, 12)
                        Spacer()
                    }
                    Spacer()
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    mouseLocation = location
                case .ended:
                    mouseLocation = nil
                @unknown default:
                    mouseLocation = nil
                }
            }
        }
        .onAppear {
            refreshManager.start(organizer: organizer)
        }
        .onDisappear {
            refreshManager.stop()
            animationManager.reset()
        }
        .onChange(of: organizer.scannedFiles.count) { oldCount, newCount in
            guard newCount > lastScannedFileCount else { return }
            let fileNames = organizer.scannedFiles.map(\.name)
            animationManager.processScannedFiles(fileNames)
            lastScannedFileCount = newCount
        }
        .onChange(of: organizer.liveOrganizationMoves.count) { _, newCount in
            guard newCount > lastMoveCount else { return }
            animationManager.processLiveMoves(organizer.liveOrganizationMoves, previousCount: lastMoveCount)
            lastMoveCount = newCount
        }
        .onChange(of: organizer.getCachedInsights().history.count) { _, newCount in
            guard newCount > lastInsightCount else { return }
            animationManager.processInsights(organizer.getCachedInsights().history, previousCount: lastInsightCount)
            lastInsightCount = newCount
        }
        .onChange(of: organizer.state) { _, newState in
            switch newState {
            case .scanning:
                animationManager.isActive = true
                if !organizer.scannedFiles.isEmpty {
                    animationManager.addScanningParticles(fileNames: organizer.scannedFiles.map(\.name))
                }
            case .organizing:
                animationManager.isActive = true
            case .completed:
                HapticFeedbackManager.shared.success()
            case .idle:
                animationManager.reset()
                lastMoveCount = 0
                lastInsightCount = 0
                lastScannedFileCount = 0
            default:
                break
            }
        }
        .animation(.easeInOut(duration: 0.3), value: animationManager.folderNodes.count)
        .animation(.easeInOut(duration: 0.2), value: animationManager.particles.count)
    }

    // MARK: - Subviews

    private var sourceHopperView: some View {
        VStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
            Text("Source")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .opacity(0.6)
        )
    }

    private var progressBadge: some View {
        let pct = Int(organizer.progress * 100)
        let elapsed = Int(organizer.elapsedTime)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let timeString = minutes > 0
            ? String(format: "%d:%02d", minutes, seconds)
            : "\(seconds)s"

        return HStack(spacing: 6) {
            Text("\(pct)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(timeString)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 1)
                )
        )
    }

    private var compactModeToggle: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            withAnimation(.easeInOut(duration: 0.25)) {
                isCompactMode.toggle()
            }
        } label: {
            Image(systemName: isCompactMode ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.ultraThinMaterial)
                )
        }
        .buttonStyle(.plain)
        .help(isCompactMode ? "Expand to lab view" : "Switch to compact view")
        .accessibilityIdentifier("SortingLabCompactModeToggle")
    }

    // MARK: - Particle Positioning

    private func particlePosition(for particle: LabAnimationManager.Particle, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let sourcePoint = CGPoint(x: 60, y: 60)

        switch particle.phase {
        case .enteringPortal:
            return interpolate(from: sourcePoint, to: center, progress: particle.normalizedProgress)
        case .processingAtPortal:
            let jitter = CGFloat(sin(particle.createdAt.timeIntervalSinceReferenceDate * 5)) * 3
            return CGPoint(x: center.x + jitter, y: center.y + jitter)
        case .travelingToFolder:
            if let folderName = particle.destinationFolder,
               let node = animationManager.folderNodes.first(where: { $0.name == folderName }) {
                let folderPos = folderNodePosition(for: node, in: size)
                return interpolate(from: center, to: folderPos, progress: particle.normalizedProgress)
            }
            return center
        case .arrived:
            if let folderName = particle.destinationFolder,
               let node = animationManager.folderNodes.first(where: { $0.name == folderName }) {
                return folderNodePosition(for: node, in: size)
            }
            return center
        }
    }

    private func folderNodePosition(for node: LabAnimationManager.FolderNode, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.32
        let x = center.x + cos(node.angleFromCenter) * radius
        let y = center.y + sin(node.angleFromCenter) * radius
        return CGPoint(x: x, y: y)
    }

    private func interpolate(from: CGPoint, to: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(
            x: from.x + (to.x - from.x) * progress,
            y: from.y + (to.y - from.y) * progress
        )
    }
}

// MARK: - Preview

#Preview {
    SortingLabView(isCompactMode: .constant(false))
        .environmentObject(FolderOrganizer())
        .frame(width: 800, height: 600)
}

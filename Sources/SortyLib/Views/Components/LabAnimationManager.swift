//
//  LabAnimationManager.swift
//  Sorty
//
//  Manages the state and lifecycle of animated particles and folder nodes in the Sorting Lab.
//

import SwiftUI
import Combine

/// Orchestrates file particle animations flowing from source → AI Portal → folder destinations.
@MainActor
final class LabAnimationManager: ObservableObject {

    // MARK: - Types

    /// A file particle traveling through the lab.
    struct Particle: Identifiable {
        let id = UUID()
        let fileName: String
        var phase: Phase
        var normalizedProgress: CGFloat
        var destinationFolder: String?
        let createdAt: Date

        enum Phase {
            case enteringPortal
            case processingAtPortal
            case travelingToFolder
            case arrived
        }
    }

    /// A folder node destination.
    struct FolderNode: Identifiable, Equatable {
        let id = UUID()
        let name: String
        var fileCount: Int
        var isLoading: Bool
        var isReceivingFile: Bool
        var angleFromCenter: Double

        static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
            lhs.name == rhs.name
        }
    }

    // MARK: - Published State

    @Published var particles: [Particle] = []
    @Published var folderNodes: [FolderNode] = []
    @Published var portalReceivedFilePulse: Bool = false
    @Published var isActive: Bool = false

    // MARK: - Private State

    private var lastProcessedMoveCount: Int = 0
    private var lastProcessedInsightCount: Int = 0
    private var particleCleanupTask: Task<Void, Never>?
    private var batchBuffer: [String] = []
    private let maxActiveParticles = 12
    private let maxVisibleFolders = 8
    private let progressDelta: CGFloat = 0.035
    private let phaseLifetime: TimeInterval = 2.5

    // MARK: - Public Methods

    /// Process scanned files by spawning a sample of entering-portal particles.
    func processScannedFiles(_ fileNames: [String]) {
        guard !fileNames.isEmpty else { return }
        isActive = true

        let sampled = sampleFileNames(fileNames, maxCount: 20)
        let slotsAvailable = maxActiveParticles - activeParticleCount
        let toCreate = sampled.prefix(max(slotsAvailable, 0))

        let now = Date()
        let newParticles = toCreate.map { name in
            Particle(
                fileName: name,
                phase: .enteringPortal,
                normalizedProgress: 0,
                destinationFolder: nil,
                createdAt: now
            )
        }
        particles.append(contentsOf: newParticles)
    }

    /// Detect new moves and create folder-bound particles for each.
    func processLiveMoves(_ moves: [LiveOrganizationMove], previousCount: Int) {
        let newMoves = Array(moves.dropFirst(previousCount))
        guard !newMoves.isEmpty else { return }
        isActive = true

        let now = Date()
        for move in newMoves {
            let folderIndex = findOrCreateFolderNode(named: move.destinationFolder)
            folderNodes[folderIndex].fileCount += 1

            let slotsAvailable = maxActiveParticles - activeParticleCount
            if slotsAvailable > 0 {
                let particle = Particle(
                    fileName: move.fileName,
                    phase: .travelingToFolder,
                    normalizedProgress: 0,
                    destinationFolder: move.destinationFolder,
                    createdAt: now
                )
                particles.append(particle)
            }

            // Briefly flash the receiving indicator
            folderNodes[folderIndex].isReceivingFile = true
            let folderName = folderNodes[folderIndex].name
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                if let idx = self.folderNodes.firstIndex(where: { $0.name == folderName }) {
                    self.folderNodes[idx].isReceivingFile = false
                }
            }

            portalReceivedFilePulse.toggle()
        }

        lastProcessedMoveCount = moves.count
    }

    /// Add folder nodes from new folder-type insights.
    func processInsights(_ insights: [AIInsight], previousCount: Int) {
        let newInsights = Array(insights.dropFirst(previousCount))
        let folderInsights = newInsights.filter { $0.category == .folder }

        for insight in folderInsights {
            let folderName = insight.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: " ").first ?? insight.text

            if !folderNodes.contains(where: { $0.name == folderName }) &&
                folderNodes.count < maxVisibleFolders {
                let node = FolderNode(
                    name: folderName,
                    fileCount: 0,
                    isLoading: true,
                    isReceivingFile: false,
                    angleFromCenter: 0
                )
                folderNodes.append(node)
                redistributeFolderAngles()
            }
        }

        lastProcessedInsightCount = insights.count
    }

    /// Advance particle progress and handle phase transitions. Called from a TimelineView or timer.
    func tick() {
        guard isActive else { return }

        var indicesToRemove: [Int] = []
        let now = Date()

        for i in particles.indices {
            particles[i].normalizedProgress += progressDelta

            switch particles[i].phase {
            case .enteringPortal:
                if particles[i].normalizedProgress >= 1.0 {
                    particles[i].phase = .processingAtPortal
                    particles[i].normalizedProgress = 0
                }

            case .processingAtPortal:
                if particles[i].normalizedProgress >= 1.0 {
                    if particles[i].destinationFolder != nil {
                        particles[i].phase = .travelingToFolder
                        particles[i].normalizedProgress = 0
                    } else {
                        particles[i].phase = .arrived
                    }
                }

            case .travelingToFolder:
                if particles[i].normalizedProgress >= 1.0 {
                    particles[i].phase = .arrived
                    particles[i].normalizedProgress = 1.0
                }

            case .arrived:
                break
            }

            // Clean up arrived particles or those that exceeded lifetime
            if particles[i].phase == .arrived ||
                now.timeIntervalSince(particles[i].createdAt) > phaseLifetime * 3 {
                indicesToRemove.append(i)
            }
        }

        // Remove expired particles in reverse order to preserve indices
        for i in indicesToRemove.reversed() {
            particles.remove(at: i)
        }

        // Cap active particles for performance
        if particles.count > maxActiveParticles {
            particles = Array(particles.suffix(maxActiveParticles))
        }

        if particles.isEmpty && folderNodes.allSatisfy({ !$0.isLoading }) {
            isActive = false
        }
    }

    /// Add a batch of scanning particles sampled from file names.
    func addScanningParticles(fileNames: [String]) {
        let sampled = sampleFileNames(fileNames, maxCount: 6)
        let slotsAvailable = maxActiveParticles - activeParticleCount
        guard slotsAvailable > 0 else { return }

        let now = Date()
        let newParticles = sampled.prefix(slotsAvailable).map { name in
            Particle(
                fileName: name,
                phase: .enteringPortal,
                normalizedProgress: CGFloat.random(in: 0...0.3),
                destinationFolder: nil,
                createdAt: now
            )
        }
        particles.append(contentsOf: newParticles)
        isActive = true
    }

    /// Clear all animation state.
    func reset() {
        particles.removeAll()
        folderNodes.removeAll()
        portalReceivedFilePulse = false
        isActive = false
        lastProcessedMoveCount = 0
        lastProcessedInsightCount = 0
        batchBuffer.removeAll()
        particleCleanupTask?.cancel()
        particleCleanupTask = nil
    }

    // MARK: - Private Helpers

    private var activeParticleCount: Int {
        particles.filter { $0.phase != .arrived }.count
    }

    /// Sample a subset of file names for display, avoiding overwhelming the animation.
    private func sampleFileNames(_ names: [String], maxCount: Int) -> [String] {
        guard names.count > maxCount else { return names }
        var sampled: [String] = []
        var indices = Set<Int>()
        while sampled.count < maxCount {
            let idx = Int.random(in: 0..<names.count)
            if indices.insert(idx).inserted {
                sampled.append(names[idx])
            }
        }
        return sampled
    }

    /// Find an existing folder node by name or create a new one. Returns the index.
    @discardableResult
    private func findOrCreateFolderNode(named name: String) -> Int {
        if let idx = folderNodes.firstIndex(where: { $0.name == name }) {
            folderNodes[idx].isLoading = false
            return idx
        }

        // Evict the oldest low-count folder if at capacity
        if folderNodes.count >= maxVisibleFolders {
            if let minIdx = folderNodes.enumerated()
                .min(by: { $0.element.fileCount < $1.element.fileCount })?.offset {
                folderNodes.remove(at: minIdx)
            }
        }

        let node = FolderNode(
            name: name,
            fileCount: 0,
            isLoading: false,
            isReceivingFile: false,
            angleFromCenter: 0
        )
        folderNodes.append(node)
        redistributeFolderAngles()
        return folderNodes.count - 1
    }

    /// Distribute folder nodes evenly around a circle.
    private func redistributeFolderAngles() {
        let count = folderNodes.count
        guard count > 0 else { return }
        for i in folderNodes.indices {
            folderNodes[i].angleFromCenter = (2 * .pi / Double(count)) * Double(i)
        }
    }
}

//
//  WorkspaceHealth.swift
//  FileOrganizer
//
//  Automated Workspace Health Insights
//  Tracks clutter growth and cleanup opportunities over time
//

import Foundation
import SwiftUI
import Combine

// MARK: - Configuration Models

/// Configuration for Workspace Health analysis
public struct WorkspaceHealthConfig: Codable, Equatable, Sendable {
    public var largeFileSizeThreshold: Int64
    public var oldFileThreshold: TimeInterval
    public var downloadClutterThreshold: TimeInterval
    public var enabledChecks: Set<CleanupOpportunity.OpportunityType>
    public var ignoredPaths: [String]
    
    public init(
        largeFileSizeThreshold: Int64 = 100_000_000, // 100MB
        oldFileThreshold: TimeInterval = 365 * 86400, // 1 year
        downloadClutterThreshold: TimeInterval = 30 * 86400, // 30 days
        enabledChecks: Set<CleanupOpportunity.OpportunityType> = Set(CleanupOpportunity.OpportunityType.allCases),
        ignoredPaths: [String] = []
    ) {
        self.largeFileSizeThreshold = largeFileSizeThreshold
        self.oldFileThreshold = oldFileThreshold
        self.downloadClutterThreshold = downloadClutterThreshold
        self.enabledChecks = enabledChecks
        self.ignoredPaths = ignoredPaths
    }
}

// MARK: - Data Models

/// Snapshot of a directory's state at a point in time
public struct DirectorySnapshot: Codable, Identifiable, Sendable {
    public let id: UUID
    public let directoryPath: String
    public let timestamp: Date
    public let totalFiles: Int
    public let totalSize: Int64
    public let filesByExtension: [String: Int]
    public let unorganizedCount: Int
    public let averageFileAge: TimeInterval // Days since creation

    public init(
        id: UUID = UUID(),
        directoryPath: String,
        timestamp: Date = Date(),
        totalFiles: Int,
        totalSize: Int64,
        filesByExtension: [String: Int] = [:],
        unorganizedCount: Int = 0,
        averageFileAge: TimeInterval = 0
    ) {
        self.id = id
        self.directoryPath = directoryPath
        self.timestamp = timestamp
        self.totalFiles = totalFiles
        self.totalSize = totalSize
        self.filesByExtension = filesByExtension
        self.unorganizedCount = unorganizedCount
        self.averageFileAge = averageFileAge
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    public var formattedAverageAge: String {
        let days = Int(averageFileAge / 86400)
        if days == 0 {
            return "< 1 day"
        } else if days == 1 {
            return "1 day"
        } else if days < 30 {
            return "\(days) days"
        } else if days < 365 {
            let months = days / 30
            return "\(months) month\(months == 1 ? "" : "s")"
        } else {
            let years = days / 365
            return "\(years) year\(years == 1 ? "" : "s")"
        }
    }
}

/// Represents growth/change between two snapshots
public struct DirectoryGrowth: Sendable {
    public let previousSnapshot: DirectorySnapshot
    public let currentSnapshot: DirectorySnapshot
    public let period: TimeInterval

    public init(previous: DirectorySnapshot, current: DirectorySnapshot) {
        self.previousSnapshot = previous
        self.currentSnapshot = current
        self.period = current.timestamp.timeIntervalSince(previous.timestamp)
    }

    public var fileCountChange: Int {
        currentSnapshot.totalFiles - previousSnapshot.totalFiles
    }

    public var sizeChange: Int64 {
        currentSnapshot.totalSize - previousSnapshot.totalSize
    }

    public var formattedSizeChange: String {
        let prefix = sizeChange >= 0 ? "+" : ""
        return prefix + ByteCountFormatter.string(fromByteCount: sizeChange, countStyle: .file)
    }

    public var percentageGrowth: Double {
        guard previousSnapshot.totalSize > 0 else { return 0 }
        return Double(sizeChange) / Double(previousSnapshot.totalSize) * 100
    }

    public var isGrowing: Bool {
        sizeChange > 0
    }

    public var growthRate: GrowthRate {
        if sizeChange <= 0 {
            return .stable
        } else if sizeChange < 100_000_000 { // < 100MB
            return .slow
        } else if sizeChange < 1_000_000_000 { // < 1GB
            return .moderate
        } else {
            return .rapid
        }
    }

    public enum GrowthRate: String, Sendable {
        case stable = "Stable"
        case slow = "Slow Growth"
        case moderate = "Moderate Growth"
        case rapid = "Rapid Growth"

        public var color: Color {
            switch self {
            case .stable: return .green
            case .slow: return .blue
            case .moderate: return .orange
            case .rapid: return .red
            }
        }

        public var icon: String {
            switch self {
            case .stable: return "checkmark.circle"
            case .slow: return "arrow.up.right"
            case .moderate: return "arrow.up"
            case .rapid: return "exclamationmark.arrow.triangle.2.circlepath"
            }
        }
    }

    /// Get the most growing file types
    public var topGrowingTypes: [(extension: String, count: Int)] {
        var changes: [String: Int] = [:]

        for (ext, count) in currentSnapshot.filesByExtension {
            let previousCount = previousSnapshot.filesByExtension[ext] ?? 0
            let change = count - previousCount
            if change > 0 {
                changes[ext] = change
            }
        }

        return changes
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { ($0.key, $0.value) }
    }
}

/// A cleanup opportunity identified by the health system
public struct CleanupOpportunity: Codable, Identifiable, Sendable {
    public let id: UUID
    public let type: OpportunityType
    public let directoryPath: String
    public let description: String
    public let estimatedSavings: Int64
    public let fileCount: Int
    public let priority: Priority
    public let createdAt: Date
    public var isDismissed: Bool
    public let action: QuickAction?

    public enum QuickAction: String, Codable, Sendable {
        case archiveOldDownloads = "Archive Old Downloads"
        case groupScreenshots = "Group Screenshots"
        case cleanInstallers = "Clean Installers"
        case pruneEmptyFolders = "Prune Empty Folders"
        case removeBrokenSymlinks = "Remove Broken Symlinks"
        case organizeRoot = "Organize Root Files"
        
        public var icon: String {
            switch self {
            case .archiveOldDownloads: return "archivebox"
            case .groupScreenshots: return "rectangle.stack"
            case .cleanInstallers: return "trash"
            case .pruneEmptyFolders: return "folder.badge.minus"
            case .removeBrokenSymlinks: return "link.badge.minus"
            case .organizeRoot: return "wand.and.stars"
            }
        }
    }

    public enum OpportunityType: String, Codable, Sendable, CaseIterable {
        case duplicateFiles = "Duplicate Files"
        case unorganizedFiles = "Unorganized Files"
        case largeFiles = "Large Files"
        case oldFiles = "Old Files"
        case veryOldFiles = "Very Old Files"
        case screenshotClutter = "Screenshot Clutter"
        case downloadClutter = "Download Clutter"
        case cacheFiles = "Cache Files"
        case temporaryFiles = "Temporary Files"
        case emptyFolders = "Empty Folders"
        case brokenSymlinks = "Broken Symlinks"
        
        public static var allCases: [OpportunityType] {
            [.duplicateFiles, .unorganizedFiles, .largeFiles, .oldFiles, .veryOldFiles, .screenshotClutter, .downloadClutter, .cacheFiles, .temporaryFiles, .emptyFolders, .brokenSymlinks]
        }
        


        public var icon: String {
            switch self {
            case .duplicateFiles: return "doc.on.doc"
            case .unorganizedFiles: return "folder.badge.questionmark"
            case .largeFiles: return "externaldrive.fill"
            case .oldFiles: return "clock.arrow.circlepath"
            case .veryOldFiles: return "clock.badge.exclamationmark"
            case .screenshotClutter: return "camera.viewfinder"
            case .downloadClutter: return "arrow.down.circle"
            case .cacheFiles: return "archivebox"
            case .temporaryFiles: return "trash"
            case .emptyFolders: return "folder.badge.minus"
            case .brokenSymlinks: return "link.badge.plus"
            }
        }

        public var color: Color {
            switch self {
            case .duplicateFiles: return .purple
            case .unorganizedFiles: return .orange
            case .largeFiles: return .red
            case .oldFiles: return .gray
            case .veryOldFiles: return .brown
            case .screenshotClutter: return .blue
            case .downloadClutter: return .green
            case .cacheFiles: return .yellow
            case .temporaryFiles: return .pink
            case .emptyFolders: return .indigo
            case .brokenSymlinks: return .red
            }
        }
    }

    public enum Priority: Int, Codable, Comparable, Sendable {
        case low = 0
        case medium = 1
        case high = 2
        case critical = 3

        public static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var displayName: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .critical: return "Critical"
            }
        }

        public var color: Color {
            switch self {
            case .low: return .gray
            case .medium: return .blue
            case .high: return .orange
            case .critical: return .red
            }
        }
    }

    public init(
        id: UUID = UUID(),
        type: OpportunityType,
        directoryPath: String,
        description: String,
        estimatedSavings: Int64,
        fileCount: Int,
        priority: Priority = .medium,
        createdAt: Date = Date(),
        isDismissed: Bool = false,
        action: QuickAction? = nil
    ) {
        self.id = id
        self.type = type
        self.directoryPath = directoryPath
        self.description = description
        self.estimatedSavings = estimatedSavings
        self.fileCount = fileCount
        self.priority = priority
        self.createdAt = createdAt
        self.isDismissed = isDismissed
        self.action = action
    }

    public var formattedSavings: String {
        ByteCountFormatter.string(fromByteCount: estimatedSavings, countStyle: .file)
    }
}

/// Health insight notification for the user
public struct HealthInsight: Codable, Identifiable, Sendable {
    public let id: UUID
    public let directoryPath: String
    public let message: String
    public let details: String
    public let type: InsightType
    public let actionPrompt: String?
    public let createdAt: Date
    public var isRead: Bool

    public enum InsightType: String, Codable, Sendable {
        case growth = "Growth Alert"
        case opportunity = "Cleanup Opportunity"
        case milestone = "Milestone"
        case suggestion = "Suggestion"
        case warning = "Warning"

        public var icon: String {
            switch self {
            case .growth: return "chart.line.uptrend.xyaxis"
            case .opportunity: return "sparkles"
            case .milestone: return "flag.fill"
            case .suggestion: return "lightbulb"
            case .warning: return "exclamationmark.triangle"
            }
        }

        public var color: Color {
            switch self {
            case .growth: return .blue
            case .opportunity: return .green
            case .milestone: return .purple
            case .suggestion: return .orange
            case .warning: return .red
            }
        }
    }

    public init(
        id: UUID = UUID(),
        directoryPath: String,
        message: String,
        details: String,
        type: InsightType,
        actionPrompt: String? = nil,
        createdAt: Date = Date(),
        isRead: Bool = false
    ) {
        self.id = id
        self.directoryPath = directoryPath
        self.message = message
        self.details = details
        self.type = type
        self.actionPrompt = actionPrompt
        self.createdAt = createdAt
        self.isRead = isRead
    }
}

// MARK: - Workspace Health Manager

@MainActor
public class WorkspaceHealthManager: ObservableObject {
    @Published public var config: WorkspaceHealthConfig = WorkspaceHealthConfig()
    @Published public var snapshots: [String: [DirectorySnapshot]] = [:] // Path -> Snapshots
    @Published public var opportunities: [CleanupOpportunity] = []
    @Published public var insights: [HealthInsight] = []
    @Published public var isAnalyzing: Bool = false
    @Published public var lastAnalysisDate: Date?

    private let userDefaults = UserDefaults.standard
    private let configKey = "workspaceHealthConfig"
    private let snapshotsKey = "workspaceSnapshots"
    private let opportunitiesKey = "cleanupOpportunities"
    private let insightsKey = "healthInsights"
    private let maxSnapshotsPerDirectory = 52 // ~1 year of weekly snapshots
    
    // File Monitoring
    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitorFileDescriptor: Int32 = -1
    private var monitorQueue = DispatchQueue(label: "com.fileorganizer.healthmonitor", qos: .utility)
    private var monitorDebounceTimer: DispatchWorkItem?
    private var pollingTimer: Timer?
    private var lastModDate: Date?
    private var currentMonitoredPath: String?
    
    @Published public var fileChangeDetected: Date?

    public init() {
        loadData()
    }
    


    // MARK: - Public Methods

    /// Take a snapshot of a directory's current state
    public func takeSnapshot(at path: String, files: [FileItem]) async {
        let totalFiles = files.count
        let totalSize = files.reduce(0) { $0 + $1.size }

        // Count files by extension
        var byExtension: [String: Int] = [:]
        for file in files {
            let ext = file.extension.lowercased().isEmpty ? "no_extension" : file.extension.lowercased()
            byExtension[ext, default: 0] += 1
        }

        // Estimate unorganized files (files in root)
        let unorganized = files.filter { file in
            let relativePath = file.path.replacingOccurrences(of: path + "/", with: "")
            return !relativePath.contains("/")
        }.count

        // Calculate average file age
        let now = Date()
        let totalAge = files.compactMap { $0.creationDate }.reduce(0.0) { total, date in
            total + now.timeIntervalSince(date)
        }
        let averageAge = files.isEmpty ? 0 : totalAge / Double(files.count)

        let snapshot = DirectorySnapshot(
            directoryPath: path,
            totalFiles: totalFiles,
            totalSize: totalSize,
            filesByExtension: byExtension,
            unorganizedCount: unorganized,
            averageFileAge: averageAge
        )

        // Add to snapshots
        var directorySnapshots = snapshots[path] ?? []
        directorySnapshots.append(snapshot)

        // Trim old snapshots
        if directorySnapshots.count > maxSnapshotsPerDirectory {
            directorySnapshots = Array(directorySnapshots.suffix(maxSnapshotsPerDirectory))
        }

        snapshots[path] = directorySnapshots
        saveData()

        // Generate insights based on new snapshot
        await generateInsights(for: path)
    }

    /// Get growth analysis for a directory
    public func getGrowth(for path: String, period: TimePeriod = .week) -> DirectoryGrowth? {
        guard let directorySnapshots = snapshots[path],
              directorySnapshots.count >= 2 else {
            return nil
        }

        let cutoffDate = Date().addingTimeInterval(-period.timeInterval)

        // Find the snapshot closest to the cutoff date
        let previousSnapshot = directorySnapshots
            .filter { $0.timestamp <= cutoffDate }
            .max { $0.timestamp < $1.timestamp }

        guard let previous = previousSnapshot,
              let current = directorySnapshots.last else {
            return nil
        }

        return DirectoryGrowth(previous: previous, current: current)
    }

    /// Analyze a directory and identify cleanup opportunities
    public func analyzeDirectory(path: String, files: [FileItem]) async {
        isAnalyzing = true
        defer {
            isAnalyzing = false
            lastAnalysisDate = Date()
        }

        // Remove old opportunities for this path
        opportunities.removeAll { $0.directoryPath == path }

        // Check for Screenshot Clutter
        if config.enabledChecks.contains(.screenshotClutter) {
            let screenshots = files.filter { isScreenshot($0) }
            if screenshots.count >= 10 { // Still hardcoded min count for now, could be configurable
                opportunities.append(CleanupOpportunity(
                    type: .screenshotClutter,
                    directoryPath: path,
                    description: "\(screenshots.count) screenshots detected. Consider organizing by date or project.",
                    estimatedSavings: 0, // Not suggesting deletion
                    fileCount: screenshots.count,
                    priority: screenshots.count >= 50 ? .high : .medium,
                    action: .groupScreenshots
                ))
            }
        }

        // Check for Download Clutter
        if config.enabledChecks.contains(.downloadClutter) {
            let oldDownloads = files.filter { file in
                guard let date = file.creationDate else { return false }
                let age = Date().timeIntervalSince(date)
                return age > config.downloadClutterThreshold
            }
            if oldDownloads.count >= 20 {
                let totalSize = oldDownloads.reduce(0) { $0 + $1.size }
                let days = Int(config.downloadClutterThreshold / 86400)
                opportunities.append(CleanupOpportunity(
                    type: .downloadClutter,
                    directoryPath: path,
                    description: "\(oldDownloads.count) files are older than \(days) days.",
                    estimatedSavings: totalSize,
                    fileCount: oldDownloads.count,
                    priority: totalSize > 1_000_000_000 ? .high : .medium,
                    action: .archiveOldDownloads
                ))
            }
        }

        // Check for Large Files
        if config.enabledChecks.contains(.largeFiles) {
            let largeFiles = files.filter { $0.size > config.largeFileSizeThreshold }
            if !largeFiles.isEmpty {
                let totalSize = largeFiles.reduce(0) { $0 + $1.size }
                let sizeStr = ByteCountFormatter.string(fromByteCount: config.largeFileSizeThreshold, countStyle: .file)
                opportunities.append(CleanupOpportunity(
                    type: .largeFiles,
                    directoryPath: path,
                    description: "\(largeFiles.count) large files (>\(sizeStr)) found. Review for archival.",
                    estimatedSavings: totalSize,
                    fileCount: largeFiles.count,
                    priority: largeFiles.count >= 5 ? .high : .low
                ))
            }
        }

        // Check for Unorganized Files (Root)
        if config.enabledChecks.contains(.unorganizedFiles) {
            let rootFiles = files.filter { file in
                let relativePath = file.path.replacingOccurrences(of: path + "/", with: "")
                return !relativePath.contains("/") && !file.isDirectory
            }
            if rootFiles.count >= 20 {
                opportunities.append(CleanupOpportunity(
                    type: .unorganizedFiles,
                    directoryPath: path,
                    description: "\(rootFiles.count) unorganized files in root. Let AI organize them!",
                    estimatedSavings: 0,
                    fileCount: rootFiles.count,
                    priority: rootFiles.count >= 50 ? .critical : .high,
                    action: .organizeRoot
                ))
            }
        }

        // Check for Installers (Smart Grouping)
        // We'll treat this as a subset of other file checks or a standalone check
        let installers = files.filter { ["dmg", "pkg", "iso"].contains($0.extension.lowercased()) }
        if !installers.isEmpty {
            let totalSize = installers.reduce(0) { $0 + $1.size }
            opportunities.append(CleanupOpportunity(
                type: .largeFiles, // Re-using large files type or could be new 'installerClutter' type
                directoryPath: path,
                description: "\(installers.count) installer files found. Most can be safely deleted after installation.",
                estimatedSavings: totalSize,
                fileCount: installers.count,
                priority: .medium,
                action: .cleanInstallers
            ))
        }

        // Check for Temporary/Cache Files
        if config.enabledChecks.contains(.temporaryFiles) || config.enabledChecks.contains(.cacheFiles) {
            let tempFiles = files.filter { isTempOrCacheFile($0) }
            if !tempFiles.isEmpty {
                let totalSize = tempFiles.reduce(0) { $0 + $1.size }
                opportunities.append(CleanupOpportunity(
                    type: .temporaryFiles,
                    directoryPath: path,
                    description: "\(tempFiles.count) temporary files can be safely removed.",
                    estimatedSavings: totalSize,
                    fileCount: tempFiles.count,
                    priority: totalSize > 500_000_000 ? .high : .low
                ))
            }
        }

        // Check for Very Old Files
        if config.enabledChecks.contains(.veryOldFiles) || config.enabledChecks.contains(.oldFiles) {
            let veryOldFiles = files.filter { file in
                guard let accessDate = file.lastAccessDate ?? file.modificationDate else { return false }
                let age = Date().timeIntervalSince(accessDate)
                return age > config.oldFileThreshold
            }
            if veryOldFiles.count >= 10 {
                let totalSize = veryOldFiles.reduce(0) { $0 + $1.size }
                let years = String(format: "%.1f", config.oldFileThreshold / (365 * 86400))
                opportunities.append(CleanupOpportunity(
                    type: .veryOldFiles,
                    directoryPath: path,
                    description: "\(veryOldFiles.count) files haven't been accessed in over \(years) years. Consider archiving.",
                    estimatedSavings: totalSize,
                    fileCount: veryOldFiles.count,
                    priority: totalSize > 1_000_000_000 ? .high : .medium
                ))
            }
        }

        // Check for Empty Folders
        if config.enabledChecks.contains(.emptyFolders) {
            let emptyFolders = await findEmptyFolders(at: path)
            if !emptyFolders.isEmpty {
                opportunities.append(CleanupOpportunity(
                    type: .emptyFolders,
                    directoryPath: path,
                    description: "\(emptyFolders.count) empty folders can be removed to reduce clutter.",
                    estimatedSavings: 0,
                    fileCount: emptyFolders.count,
                    priority: emptyFolders.count >= 20 ? .medium : .low,
                    action: .pruneEmptyFolders
                ))
            }
        }

        // Check for Broken Symlinks
        if config.enabledChecks.contains(.brokenSymlinks) {
            let brokenSymlinks = await findBrokenSymlinks(at: path)
            if !brokenSymlinks.isEmpty {
                opportunities.append(CleanupOpportunity(
                    type: .brokenSymlinks,
                    directoryPath: path,
                    description: "\(brokenSymlinks.count) broken symbolic links found. These point to non-existent targets.",
                    estimatedSavings: 0,
                    fileCount: brokenSymlinks.count,
                    priority: brokenSymlinks.count >= 5 ? .medium : .low,
                    action: .removeBrokenSymlinks
                ))
            }
        }

        saveData()
    }

    /// Dismiss an opportunity
    public func dismissOpportunity(_ opportunity: CleanupOpportunity) {
        if let index = opportunities.firstIndex(where: { $0.id == opportunity.id }) {
            opportunities[index].isDismissed = true
            saveData()
        }
    }

    /// Mark insight as read
    public func markInsightAsRead(_ insight: HealthInsight) {
        if let index = insights.firstIndex(where: { $0.id == insight.id }) {
            insights[index].isRead = true
            saveData()
        }
    }

    /// Clear all insights
    public func clearInsights() {
        insights.removeAll()
        saveData()
    }

    /// Update configuration
    public func updateConfig(_ newConfig: WorkspaceHealthConfig) {
        self.config = newConfig
        saveData()
    }
    
    // MARK: - File Monitoring
    
    /// Start monitoring a directory for changes
    public func startMonitoring(path: String) {
        // If already monitoring this path, don't restart everything, just ensure it's active
        if path == currentMonitoredPath && monitorSource != nil {
            return
        }
        
        stopMonitoring() // Stop existing
        currentMonitoredPath = path
        
        // 1. Start DispatchSource Monitoring (Immediate)
        let fd = open(path, O_EVTONLY)
        if fd >= 0 {
            monitorFileDescriptor = fd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .extend, .attrib],
                queue: monitorQueue
            )
            
            source.setEventHandler { [weak self] in
                self?.handleFileEvent()
            }
            
            source.setCancelHandler { [weak self] in
                if let fd = self?.monitorFileDescriptor, fd >= 0 {
                    close(fd)
                }
                self?.monitorFileDescriptor = -1
            }
            
            monitorSource = source
            source.resume()
            DebugLogger.log("WorkspaceHealth: DispatchSource monitoring active for \(path)")
        } else {
            DebugLogger.log("WorkspaceHealth: Failed to open path for DispatchSource, falling back to polling: \(path)")
        }
        
        // 2. Start Polling Backup (Robustness)
        // Check every 3 seconds for modification date changes
        updateLastModDate(path: path)
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkDirectoryModDate()
            }
        }
    }
    
    /// Stop monitoring current directory
    public func stopMonitoring() {
        monitorDebounceTimer?.cancel()
        monitorDebounceTimer = nil
        
        if let source = monitorSource {
            source.cancel()
            monitorSource = nil
        }
        
        pollingTimer?.invalidate()
        pollingTimer = nil
        currentMonitoredPath = nil
    }
    
    private func updateLastModDate(path: String) {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attrs[.modificationDate] as? Date {
            lastModDate = date
        }
    }
    
    private func checkDirectoryModDate() {
        guard let path = currentMonitoredPath else { return }
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attrs[.modificationDate] as? Date {
            
            if let last = lastModDate, date > last {
                DebugLogger.log("WorkspaceHealth: Polling detected change in \(path)")
                handleFileEvent() // Reuse debounce logic
                lastModDate = date
            } else if lastModDate == nil {
                lastModDate = date
            }
        }
    }
    
    private func handleFileEvent() {
        // Debounce logic
        monitorDebounceTimer?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                DebugLogger.log("WorkspaceHealth: File system change detected")
                self?.fileChangeDetected = Date()
            }
        }
        
        monitorDebounceTimer = workItem
        monitorQueue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    /// Perform a quick action for an opportunity
    public func performAction(_ action: CleanupOpportunity.QuickAction, for opportunity: CleanupOpportunity) async throws {
        let path = opportunity.directoryPath
        
        switch action {
        case .archiveOldDownloads:
            try await archiveOldDownloads(at: path)
        case .groupScreenshots:
            try await groupScreenshots(at: path)
        case .cleanInstallers:
            try await cleanInstallers(at: path)
        case .pruneEmptyFolders:
            try await pruneEmptyFoldersRecursively(at: path) // Renamed to disambiguate
        case .removeBrokenSymlinks:
            try await removeBrokenSymlinks(at: path)
        case .organizeRoot:
            // This is handled by the main organizer flow found elsewhere, 
            // but we could trigger a specific mode here if needed.
            // For now, we'll assume the UI routes this to the main organizer.
            break
        }
        
        // Refresh analysis after action
        // We need to re-scan the files. Since we don't have the file list here easily without re-scanning,
        // we might need to rely on the UI to trigger a re-scan or do a lightweight check.
        // For now, let's just mark the opportunity as dismissed/resolved relative to the UI state if possible,
        // but ideally we re-analyze.
        dismissOpportunity(opportunity)
    }

    // MARK: - Computed Properties

    public var activeOpportunities: [CleanupOpportunity] {
        opportunities.filter { !$0.isDismissed }.sorted { $0.priority > $1.priority }
    }

    public var unreadInsights: [HealthInsight] {
        insights.filter { !$0.isRead }.sorted { $0.createdAt > $1.createdAt }
    }

    public var totalPotentialSavings: Int64 {
        activeOpportunities.reduce(0) { $0 + $1.estimatedSavings }
    }

    public var formattedTotalSavings: String {
        ByteCountFormatter.string(fromByteCount: totalPotentialSavings, countStyle: .file)
    }

    /// Calculate overall health score (0-100)
    /// 100 = Perfect
    public var healthScore: Double {
        var score = 100.0
        
        // Deduct for active opportunities based on priority
        for opportunity in activeOpportunities {
            switch opportunity.priority {
            case .critical: score -= 10.0
            case .high: score -= 5.0
            case .medium: score -= 2.0
            case .low: score -= 0.5
            }
        }
        
        // Deduct for rapid growth in any tracked directory
        for (path, _) in snapshots {
            if let growth = getGrowth(for: path, period: .week), growth.growthRate == .rapid {
                score -= 5.0
            }
        }
        
        return max(0, min(100, score))
    }
    
    public var healthStatus: (title: String, color: Color) {
        let score = healthScore
        if score >= 90 {
            return ("Excellent", .green)
        } else if score >= 70 {
            return ("Good", .blue)
        } else if score >= 50 {
            return ("Fair", .orange)
        } else {
            return ("Needs Attention", .red)
        }
    }

    // MARK: - Private Methods

    private func generateInsights(for path: String) async {
        guard let directorySnapshots = snapshots[path], directorySnapshots.count >= 2 else {
            return
        }

        // Weekly growth insight
        if let growth = getGrowth(for: path, period: .week), growth.isGrowing {
            let directoryName = URL(fileURLWithPath: path).lastPathComponent

            // Create insight for significant growth
            if growth.sizeChange > 500_000_000 { // > 500MB
                let topTypes = growth.topGrowingTypes.prefix(3).map { "\($0.count) \($0.extension) files" }.joined(separator: ", ")

                let insight = HealthInsight(
                    directoryPath: path,
                    message: "Your \(directoryName) folder grew by \(growth.formattedSizeChange) this week",
                    details: topTypes.isEmpty ? "Consider organizing to keep things tidy." : "Main contributors: \(topTypes)",
                    type: .growth,
                    actionPrompt: "Would you like me to organize new files?"
                )

                // Only add if we don't have a similar recent insight
                let hasRecent = insights.contains { existing in
                    existing.directoryPath == path &&
                    existing.type == .growth &&
                    Date().timeIntervalSince(existing.createdAt) < 7 * 86400
                }

                if !hasRecent {
                    insights.insert(insight, at: 0)
                    saveData()

                    // Send notification if enabled
                    await sendNotification(insight)
                }
            }
        }
    }

    private func sendNotification(_ insight: HealthInsight) async {
        let center = UNUserNotificationCenter.current()

        // Request authorization if needed
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "FileOrganizer"
            content.body = insight.message
            content.sound = .default

            if let prompt = insight.actionPrompt {
                content.subtitle = prompt
            }

            let request = UNNotificationRequest(
                identifier: insight.id.uuidString,
                content: content,
                trigger: nil // Deliver immediately
            )

            try await center.add(request)
        } catch {
            DebugLogger.log("Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Action Helpers
    
    private func archiveOldDownloads(at path: String) async throws {
        let fileManager = FileManager.default
        let archiveFolder = URL(fileURLWithPath: path).appendingPathComponent("Archive")
        
        // Create Archive folder if needed
        if !fileManager.fileExists(atPath: archiveFolder.path) {
            try fileManager.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        }
        
        let files = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        
        for file in files {
            guard !file.hasDirectoryPath else { continue }
            
            // customized for download clutter threshold
            if let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
               Date().timeIntervalSince(date) > config.downloadClutterThreshold {
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM"
                let dateFolder = archiveFolder.appendingPathComponent(dateFormatter.string(from: date))
                
                if !fileManager.fileExists(atPath: dateFolder.path) {
                    try fileManager.createDirectory(at: dateFolder, withIntermediateDirectories: true)
                }
                
                var destination = dateFolder.appendingPathComponent(file.lastPathComponent)
                
                // If conflict exists in archive, append human-readable timestamp to make unique
                if fileManager.fileExists(atPath: destination.path) {
                    let fileName = file.deletingPathExtension().lastPathComponent
                    let fileExt = file.pathExtension
                    
                    let timestamp = Date().filenameTimestamp
                    let uniqueName = "\(fileName)_\(timestamp).\(fileExt)"
                    destination = dateFolder.appendingPathComponent(uniqueName)
                }
                
                try fileManager.moveItem(at: file, to: destination)
            }
        }
    }
    
    private func groupScreenshots(at path: String) async throws {
        let fileManager = FileManager.default
        let screenshotsFolder = URL(fileURLWithPath: path).appendingPathComponent("Screenshots")
        
        let files = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        
        for file in files {
            let filename = file.lastPathComponent.lowercased()
            // Re-use isScreenshot logic but adapted for URL
            let isScreenie = ["screenshot", "screen shot", "capture"].contains { filename.contains($0) }
            
            if isScreenie {
                if !fileManager.fileExists(atPath: screenshotsFolder.path) {
                    try fileManager.createDirectory(at: screenshotsFolder, withIntermediateDirectories: true)
                }
                
                // Group by year-month
                if let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate {
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM"
                    let dateFolder = screenshotsFolder.appendingPathComponent(dateFormatter.string(from: date))
                    
                    if !fileManager.fileExists(atPath: dateFolder.path) {
                        try fileManager.createDirectory(at: dateFolder, withIntermediateDirectories: true)
                    }
                    
                    let destination = dateFolder.appendingPathComponent(file.lastPathComponent)
                    try fileManager.moveItem(at: file, to: destination)
                } else {
                    // Fallback to strict move if no date
                       let destination = screenshotsFolder.appendingPathComponent(file.lastPathComponent)
                       try fileManager.moveItem(at: file, to: destination)
                }
            }
        }
    }
    
    private func cleanInstallers(at path: String) async throws {
        let fileManager = FileManager.default
        let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first!
        
        let files = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        
        for file in files {
             let ext = file.pathExtension.lowercased()
             if ["dmg", "pkg", "iso"].contains(ext) {
                 var destination = trashURL.appendingPathComponent(file.lastPathComponent)
                 
                 // If conflict exists in trash, append human-readable timestamp to make unique
                 if fileManager.fileExists(atPath: destination.path) {
                     let fileName = file.deletingPathExtension().lastPathComponent
                     let fileExt = file.pathExtension
                     
                     let timestamp = Date().filenameTimestamp
                     let uniqueName = "\(fileName)_\(timestamp).\(fileExt)"
                     destination = trashURL.appendingPathComponent(uniqueName)
                 }
                 
                 try fileManager.moveItem(at: file, to: destination)
             }
        }
    }
    
    private func pruneEmptyFoldersRecursively(at path: String) async throws {
        let fileManager = FileManager.default
        // We need a depth-first traversal to remove nested empty folders
        // Simple implementation: repeatedly find empty folders and remove them until none found
        
        var hasRemoved = true
        while hasRemoved {
            hasRemoved = false
            let emptyFolders = await findEmptyFolders(at: path)
            for folderPath in emptyFolders {
                try fileManager.removeItem(atPath: folderPath)
                hasRemoved = true
            }
        }
    }
    
    private func removeBrokenSymlinks(at path: String) async throws {
        let fileManager = FileManager.default
        let brokenLinks = await findBrokenSymlinks(at: path)
        for linkPath in brokenLinks {
            try fileManager.removeItem(atPath: linkPath)
        }
    }

    private func isScreenshot(_ file: FileItem) -> Bool {
        let name = file.name.lowercased()
        let patterns = ["screenshot", "screen shot", "capture", "スクリーンショット", "截屏"]
        return patterns.contains { name.contains($0) }
    }

    private func isTempOrCacheFile(_ file: FileItem) -> Bool {
        let name = file.name.lowercased()
        let ext = file.extension.lowercased()

        let tempExtensions = ["tmp", "temp", "cache", "bak", "old", "swp"]
        let tempPatterns = [".ds_store", "thumbs.db", "desktop.ini", "~$"]

        return tempExtensions.contains(ext) ||
               tempPatterns.contains { name.contains($0) } ||
               name.hasPrefix("~") ||
               name.hasSuffix("~")
    }

    /// Find empty folders in a directory (non-recursive check for immediate children)
    private func findEmptyFolders(at path: String) async -> [String] {
        let fileManager = FileManager.default
        var emptyFolders: [String] = []

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        while let url = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    let contents = try fileManager.contentsOfDirectory(atPath: url.path)
                    // Filter out hidden files
                    let visibleContents = contents.filter { !$0.hasPrefix(".") }
                    if visibleContents.isEmpty {
                        emptyFolders.append(url.path)
                    }
                }
            } catch {
                continue
            }
        }

        return emptyFolders
    }

    /// Find broken symbolic links in a directory
    private func findBrokenSymlinks(at path: String) async -> [String] {
        let fileManager = FileManager.default
        var brokenLinks: [String] = []

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        while let url = enumerator.nextObject() as? URL {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                if resourceValues.isSymbolicLink == true {
                    // Try to resolve the symlink
                    let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
                    let destinationURL = URL(fileURLWithPath: destination, relativeTo: url.deletingLastPathComponent())
                    
                    if !fileManager.fileExists(atPath: destinationURL.path) {
                        brokenLinks.append(url.path)
                    }
                }
            } catch {
                // If we can't resolve, it's broken
                brokenLinks.append(url.path)
            }
        }

        return brokenLinks
    }

    // MARK: - Persistence

    private func loadData() {
        // Load config
        if let data = userDefaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(WorkspaceHealthConfig.self, from: data) {
            config = decoded
        }

        // Load snapshots
        if let data = userDefaults.data(forKey: snapshotsKey),
           let decoded = try? JSONDecoder().decode([String: [DirectorySnapshot]].self, from: data) {
            snapshots = decoded
        }

        // Load opportunities
        if let data = userDefaults.data(forKey: opportunitiesKey),
           let decoded = try? JSONDecoder().decode([CleanupOpportunity].self, from: data) {
            opportunities = decoded
        }

        // Load insights
        if let data = userDefaults.data(forKey: insightsKey),
           let decoded = try? JSONDecoder().decode([HealthInsight].self, from: data) {
            insights = decoded
        }
    }

    private func saveData() {
        if let encoded = try? JSONEncoder().encode(config) {
            userDefaults.set(encoded, forKey: configKey)
        }
        
        if let encoded = try? JSONEncoder().encode(snapshots) {
            userDefaults.set(encoded, forKey: snapshotsKey)
        }

        if let encoded = try? JSONEncoder().encode(opportunities) {
            userDefaults.set(encoded, forKey: opportunitiesKey)
        }

        if let encoded = try? JSONEncoder().encode(insights) {
            userDefaults.set(encoded, forKey: insightsKey)
        }
    }
}

// MARK: - Time Period

public enum TimePeriod: String, CaseIterable, Identifiable, Sendable {
    case day = "24 Hours"
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    public var id: String { rawValue }

    public var timeInterval: TimeInterval {
        switch self {
        case .day: return 86400
        case .week: return 7 * 86400
        case .month: return 30 * 86400
        case .quarter: return 90 * 86400
        case .year: return 365 * 86400
        }
    }
}

// Required for notifications
import UserNotifications

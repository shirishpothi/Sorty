//
//  WorkspaceHealth.swift
//  Sorty
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
    public var minScreenshotCount: Int
    public var minDownloadCount: Int
    public var minUnorganizedCount: Int
    public var minOldFileCount: Int
    public var enabledChecks: Set<CleanupOpportunity.OpportunityType>
    public var ignoredPaths: [String]
    
    public init(
        largeFileSizeThreshold: Int64 = 100_000_000, // 100MB
        oldFileThreshold: TimeInterval = 365 * 86400, // 1 year
        downloadClutterThreshold: TimeInterval = 30 * 86400, // 30 days
        minScreenshotCount: Int = 10,
        minDownloadCount: Int = 5,
        minUnorganizedCount: Int = 10,
        minOldFileCount: Int = 10,
        enabledChecks: Set<CleanupOpportunity.OpportunityType> = Set(CleanupOpportunity.OpportunityType.allCases),
        ignoredPaths: [String] = []
    ) {
        self.largeFileSizeThreshold = largeFileSizeThreshold
        self.oldFileThreshold = oldFileThreshold
        self.downloadClutterThreshold = downloadClutterThreshold
        self.minScreenshotCount = minScreenshotCount
        self.minDownloadCount = minDownloadCount
        self.minUnorganizedCount = minUnorganizedCount
        self.minOldFileCount = minOldFileCount
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
    
    // NEW: Detailed fields for preview and smart actions
    public let affectedFiles: [AffectedFile]
    public let detailedReason: String
    public let confidence: Int // 0-100

    public struct AffectedFile: Codable, Identifiable, Sendable {
        public let id: UUID
        public let path: String
        public let name: String
        public let size: Int64
        public let lastAccessed: Date?
        public let reason: String // Why this specific file is flagged
        
        public init(id: UUID = UUID(), path: String, name: String, size: Int64, lastAccessed: Date?, reason: String) {
            self.id = id
            self.path = path
            self.name = name
            self.size = size
            self.lastAccessed = lastAccessed
            self.reason = reason
        }
    }

    public enum QuickAction: String, Codable, Sendable {
        case archiveOldDownloads = "Archive Old Downloads"
        case groupScreenshots = "Group Screenshots"
        case cleanInstallers = "Clean Installers"
        case pruneEmptyFolders = "Prune Empty Folders"
        case removeBrokenSymlinks = "Remove Broken Symlinks"
        case organizeRoot = "Organize Root Files"
        case archiveVeryOldFiles = "Archive Very Old Files"
        
        public var icon: String {
            switch self {
            case .archiveOldDownloads: return "archivebox"
            case .groupScreenshots: return "rectangle.stack"
            case .cleanInstallers: return "trash"
            case .pruneEmptyFolders: return "folder.badge.minus"
            case .removeBrokenSymlinks: return "link.badge.minus"
            case .organizeRoot: return "wand.and.stars"
            case .archiveVeryOldFiles: return "archivebox.fill"
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
        action: QuickAction? = nil,
        affectedFiles: [AffectedFile] = [],
        detailedReason: String = "",
        confidence: Int = 100
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
        self.affectedFiles = affectedFiles
        self.detailedReason = detailedReason
        self.confidence = confidence
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

// MARK: - History & Undo

public struct CleanupHistoryItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let actionName: String
    public let affectedFilePaths: [String]
    public let type: ActionType
    
    public enum ActionType: String, Codable, Sendable {
        case move
        case trash
        case delete
    }
    
    // For moves, we store where they went so we can move them back
    public let destinationPaths: [String]? 
    
    public init(id: UUID = UUID(), date: Date = Date(), actionName: String, affectedFilePaths: [String], type: ActionType, destinationPaths: [String]? = nil) {
        self.id = id
        self.date = date
        self.actionName = actionName
        self.affectedFilePaths = affectedFilePaths
        self.type = type
        self.destinationPaths = destinationPaths
    }
}

public enum WorkspaceHealthScanError: LocalizedError, Sendable {
    case unreadableDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableDirectory(let path):
            return "Unable to scan \(path). Check permissions and try again."
        }
    }
}

// MARK: - Workspace Health Manager

@MainActor
public class WorkspaceHealthManager: ObservableObject {
    @Published public var config: WorkspaceHealthConfig = WorkspaceHealthConfig()
    @Published public var snapshots: [String: [DirectorySnapshot]] = [:] // Path -> Snapshots
    @Published public var opportunities: [CleanupOpportunity] = [] {
        didSet { refreshDerivedHealthSummary() }
    }
    @Published public var insights: [HealthInsight] = [] {
        didSet { refreshDerivedHealthSummary() }
    }
    @Published public var cleanupHistory: [CleanupHistoryItem] = []
    @Published public var isAnalyzing: Bool = false
    @Published public var lastAnalysisDate: Date?
    @Published public private(set) var activeOpportunities: [CleanupOpportunity] = []
    @Published public private(set) var unreadInsights: [HealthInsight] = []
    @Published public private(set) var totalPotentialSavings: Int64 = 0
    @Published public private(set) var formattedTotalSavings: String = ByteCountFormatter.string(
        fromByteCount: 0,
        countStyle: .file
    )

    private let userDefaults = UserDefaults.standard
    private let configKey = "workspaceHealthConfig"
    private let snapshotsKey = "workspaceSnapshots"
    private let opportunitiesKey = "cleanupOpportunities"
    private let insightsKey = "healthInsights"
    private let historyStore = CleanupHistoryStore() // File-based storage
    private let maxSnapshotsPerDirectory = 52 // ~1 year of weekly snapshots
    
    // File Monitoring
    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitorFileDescriptor: Int32 = -1
    private var monitorQueue = DispatchQueue(label: "com.sorty.healthmonitor", qos: .utility)
    private var pollingTimer: Timer?
    private var lastModDate: Date?
    private var currentMonitoredPath: String?

    private struct ScanSignature: Equatable, Sendable {
        let fileCount: Int
        let totalSize: Int64
        let latestModified: Date?
    }

    private struct ScanCache: Sendable {
        let signature: ScanSignature
        let directoryModDate: Date?
        let files: [FileItem]
        let timestamp: Date
    }

    private var scanCache: [String: ScanCache] = [:]
    private var lastAnalysisSignature: [String: ScanSignature] = [:]
    private let scanCacheTTL: TimeInterval = 30
    private let maxAffectedFilesPerOpportunity = 250
    
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

    /// Retrieve the directory modification date for quick change detection
    public func directoryModDate(for path: String) -> Date? {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let date = attrs[.modificationDate] as? Date {
            return date
        }
        return nil
    }

    /// Return cached files if the directory has not changed recently
    public func cachedFilesIfFresh(path: String, directoryModDate: Date?) -> [FileItem]? {
        guard let cache = scanCache[path] else { return nil }

        if let directoryModDate,
           let cachedModDate = cache.directoryModDate,
           directoryModDate > cachedModDate {
            return nil
        }

        if Date().timeIntervalSince(cache.timestamp) > scanCacheTTL {
            return nil
        }

        return cache.files
    }

    /// Update scan cache with the latest files and signature
    public func updateScanCache(path: String, directoryModDate: Date?, files: [FileItem]) {
        let signature = scanSignature(for: files)
        scanCache[path] = ScanCache(
            signature: signature,
            directoryModDate: directoryModDate,
            files: files,
            timestamp: Date()
        )
    }

    /// Determine if analysis is already up to date for the current signature
    public func isAnalysisUpToDate(path: String, files: [FileItem]) -> Bool {
        let signature = scanSignature(for: files)
        return lastAnalysisSignature[path] == signature
    }

    /// Mark analysis as complete for the given files
    public func markAnalysisComplete(path: String, files: [FileItem]) {
        lastAnalysisSignature[path] = scanSignature(for: files)
        lastAnalysisDate = Date()
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
        }

        // Remove old opportunities for this path
        opportunities.removeAll { $0.directoryPath == path }
        var newOpportunities: [CleanupOpportunity] = []

        let ignoredPrefixes = Set(config.ignoredPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })

        let filesToAnalyze = files.filter { file in
            !ignoredPrefixes.contains { file.path.hasPrefix($0) }
        }

        // --- Smart Detection Helpers ---
        var projectDirCache: [String: Bool] = [:]
        
        func isFileInProject(_ file: FileItem) -> Bool {
             let fileURL = URL(fileURLWithPath: file.path)
             let dirPath = fileURL.deletingLastPathComponent().path
             
             // Check cache first
             if let cached = projectDirCache[dirPath] { return cached }
             
             // Traverse up to root to find project markers
             var current = fileURL.deletingLastPathComponent()
             let rootURL = URL(fileURLWithPath: path)
             var foundProject = false
             var visitedPaths: [String] = []
             
             // Safety check for loop
             while current.path.count >= rootURL.path.count {
                 visitedPaths.append(current.path)

                 // Check cache for this level
                 if let cached = projectDirCache[current.path] {
                     foundProject = cached
                     break
                 }
                 
                 let gitPath = current.appendingPathComponent(".git").path
                 let pkgPath = current.appendingPathComponent("package.json").path
                 let swiftPath = current.appendingPathComponent("Package.swift").path
                 
                 if FileManager.default.fileExists(atPath: gitPath) ||
                    FileManager.default.fileExists(atPath: pkgPath) ||
                    FileManager.default.fileExists(atPath: swiftPath) {
                     foundProject = true
                     break
                 }
                 
                 // Check for .xcodeproj or .xcworkspace by scanning children
                 do {
                     let contents = try FileManager.default.contentsOfDirectory(atPath: current.path)
                     for item in contents {
                         if item.hasSuffix(".xcodeproj") || item.hasSuffix(".xcworkspace") {
                             foundProject = true
                             break
                         }
                     }
                     if foundProject { break }
                 } catch {
                     // If we can't read directory, continue
                 }
                 
                 if current.path == rootURL.path { break }
                 current = current.deletingLastPathComponent()
             }
             
             for visitedPath in visitedPaths {
                 projectDirCache[visitedPath] = foundProject
             }
             return foundProject
        }
        
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        func affectedFilesSample<T>(
            from items: [T],
            transform: (T) -> CleanupOpportunity.AffectedFile
        ) -> [CleanupOpportunity.AffectedFile] {
            items.prefix(maxAffectedFilesPerOpportunity).map(transform)
        }

        func yieldIfNeeded(_ index: Int) async -> Bool {
            if Task.isCancelled { return false }
            if index % 500 == 0 {
                await Task.yield()
            }
            return !Task.isCancelled
        }
        
        // --- Checks ---

        // 1. Screenshot Clutter
        if config.enabledChecks.contains(.screenshotClutter) {
            var screenshots: [FileItem] = []
            for (index, file) in filesToAnalyze.enumerated() {
                guard await yieldIfNeeded(index) else { return }
                if !isFileInProject(file) && isScreenshot(file) {
                    screenshots.append(file)
                }
            }
            if screenshots.count >= config.minScreenshotCount {
                let affected = affectedFilesSample(from: screenshots) { file -> CleanupOpportunity.AffectedFile in
                    let dateStr = file.creationDate.map { dateFormatter.string(from: $0) } ?? "Unknown date"
                    return CleanupOpportunity.AffectedFile(
                        path: file.path,
                        name: file.name,
                        size: file.size,
                        lastAccessed: file.lastAccessDate,
                        reason: "Screenshot created on \(dateStr)"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .screenshotClutter,
                    directoryPath: path,
                    description: "\(screenshots.count) screenshots detected.",
                    estimatedSavings: 0,
                    fileCount: screenshots.count,
                    priority: screenshots.count >= 50 ? .high : .medium,
                    action: .groupScreenshots,
                    affectedFiles: affected,
                    detailedReason: "Screenshots often accumulate on the desktop and downloads folder. Grouping them helps declutter your view.",
                    confidence: 100
                ))
            }
        }

        // 2. Download Clutter (Smart)
        if config.enabledChecks.contains(.downloadClutter) {
            var oldDownloads: [FileItem] = []
            for (index, file) in filesToAnalyze.enumerated() {
                guard await yieldIfNeeded(index) else { return }
                guard !isFileInProject(file) else { continue }
                
                // Use last access if available, otherwise creation
                let relevantDate = file.lastAccessDate ?? file.creationDate
                guard let date = relevantDate else { continue }
                
                let age = now.timeIntervalSince(date)
                if age > config.downloadClutterThreshold {
                    oldDownloads.append(file)
                }
            }
            
            if oldDownloads.count >= config.minDownloadCount {
                let totalSize = oldDownloads.reduce(0) { $0 + $1.size }
                let days = Int(config.downloadClutterThreshold / 86400)
                
                let affected = affectedFilesSample(from: oldDownloads) { file -> CleanupOpportunity.AffectedFile in
                    let date = file.lastAccessDate ?? file.creationDate
                    let dateStr = date.map { dateFormatter.string(from: $0) } ?? "Unknown"
                    return CleanupOpportunity.AffectedFile(
                        path: file.path,
                        name: file.name,
                        size: file.size,
                        lastAccessed: file.lastAccessDate,
                        reason: "Not accessed since \(dateStr)"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .downloadClutter,
                    directoryPath: path,
                    description: "\(oldDownloads.count) unused downloads older than \(days) days.",
                    estimatedSavings: totalSize,
                    fileCount: oldDownloads.count,
                    priority: totalSize > 1_000_000_000 ? .high : .medium,
                    action: .archiveOldDownloads,
                    affectedFiles: affected,
                    detailedReason: "These files have not been opened in over \(days) days. They are safe to archive or delete.",
                    confidence: 90
                ))
            }
        }

        // 3. Large Files (Smart)
        if config.enabledChecks.contains(.largeFiles) {
            var largeFiles: [FileItem] = []
            for (index, file) in filesToAnalyze.enumerated() {
                guard await yieldIfNeeded(index) else { return }
                // Smart check: Skip project files
                if isFileInProject(file) { continue }
                if file.size > config.largeFileSizeThreshold {
                    largeFiles.append(file)
                }
            }
            
            if !largeFiles.isEmpty {
                let totalSize = largeFiles.reduce(0) { $0 + $1.size }
                let sizeStr = ByteCountFormatter.string(fromByteCount: config.largeFileSizeThreshold, countStyle: .file)
                
                let affected = affectedFilesSample(from: largeFiles) { file -> CleanupOpportunity.AffectedFile in
                    let size = ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
                    return CleanupOpportunity.AffectedFile(
                        path: file.path,
                        name: file.name,
                        size: file.size,
                        lastAccessed: file.lastAccessDate,
                        reason: "Large file occupying \(size)"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .largeFiles,
                    directoryPath: path,
                    description: "\(largeFiles.count) large files (>\(sizeStr)) found.",
                    estimatedSavings: totalSize,
                    fileCount: largeFiles.count,
                    priority: largeFiles.count >= 5 ? .high : .low,
                    affectedFiles: affected,
                    detailedReason: "These files are taking up significant space and are not part of an active project.",
                    confidence: 95
                ))
            }
        }

        // 4. Unorganized Files (Root)
        if config.enabledChecks.contains(.unorganizedFiles) {
            var rootFiles: [FileItem] = []
            for (index, file) in filesToAnalyze.enumerated() {
                guard await yieldIfNeeded(index) else { return }
                let relativePath = file.path.replacingOccurrences(of: path + "/", with: "")
                if !relativePath.contains("/") && !file.isDirectory && !file.name.hasPrefix(".") {
                    rootFiles.append(file)
                }
            }
            if rootFiles.count >= config.minUnorganizedCount {
                let affected = affectedFilesSample(from: rootFiles) { file -> CleanupOpportunity.AffectedFile in
                    CleanupOpportunity.AffectedFile(
                        path: file.path,
                        name: file.name,
                        size: file.size,
                        lastAccessed: file.lastAccessDate,
                        reason: "Loose file in root folder"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .unorganizedFiles,
                    directoryPath: path,
                    description: "\(rootFiles.count) unorganized files in root.",
                    estimatedSavings: 0,
                    fileCount: rootFiles.count,
                    priority: rootFiles.count >= 50 ? .critical : .high,
                    action: .organizeRoot,
                    affectedFiles: affected,
                    detailedReason: "Too many files in the root folder makes it hard to find things. Sorty can help organize them.",
                    confidence: 100
                ))
            }
        }

        // 5. Installers
        let installers = filesToAnalyze.filter { ["dmg", "pkg", "iso"].contains($0.extension.lowercased()) }
        if !installers.isEmpty {
            let totalSize = installers.reduce(0) { $0 + $1.size }
            let affected = affectedFilesSample(from: installers) { file -> CleanupOpportunity.AffectedFile in
                CleanupOpportunity.AffectedFile(
                    path: file.path,
                    name: file.name,
                    size: file.size,
                    lastAccessed: file.lastAccessDate,
                    reason: "Installer file"
                )
            }
            
            newOpportunities.append(CleanupOpportunity(
                type: .largeFiles, // Keeping type for compatibility, logic separates them
                directoryPath: path,
                description: "\(installers.count) installer files found.",
                estimatedSavings: totalSize,
                fileCount: installers.count,
                priority: .medium,
                action: .cleanInstallers,
                affectedFiles: affected,
                detailedReason: "Installers are usually not needed after the application is installed.",
                confidence: 95
            ))
        }

        // 6. Temp/Cache
        if config.enabledChecks.contains(.temporaryFiles) || config.enabledChecks.contains(.cacheFiles) {
            var tempFiles: [FileItem] = []
            for (index, file) in filesToAnalyze.enumerated() {
                guard await yieldIfNeeded(index) else { return }
                if isTempOrCacheFile(file) {
                    tempFiles.append(file)
                }
            }
            if !tempFiles.isEmpty {
                let totalSize = tempFiles.reduce(0) { $0 + $1.size }
                let affected = affectedFilesSample(from: tempFiles) { file -> CleanupOpportunity.AffectedFile in
                    CleanupOpportunity.AffectedFile(
                        path: file.path,
                        name: file.name,
                        size: file.size,
                        lastAccessed: file.lastAccessDate,
                        reason: "Temporary/Cache file"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .temporaryFiles,
                    directoryPath: path,
                    description: "\(tempFiles.count) temporary files found.",
                    estimatedSavings: totalSize,
                    fileCount: tempFiles.count,
                    priority: totalSize > 500_000_000 ? .high : .low,
                    affectedFiles: affected,
                    detailedReason: "These are temporary files created by system or apps and can be safely removed.",
                    confidence: 100
                ))
            }
        }

        // 7. Old Files
        if config.enabledChecks.contains(.veryOldFiles) || config.enabledChecks.contains(.oldFiles) {
            var veryOldFiles: [FileItem] = []
            for (index, file) in filesToAnalyze.enumerated() {
                guard await yieldIfNeeded(index) else { return }
                if isFileInProject(file) { continue } // Smart check
                guard let accessDate = file.lastAccessDate ?? file.modificationDate else { continue }
                let age = now.timeIntervalSince(accessDate)
                if age > config.oldFileThreshold {
                    veryOldFiles.append(file)
                }
            }
            if veryOldFiles.count >= config.minOldFileCount {
                let totalSize = veryOldFiles.reduce(0) { $0 + $1.size }
                let years = String(format: "%.1f", config.oldFileThreshold / (365 * 86400))
                
                let affected = affectedFilesSample(from: veryOldFiles) { file -> CleanupOpportunity.AffectedFile in
                    let dateStr = (file.lastAccessDate ?? file.modificationDate).map { dateFormatter.string(from: $0) } ?? "Unknown"
                    return CleanupOpportunity.AffectedFile(
                        path: file.path,
                        name: file.name,
                        size: file.size,
                        lastAccessed: file.lastAccessDate,
                        reason: "Not accessed since \(dateStr)"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .veryOldFiles,
                    directoryPath: path,
                    description: "\(veryOldFiles.count) files inactive for >\(years) years.",
                    estimatedSavings: totalSize,
                    fileCount: veryOldFiles.count,
                    priority: totalSize > 1_000_000_000 ? .high : .medium,
                    action: .archiveVeryOldFiles,
                    affectedFiles: affected,
                    detailedReason: "These files haven't been touched in a long time. Consider archiving them.",
                    confidence: 85
                ))
            }
        }

        // 8. Empty Folders
        if config.enabledChecks.contains(.emptyFolders) {
            let emptyFolders = await findEmptyFolders(at: path)
            if !emptyFolders.isEmpty {
                let affected = affectedFilesSample(from: emptyFolders) { folderPath -> CleanupOpportunity.AffectedFile in
                    CleanupOpportunity.AffectedFile(
                        path: folderPath,
                        name: URL(fileURLWithPath: folderPath).lastPathComponent,
                        size: 0,
                        lastAccessed: nil,
                        reason: "Empty folder"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .emptyFolders,
                    directoryPath: path,
                    description: "\(emptyFolders.count) empty folders.",
                    estimatedSavings: 0,
                    fileCount: emptyFolders.count,
                    priority: emptyFolders.count >= 20 ? .medium : .low,
                    action: .pruneEmptyFolders,
                    affectedFiles: affected,
                    detailedReason: "Empty folders create visual clutter.",
                    confidence: 100
                ))
            }
        }

        // 9. Broken Symlinks
        if config.enabledChecks.contains(.brokenSymlinks) {
            let brokenSymlinks = await findBrokenSymlinks(at: path)
            if !brokenSymlinks.isEmpty {
                let affected = affectedFilesSample(from: brokenSymlinks) { linkPath -> CleanupOpportunity.AffectedFile in
                    CleanupOpportunity.AffectedFile(
                        path: linkPath,
                        name: URL(fileURLWithPath: linkPath).lastPathComponent,
                        size: 0,
                        lastAccessed: nil,
                        reason: "Points to non-existent location"
                    )
                }
                
                newOpportunities.append(CleanupOpportunity(
                    type: .brokenSymlinks,
                    directoryPath: path,
                    description: "\(brokenSymlinks.count) broken symbolic links.",
                    estimatedSavings: 0,
                    fileCount: brokenSymlinks.count,
                    priority: brokenSymlinks.count >= 5 ? .medium : .low,
                    action: .removeBrokenSymlinks,
                    affectedFiles: affected,
                    detailedReason: "These shortcuts point to files that no longer exist.",
                    confidence: 100
                ))
            }
        }

        opportunities.append(contentsOf: newOpportunities)
        lastAnalysisDate = Date()
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
            
            source.setEventHandler { @Sendable [weak self] in
                // Dispatch to MainActor since handleFileEvent accesses @MainActor isolated state
                Task { @MainActor [weak self] in
                    self?.handleFileEvent()
                }
            }
            
            // Capture fd by value in a @Sendable closure to avoid @MainActor isolation
            // being inherited from the enclosing context (which would crash on the background queue)
            let capturedFd = fd
            source.setCancelHandler { @Sendable in
                if capturedFd >= 0 {
                    close(capturedFd)
                }
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
        debounceTask?.cancel()
        debounceTask = nil
        
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
    
    private var debounceTask: Task<Void, Never>?
    
    private func handleFileEvent() {
        // Debounce logic - cancel any pending task
        debounceTask?.cancel()
        
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
            guard !Task.isCancelled else { return }
            DebugLogger.log("WorkspaceHealth: File system change detected")
            self?.fileChangeDetected = Date()
        }
    }

    /// Undo the last cleanup action
    public func undoLastAction() async throws {
        let fileManager = FileManager.default
        
        // Find the first undoable action from the end
        while let lastAction = cleanupHistory.last {
            // Skip .delete actions as they cannot be undone
            if lastAction.type == .delete {
                cleanupHistory.removeLast()
                saveData()
                continue
            }
            
            var allSucceeded = true
            var lastError: Error?
            
            switch lastAction.type {
            case .trash:
                // "Trash" actions in this context were moves to Trash
                // To undo, we need to move them back from Trash to original paths.
                if let destinations = lastAction.destinationPaths {
                    // Use zip to safely iterate over both arrays and prevent index-out-of-bounds
                    for (trashPath, originalPath) in zip(destinations, lastAction.affectedFilePaths) {
                        let trashURL = URL(fileURLWithPath: trashPath)
                        let originalURL = URL(fileURLWithPath: originalPath)
                        
                        if fileManager.fileExists(atPath: trashPath) {
                            do {
                                try? fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                                try fileManager.moveItem(at: trashURL, to: originalURL)
                            } catch {
                                allSucceeded = false
                                lastError = error
                            }
                        } else {
                            allSucceeded = false
                        }
                    }
                }
                
            case .move:
                // Reverse the move
                if let destinations = lastAction.destinationPaths {
                    for (destPath, originalPath) in zip(destinations, lastAction.affectedFilePaths) {
                        let destURL = URL(fileURLWithPath: destPath)
                        let originalURL = URL(fileURLWithPath: originalPath)
                        
                        if fileManager.fileExists(atPath: destPath) {
                            do {
                                try? fileManager.createDirectory(at: originalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                                try fileManager.moveItem(at: destURL, to: originalURL)
                            } catch {
                                allSucceeded = false
                                lastError = error
                            }
                        } else {
                            allSucceeded = false
                        }
                    }
                }
                
            case .delete:
                // Already handled above
                break
            }
            
            if allSucceeded {
                cleanupHistory.removeLast()
                saveData()
                return
            } else {
                throw lastError ?? NSError(domain: "Sorty", code: 500, userInfo: [NSLocalizedDescriptionKey: "Partial success: some files could not be restored."])
            }
        }
        
        // No undoable entries found
        throw NSError(domain: "Sorty", code: 404, userInfo: [NSLocalizedDescriptionKey: "No undoable cleanup actions found."])
    }

    /// Perform a quick action for an opportunity
    public func performAction(_ action: CleanupOpportunity.QuickAction, for opportunity: CleanupOpportunity, selectedFiles: [CleanupOpportunity.AffectedFile]? = nil) async throws {
        let path = opportunity.directoryPath
        
        // If selectedFiles provided, use them. Otherwise default to all/auto logic.
        // For now, we update the helpers to take the list if available.
        
        switch action {
        case .archiveOldDownloads:
            try await archiveOldDownloads(at: path, specificFiles: selectedFiles)
        case .groupScreenshots:
            try await groupScreenshots(at: path, specificFiles: selectedFiles)
        case .cleanInstallers:
            try await cleanInstallers(at: path, specificFiles: selectedFiles)
        case .pruneEmptyFolders:
            try await pruneEmptyFoldersRecursively(at: path, specificFiles: selectedFiles)
        case .removeBrokenSymlinks:
            try await removeBrokenSymlinks(at: path, specificFiles: selectedFiles)
        case .organizeRoot:
            // Handled by UI routing or AI agent
            break
        case .archiveVeryOldFiles:
            try await archiveVeryOldFiles(at: path, specificFiles: selectedFiles)
        }
        
        dismissOpportunity(opportunity)
    }

    // MARK: - Derived Properties

    private func refreshDerivedHealthSummary() {
        let active = opportunities.filter { !$0.isDismissed }.sorted { $0.priority > $1.priority }
        let totalSavings = active.reduce(0) { $0 + $1.estimatedSavings }

        activeOpportunities = active
        unreadInsights = insights.filter { !$0.isRead }.sorted { $0.createdAt > $1.createdAt }
        totalPotentialSavings = totalSavings
        formattedTotalSavings = ByteCountFormatter.string(fromByteCount: totalSavings, countStyle: .file)
    }

    public func sortedActiveOpportunities(for path: String?) -> [CleanupOpportunity] {
        let filtered = activeOpportunities.filter { opportunity in
            guard let path else { return true }
            return opportunity.directoryPath == path
        }

        return filtered.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            if $0.estimatedSavings != $1.estimatedSavings { return $0.estimatedSavings > $1.estimatedSavings }
            if $0.fileCount != $1.fileCount { return $0.fileCount > $1.fileCount }
            return $0.createdAt > $1.createdAt
        }
    }

    public func topActionableOpportunities(for path: String?, limit: Int = 3) -> [CleanupOpportunity] {
        sortedActiveOpportunities(for: path)
            .filter { $0.action != nil }
            .prefix(limit)
            .map { $0 }
    }

    /// Calculate overall health score (0-100)
    /// 100 = Perfect
    public var healthScore: Double {
        var score = 100.0

        let totalImpact = activeOpportunities.reduce(0.0) { $0 + opportunityImpact($1) }
        score -= min(totalImpact, 45)

        for (path, _) in snapshots {
            if let growth = getGrowth(for: path, period: .week) {
                switch growth.growthRate {
                case .rapid: score -= 6.0
                case .moderate: score -= 3.0
                case .slow, .stable: break
                }
            }
        }

        return max(0, min(100, score))
    }

    public func healthScore(for path: String) -> Int {
        var score = 100.0

        if let snapshot = snapshots[path]?.last {
            let unorganizedRatio = Double(snapshot.unorganizedCount) / max(Double(snapshot.totalFiles), 1)
            score -= unorganizedRatio * 20

            if snapshot.totalFiles > 2500 {
                score -= 8
            }

            let avgDays = snapshot.averageFileAge / 86400
            if avgDays > 365 { score -= 10 }
            if avgDays > 730 { score -= 6 }
        }

        let pathOpportunities = activeOpportunities.filter { $0.directoryPath == path }
        let impact = pathOpportunities.reduce(0.0) { $0 + opportunityImpact($1) }
        score -= min(impact, 40)

        if let growth = getGrowth(for: path, period: .week) {
            switch growth.growthRate {
            case .rapid: score -= 6
            case .moderate: score -= 3
            case .slow, .stable: break
            }
        }

        return Int(max(0, min(100, score)))
    }

    public enum HealthScoreBand: String, Sendable {
        case healthy
        case caution
        case critical

        public var color: Color {
            switch self {
            case .healthy: return .green
            case .caution: return .yellow
            case .critical: return .red
            }
        }
    }

    public func healthScoreBand(for score: Int) -> HealthScoreBand {
        switch score {
        case 80...100:
            return .healthy
        case 60..<80:
            return .caution
        default:
            return .critical
        }
    }
    
    public var healthStatus: (title: String, color: Color) {
        let score = Int(healthScore.rounded())
        let band = healthScoreBand(for: score)
        let title = score >= 80 ? "Excellent" : (score >= 60 ? "Good" : "Needs Attention")
        return (title, band.color)
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

    private func scanSignature(for files: [FileItem]) -> ScanSignature {
        let totalSize = files.reduce(0) { $0 + $1.size }
        let latestModified = files.compactMap { $0.modificationDate ?? $0.lastAccessDate }.max()
        return ScanSignature(fileCount: files.count, totalSize: totalSize, latestModified: latestModified)
    }

    private func opportunityImpact(_ opportunity: CleanupOpportunity) -> Double {
        let base: Double
        switch opportunity.priority {
        case .critical: base = 7
        case .high: base = 4.5
        case .medium: base = 2.5
        case .low: base = 1
        }

        let confidenceMultiplier = Double(max(40, opportunity.confidence)) / 100
        return base * confidenceMultiplier
    }

    private func sendNotification(_ insight: HealthInsight) async {
        // Avoid running in xctest tool environment which crashes UNUserNotificationCenter
        guard Bundle.main.bundleIdentifier != "com.apple.dt.xctest.tool" else { return }
        
        let center = UNUserNotificationCenter.current()

        // Request authorization if needed
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }

            // Create all notification content on MainActor, then send
            let content = UNMutableNotificationContent()
            content.title = "Sorty"
            content.body = insight.message
            content.sound = .default
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0

            if let prompt = insight.actionPrompt {
                content.subtitle = prompt
            }

            // Attach app icon to ensure it displays in the notification
            if let iconAttachment = NotificationManager.createAppIconAttachment() {
                content.attachments = [iconAttachment]
            }

            let request = UNNotificationRequest(
                identifier: insight.id.uuidString,
                content: content,
                trigger: nil // Deliver immediately
            )

            // Send the notification request - explicitly on MainActor to satisfy Swift 6 concurrency
            await MainActor.run {
                Task {
                    try? await center.add(request)
                }
            }
        } catch {
            DebugLogger.log("Failed to send notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Action Helpers
    
    private func archiveOldDownloads(at path: String, specificFiles: [CleanupOpportunity.AffectedFile]? = nil) async throws {
        let fileManager = FileManager.default
        let archiveFolder = URL(fileURLWithPath: path).appendingPathComponent("Archive")
        
        // Create Archive folder if needed
        if !fileManager.fileExists(atPath: archiveFolder.path) {
            try fileManager.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        }
        
        let filesToProcess: [URL]
        
        if let specificFiles = specificFiles {
            filesToProcess = specificFiles.map { URL(fileURLWithPath: $0.path) }
        } else {
            let allFiles = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
            filesToProcess = allFiles.filter { file in
                guard !file.hasDirectoryPath else { return false }
                if let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   Date().timeIntervalSince(date) > config.downloadClutterThreshold {
                    return true
                }
                return false
            }
        }
        
        var originalPaths: [String] = []
        var destPaths: [String] = []
        
        for file in filesToProcess {
             // Re-verify existence just in case
             guard fileManager.fileExists(atPath: file.path) else { continue }
             
             let date = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
             let dateFormatter = DateFormatter()
             dateFormatter.dateFormat = "yyyy-MM"
             let dateFolder = archiveFolder.appendingPathComponent(dateFormatter.string(from: date))
             
             if !fileManager.fileExists(atPath: dateFolder.path) {
                 try fileManager.createDirectory(at: dateFolder, withIntermediateDirectories: true)
             }
             
             var destination = dateFolder.appendingPathComponent(file.lastPathComponent)
             
             if fileManager.fileExists(atPath: destination.path) {
                 let fileName = file.deletingPathExtension().lastPathComponent
                 let fileExt = file.pathExtension
                 let timestamp = Date().filenameTimestamp
                 let uniqueName = "\(fileName)_\(timestamp).\(fileExt)"
                 destination = dateFolder.appendingPathComponent(uniqueName)
             }
             
             try fileManager.moveItem(at: file, to: destination)
             originalPaths.append(file.path)
             destPaths.append(destination.path)
        }
        
        // Record history
        if !originalPaths.isEmpty {
            let item = CleanupHistoryItem(
                actionName: "Archive Old Downloads",
                affectedFilePaths: originalPaths,
                type: .move,
                destinationPaths: destPaths
            )
            cleanupHistory.append(item)
            saveData()
        }
    }
    
    private func groupScreenshots(at path: String, specificFiles: [CleanupOpportunity.AffectedFile]? = nil) async throws {
        let fileManager = FileManager.default
        let screenshotsFolder = URL(fileURLWithPath: path).appendingPathComponent("Screenshots")
        
        let filesToProcess: [URL]
        
        if let specificFiles = specificFiles {
            filesToProcess = specificFiles.map { URL(fileURLWithPath: $0.path) }
        } else {
             // Fallback to old scanning logic if no list provided (e.g. from background task)
             let allFiles = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
             filesToProcess = allFiles.filter { file in
                 let filename = file.lastPathComponent.lowercased()
                 return ["screenshot", "screen shot", "capture"].contains { filename.contains($0) }
             }
        }
        
        var originalPaths: [String] = []
        var destPaths: [String] = []
        
        for file in filesToProcess {
            if !fileManager.fileExists(atPath: screenshotsFolder.path) {
                try fileManager.createDirectory(at: screenshotsFolder, withIntermediateDirectories: true)
            }
            
            var destination: URL
            
            if let date = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM"
                let dateFolder = screenshotsFolder.appendingPathComponent(dateFormatter.string(from: date))
                
                if !fileManager.fileExists(atPath: dateFolder.path) {
                    try fileManager.createDirectory(at: dateFolder, withIntermediateDirectories: true)
                }
                
                destination = dateFolder.appendingPathComponent(file.lastPathComponent)
            } else {
                destination = screenshotsFolder.appendingPathComponent(file.lastPathComponent)
            }
            
            try fileManager.moveItem(at: file, to: destination)
            originalPaths.append(file.path)
            destPaths.append(destination.path)
        }
        
        if !originalPaths.isEmpty {
            let item = CleanupHistoryItem(
                actionName: "Group Screenshots",
                affectedFilePaths: originalPaths,
                type: .move,
                destinationPaths: destPaths
            )
            cleanupHistory.append(item)
            saveData()
        }
    }
    
    private func cleanInstallers(at path: String, specificFiles: [CleanupOpportunity.AffectedFile]? = nil) async throws {
        let fileManager = FileManager.default
        let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first!
        
        let filesToProcess: [URL]
        
        if let specificFiles = specificFiles {
             filesToProcess = specificFiles.map { URL(fileURLWithPath: $0.path) }
        } else {
             let allFiles = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
             filesToProcess = allFiles.filter { ["dmg", "pkg", "iso"].contains($0.pathExtension.lowercased()) }
        }
        
        var originalPaths: [String] = []
        var destPaths: [String] = []
        
        for file in filesToProcess {
             var trashedURL: NSURL?
             try fileManager.trashItem(at: file, resultingItemURL: &trashedURL)
             
             originalPaths.append(file.path)
             if let finalURL = trashedURL as? URL {
                 destPaths.append(finalURL.path)
             } else {
                 // Fallback in case resultingItemURL isn't populated (rare)
                 destPaths.append(trashURL.appendingPathComponent(file.lastPathComponent).path)
             }
        }
        
        if !originalPaths.isEmpty {
            let item = CleanupHistoryItem(
                actionName: "Clean Installers",
                affectedFilePaths: originalPaths,
                type: .trash,
                destinationPaths: destPaths
            )
            cleanupHistory.append(item)
            saveData()
        }
    }
    
    private func pruneEmptyFoldersRecursively(at path: String, specificFiles: [CleanupOpportunity.AffectedFile]? = nil) async throws {
        let fileManager = FileManager.default
        let disposableFiles: Set<String> = [".DS_Store", "Thumbs.db", "desktop.ini", ".localized"]
        var removedFolders: [String] = []
        var errors: [Error] = []
        
        if let specificFiles = specificFiles {
            // Just delete the specifically selected folders
            for file in specificFiles {
                do {
                    // First, remove any disposable files inside
                    if let contents = try? fileManager.contentsOfDirectory(atPath: file.path) {
                        for item in contents {
                            if disposableFiles.contains(item) {
                                let itemPath = (file.path as NSString).appendingPathComponent(item)
                                try? fileManager.removeItem(atPath: itemPath)
                            }
                        }
                    }
                    try fileManager.removeItem(atPath: file.path)
                    removedFolders.append(file.path)
                } catch {
                    errors.append(error)
                    DebugLogger.log("Failed to remove folder: \(file.path), error: \(error.localizedDescription)")
                }
            }
        } else {
            // Find all empty folders (already identifies nested empties correctly)
            let emptyFolders = await findEmptyFolders(at: path)
            
            // Sort by depth (deepest first) to ensure child folders are removed before parents
            let sortedFolders = emptyFolders.sorted { path1, path2 in
                path1.components(separatedBy: "/").count > path2.components(separatedBy: "/").count
            }
            
            // Remove all empty folders in one pass
            for folderPath in sortedFolders {
                do {
                    // First, remove any disposable files inside
                    let contents = try fileManager.contentsOfDirectory(atPath: folderPath)
                    for item in contents {
                        if disposableFiles.contains(item) {
                            let itemPath = (folderPath as NSString).appendingPathComponent(item)
                            try? fileManager.removeItem(atPath: itemPath)
                        }
                    }
                    
                    // Now try to remove the folder itself
                    try fileManager.removeItem(atPath: folderPath)
                    removedFolders.append(folderPath)
                } catch {
                    errors.append(error)
                    DebugLogger.log("Failed to remove empty folder at \(folderPath): \(error.localizedDescription)")
                }
            }
        }
        
        if !removedFolders.isEmpty {
            let item = CleanupHistoryItem(
                actionName: "Prune Empty Folders",
                affectedFilePaths: removedFolders,
                type: .delete
            )
            cleanupHistory.append(item)
            saveData()
            DebugLogger.log("Pruned \(removedFolders.count) empty folders")
        }
        
        // Propagate error if significantly failed but still record partial success
        if removedFolders.isEmpty && !errors.isEmpty {
            throw errors.first!
        }
    }
    
    private func removeBrokenSymlinks(at path: String, specificFiles: [CleanupOpportunity.AffectedFile]? = nil) async throws {
        let fileManager = FileManager.default
        var removedLinks: [String] = []
        
        if let specificFiles = specificFiles {
            for file in specificFiles {
                try fileManager.removeItem(atPath: file.path)
                removedLinks.append(file.path)
            }
        } else {
            let brokenLinks = await findBrokenSymlinks(at: path)
            for linkPath in brokenLinks {
                try fileManager.removeItem(atPath: linkPath)
                removedLinks.append(linkPath)
            }
        }
        
        if !removedLinks.isEmpty {
            let item = CleanupHistoryItem(
                actionName: "Remove Broken Symlinks",
                affectedFilePaths: removedLinks,
                type: .delete
            )
            cleanupHistory.append(item)
            saveData()
        }
    }
    
    private func archiveVeryOldFiles(at path: String, specificFiles: [CleanupOpportunity.AffectedFile]? = nil) async throws {
        let fileManager = FileManager.default
        let archiveFolder = URL(fileURLWithPath: path).appendingPathComponent("Old Files Archive")
        
        // Create Archive folder if needed
        if !fileManager.fileExists(atPath: archiveFolder.path) {
            try fileManager.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        }
        
        let filesToProcess: [URL]
        
        if let specificFiles = specificFiles {
            filesToProcess = specificFiles.map { URL(fileURLWithPath: $0.path) }
        } else {
            // Fallback: find all very old files
            let allFiles = try fileManager.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.contentModificationDateKey, .contentAccessDateKey], options: [.skipsHiddenFiles])
            let now = Date()
            filesToProcess = allFiles.filter { file in
                guard !file.hasDirectoryPath else { return false }
                let accessDate = (try? file.resourceValues(forKeys: [.contentAccessDateKey]).contentAccessDate) ??
                                 (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                guard let date = accessDate else { return false }
                return now.timeIntervalSince(date) > config.oldFileThreshold
            }
        }
        
        var originalPaths: [String] = []
        var destPaths: [String] = []
        
        for file in filesToProcess {
            guard fileManager.fileExists(atPath: file.path) else { continue }
            
            // Organize by year of last modification
            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy"
            let yearFolder = archiveFolder.appendingPathComponent(dateFormatter.string(from: modDate))
            
            if !fileManager.fileExists(atPath: yearFolder.path) {
                try fileManager.createDirectory(at: yearFolder, withIntermediateDirectories: true)
            }
            
            var destination = yearFolder.appendingPathComponent(file.lastPathComponent)
            
            if fileManager.fileExists(atPath: destination.path) {
                let fileName = file.deletingPathExtension().lastPathComponent
                let fileExt = file.pathExtension
                let timestamp = Date().filenameTimestamp
                let uniqueName = "\(fileName)_\(timestamp).\(fileExt)"
                destination = yearFolder.appendingPathComponent(uniqueName)
            }
            
            try fileManager.moveItem(at: file, to: destination)
            originalPaths.append(file.path)
            destPaths.append(destination.path)
        }
        
        if !originalPaths.isEmpty {
            let item = CleanupHistoryItem(
                actionName: "Archive Very Old Files",
                affectedFilePaths: originalPaths,
                type: .move,
                destinationPaths: destPaths
            )
            cleanupHistory.append(item)
            saveData()
        }
    }
    
    private func archiveVeryOldFiles(at path: String) async throws {
        let fileManager = FileManager.default
        
        // Get the user's home directory and create Archives folder in Documents
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let documentsFolder = homeDirectory.appendingPathComponent("Documents")
        let archiveFolder = documentsFolder.appendingPathComponent("Archives")
        
        // Create Archives folder if it doesn't exist
        if !fileManager.fileExists(atPath: archiveFolder.path) {
            try fileManager.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
        }
        
        // Get all files in the directory
        let files = try fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: path), 
            includingPropertiesForKeys: [.contentAccessDateKey, .contentModificationDateKey], 
            options: [.skipsHiddenFiles]
        )
        
        var movedCount = 0
        
        for file in files {
            guard !file.hasDirectoryPath else { continue }
            
            // Check if file is "very old" using the same criteria as analysis
            let resourceValues = try? file.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
            let accessDate = resourceValues?.contentAccessDate ?? resourceValues?.contentModificationDate
            
            if let lastAccess = accessDate,
               Date().timeIntervalSince(lastAccess) > config.oldFileThreshold {
                
                var destination = archiveFolder.appendingPathComponent(file.lastPathComponent)
                
                // Handle filename conflicts by appending a timestamp
                if fileManager.fileExists(atPath: destination.path) {
                    let fileName = file.deletingPathExtension().lastPathComponent
                    let ext = file.pathExtension
                    let timestamp = Date().filenameTimestamp
                    // Add extension with dot only if file has an extension
                    let uniqueName = ext.isEmpty ? "\(fileName)_\(timestamp)" : "\(fileName)_\(timestamp).\(ext)"
                    destination = archiveFolder.appendingPathComponent(uniqueName)
                }
                
                try fileManager.moveItem(at: file, to: destination)
                movedCount += 1
            }
        }
        
        DebugLogger.log("Archived \(movedCount) very old files to \(archiveFolder.path)")
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

    /// Find empty folders in a directory, including folders that only contain other empty folders
    private func findEmptyFolders(at path: String) async -> [String] {
        let fileManager = FileManager.default
        var allDirectories: [(path: String, depth: Int)] = []
        
        // Disposable files that should be considered as "empty" content
        let disposableFiles: Set<String> = [".DS_Store", "Thumbs.db", "desktop.ini", ".localized"]

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [] // Don't skip hidden files - we need to check all content to identify truly empty folders
        ) else {
            return []
        }

        // First pass: collect all directories with their depth
        while let url = enumerator.nextObject() as? URL {
            if Task.isCancelled { return [] }

            do {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    let depth = url.pathComponents.count
                    allDirectories.append((path: url.path, depth: depth))
                }
            } catch {
                continue
            }
        }

        // Sort by depth (deepest first) to process leaf directories before their parents
        allDirectories.sort { $0.depth > $1.depth }

        // Second pass: determine which directories are truly empty
        var emptyFolders = Set<String>()
        for (index, directory) in allDirectories.enumerated() {
            if Task.isCancelled { return [] }
            if index % 500 == 0 {
                await Task.yield()
            }

            do {
                let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
                
                // Filter out disposable files - treat them as if they don't exist
                let significantContents = contents.filter { !disposableFiles.contains($0) }
                
                // Check if all significant contents are directories that are already marked as empty
                var allContentsAreEmpty = true
                for item in significantContents {
                    let itemPath = (directory.path as NSString).appendingPathComponent(item)
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: itemPath, isDirectory: &isDirectory) {
                        if isDirectory.boolValue {
                            // If it's a directory but not in our empty set, then this parent is not empty
                            if !emptyFolders.contains(itemPath) {
                                allContentsAreEmpty = false
                                break
                            }
                        } else {
                            // If it's a file, then this directory is not empty
                            allContentsAreEmpty = false
                            break
                        }
                    }
                }
                
                if significantContents.isEmpty || allContentsAreEmpty {
                    emptyFolders.insert(directory.path)
                }
            } catch {
                continue
            }
        }

        return Array(emptyFolders)
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
            if Task.isCancelled { return [] }

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
        // Load history
        cleanupHistory = historyStore.load()
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
        
        historyStore.save(cleanupHistory)
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

/// Manages file-based persistence for cleanup history
class CleanupHistoryStore {
    private let fileManager = FileManager.default
    private let maxHistoryItems = 100
    
    private var historyFileURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("Sorty/Data", isDirectory: true)
        
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        return directory.appendingPathComponent("cleanup_history.json")
    }
    
    func save(_ history: [CleanupHistoryItem]) {
        do {
            // Trim history if needed
            let itemsToSave: [CleanupHistoryItem]
            if history.count > maxHistoryItems {
                itemsToSave = Array(history.suffix(maxHistoryItems))
            } else {
                itemsToSave = history
            }
            
            let data = try JSONEncoder().encode(itemsToSave)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            DebugLogger.log("Failed to save cleanup history: \(error.localizedDescription)")
        }
    }
    
    func load() -> [CleanupHistoryItem] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else { return [] }
        
        do {
            let data = try Data(contentsOf: historyFileURL)
            return try JSONDecoder().decode([CleanupHistoryItem].self, from: data)
        } catch {
            DebugLogger.log("Failed to load cleanup history: \(error.localizedDescription)")
            return []
        }
    }
}

public extension WorkspaceHealthManager {
    nonisolated static func scanFiles(at url: URL, ignoredPaths: [String]) throws -> [FileItem] {
        var files: [FileItem] = []
        let fileManager = FileManager.default

        let ignoredPrefixes = Set(ignoredPaths.map {
            URL(fileURLWithPath: $0).standardizedFileURL.path
        })

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentAccessDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw WorkspaceHealthScanError.unreadableDirectory(url.path)
        }

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()

            let standardizedPath = fileURL.standardizedFileURL.path
            if ignoredPrefixes.contains(where: { standardizedPath.hasPrefix($0) }) {
                enumerator.skipDescendants()
                continue
            }

            autoreleasepool {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .contentAccessDateKey, .isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    return
                }

                let name = fileURL.deletingPathExtension().lastPathComponent
                let item = FileItem(
                    path: fileURL.path,
                    name: name,
                    extension: fileURL.pathExtension,
                    size: Int64(resourceValues?.fileSize ?? 0),
                    isDirectory: false,
                    creationDate: resourceValues?.creationDate,
                    modificationDate: resourceValues?.contentModificationDate,
                    lastAccessDate: resourceValues?.contentAccessDate
                )

                files.append(item)
            }
        }

        return files
    }
}

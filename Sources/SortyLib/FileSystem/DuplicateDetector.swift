//
//  DuplicateDetector.swift
//  Sorty
//
//  Detects duplicate files using SHA-256 hashing
//

import Foundation
import CryptoKit
import Combine

/// Group of files with identical content
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let hash: String
    public let files: [FileItem]
    public let totalSize: Int64
    public let potentialSavings: Int64 // Size that could be recovered by deleting duplicates
    
    public init(hash: String, files: [FileItem]) {
        self.id = UUID()
        self.hash = hash
        self.files = files
        self.totalSize = files.reduce(0) { $0 + $1.size }
        // Savings = total - one copy
        self.potentialSavings = files.dropFirst().reduce(0) { $0 + $1.size }
    }
    
    public var duplicateCount: Int {
        max(0, files.count - 1)
    }
}

/// Unified wrapper for both exact and semantic duplicate groups
public enum UnifiedDuplicateGroup: Identifiable, Hashable {
    case exact(DuplicateGroup)
    case semantic(SemanticDuplicateGroup)
    
    public var id: UUID {
        switch self {
        case .exact(let group): return group.id
        case .semantic(let group): return group.id
        }
    }
    
    public var files: [FileItem] {
        switch self {
        case .exact(let group): return group.files
        case .semantic(let group): return group.files
        }
    }
    
    public var potentialSavings: Int64 {
        switch self {
        case .exact(let group): return group.potentialSavings
        case .semantic(let group): return group.potentialSavings
        }
    }
    
    public var isExact: Bool {
        if case .exact = self { return true }
        return false
    }
    
    public var isSemantic: Bool {
        if case .semantic = self { return true }
        return false
    }
    
    public var displayName: String {
        files.first?.displayName ?? "Unknown File"
    }
    
    public var groupTypeLabel: String {
        switch self {
        case .exact:
            return "Exact Match"
        case .semantic(let group):
            return group.groupType.rawValue
        }
    }
    
    public var similarityPercentage: String? {
        switch self {
        case .exact:
            return "100%"
        case .semantic(let group):
            return group.similarityPercentage
        }
    }
    
    public var similarity: Double {
        switch self {
        case .exact:
            return 1.0
        case .semantic(let group):
            return group.similarity
        }
    }
    
    public var recommendation: SemanticDuplicateGroup.DuplicateRecommendation? {
        switch self {
        case .exact:
            return nil
        case .semantic(let group):
            return group.recommendation
        }
    }
    
    public var recommendedFileId: UUID? {
        switch self {
        case .exact(let group):
            // For exact matches, recommend keeping the oldest (original)
            return group.files.min(by: { ($0.creationDate ?? .distantFuture) < ($1.creationDate ?? .distantFuture) })?.id
        case .semantic(let group):
            switch group.recommendation {
            case .keepHighestResolution(let id), .keepNewest(let id), .keepOldest(let id), .keepLargest(let id), .archiveOlderVersions(let id, _):
                return id
            case .manualReview:
                return nil
            }
        }
    }
    
    /// Confidence level for safe bulk actions
    public var confidenceLevel: ConfidenceLevel {
        switch self {
        case .exact:
            return .high
        case .semantic(let group):
            if group.similarity >= 0.98 {
                return .high
            } else if group.similarity >= 0.90 {
                return .medium
            } else {
                return .low
            }
        }
    }
    
    public enum ConfidenceLevel: String {
        case high = "Safe to Merge"
        case medium = "Review Suggested"
        case low = "Manual Review"
        
        public var color: String {
            switch self {
            case .high: return "green"
            case .medium: return "yellow"
            case .low: return "orange"
            }
        }
    }
    
    // Hashable conformance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: UnifiedDuplicateGroup, rhs: UnifiedDuplicateGroup) -> Bool {
        lhs.id == rhs.id
    }
}

/// Actor for detecting duplicate files based on content hash
public actor DuplicateDetector {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Find all duplicate files in a list of file items
    /// Files must have sha256Hash already computed
    public func findDuplicates(in files: [FileItem]) -> [DuplicateGroup] {
        // Group by hash
        var hashGroups: [String: [FileItem]] = [:]
        
        for file in files {
            guard let hash = file.sha256Hash else { continue }
            if hashGroups[hash] != nil {
                hashGroups[hash]?.append(file)
            } else {
                hashGroups[hash] = [file]
            }
        }
        
        // Filter to only groups with more than one file
        let duplicates = hashGroups
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(hash: $0.key, files: $0.value) }
            .sorted { $0.potentialSavings > $1.potentialSavings }
        
        return duplicates
    }
    
    /// Compute hashes for files that don't have them
    public func computeHashes(for files: inout [FileItem], progressHandler: ((Int, Int) -> Void)? = nil) async {
        for i in 0..<files.count {
            if files[i].sha256Hash == nil {
                files[i].sha256Hash = HashUtility.computeSHA256(for: URL(fileURLWithPath: files[i].path))
            }
            progressHandler?(i + 1, files.count)
            
            // Yield periodically for UI updates
            if i % 10 == 0 {
                await Task.yield()
            }
        }
    }
    
    /// Compute SHA-256 hash for a file (DEPRECATED: Use HashUtility instead)
    private func computeSHA256(for url: URL) -> String? {
        HashUtility.computeSHA256(for: url)
    }
    
    /// Get total potential savings from all duplicate groups
    public func totalPotentialSavings(in groups: [DuplicateGroup]) -> Int64 {
        groups.reduce(0) { $0 + $1.potentialSavings }
    }
    
    /// Get formatted savings string
    public func formattedSavings(in groups: [DuplicateGroup]) -> String {
        let savings = totalPotentialSavings(in: groups)
        return ByteCountFormatter.string(fromByteCount: savings, countStyle: .file)
    }
}

/// State of the duplicate scan process
public enum DuplicateScanState: Equatable {
    case idle
    case preparing
    case scanning(progress: Double)
    case completed(count: Int)
    case failed(String)
}

/// Manager for duplicate detection settings and results
@MainActor
public class DuplicateDetectionManager: ObservableObject {
    @Published public var state: DuplicateScanState = .idle
    @Published public var duplicateGroups: [DuplicateGroup] = []
    @Published public var isScanning = false
    @Published public var scanProgress: Double = 0
    @Published public var lastScanDate: Date?
    @Published public var semanticGroups: [SemanticDuplicateGroup] = []
    @Published public var scanStage: String = ""
    
    private let detector = DuplicateDetector()
    
    public init() {}
    
    public var totalDuplicates: Int {
        duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
    }
    
    public var potentialSavings: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.potentialSavings }
    }
    
    public var formattedSavings: String {
        ByteCountFormatter.string(fromByteCount: potentialSavings, countStyle: .file)
    }
    
    /// All duplicate groups (exact + semantic) unified
    public var allGroups: [UnifiedDuplicateGroup] {
        let exactGroups = duplicateGroups.map { UnifiedDuplicateGroup.exact($0) }
        let semanticGroupsMapped = semanticGroups.map { UnifiedDuplicateGroup.semantic($0) }
        return (exactGroups + semanticGroupsMapped).sorted { $0.potentialSavings > $1.potentialSavings }
    }
    
    /// Total duplicates including semantic matches
    public var totalDuplicatesIncludingSemantic: Int {
        let exactCount = duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
        let semanticCount = semanticGroups.reduce(0) { $0 + max(0, $1.files.count - 1) }
        return exactCount + semanticCount
    }
    
    /// Potential savings including semantic matches
    public var potentialSavingsIncludingSemantic: Int64 {
        let exactSavings = duplicateGroups.reduce(0) { $0 + $1.potentialSavings }
        let semanticSavings = semanticGroups.reduce(0) { $0 + $1.potentialSavings }
        return exactSavings + semanticSavings
    }
    
    /// Formatted savings including semantic matches
    public var formattedSavingsIncludingSemantic: String {
        ByteCountFormatter.string(fromByteCount: potentialSavingsIncludingSemantic, countStyle: .file)
    }
    
    /// Count of exact match groups
    public var exactGroupCount: Int {
        duplicateGroups.count
    }
    
    /// Count of semantic match groups
    public var semanticGroupCount: Int {
        semanticGroups.count
    }
    
    public func scanForDuplicates(files: [FileItem], settings: DuplicateSettings) async {
        state = .scanning(progress: 0)
        isScanning = true
        scanProgress = 0
        scanStage = "Preparing..."
        
        var mutableFiles = files
        let total = files.count
        
        // Step 1: Compute keys for grouping based on comparison method
        scanStage = "Computing hashes..."
        for i in 0..<mutableFiles.count {
            if Task.isCancelled { break }
            
            // Only compute hash if using Exact method or explicitly requested
            if settings.comparisonMethod == .exact && mutableFiles[i].sha256Hash == nil {
                mutableFiles[i].sha256Hash = HashUtility.computeSHA256(for: URL(fileURLWithPath: mutableFiles[i].path))
            }
            
            // Only update progress if not cancelled
            if !Task.isCancelled {
                scanProgress = Double(i + 1) / Double(total)
                state = .scanning(progress: scanProgress)
            }
            
            // Yield periodically for UI updates and to allow cancellation
            if i % 10 == 0 {
                await Task.yield()
            }
        }
        
        if Task.isCancelled {
            isScanning = false
            state = .idle
            scanStage = ""
            return
        }
        
        // Step 2: Grouping Logic based on ComparisonMethod
        scanStage = "Finding duplicates..."
        var groupsMap: [String: [FileItem]] = [:]
        
        for file in mutableFiles {
            let key: String?
            switch settings.comparisonMethod {
            case .exact:
                key = file.sha256Hash
            case .fast:
                key = "\(file.name)_\(file.size)"
            case .metadata:
                let timestamp = file.modificationDate?.timeIntervalSince1970 ?? 0
                key = "\(file.name)_\(file.size)_\(Int(timestamp))"
            }
            
            if let k = key {
                groupsMap[k, default: []].append(file)
            }
        }
        
        // Filter to only groups with more than one file
        let groups = groupsMap
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(hash: $0.key, files: $0.value) }
            .sorted { $0.potentialSavings > $1.potentialSavings }
        
        duplicateGroups = groups
        
        // Step 3: Semantic duplicate detection (if enabled)
        if settings.includeSemanticDuplicates && !Task.isCancelled {
            scanStage = "Semantic analysis..."
            let semanticDetector = SemanticDuplicateDetector()
            semanticGroups = await semanticDetector.findSemanticDuplicates(in: mutableFiles) { current, total, stage in
                Task { @MainActor in
                    self.scanStage = stage
                }
            }
        } else {
            semanticGroups = []
        }
        
        lastScanDate = Date()
        isScanning = false
        scanProgress = 1.0
        scanStage = ""
        state = .completed(count: groups.count)
    }
    
    /// Compute SHA-256 hash for a file (DEPRECATED: Use HashUtility instead)
    private static func computeSHA256(for url: URL) -> String? {
        HashUtility.computeSHA256(for: url)
    }
    
    public func clearResults() {
        duplicateGroups = []
        lastScanDate = nil
        state = .idle
    }
}

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
    private struct HashCacheKey: Hashable {
        let path: String
        let size: Int64
        let modificationDate: Date?
    }

    public struct ExactScanResult: Sendable {
        public let groups: [DuplicateGroup]
        public let candidateCount: Int
        public let hashedCount: Int
        public let cacheHitCount: Int
        public let unreadableCount: Int
    }

    private var hashCache: [HashCacheKey: String] = [:]
    private let maximumConcurrentHashers = 2
    
    public init() {}

    /// Finds byte-identical files while avoiding unnecessary disk reads.
    /// Only files sharing the same size can be exact duplicates, so unique-size
    /// files are discarded before hashing.
    public func findExactDuplicates(
        in files: [FileItem],
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> ExactScanResult {
        let candidates = Dictionary(grouping: files.filter { !$0.isDirectory }, by: \.size)
            .values
            .filter { $0.count > 1 }
            .flatMap { $0 }

        guard !candidates.isEmpty else {
            return ExactScanResult(
                groups: [],
                candidateCount: 0,
                hashedCount: 0,
                cacheHitCount: 0,
                unreadableCount: 0
            )
        }

        let activeKeys = Set(candidates.map(Self.cacheKey(for:)))
        hashCache = hashCache.filter { activeKeys.contains($0.key) }

        var resolvedFiles: [(file: FileItem, hash: String)] = []
        var pendingFiles: [(file: FileItem, key: HashCacheKey)] = []
        var completedCount = 0
        var cacheHitCount = 0
        var hashedCount = 0
        var unreadableCount = 0

        for file in candidates {
            if Task.isCancelled {
                break
            }

            if let existingHash = file.sha256Hash {
                resolvedFiles.append((file, existingHash))
                completedCount += 1
                progressHandler?(completedCount, candidates.count)
                continue
            }

            let key = Self.cacheKey(for: file)
            if let cachedHash = hashCache[key] {
                resolvedFiles.append((file, cachedHash))
                cacheHitCount += 1
                completedCount += 1
                progressHandler?(completedCount, candidates.count)
            } else {
                pendingFiles.append((file, key))
            }
        }

        let concurrencyLimit = min(maximumConcurrentHashers, pendingFiles.count)
        var nextPendingIndex = 0

        await withTaskGroup(of: (FileItem, HashCacheKey, String?).self) { group in
            for _ in 0..<concurrencyLimit {
                let pending = pendingFiles[nextPendingIndex]
                nextPendingIndex += 1
                group.addTask(priority: .utility) {
                    let hash = HashUtility.computeSHA256(for: URL(fileURLWithPath: pending.file.path))
                    return (pending.file, pending.key, hash)
                }
            }

            while let (file, key, hash) = await group.next() {
                if let hash {
                    hashCache[key] = hash
                    resolvedFiles.append((file, hash))
                    hashedCount += 1
                } else {
                    unreadableCount += 1
                }

                completedCount += 1
                progressHandler?(completedCount, candidates.count)

                if nextPendingIndex < pendingFiles.count, !Task.isCancelled {
                    let pending = pendingFiles[nextPendingIndex]
                    nextPendingIndex += 1
                    group.addTask(priority: .utility) {
                        let hash = HashUtility.computeSHA256(for: URL(fileURLWithPath: pending.file.path))
                        return (pending.file, pending.key, hash)
                    }
                }
            }
        }

        var groupsByHash: [String: [FileItem]] = [:]
        for resolvedFile in resolvedFiles {
            groupsByHash[resolvedFile.hash, default: []].append(resolvedFile.file)
        }

        let groups = groupsByHash
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(hash: $0.key, files: $0.value) }
            .sorted { $0.potentialSavings > $1.potentialSavings }

        return ExactScanResult(
            groups: groups,
            candidateCount: candidates.count,
            hashedCount: hashedCount,
            cacheHitCount: cacheHitCount,
            unreadableCount: unreadableCount
        )
    }
    
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
            if Task.isCancelled {
                return
            }

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
    
    /// Get total potential savings from all duplicate groups
    public func totalPotentialSavings(in groups: [DuplicateGroup]) -> Int64 {
        groups.reduce(0) { $0 + $1.potentialSavings }
    }
    
    /// Get formatted savings string
    public func formattedSavings(in groups: [DuplicateGroup]) -> String {
        let savings = totalPotentialSavings(in: groups)
        return ByteCountFormatter.string(fromByteCount: savings, countStyle: .file)
    }

    private static func cacheKey(for file: FileItem) -> HashCacheKey {
        HashCacheKey(
            path: URL(fileURLWithPath: file.path).standardizedFileURL.path,
            size: file.size,
            modificationDate: file.modificationDate
        )
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
    @Published public var duplicateGroups: [DuplicateGroup] = [] {
        didSet { refreshDerivedDuplicateSummary() }
    }
    @Published public var isScanning = false
    @Published public var scanProgress: Double = 0
    @Published public var lastScanDate: Date?
    @Published public var semanticGroups: [SemanticDuplicateGroup] = [] {
        didSet { refreshDerivedDuplicateSummary() }
    }
    @Published public var scanStage: String = ""
    @Published public private(set) var allGroups: [UnifiedDuplicateGroup] = []
    @Published public private(set) var totalDuplicates: Int = 0
    @Published public private(set) var potentialSavings: Int64 = 0
    @Published public private(set) var formattedSavings: String = ByteCountFormatter.string(
        fromByteCount: 0,
        countStyle: .file
    )
    @Published public private(set) var totalDuplicatesIncludingSemantic: Int = 0
    @Published public private(set) var potentialSavingsIncludingSemantic: Int64 = 0
    @Published public private(set) var formattedSavingsIncludingSemantic: String = ByteCountFormatter.string(
        fromByteCount: 0,
        countStyle: .file
    )
    @Published public private(set) var exactGroupCount: Int = 0
    @Published public private(set) var semanticGroupCount: Int = 0
    @Published public private(set) var scannedFileCount: Int = 0
    @Published public private(set) var hashCandidateCount: Int = 0
    @Published public private(set) var hashedFileCount: Int = 0
    @Published public private(set) var hashCacheHitCount: Int = 0
    @Published public private(set) var unreadableFileCount: Int = 0
    @Published public private(set) var scanDuration: TimeInterval = 0
    
    private let detector = DuplicateDetector()
    private var lastProgressUpdate = Date.distantPast
    private let progressUpdateInterval: TimeInterval = 0.12
    
    public init() {}

    private func refreshDerivedDuplicateSummary() {
        let exactGroups = duplicateGroups.map { UnifiedDuplicateGroup.exact($0) }
        let semanticGroupsMapped = semanticGroups.map { UnifiedDuplicateGroup.semantic($0) }
        let exactSavings = duplicateGroups.reduce(0) { $0 + $1.potentialSavings }
        let semanticSavings = semanticGroups.reduce(0) { $0 + $1.potentialSavings }
        let exactDuplicateCount = duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
        let semanticDuplicateCount = semanticGroups.reduce(0) { $0 + max(0, $1.files.count - 1) }

        allGroups = (exactGroups + semanticGroupsMapped).sorted { $0.potentialSavings > $1.potentialSavings }
        totalDuplicates = exactDuplicateCount
        potentialSavings = exactSavings
        formattedSavings = ByteCountFormatter.string(fromByteCount: exactSavings, countStyle: .file)
        totalDuplicatesIncludingSemantic = exactDuplicateCount + semanticDuplicateCount
        potentialSavingsIncludingSemantic = exactSavings + semanticSavings
        formattedSavingsIncludingSemantic = ByteCountFormatter.string(
            fromByteCount: exactSavings + semanticSavings,
            countStyle: .file
        )
        exactGroupCount = duplicateGroups.count
        semanticGroupCount = semanticGroups.count
    }
    
    public func scanForDuplicates(files: [FileItem], settings: DuplicateSettings) async {
        let scanStartedAt = Date()
        state = .scanning(progress: 0)
        isScanning = true
        scanProgress = 0
        scanStage = "Preparing..."
        lastProgressUpdate = .distantPast
        
        let eligibleFiles = eligibleFiles(from: files, settings: settings)
        scannedFileCount = eligibleFiles.count
        hashCandidateCount = 0
        hashedFileCount = 0
        hashCacheHitCount = 0
        unreadableFileCount = 0
        scanDuration = 0

        let total = eligibleFiles.count
        guard total > 0 else {
            duplicateGroups = []
            semanticGroups = []
            lastScanDate = Date()
            isScanning = false
            scanProgress = 1.0
            scanStage = ""
            scanDuration = Date().timeIntervalSince(scanStartedAt)
            state = .completed(count: 0)
            return
        }
        
        // Exact groups always require matching content. Size bucketing keeps
        // this reliable without hashing every file in large directories.
        scanStage = "Comparing file contents..."

        let exactResult = await detector.findExactDuplicates(in: eligibleFiles) { current, candidateTotal in
            Task { @MainActor in
                let candidateProgress = candidateTotal > 0
                    ? Double(current) / Double(candidateTotal)
                    : 1
                self.publishScanProgress(candidateProgress * 0.7, force: current == candidateTotal)
            }
        }

        hashCandidateCount = exactResult.candidateCount
        hashedFileCount = exactResult.hashedCount
        hashCacheHitCount = exactResult.cacheHitCount
        unreadableFileCount = exactResult.unreadableCount
        
        if Task.isCancelled {
            isScanning = false
            state = .idle
            scanStage = ""
            return
        }
        
        var groups = exactResult.groups
        duplicateGroups = groups
        
        // Step 3: Semantic duplicate detection (if enabled)
        if settings.includeSemanticDuplicates && !Task.isCancelled {
            scanStage = "Semantic analysis..."
            let exactFileIDs = Set(groups.flatMap(\.files).map(\.id))
            let semanticCandidates = eligibleFiles.filter { !exactFileIDs.contains($0.id) }
            let semanticDetector = SemanticDuplicateDetector(
                similarityThreshold: settings.normalizedSemanticSimilarityThreshold
            )
            let detectedSemanticGroups = await semanticDetector.findSemanticDuplicates(in: semanticCandidates) { current, total, stage in
                Task { @MainActor in
                    self.scanStage = stage
                    let semanticProgress = total > 0 ? Double(current) / Double(total) : 1
                    self.publishScanProgress(0.7 + semanticProgress * 0.3, force: current == total)
                }
            }
            let promotedExactGroups = await promoteExactMatches(from: detectedSemanticGroups)
            let promotedFileIDs = Set(promotedExactGroups.flatMap(\.files).map(\.id))
            if !promotedExactGroups.isEmpty {
                groups = mergeExactGroupsByHash(groups + promotedExactGroups)
                duplicateGroups = groups
            }
            semanticGroups = detectedSemanticGroups.compactMap { group in
                let remainingFiles = group.files.filter { !promotedFileIDs.contains($0.id) }
                guard remainingFiles.count > 1 else { return nil }
                return SemanticDuplicateGroup(
                    groupType: group.groupType,
                    files: remainingFiles,
                    similarity: group.similarity,
                    recommendation: group.recommendation
                )
            }
        } else {
            semanticGroups = []
        }
        
        lastScanDate = Date()
        isScanning = false
        scanProgress = 1.0
        scanStage = ""
        scanDuration = Date().timeIntervalSince(scanStartedAt)
        state = .completed(count: allGroups.count)
    }
    
    public func clearResults() {
        duplicateGroups = []
        semanticGroups = []
        lastScanDate = nil
        scanProgress = 0
        scanStage = ""
        isScanning = false
        state = .idle
        scannedFileCount = 0
        hashCandidateCount = 0
        hashedFileCount = 0
        hashCacheHitCount = 0
        unreadableFileCount = 0
        scanDuration = 0
    }

    private func eligibleFiles(
        from files: [FileItem],
        settings: DuplicateSettings
    ) -> [FileItem] {
        let includedExtensions = Set(settings.includeExtensions.map(Self.normalizedExtension))
        let excludedExtensions = Set(settings.excludeExtensions.map(Self.normalizedExtension))

        return files.filter { file in
            guard !file.isDirectory, file.size >= settings.minFileSize else {
                return false
            }

            let fileExtension = Self.normalizedExtension(file.extension)
            if !includedExtensions.isEmpty, !includedExtensions.contains(fileExtension) {
                return false
            }
            return !excludedExtensions.contains(fileExtension)
                && !settings.excludeExtensions.contains(file.displayName)
        }
    }

    private static func normalizedExtension(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func publishScanProgress(_ progress: Double, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval else {
            return
        }

        lastProgressUpdate = now
        scanProgress = progress
        state = .scanning(progress: progress)
    }

    private func promoteExactMatches(from semanticGroups: [SemanticDuplicateGroup]) async -> [DuplicateGroup] {
        var promotedGroups: [DuplicateGroup] = []

        for group in semanticGroups {
            let sameSizeBuckets = Dictionary(grouping: group.files.filter { !$0.isDirectory }, by: \.size)
                .values
                .filter { $0.count > 1 }

            for files in sameSizeBuckets {
                let exactResult = await detector.findExactDuplicates(in: Array(files))
                promotedGroups.append(contentsOf: exactResult.groups)
            }
        }

        return mergeExactGroupsByHash(promotedGroups)
    }

    private func mergeExactGroupsByHash(_ groups: [DuplicateGroup]) -> [DuplicateGroup] {
        var filesByHash: [String: [UUID: FileItem]] = [:]
        for group in groups {
            for file in group.files {
                filesByHash[group.hash, default: [:]][file.id] = file
            }
        }

        return filesByHash
            .compactMap { hash, filesById in
                let files = filesById.values.sorted {
                    if $0.displayName == $1.displayName {
                        return $0.path < $1.path
                    }
                    return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
                }
                guard files.count > 1 else { return nil }
                return DuplicateGroup(hash: hash, files: files)
            }
            .sorted { $0.potentialSavings > $1.potentialSavings }
    }
}

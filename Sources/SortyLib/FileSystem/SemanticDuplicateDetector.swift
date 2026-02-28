//
//  SemanticDuplicateDetector.swift
//  Sorty
//
//  Semantic Duplicate Detection for near-duplicates
//  Finds similar documents, burst photos, and different versions of files
//

import Foundation
import CryptoKit
import Combine
import Vision
import AppKit

/// Represents a group of semantically similar files (near-duplicates)
public struct SemanticDuplicateGroup: Identifiable, Sendable {
    public let id: UUID
    public let groupType: DuplicateType
    public let files: [FileItem]
    public let similarity: Double // 0.0 - 1.0
    public let recommendation: DuplicateRecommendation

    public enum DuplicateType: String, Codable, Sendable {
        case burstPhotos = "Burst Photos"
        case documentVersions = "Document Versions"
        case resolutionVariants = "Resolution Variants"
        case nearIdenticalImages = "Near-Identical Images"
        case similarDocuments = "Similar Documents"
        case exactDuplicates = "Exact Duplicates"
        case vibeGroup = "Vibe Group"
    }

    public enum DuplicateRecommendation: Codable, Sendable, Equatable {
        case keepHighestResolution(fileId: UUID)
        case keepNewest(fileId: UUID)
        case keepOldest(fileId: UUID)
        case keepLargest(fileId: UUID)
        case archiveOlderVersions(keepId: UUID, archiveIds: [UUID])
        case manualReview

        public var description: String {
            switch self {
            case .keepHighestResolution:
                return "Keep the highest resolution version"
            case .keepNewest:
                return "Keep the most recent version"
            case .keepOldest:
                return "Keep the original version"
            case .keepLargest:
                return "Keep the largest file"
            case .archiveOlderVersions:
                return "Archive older drafts"
            case .manualReview:
                return "Review manually"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        groupType: DuplicateType,
        files: [FileItem],
        similarity: Double,
        recommendation: DuplicateRecommendation = .manualReview
    ) {
        self.id = id
        self.groupType = groupType
        self.files = files
        self.similarity = similarity
        self.recommendation = recommendation
    }

    public var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    /// Potential savings if keeping only one file
    public var potentialSavings: Int64 {
        guard files.count > 1 else { return 0 }
        let sorted = files.sorted { $0.size > $1.size }
        return sorted.dropFirst().reduce(0) { $0 + $1.size }
    }

    public var formattedSavings: String {
        ByteCountFormatter.string(fromByteCount: potentialSavings, countStyle: .file)
    }

    public var similarityPercentage: String {
        String(format: "%.0f%%", similarity * 100)
    }
}

/// Actor for detecting semantically similar files
public actor SemanticDuplicateDetector {
    private static let perceptualHashBitLength = 64

    private let visionAnalyzer = VisionAnalyzer()
    private let similarityThreshold: Double
    private let hammingThreshold: Int
    private let vibeFeaturePrintThreshold: Float
    private let vibeTextSimilarityThreshold: Double

    public init(similarityThreshold: Double = DuplicateSettings.defaultSemanticSimilarityThreshold) {
        let normalizedThreshold = Self.clampedMinimumSimilarity(similarityThreshold)
        self.similarityThreshold = normalizedThreshold
        self.hammingThreshold = Self.hammingThreshold(for: normalizedThreshold, hashBits: Self.perceptualHashBitLength)
        self.vibeFeaturePrintThreshold = Self.vibeFeatureThreshold(for: normalizedThreshold)
        self.vibeTextSimilarityThreshold = Self.vibeTextThreshold(for: normalizedThreshold)
    }

    static func clampedMinimumSimilarity(_ value: Double) -> Double {
        DuplicateSettings.clampedSemanticSimilarityThreshold(value)
    }

    static func hammingThreshold(for minimumSimilarity: Double, hashBits: Int = 64) -> Int {
        let normalizedThreshold = clampedMinimumSimilarity(minimumSimilarity)
        let rawThreshold = Int(floor((1.0 - normalizedThreshold) * Double(hashBits)))
        return max(0, min(hashBits, rawThreshold))
    }

    static func similarityForHammingDistance(_ distance: Int, hashBits: Int = 64) -> Double {
        guard hashBits > 0 else { return 0 }
        let clampedDistance = max(0, min(distance, hashBits))
        let similarity = 1.0 - (Double(clampedDistance) / Double(hashBits))
        return max(0, min(1.0, similarity))
    }

    static func vibeFeatureThreshold(for minimumSimilarity: Double) -> Float {
        let normalizedThreshold = clampedMinimumSimilarity(minimumSimilarity)
        let strictness = (normalizedThreshold - DuplicateSettings.minSemanticSimilarityThreshold)
            / (DuplicateSettings.maxSemanticSimilarityThreshold - DuplicateSettings.minSemanticSimilarityThreshold)
        // Lower feature-print distance is stricter.
        return max(8.0, 15.0 - Float(strictness) * 7.0)
    }

    static func vibeTextThreshold(for minimumSimilarity: Double) -> Double {
        let normalizedThreshold = clampedMinimumSimilarity(minimumSimilarity)
        return max(0.55, min(0.90, normalizedThreshold - 0.20))
    }

    /// Find all semantic duplicates in a list of files
    public func findSemanticDuplicates(
        in files: [FileItem],
        progressHandler: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []
        let shouldRunVibeDetection = similarityThreshold <= 0.85

        // Separate files by type
        let imageFiles = files.filter { isImageFile($0) }
        let documentFiles = files.filter { isDocumentFile($0) }

        let totalSteps = shouldRunVibeDetection ? 5 : 4
        var currentStep = 0

        // Step 1: Find burst photos (images taken within seconds of each other)
        progressHandler?(currentStep, totalSteps, "Analyzing burst photos...")
        let burstGroups = await findBurstPhotos(in: imageFiles)
        groups.append(contentsOf: burstGroups)
        currentStep += 1

        // Step 2: Find near-identical images using perceptual hashing
        progressHandler?(currentStep, totalSteps, "Comparing images...")
        let similarImageGroups = await findSimilarImages(in: imageFiles)
        groups.append(contentsOf: similarImageGroups)
        currentStep += 1

        // Step 3: Find resolution variants (same image, different sizes)
        progressHandler?(currentStep, totalSteps, "Finding resolution variants...")
        let resolutionGroups = await findResolutionVariants(in: imageFiles)
        groups.append(contentsOf: resolutionGroups)
        currentStep += 1

        // Step 4: Find similar documents
        progressHandler?(currentStep, totalSteps, "Analyzing documents...")
        let documentGroups = await findSimilarDocuments(in: documentFiles)
        groups.append(contentsOf: documentGroups)
        currentStep += 1

        // Step 5: Find vibe groups (only for looser thresholds)
        if shouldRunVibeDetection {
            progressHandler?(currentStep, totalSteps, "Finding vibe groups...")
            let vibeGroups = await findVibeGroups(in: files)
            groups.append(contentsOf: vibeGroups)
            currentStep += 1
        }

        // Keep only groups at or above the configured similarity level.
        let thresholdedGroups = groups.filter { $0.similarity >= similarityThreshold }

        // Remove duplicates between groups and merge overlapping.
        let mergedGroups = mergeOverlappingGroups(thresholdedGroups)

        return mergedGroups.sorted {
            if $0.similarity == $1.similarity {
                return $0.potentialSavings > $1.potentialSavings
            }
            return $0.similarity > $1.similarity
        }
    }

    // MARK: - Burst Photo Detection

    private func findBurstPhotos(in images: [FileItem]) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []

        // Group by creation date within 2-second window
        let sortedByDate = images
            .filter { $0.creationDate != nil }
            .sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        var currentGroup: [FileItem] = []
        var lastDate: Date?

        for file in sortedByDate {
            guard let fileDate = file.creationDate else { continue }

            if let last = lastDate {
                let interval = fileDate.timeIntervalSince(last)
                if interval <= 2.0 { // Within 2 seconds
                    currentGroup.append(file)
                } else {
                    if currentGroup.count > 1 {
                        let recommendation = recommendForBurstPhotos(currentGroup)
                        groups.append(SemanticDuplicateGroup(
                            groupType: .burstPhotos,
                            files: currentGroup,
                            similarity: 0.95,
                            recommendation: recommendation
                        ))
                    }
                    currentGroup = [file]
                }
            } else {
                currentGroup = [file]
            }

            lastDate = fileDate
        }

        // Don't forget the last group
        if currentGroup.count > 1 {
            let recommendation = recommendForBurstPhotos(currentGroup)
            groups.append(SemanticDuplicateGroup(
                groupType: .burstPhotos,
                files: currentGroup,
                similarity: 0.95,
                recommendation: recommendation
            ))
        }

        return groups
    }

    // MARK: - Perceptual Hash Comparison

    private func findSimilarImages(in images: [FileItem]) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []
        var processedIds: Set<UUID> = []

        // Generate perceptual hashes for all images
        var imageHashes: [(file: FileItem, hash: String)] = []

        for file in images {
            guard let url = file.url else { continue }

            if let existingHash = file.contentFingerprint {
                imageHashes.append((file, existingHash))
            } else if let hash = await visionAnalyzer.generatePerceptualHash(at: url) {
                imageHashes.append((file, hash))
            }
        }

        // Compare all pairs
        for i in 0..<imageHashes.count {
            guard !processedIds.contains(imageHashes[i].file.id) else { continue }

            var similarFiles: [FileItem] = [imageHashes[i].file]
            var matchedDistances: [Int] = []

            for j in (i + 1)..<imageHashes.count {
                guard !processedIds.contains(imageHashes[j].file.id) else { continue }

                if let distance = imageHashes[i].hash.hammingDistance(to: imageHashes[j].hash),
                   distance <= hammingThreshold {
                    similarFiles.append(imageHashes[j].file)
                    matchedDistances.append(distance)
                    processedIds.insert(imageHashes[j].file.id)
                }
            }

            if similarFiles.count > 1 {
                processedIds.insert(imageHashes[i].file.id)
                let worstDistance = matchedDistances.max() ?? 0
                let similarity = Self.similarityForHammingDistance(worstDistance, hashBits: Self.perceptualHashBitLength)
                let recommendation = recommendForSimilarImages(similarFiles)

                groups.append(SemanticDuplicateGroup(
                    groupType: .nearIdenticalImages,
                    files: similarFiles,
                    similarity: similarity,
                    recommendation: recommendation
                ))
            }
        }

        return groups
    }

    // MARK: - Resolution Variant Detection

    private func findResolutionVariants(in images: [FileItem]) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []
        var processedIds: Set<UUID> = []

        // Group by similar filename patterns
        let baseNameGroups = Dictionary(grouping: images) { file -> String in
            // Extract base name without resolution suffix patterns
            let name = file.name.lowercased()
            let patterns = [
                #"_\d+x\d+"#,      // _1920x1080
                #"@\d+x"#,         // @2x, @3x
                #"-small"#,
                #"-medium"#,
                #"-large"#,
                #"-thumbnail"#,
                #"-thumb"#,
                #"_hd"#,
                #"_sd"#,
                #"_4k"#,
                #"_1080p"#,
                #"_720p"#
            ]

            var baseName = name
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(baseName.startIndex..., in: baseName)
                    baseName = regex.stringByReplacingMatches(in: baseName, range: range, withTemplate: "")
                }
            }

            return baseName
        }

        for (_, filesInGroup) in baseNameGroups where filesInGroup.count > 1 {
            // Filter to only those with dimension info
            let withDimensions = filesInGroup.filter { $0.imageWidth != nil && $0.imageHeight != nil }

            guard withDimensions.count > 1 else { continue }

            // Check if they're actually different resolutions of the same image
            let sortedBySize = withDimensions.sorted { ($0.totalPixels ?? 0) > ($1.totalPixels ?? 0) }

            // Skip if all same resolution
            guard let first = sortedBySize.first?.totalPixels,
                  let last = sortedBySize.last?.totalPixels,
                  first != last else { continue }

            for file in sortedBySize {
                processedIds.insert(file.id)
            }

            groups.append(SemanticDuplicateGroup(
                groupType: .resolutionVariants,
                files: sortedBySize,
                similarity: 0.98,
                recommendation: .keepHighestResolution(fileId: sortedBySize.first!.id)
            ))
        }

        return groups
    }

    // MARK: - Similar Document Detection

    private func findSimilarDocuments(in documents: [FileItem]) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []
        var processedIds: Set<UUID> = []

        // Group documents by filename similarity (version patterns)
        let versionPattern = #"[\s_-]*(v?\d+\.?\d*|draft|final|rev\d*|copy|old|new|backup)[\s_-]*"#

        let baseNameGroups = Dictionary(grouping: documents) { file -> String in
            var baseName = file.name.lowercased()

            if let regex = try? NSRegularExpression(pattern: versionPattern, options: .caseInsensitive) {
                let range = NSRange(baseName.startIndex..., in: baseName)
                baseName = regex.stringByReplacingMatches(in: baseName, range: range, withTemplate: "")
            }

            return baseName + "." + file.extension.lowercased()
        }

        for (_, filesInGroup) in baseNameGroups where filesInGroup.count > 1 {
            for file in filesInGroup {
                processedIds.insert(file.id)
            }

            // Sort by modification date or creation date
            let sortedByDate = filesInGroup.sorted {
                ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
            }

            let recommendation: SemanticDuplicateGroup.DuplicateRecommendation
            if sortedByDate.count > 2 {
                recommendation = .archiveOlderVersions(
                    keepId: sortedByDate.first!.id,
                    archiveIds: Array(sortedByDate.dropFirst().map { $0.id })
                )
            } else {
                recommendation = .keepNewest(fileId: sortedByDate.first!.id)
            }

            groups.append(SemanticDuplicateGroup(
                groupType: .documentVersions,
                files: sortedByDate,
                similarity: 0.90,
                recommendation: recommendation
            ))
        }

        // Also compare document content if available
        let withContent = documents.filter { $0.hasSemanticContent }
        let contentGroups = await findSimilarByContent(withContent, processedIds: processedIds)
        groups.append(contentsOf: contentGroups)

        return groups
    }

    private func findSimilarByContent(_ documents: [FileItem], processedIds: Set<UUID>) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []
        var localProcessed = processedIds

        for i in 0..<documents.count {
            guard !localProcessed.contains(documents[i].id),
                  let content1 = documents[i].semanticTextContent else { continue }

            var similarFiles: [FileItem] = [documents[i]]
            var lowestSimilarityInGroup = 1.0

            for j in (i + 1)..<documents.count {
                guard !localProcessed.contains(documents[j].id),
                      let content2 = documents[j].semanticTextContent else { continue }

                let similarity = calculateTextSimilarity(content1, content2)
                if similarity >= similarityThreshold {
                    similarFiles.append(documents[j])
                    lowestSimilarityInGroup = min(lowestSimilarityInGroup, similarity)
                    localProcessed.insert(documents[j].id)
                }
            }

            if similarFiles.count > 1 {
                localProcessed.insert(documents[i].id)
                let groupSimilarity = max(similarityThreshold, lowestSimilarityInGroup)

                groups.append(SemanticDuplicateGroup(
                    groupType: .similarDocuments,
                    files: similarFiles,
                    similarity: groupSimilarity,
                    recommendation: .manualReview
                ))
            }
        }

        return groups
    }

    // MARK: - Vibe Group Detection

    private func findVibeGroups(in files: [FileItem]) async -> [SemanticDuplicateGroup] {
        let imageFiles = files.filter { isImageFile($0) }
        let documentFiles = files.filter { isDocumentFile($0) }

        var groups: [SemanticDuplicateGroup] = []

        let imageVibeGroups = await findImageVibeGroups(in: imageFiles)
        groups.append(contentsOf: imageVibeGroups)

        let documentVibeGroups = await findDocumentVibeGroups(in: documentFiles)
        groups.append(contentsOf: documentVibeGroups)

        return groups
    }

    private func findImageVibeGroups(in images: [FileItem]) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []
        var processedIds: Set<UUID> = []

        var featurePrints: [(file: FileItem, featurePrint: VNFeaturePrintObservation)] = []

        for file in images {
            guard let url = file.url else { continue }
            if let featurePrint = await generateFeaturePrint(at: url) {
                featurePrints.append((file, featurePrint))
            }
        }

        for i in 0..<featurePrints.count {
            guard !processedIds.contains(featurePrints[i].file.id) else { continue }

            var similarFiles: [FileItem] = [featurePrints[i].file]
            var matchedDistances: [Float] = []

            for j in (i + 1)..<featurePrints.count {
                guard !processedIds.contains(featurePrints[j].file.id) else { continue }

                var distance: Float = 0
                do {
                    try featurePrints[i].featurePrint.computeDistance(&distance, to: featurePrints[j].featurePrint)
                } catch {
                    continue
                }

                if distance < vibeFeaturePrintThreshold {
                    similarFiles.append(featurePrints[j].file)
                    matchedDistances.append(distance)
                    processedIds.insert(featurePrints[j].file.id)
                }
            }

            if similarFiles.count > 1 {
                processedIds.insert(featurePrints[i].file.id)
                let worstDistance = matchedDistances.max() ?? 0
                let normalizedDistance = Double(worstDistance / max(vibeFeaturePrintThreshold, 0.001))
                let normalizedSimilarity = max(0.0, 1.0 - min(1.0, normalizedDistance) * 0.35)

                groups.append(SemanticDuplicateGroup(
                    groupType: .vibeGroup,
                    files: similarFiles,
                    similarity: normalizedSimilarity,
                    recommendation: .manualReview
                ))
            }
        }

        return groups
    }

    private func findDocumentVibeGroups(in documents: [FileItem]) async -> [SemanticDuplicateGroup] {
        var groups: [SemanticDuplicateGroup] = []
        var processedIds: Set<UUID> = []

        let withContent = documents.filter { $0.hasSemanticContent }

        for i in 0..<withContent.count {
            guard !processedIds.contains(withContent[i].id),
                  let content1 = withContent[i].semanticTextContent else { continue }

            var similarFiles: [FileItem] = [withContent[i]]
            var lowestSimilarityInGroup = 1.0

            for j in (i + 1)..<withContent.count {
                guard !processedIds.contains(withContent[j].id),
                      let content2 = withContent[j].semanticTextContent else { continue }

                let similarity = calculateTextSimilarity(content1, content2)
                if similarity >= vibeTextSimilarityThreshold {
                    similarFiles.append(withContent[j])
                    lowestSimilarityInGroup = min(lowestSimilarityInGroup, similarity)
                    processedIds.insert(withContent[j].id)
                }
            }

            if similarFiles.count > 1 {
                processedIds.insert(withContent[i].id)
                let groupSimilarity = max(vibeTextSimilarityThreshold, lowestSimilarityInGroup)

                groups.append(SemanticDuplicateGroup(
                    groupType: .vibeGroup,
                    files: similarFiles,
                    similarity: groupSimilarity,
                    recommendation: .manualReview
                ))
            }
        }

        return groups
    }

    private func generateFeaturePrint(at url: URL) async -> VNFeaturePrintObservation? {
        guard let cgImage = loadCGImage(from: url) else { return nil }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            DebugLogger.log("Failed to generate feature print: \(error.localizedDescription)")
            return nil
        }

        guard let result = request.results?.first else {
            return nil
        }

        return result
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            if let image = NSImage(contentsOf: url) {
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: - Text Similarity (Jaccard Index)

    private func calculateTextSimilarity(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().split(separator: " ").map { String($0) })
        let words2 = Set(text2.lowercased().split(separator: " ").map { String($0) })

        guard !words1.isEmpty && !words2.isEmpty else { return 0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        return Double(intersection) / Double(union)
    }

    // MARK: - Helper Methods

    private func isImageFile(_ file: FileItem) -> Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "bmp", "gif", "webp", "raw", "cr2", "nef", "arw"]
        return imageExtensions.contains(file.extension.lowercased())
    }

    private func isDocumentFile(_ file: FileItem) -> Bool {
        let documentExtensions = ["pdf", "doc", "docx", "txt", "rtf", "md", "pages", "odt", "xls", "xlsx", "ppt", "pptx"]
        return documentExtensions.contains(file.extension.lowercased())
    }

    private func recommendForBurstPhotos(_ files: [FileItem]) -> SemanticDuplicateGroup.DuplicateRecommendation {
        // For burst photos, recommend keeping the highest resolution
        if let best = files.max(by: { ($0.totalPixels ?? 0) < ($1.totalPixels ?? 0) }) {
            return .keepHighestResolution(fileId: best.id)
        }
        // Fallback to largest file
        if let largest = files.max(by: { $0.size < $1.size }) {
            return .keepLargest(fileId: largest.id)
        }
        return .manualReview
    }

    private func recommendForSimilarImages(_ files: [FileItem]) -> SemanticDuplicateGroup.DuplicateRecommendation {
        // Prefer highest resolution
        if let best = files.max(by: { ($0.totalPixels ?? 0) < ($1.totalPixels ?? 0) }),
           best.totalPixels != nil {
            return .keepHighestResolution(fileId: best.id)
        }
        // Then largest size
        if let largest = files.max(by: { $0.size < $1.size }) {
            return .keepLargest(fileId: largest.id)
        }
        return .manualReview
    }

    private func mergeOverlappingGroups(_ groups: [SemanticDuplicateGroup]) -> [SemanticDuplicateGroup] {
        let sortedGroups = groups.sorted {
            if $0.similarity == $1.similarity {
                return $0.potentialSavings > $1.potentialSavings
            }
            return $0.similarity > $1.similarity
        }

        var result: [SemanticDuplicateGroup] = []
        var usedFileIds: Set<UUID> = []

        for group in sortedGroups {
            // Check if any file in this group is already in another group
            let fileIds = Set(group.files.map { $0.id })
            if fileIds.isDisjoint(with: usedFileIds) {
                result.append(group)
                usedFileIds.formUnion(fileIds)
            }
        }

        return result
    }
}

// MARK: - Manager for UI Integration

@MainActor
public class SemanticDuplicateManager: ObservableObject {
    @Published public var duplicateGroups: [SemanticDuplicateGroup] = []
    @Published public var isScanning = false
    @Published public var scanProgress: Double = 0
    @Published public var currentStage: String = ""
    @Published public var lastScanDate: Date?

    private let detector = SemanticDuplicateDetector()

    public init() {}

    public var totalDuplicates: Int {
        duplicateGroups.reduce(0) { $0 + max(0, $1.files.count - 1) }
    }

    public var potentialSavings: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.potentialSavings }
    }

    public var formattedSavings: String {
        ByteCountFormatter.string(fromByteCount: potentialSavings, countStyle: .file)
    }

    public var groupsByType: [SemanticDuplicateGroup.DuplicateType: [SemanticDuplicateGroup]] {
        Dictionary(grouping: duplicateGroups) { $0.groupType }
    }

    public func scanForDuplicates(files: [FileItem]) async {
        isScanning = true
        scanProgress = 0
        currentStage = "Starting scan..."

        let groups = await detector.findSemanticDuplicates(in: files) { current, total, stage in
            Task { @MainActor in
                self.scanProgress = Double(current) / Double(total)
                self.currentStage = stage
            }
        }

        duplicateGroups = groups
        lastScanDate = Date()
        isScanning = false
        scanProgress = 1.0
        currentStage = "Scan complete"
    }

    public func clearResults() {
        duplicateGroups = []
        lastScanDate = nil
    }

    /// Apply a recommendation by returning files to keep and files to remove/archive
    public func applyRecommendation(for group: SemanticDuplicateGroup) -> (keep: [FileItem], remove: [FileItem]) {
        switch group.recommendation {
        case .keepHighestResolution(let fileId),
             .keepNewest(let fileId),
             .keepOldest(let fileId),
             .keepLargest(let fileId):
            let keep = group.files.filter { $0.id == fileId }
            let remove = group.files.filter { $0.id != fileId }
            return (keep, remove)

        case .archiveOlderVersions(let keepId, _):
            let keep = group.files.filter { $0.id == keepId }
            let remove = group.files.filter { $0.id != keepId }
            return (keep, remove)

        case .manualReview:
            return (group.files, [])
        }
    }
}

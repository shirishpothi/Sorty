//
//  DuplicateSettings.swift
//  Sorty
//
//  Settings model for duplicate detection configuration
//

import Foundation
import Combine

/// Settings for duplicate detection behavior
public struct DuplicateSettings: Codable, Sendable {
    public static let minSemanticSimilarityThreshold: Double = 0.70
    public static let maxSemanticSimilarityThreshold: Double = 1.00
    public static let defaultSemanticSimilarityThreshold: Double = 0.90

    /// Method used to determine if files are duplicates
    public var comparisonMethod: ComparisonMethod

    /// Minimum file size to include in scan (bytes)
    public var minFileSize: Int64
    
    /// Maximum scan depth (-1 for unlimited)
    public var maxScanDepth: Int
    
    /// File extensions to include (empty = all)
    public var includeExtensions: [String]
    
    /// File extensions to exclude
    public var excludeExtensions: [String]
    
    /// Default keep strategy when bulk deleting
    public var defaultKeepStrategy: KeepStrategy
    
    /// Enable safe deletion (move to trash with restore option)
    public var enableSafeDeletion: Bool
    
    /// Auto-start scan when opening duplicates view
    public var autoStartScan: Bool
    
    /// Show semantic/similar duplicates (not just exact matches)
    public var includeSemanticDuplicates: Bool
    
    /// Similarity threshold for semantic duplicates (0.70 - 1.00)
    public var semanticSimilarityThreshold: Double

    public static func clampedSemanticSimilarityThreshold(_ value: Double) -> Double {
        min(max(value, minSemanticSimilarityThreshold), maxSemanticSimilarityThreshold)
    }

    public var normalizedSemanticSimilarityThreshold: Double {
        Self.clampedSemanticSimilarityThreshold(semanticSimilarityThreshold)
    }
    
    public init(
        comparisonMethod: ComparisonMethod = .exact,
        minFileSize: Int64 = 0,
        maxScanDepth: Int = -1,
        includeExtensions: [String] = [],
        excludeExtensions: [String] = [".DS_Store", ".localized"],
        defaultKeepStrategy: KeepStrategy = .newest,
        enableSafeDeletion: Bool = true,
        autoStartScan: Bool = true,
        includeSemanticDuplicates: Bool = true,
        semanticSimilarityThreshold: Double = DuplicateSettings.defaultSemanticSimilarityThreshold
    ) {
        self.comparisonMethod = comparisonMethod
        self.minFileSize = minFileSize
        self.maxScanDepth = maxScanDepth
        self.includeExtensions = includeExtensions
        self.excludeExtensions = excludeExtensions
        self.defaultKeepStrategy = defaultKeepStrategy
        self.enableSafeDeletion = enableSafeDeletion
        self.autoStartScan = autoStartScan
        self.includeSemanticDuplicates = includeSemanticDuplicates
        self.semanticSimilarityThreshold = Self.clampedSemanticSimilarityThreshold(semanticSimilarityThreshold)
    }
}

public enum ComparisonMethod: String, Codable, CaseIterable, Sendable {
    case exact = "exact"       // Content hash (SHA-256)
    case fast = "fast"         // Name + Size
    case metadata = "metadata" // Name + Size + Modified Date
    
    public var displayName: String {
        switch self {
        case .exact: return "Content Match"
        case .fast: return "Fast Match"
        case .metadata: return "Metadata Match"
        }
    }
    
    public var description: String {
        switch self {
        case .exact: return "Identifies files with identical content using SHA-256 hashing. Very reliable but slower."
        case .fast: return "Matches files with the same name and size. Much faster for large directories."
        case .metadata: return "Matches name, size, and modification date. Good balance of speed and reliability."
        }
    }
}

public enum KeepStrategy: String, Codable, CaseIterable, Sendable {
    case newest = "newest"
    case oldest = "oldest"
    case largest = "largest"
    case smallest = "smallest"
    case shortestPath = "shortestPath"
    
    public var displayName: String {
        switch self {
        case .newest: return "Keep Newest"
        case .oldest: return "Keep Oldest"
        case .largest: return "Keep Largest"
        case .smallest: return "Keep Smallest"
        case .shortestPath: return "Keep Shortest Path"
        }
    }
    
    public var description: String {
        switch self {
        case .newest: return "Keep the most recently modified file"
        case .oldest: return "Keep the oldest file"
        case .largest: return "Keep the largest file (may have better quality)"
        case .smallest: return "Keep the smallest file"
        case .shortestPath: return "Keep the file with the shortest path"
        }
    }
}

/// Manager for duplicate settings persistence
@MainActor
public class DuplicateSettingsManager: ObservableObject {
    @Published public var settings: DuplicateSettings
    
    private let userDefaults = UserDefaults.standard
    private let storageKey = "duplicateSettings"

    private enum OverrideKey {
        static let comparisonMethod = "duplicates.comparisonMethod"
        static let minimumFileSizeMB = "duplicates.minimumFileSizeMB"
        static let maximumScanDepth = "duplicates.maximumScanDepth"
        static let includeExtensions = "duplicates.includeExtensions"
        static let excludeExtensions = "duplicates.excludeExtensions"
        static let autoStartScan = "duplicates.autoStartScan"
        static let semanticMatching = "duplicates.semanticMatching"
        static let semanticThreshold = "duplicates.semanticThreshold"
        static let safeDeletion = "duplicates.safeDeletion"
    }
    
    public init() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DuplicateSettings.self, from: data) {
            self.settings = Self.normalize(Self.applyingOverrides(to: decoded, defaults: userDefaults))
        } else {
            self.settings = Self.normalize(Self.applyingOverrides(to: DuplicateSettings(), defaults: userDefaults))
        }
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.reset()
        }
    }
    
    public func save() {
        settings = Self.normalize(settings)
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
    
    public func reset() {
        Self.allOverrideKeys.forEach(userDefaults.removeObject(forKey:))
        settings = DuplicateSettings()
        save()
    }

    private static func normalize(_ settings: DuplicateSettings) -> DuplicateSettings {
        var normalized = settings
        normalized.semanticSimilarityThreshold = settings.normalizedSemanticSimilarityThreshold
        return normalized
    }

    private static func applyingOverrides(to settings: DuplicateSettings, defaults: UserDefaults) -> DuplicateSettings {
        var overridden = settings
        let recommended = DuplicateSettings()

        overridden.comparisonMethod = recommended.comparisonMethod
        overridden.minFileSize = recommended.minFileSize
        overridden.maxScanDepth = recommended.maxScanDepth
        overridden.includeExtensions = recommended.includeExtensions
        overridden.excludeExtensions = recommended.excludeExtensions
        overridden.enableSafeDeletion = recommended.enableSafeDeletion
        overridden.autoStartScan = recommended.autoStartScan
        overridden.includeSemanticDuplicates = recommended.includeSemanticDuplicates
        overridden.semanticSimilarityThreshold = recommended.semanticSimilarityThreshold

        if let rawMethod = defaults.string(forKey: OverrideKey.comparisonMethod),
           let method = ComparisonMethod(rawValue: rawMethod) {
            overridden.comparisonMethod = method
        }
        if defaults.object(forKey: OverrideKey.minimumFileSizeMB) != nil {
            overridden.minFileSize = Int64(max(0, defaults.double(forKey: OverrideKey.minimumFileSizeMB)) * 1_048_576)
        }
        if defaults.object(forKey: OverrideKey.maximumScanDepth) != nil {
            overridden.maxScanDepth = defaults.integer(forKey: OverrideKey.maximumScanDepth)
        }
        if let extensions = defaults.string(forKey: OverrideKey.includeExtensions) {
            overridden.includeExtensions = parsedExtensions(extensions)
        }
        if let extensions = defaults.string(forKey: OverrideKey.excludeExtensions) {
            overridden.excludeExtensions = parsedExtensions(extensions)
        }
        if defaults.object(forKey: OverrideKey.autoStartScan) != nil {
            overridden.autoStartScan = defaults.bool(forKey: OverrideKey.autoStartScan)
        }
        if defaults.object(forKey: OverrideKey.semanticMatching) != nil {
            overridden.includeSemanticDuplicates = defaults.bool(forKey: OverrideKey.semanticMatching)
        }
        if defaults.object(forKey: OverrideKey.semanticThreshold) != nil {
            overridden.semanticSimilarityThreshold = defaults.double(forKey: OverrideKey.semanticThreshold)
        }
        if defaults.object(forKey: OverrideKey.safeDeletion) != nil {
            overridden.enableSafeDeletion = defaults.bool(forKey: OverrideKey.safeDeletion)
        }

        return overridden
    }

    private static func parsedExtensions(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static var allOverrideKeys: [String] {
        [
            OverrideKey.comparisonMethod,
            OverrideKey.minimumFileSizeMB,
            OverrideKey.maximumScanDepth,
            OverrideKey.includeExtensions,
            OverrideKey.excludeExtensions,
            OverrideKey.autoStartScan,
            OverrideKey.semanticMatching,
            OverrideKey.semanticThreshold,
            OverrideKey.safeDeletion
        ]
    }
}

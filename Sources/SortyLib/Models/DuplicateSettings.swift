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
        autoStartScan: Bool = false,
        includeSemanticDuplicates: Bool = false,
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
    
    public init() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(DuplicateSettings.self, from: data) {
            self.settings = Self.normalize(decoded)
        } else {
            self.settings = DuplicateSettings()
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
        settings = DuplicateSettings()
        save()
    }

    private static func normalize(_ settings: DuplicateSettings) -> DuplicateSettings {
        var normalized = settings
        normalized.semanticSimilarityThreshold = settings.normalizedSemanticSimilarityThreshold
        return normalized
    }
}

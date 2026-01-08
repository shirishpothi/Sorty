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
    
    /// Similarity threshold for semantic duplicates (0.0 - 1.0)
    public var semanticSimilarityThreshold: Double
    
    public init(
        minFileSize: Int64 = 0,
        maxScanDepth: Int = -1,
        includeExtensions: [String] = [],
        excludeExtensions: [String] = [".DS_Store", ".localized"],
        defaultKeepStrategy: KeepStrategy = .newest,
        enableSafeDeletion: Bool = true,
        autoStartScan: Bool = false,
        includeSemanticDuplicates: Bool = false,
        semanticSimilarityThreshold: Double = 0.9
    ) {
        self.minFileSize = minFileSize
        self.maxScanDepth = maxScanDepth
        self.includeExtensions = includeExtensions
        self.excludeExtensions = excludeExtensions
        self.defaultKeepStrategy = defaultKeepStrategy
        self.enableSafeDeletion = enableSafeDeletion
        self.autoStartScan = autoStartScan
        self.includeSemanticDuplicates = includeSemanticDuplicates
        self.semanticSimilarityThreshold = semanticSimilarityThreshold
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
            self.settings = decoded
        } else {
            self.settings = DuplicateSettings()
        }
    }
    
    public func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
    
    public func reset() {
        settings = DuplicateSettings()
        save()
    }
}

//
//  LearningsModels.swift
//  Sorty
//
//  Core data models for "The Learnings" feature - trainable, example-based file organization
//

import Foundation

// MARK: - Labeled Example

/// A single src → dst mapping provided by user (from manual organization or explicit labeling)
public struct LabeledExample: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let srcPath: String
    public let dstPath: String
    public let metadata: [String: String]?
    public let action: ExampleAction
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        srcPath: String,
        dstPath: String,
        metadata: [String: String]? = nil,
        action: ExampleAction = .accept,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.srcPath = srcPath
        self.dstPath = dstPath
        self.metadata = metadata
        self.action = action
        self.timestamp = timestamp
    }
}

/// Action that created the labeled example
public enum ExampleAction: String, Codable, Sendable {
    case accept        // User accepted a proposal
    case edit          // User edited a proposal
    case reject        // User rejected a proposal
    case addToExamples // User explicitly added to examples
}

// MARK: - Inferred Rule

/// A regex + template rule learned from examples
/// Enhanced with success/failure tracking and enable/disable controls
public struct InferredRule: Codable, Identifiable, Sendable {
    public let id: String
    public let pattern: String           // Regex pattern
    public let template: String           // Output template with placeholders
    public let metadataCues: [String]     // e.g., ["exif:DateTimeOriginal", "fs:ctime"]
    public var priority: Int              // Higher = more specific/preferred (0-100)
    public let exampleIds: [String]       // IDs of examples that contributed to this rule
    public let explanation: String        // Human-readable explanation
    
    // Quality tracking
    public var successCount: Int          // Times applied without correction
    public var failureCount: Int          // Times user corrected after applying
    public var isEnabled: Bool            // Can be toggled by user
    public var lastAppliedAt: Date?       // Last time this rule was used
    public var supportCount: Int          // Number of examples supporting this rule
    
    /// Calculate failure rate for quality assessment
    public var failureRate: Double {
        let total = successCount + failureCount
        guard total > 0 else { return 0 }
        return Double(failureCount) / Double(total)
    }
    
    /// Confidence level based on support and failure rate
    public var confidenceLevel: RuleConfidence {
        if failureRate > 0.3 { return .low }
        if supportCount >= 5 && failureRate < 0.1 { return .high }
        return .medium
    }
    
    public init(
        id: String = UUID().uuidString,
        pattern: String,
        template: String,
        metadataCues: [String] = [],
        priority: Int = 0,
        exampleIds: [String] = [],
        explanation: String,
        successCount: Int = 0,
        failureCount: Int = 0,
        isEnabled: Bool = true,
        lastAppliedAt: Date? = nil,
        supportCount: Int = 1
    ) {
        self.id = id
        self.pattern = pattern
        self.template = template
        self.metadataCues = metadataCues
        self.priority = priority
        self.exampleIds = exampleIds
        self.explanation = explanation
        self.successCount = successCount
        self.failureCount = failureCount
        self.isEnabled = isEnabled
        self.lastAppliedAt = lastAppliedAt
        self.supportCount = supportCount
    }
}

public enum RuleConfidence: String, Codable, Sendable {
    case high, medium, low
}

// MARK: - Proposed Mapping

/// A single file's proposed destination
public struct ProposedMapping: Codable, Identifiable, Sendable {
    public let id: String
    public let srcPath: String
    public let proposedDstPath: String
    public let ruleId: String?
    public let confidence: Double         // 0.0 - 1.0
    public let explanation: String
    public let alternatives: [AlternativeMapping]
    
    public init(
        id: String = UUID().uuidString,
        srcPath: String,
        proposedDstPath: String,
        ruleId: String? = nil,
        confidence: Double,
        explanation: String,
        alternatives: [AlternativeMapping] = []
    ) {
        self.id = id
        self.srcPath = srcPath
        self.proposedDstPath = proposedDstPath
        self.ruleId = ruleId
        self.confidence = confidence
        self.explanation = explanation
        self.alternatives = alternatives
    }
    
    /// Confidence category for UI display
    public var confidenceLevel: ConfidenceLevel {
        if confidence >= 0.8 { return .high }
        if confidence >= 0.5 { return .medium }
        return .low
    }
}

public struct AlternativeMapping: Codable, Sendable {
    public let proposedDstPath: String
    public let confidence: Double
    public let explanation: String
    
    public init(proposedDstPath: String, confidence: Double, explanation: String) {
        self.proposedDstPath = proposedDstPath
        self.confidence = confidence
        self.explanation = explanation
    }
}

public enum ConfidenceLevel: String, Codable, Sendable {
    case high, medium, low
    
    public var color: String {
        switch self {
        case .high: return "green"
        case .medium: return "orange"
        case .low: return "red"
        }
    }
}

// MARK: - Confidence Summary

/// Distribution of confidence levels in analysis
public struct ConfidenceSummary: Codable, Sendable {
    public let high: Int
    public let medium: Int
    public let low: Int
    
    public init(high: Int, medium: Int, low: Int) {
        self.high = high
        self.medium = medium
        self.low = low
    }
    
    public var total: Int { high + medium + low }
}

// MARK: - Conflict

/// Naming collision detected during analysis
public struct MappingConflict: Codable, Sendable {
    public let srcPaths: [String]
    public let proposedDstPath: String
    public let suggestedResolution: ConflictResolution
    
    public init(srcPaths: [String], proposedDstPath: String, suggestedResolution: ConflictResolution) {
        self.srcPaths = srcPaths
        self.proposedDstPath = proposedDstPath
        self.suggestedResolution = suggestedResolution
    }
}

public enum ConflictResolution: String, Codable, Sendable {
    case autoSuffix  // Append _1, _2, etc.
    case keepBoth    // Keep source filename if conflict
    case prompt      // Ask user to resolve
}

// MARK: - Staged Plan

/// One stage of staged execution
public struct StagedPlanStep: Codable, Sendable {
    public let stageDescription: String
    public let folderExamples: [String]
    public let estimatedCount: Int
    public let riskLevel: RiskLevel
    
    public init(stageDescription: String, folderExamples: [String], estimatedCount: Int, riskLevel: RiskLevel) {
        self.stageDescription = stageDescription
        self.folderExamples = folderExamples
        self.estimatedCount = estimatedCount
        self.riskLevel = riskLevel
    }
}

public enum RiskLevel: String, Codable, Sendable {
    case low, medium, high
}

// MARK: - Analysis Result

/// Full analysis result (matches required output schema)
public struct LearningsAnalysisResult: Codable, Sendable {
    public let inferredRules: [InferredRule]
    public let proposedMappings: [ProposedMapping]
    public let stagedPlan: [StagedPlanStep]
    public let confidenceSummary: ConfidenceSummary
    public let conflicts: [MappingConflict]
    public let jobManifestTemplate: String
    public let humanSummary: [String]
    
    public init(
        inferredRules: [InferredRule],
        proposedMappings: [ProposedMapping],
        stagedPlan: [StagedPlanStep] = [],
        confidenceSummary: ConfidenceSummary,
        conflicts: [MappingConflict] = [],
        jobManifestTemplate: String = "",
        humanSummary: [String] = []
    ) {
        self.inferredRules = inferredRules
        self.proposedMappings = proposedMappings
        self.stagedPlan = stagedPlan
        self.confidenceSummary = confidenceSummary
        self.conflicts = conflicts
        self.jobManifestTemplate = jobManifestTemplate
        self.humanSummary = humanSummary
    }
    
    /// Export to JSON for preview
    public func toJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

// MARK: - File Type Classification

/// Classification of files for pattern matching
public enum FileCategory: String, Codable, Sendable, CaseIterable {
    case photo
    case video
    case music
    case document
    case archive
    case code
    case other
    
    /// File extensions for this category
    public var extensions: [String] {
        switch self {
        case .photo:
            return ["jpg", "jpeg", "png", "gif", "heic", "heif", "raw", "cr2", "nef", "arw", "dng", "tiff", "tif", "webp"]
        case .video:
            return ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpg", "mpeg", "3gp"]
        case .music:
            return ["mp3", "m4a", "flac", "wav", "aac", "ogg", "wma", "aiff", "alac"]
        case .document:
            return ["pdf", "doc", "docx", "txt", "rtf", "odt", "pages", "xls", "xlsx", "ppt", "pptx", "md"]
        case .archive:
            return ["zip", "rar", "7z", "tar", "gz", "bz2", "dmg", "iso"]
        case .code:
            return ["swift", "py", "js", "ts", "java", "cpp", "c", "h", "go", "rs", "rb", "php", "html", "css", "json", "xml", "yaml", "yml"]
        case .other:
            return []
        }
    }
    
    /// Determine category from file extension
    public static func from(extension ext: String) -> FileCategory {
        let lowered = ext.lowercased()
        for category in FileCategory.allCases where category != .other {
            if category.extensions.contains(lowered) {
                return category
            }
        }
        return .other
    }
}

// MARK: - Behavior Preferences

/// User's explicit organization philosophy derived from honing and behavior
public struct BehaviorPreferences: Codable, Sendable, Equatable {
    public var deletionVsArchive: DeletionPreference
    public var folderDepthPreference: FolderDepthPreference
    public var dateVsContentPreference: OrganizationAxis
    public var duplicateKeeperStrategy: DuplicateKeeperStrategy
    
    public init(
        deletionVsArchive: DeletionPreference = .archive,
        folderDepthPreference: FolderDepthPreference = .balanced,
        dateVsContentPreference: OrganizationAxis = .content,
        duplicateKeeperStrategy: DuplicateKeeperStrategy = .keepNewest
    ) {
        self.deletionVsArchive = deletionVsArchive
        self.folderDepthPreference = folderDepthPreference
        self.dateVsContentPreference = dateVsContentPreference
        self.duplicateKeeperStrategy = duplicateKeeperStrategy
    }
}

public enum DeletionPreference: String, Codable, Sendable, CaseIterable {
    case delete = "delete"
    case archive = "archive"
    case archiveByYear = "archive_by_year"
    
    public var displayName: String {
        switch self {
        case .delete: return "Delete old files"
        case .archive: return "Archive to folder"
        case .archiveByYear: return "Archive by year"
        }
    }
}

public enum FolderDepthPreference: String, Codable, Sendable, CaseIterable {
    case flat = "flat"
    case balanced = "balanced"
    case deep = "deep"
    
    public var displayName: String {
        switch self {
        case .flat: return "Flat structure"
        case .balanced: return "2-3 levels deep"
        case .deep: return "Deep hierarchy"
        }
    }
}

public enum OrganizationAxis: String, Codable, Sendable, CaseIterable {
    case date = "date"
    case content = "content"
    case project = "project"
    case hybrid = "hybrid"
    
    public var displayName: String {
        switch self {
        case .date: return "Date-based"
        case .content: return "Content-based"
        case .project: return "Project-based"
        case .hybrid: return "Hybrid approach"
        }
    }
}

public enum DuplicateKeeperStrategy: String, Codable, Sendable, CaseIterable {
    case keepNewest = "keep_newest"
    case keepOldest = "keep_oldest"
    case keepInPrimaryFolder = "keep_primary"
    case askEachTime = "ask"
    
    public var displayName: String {
        switch self {
        case .keepNewest: return "Keep newest"
        case .keepOldest: return "Keep oldest"
        case .keepInPrimaryFolder: return "Keep in main folder"
        case .askEachTime: return "Ask each time"
        }
    }
}

// MARK: - Learnings Impact Summary

/// Summary of how learnings have affected organization results
public struct LearningsImpactSummary: Sendable {
    public let runsWithLearnings: Int
    public let totalRuns: Int
    public let filesRoutedByLearnings: Int
    public let correctionsAfterAI: Int
    public let reverts: Int
    
    public var correctionRate: Double {
        guard filesRoutedByLearnings > 0 else { return 0 }
        return Double(correctionsAfterAI) / Double(filesRoutedByLearnings)
    }
    
    public var revertRate: Double {
        guard runsWithLearnings > 0 else { return 0 }
        return Double(reverts) / Double(runsWithLearnings)
    }
    
    public var successRate: Double {
        return max(0, 1.0 - correctionRate - revertRate * 0.5)
    }
    
    public init(
        runsWithLearnings: Int = 0,
        totalRuns: Int = 0,
        filesRoutedByLearnings: Int = 0,
        correctionsAfterAI: Int = 0,
        reverts: Int = 0
    ) {
        self.runsWithLearnings = runsWithLearnings
        self.totalRuns = totalRuns
        self.filesRoutedByLearnings = filesRoutedByLearnings
        self.correctionsAfterAI = correctionsAfterAI
        self.reverts = reverts
    }
}

// MARK: - Utilities

extension Sequence where Element: Hashable {
    /// Returns a new array with unique elements, preserving original order
    public func orderedDeduplicated() -> [Element] {
        var set = Set<Element>()
        return filter { set.insert($0).inserted }
    }
}

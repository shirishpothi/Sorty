//
//  LearningsModels.swift
//  FileOrganizer
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
public struct InferredRule: Codable, Identifiable, Sendable {
    public let id: String
    public let pattern: String           // Regex pattern
    public let template: String           // Output template with placeholders
    public let metadataCues: [String]     // e.g., ["exif:DateTimeOriginal", "fs:ctime"]
    public let priority: Int              // Higher = more specific/preferred
    public let exampleIds: [String]       // IDs of examples that contributed to this rule
    public let explanation: String        // Human-readable explanation
    
    public init(
        id: String = UUID().uuidString,
        pattern: String,
        template: String,
        metadataCues: [String] = [],
        priority: Int = 0,
        exampleIds: [String] = [],
        explanation: String
    ) {
        self.id = id
        self.pattern = pattern
        self.template = template
        self.metadataCues = metadataCues
        self.priority = priority
        self.exampleIds = exampleIds
        self.explanation = explanation
    }
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

//
//  LearningsProfile.swift
//  Sorty
//
//  Single source of truth for user learnings.
//  Persisted as UserProfile.learning (encrypted JSON).
//

import Foundation

public struct LearningsProfile: Codable, Sendable {
    /// Timestamp of when this profile was created
    public let createdAt: Date
    
    // MARK: - Consent
    
    /// Whether user has consented to data collection
    public var consentGranted: Bool
    
    /// When consent was granted
    public var consentDate: Date?
    
    // MARK: - User Behavior Tracking
    
    /// History of additional instructions user has provided
    public var additionalInstructionsHistory: [UserInstruction]
    
    /// History of guiding instructions (for next attempt)
    public var guidingInstructionsHistory: [UserInstruction]
    
    /// Steering prompts (post-organization feedback)
    public var steeringPrompts: [SteeringPrompt]
    
    /// Directory changes user made after AI organization
    public var postOrganizationChanges: [DirectoryChange]
    
    /// History reverts the user has performed
    public var historyReverts: [RevertEvent]
    
    // MARK: - Existing Properties
    
    /// User's philosophical preferences derived from Honing sessions
    public var honingAnswers: [HoningAnswer]
    
    /// Global rules inferred from all past interactions
    public var inferredRules: [InferredRule]
    
    /// Log of manual corrections (User moved A -> B, overriding AI)
    public var corrections: [LabeledExample]
    
    /// Log of rejected operations (User reverted session)
    public var rejections: [LabeledExample]
    
    /// Examples of good organization (User manually filed files correctly)
    public var positiveExamples: [LabeledExample]
    
    /// History of applied jobs (for rollback)
    public var jobHistory: [JobManifest]
    
    public init(
        createdAt: Date = Date(),
        consentGranted: Bool = false,
        consentDate: Date? = nil,
        additionalInstructionsHistory: [UserInstruction] = [],
        guidingInstructionsHistory: [UserInstruction] = [],
        steeringPrompts: [SteeringPrompt] = [],
        postOrganizationChanges: [DirectoryChange] = [],
        historyReverts: [RevertEvent] = [],
        honingAnswers: [HoningAnswer] = [],
        inferredRules: [InferredRule] = [],
        corrections: [LabeledExample] = [],
        rejections: [LabeledExample] = [],
        positiveExamples: [LabeledExample] = [],
        jobHistory: [JobManifest] = []
    ) {
        self.createdAt = createdAt
        self.consentGranted = consentGranted
        self.consentDate = consentDate
        self.additionalInstructionsHistory = additionalInstructionsHistory
        self.guidingInstructionsHistory = guidingInstructionsHistory
        self.steeringPrompts = steeringPrompts
        self.postOrganizationChanges = postOrganizationChanges
        self.historyReverts = historyReverts
        self.honingAnswers = honingAnswers
        self.inferredRules = inferredRules
        self.corrections = corrections
        self.rejections = rejections
        self.positiveExamples = positiveExamples
        self.jobHistory = jobHistory
    }
}

// MARK: - Behavior Tracking Models

/// Represents a user instruction (additional or guiding)
public struct UserInstruction: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let instruction: String
    public let context: String?  // e.g., folder path or organization context
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        instruction: String,
        context: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.instruction = instruction
        self.context = context
    }
}

/// Represents a directory change made by user after AI organization
public struct DirectoryChange: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let originalPath: String
    public let newPath: String
    public let wasAIOrganized: Bool
    public let aiSessionId: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        originalPath: String,
        newPath: String,
        wasAIOrganized: Bool,
        aiSessionId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalPath = originalPath
        self.newPath = newPath
        self.wasAIOrganized = wasAIOrganized
        self.aiSessionId = aiSessionId
    }
}

/// Represents a history revert event
public struct RevertEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let entryId: String
    public let operationCount: Int
    public let folderPath: String?
    public let reason: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        entryId: String,
        operationCount: Int,
        folderPath: String? = nil,
        reason: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.entryId = entryId
        self.operationCount = operationCount
        self.folderPath = folderPath
        self.reason = reason
    }
}

/// Represents a steering prompt (post-organization instruction)
public struct SteeringPrompt: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let prompt: String
    public let folderPath: String?
    public let sessionId: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        prompt: String,
        folderPath: String? = nil,
        sessionId: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.prompt = prompt
        self.folderPath = folderPath
        self.sessionId = sessionId
    }
}

// MARK: - Options

/// Options for learnings analysis
public struct LearningsOptions: Codable, Sendable {
    public var dryRun: Bool
    public var stagedApply: Bool
    public var sampleSize: Int
    public var backupMode: BackupMode
    public var confidenceThreshold: Double
    
    public init(
        dryRun: Bool = true,
        stagedApply: Bool = true,
        sampleSize: Int = 50,
        backupMode: BackupMode = .copyToBackupDir,
        confidenceThreshold: Double = 0.7
    ) {
        self.dryRun = dryRun
        self.stagedApply = stagedApply
        self.sampleSize = sampleSize
        self.backupMode = backupMode
        self.confidenceThreshold = confidenceThreshold
    }
}

public enum BackupMode: String, Codable, Sendable, CaseIterable {
    case none
    case moveToBackupDir
    case copyToBackupDir
    
    public var displayName: String {
        switch self {
        case .none: return "No Backup"
        case .moveToBackupDir: return "Move to Backup Directory"
        case .copyToBackupDir: return "Copy to Backup Directory"
        }
    }
}

// MARK: - Job Manifest

/// Manifest for a single apply job (for rollback)
public struct JobManifest: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let entries: [JobManifestEntry]
    public let projectName: String
    public let backupMode: BackupMode
    public var status: JobStatus
    
    public init(
        id: String = UUID().uuidString,
        projectName: String = "User Profile",
        entries: [JobManifestEntry] = [],
        backupMode: BackupMode = .copyToBackupDir,
        status: JobStatus = .pending
    ) {
        self.id = id
        self.timestamp = Date()
        self.projectName = projectName
        self.entries = entries
        self.backupMode = backupMode
        self.status = status
    }
    
    /// Total files in this job
    public var fileCount: Int { entries.count }
    
    /// Files that were successfully moved
    public var successCount: Int {
        entries.filter { $0.status == .success }.count
    }
}

public struct JobManifestEntry: Codable, Sendable {
    public let originalPath: String
    public let destinationPath: String
    public let backupPath: String?
    public let checksum: String?
    public var status: EntryStatus
    
    public init(
        originalPath: String,
        destinationPath: String,
        backupPath: String? = nil,
        checksum: String? = nil,
        status: EntryStatus = .pending
    ) {
        self.originalPath = originalPath
        self.destinationPath = destinationPath
        self.backupPath = backupPath
        self.checksum = checksum
        self.status = status
    }
}

public enum JobStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case rolledBack
}

public enum EntryStatus: String, Codable, Sendable {
    case pending
    case success
    case failed
    case skipped
    case rolledBack
}



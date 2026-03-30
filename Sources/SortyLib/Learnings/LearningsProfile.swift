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

    /// Rename outcomes the user accepted/edited/rejected from AI suggestions
    public var renameFeedbackHistory: [RenameFeedbackEvent]
    
    /// History reverts the user has performed
    public var historyReverts: [RevertEvent]
    
    /// Cancelled organization sessions (user cancelled before applying)
    public var cancelledOrganizations: [CancelledOrganization]
    
    /// Regenerated organization sessions (user wasn't satisfied with first result)
    public var regeneratedOrganizations: [RegeneratedOrganization]
    
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
    
    /// Rejected rule IDs with cooldown timestamps (ruleId -> cooldown end date)
    public var rejectedRuleCooldowns: [String: Date]
    
    /// Paths excluded from learning
    public var learningExclusionPatterns: [String]
    
    /// Whether session-based learning is enabled (don't persist learnings from this session)
    public var sessionLearningEnabled: Bool

    /// Session-centric timeline of organization behavior and feedback.
    /// Legacy arrays remain for compatibility while callers migrate.
    public var sessions: [OrganizationSession]
    
    /// Answers to inline post-organization learning moments
    public var inlineLearningMomentAnswers: [InlineLearningMomentAnswer]
    
    public init(
        createdAt: Date = Date(),
        consentGranted: Bool = false,
        consentDate: Date? = nil,
        additionalInstructionsHistory: [UserInstruction] = [],
        guidingInstructionsHistory: [UserInstruction] = [],
        steeringPrompts: [SteeringPrompt] = [],
        postOrganizationChanges: [DirectoryChange] = [],
        renameFeedbackHistory: [RenameFeedbackEvent] = [],
        historyReverts: [RevertEvent] = [],
        cancelledOrganizations: [CancelledOrganization] = [],
        regeneratedOrganizations: [RegeneratedOrganization] = [],
        honingAnswers: [HoningAnswer] = [],
        inferredRules: [InferredRule] = [],
        corrections: [LabeledExample] = [],
        rejections: [LabeledExample] = [],
        positiveExamples: [LabeledExample] = [],
        jobHistory: [JobManifest] = [],
        rejectedRuleCooldowns: [String: Date] = [:],
        learningExclusionPatterns: [String] = [],
        sessionLearningEnabled: Bool = true,
        sessions: [OrganizationSession] = [],
        inlineLearningMomentAnswers: [InlineLearningMomentAnswer] = []
    ) {
        self.createdAt = createdAt
        self.consentGranted = consentGranted
        self.consentDate = consentDate
        self.additionalInstructionsHistory = additionalInstructionsHistory
        self.guidingInstructionsHistory = guidingInstructionsHistory
        self.steeringPrompts = steeringPrompts
        self.postOrganizationChanges = postOrganizationChanges
        self.renameFeedbackHistory = renameFeedbackHistory
        self.historyReverts = historyReverts
        self.cancelledOrganizations = cancelledOrganizations
        self.regeneratedOrganizations = regeneratedOrganizations
        self.honingAnswers = honingAnswers
        self.inferredRules = inferredRules
        self.corrections = corrections
        self.rejections = rejections
        self.positiveExamples = positiveExamples
        self.jobHistory = jobHistory
        self.rejectedRuleCooldowns = rejectedRuleCooldowns
        self.learningExclusionPatterns = learningExclusionPatterns
        self.sessionLearningEnabled = sessionLearningEnabled
        self.sessions = sessions
        self.inlineLearningMomentAnswers = inlineLearningMomentAnswers
    }

    private enum CodingKeys: String, CodingKey {
        case createdAt
        case consentGranted
        case consentDate
        case additionalInstructionsHistory
        case guidingInstructionsHistory
        case steeringPrompts
        case postOrganizationChanges
        case renameFeedbackHistory
        case historyReverts
        case cancelledOrganizations
        case regeneratedOrganizations
        case honingAnswers
        case inferredRules
        case corrections
        case rejections
        case positiveExamples
        case jobHistory
        case rejectedRuleCooldowns
        case learningExclusionPatterns
        case sessionLearningEnabled
        case sessions
        case inlineLearningMomentAnswers
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        consentGranted = try container.decodeIfPresent(Bool.self, forKey: .consentGranted) ?? false
        consentDate = try container.decodeIfPresent(Date.self, forKey: .consentDate)
        additionalInstructionsHistory = try container.decodeIfPresent([UserInstruction].self, forKey: .additionalInstructionsHistory) ?? []
        guidingInstructionsHistory = try container.decodeIfPresent([UserInstruction].self, forKey: .guidingInstructionsHistory) ?? []
        steeringPrompts = try container.decodeIfPresent([SteeringPrompt].self, forKey: .steeringPrompts) ?? []
        postOrganizationChanges = try container.decodeIfPresent([DirectoryChange].self, forKey: .postOrganizationChanges) ?? []
        renameFeedbackHistory = try container.decodeIfPresent([RenameFeedbackEvent].self, forKey: .renameFeedbackHistory) ?? []
        historyReverts = try container.decodeIfPresent([RevertEvent].self, forKey: .historyReverts) ?? []
        cancelledOrganizations = try container.decodeIfPresent([CancelledOrganization].self, forKey: .cancelledOrganizations) ?? []
        regeneratedOrganizations = try container.decodeIfPresent([RegeneratedOrganization].self, forKey: .regeneratedOrganizations) ?? []
        honingAnswers = try container.decodeIfPresent([HoningAnswer].self, forKey: .honingAnswers) ?? []
        inferredRules = try container.decodeIfPresent([InferredRule].self, forKey: .inferredRules) ?? []
        corrections = try container.decodeIfPresent([LabeledExample].self, forKey: .corrections) ?? []
        rejections = try container.decodeIfPresent([LabeledExample].self, forKey: .rejections) ?? []
        positiveExamples = try container.decodeIfPresent([LabeledExample].self, forKey: .positiveExamples) ?? []
        jobHistory = try container.decodeIfPresent([JobManifest].self, forKey: .jobHistory) ?? []
        rejectedRuleCooldowns = try container.decodeIfPresent([String: Date].self, forKey: .rejectedRuleCooldowns) ?? [:]
        learningExclusionPatterns = try container.decodeIfPresent([String].self, forKey: .learningExclusionPatterns) ?? []
        sessionLearningEnabled = try container.decodeIfPresent(Bool.self, forKey: .sessionLearningEnabled) ?? true
        sessions = try container.decodeIfPresent([OrganizationSession].self, forKey: .sessions) ?? []
        inlineLearningMomentAnswers = try container.decodeIfPresent([InlineLearningMomentAnswer].self, forKey: .inlineLearningMomentAnswers) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(consentGranted, forKey: .consentGranted)
        try container.encodeIfPresent(consentDate, forKey: .consentDate)
        try container.encode(additionalInstructionsHistory, forKey: .additionalInstructionsHistory)
        try container.encode(guidingInstructionsHistory, forKey: .guidingInstructionsHistory)
        try container.encode(steeringPrompts, forKey: .steeringPrompts)
        try container.encode(postOrganizationChanges, forKey: .postOrganizationChanges)
        try container.encode(renameFeedbackHistory, forKey: .renameFeedbackHistory)
        try container.encode(historyReverts, forKey: .historyReverts)
        try container.encode(cancelledOrganizations, forKey: .cancelledOrganizations)
        try container.encode(regeneratedOrganizations, forKey: .regeneratedOrganizations)
        try container.encode(honingAnswers, forKey: .honingAnswers)
        try container.encode(inferredRules, forKey: .inferredRules)
        try container.encode(corrections, forKey: .corrections)
        try container.encode(rejections, forKey: .rejections)
        try container.encode(positiveExamples, forKey: .positiveExamples)
        try container.encode(jobHistory, forKey: .jobHistory)
        try container.encode(rejectedRuleCooldowns, forKey: .rejectedRuleCooldowns)
        try container.encode(learningExclusionPatterns, forKey: .learningExclusionPatterns)
        try container.encode(sessionLearningEnabled, forKey: .sessionLearningEnabled)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(inlineLearningMomentAnswers, forKey: .inlineLearningMomentAnswers)
    }
}

// MARK: - Behavior Tracking Models

/// Represents a user instruction (additional or guiding)
public struct UserInstruction: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let instruction: String
    public let context: String?  // e.g., folder path or organization context
    public let folderPath: String?
    public let fileCount: Int?
    public let isRegeneration: Bool?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        instruction: String,
        context: String? = nil,
        folderPath: String? = nil,
        fileCount: Int? = nil,
        isRegeneration: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.instruction = instruction
        self.context = context
        self.folderPath = folderPath
        self.fileCount = fileCount
        self.isRegeneration = isRegeneration
    }
}

/// Represents a cancelled organization session with rich context for learning
public struct CancelledOrganization: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let folderPath: String
    public let fileCount: Int
    public let proposedFolderCount: Int
    public let instructions: String?
    public let cancelledAtStage: String
    
    // Enhanced fields for richer learning
    public let proposedFolderNames: [String]?
    public let proposedStructureSummary: String?
    public let fileExtensionCounts: [String: Int]?
    public let regenerationCount: Int
    public let regenerationInstructions: [String]?
    public let aiModel: String?
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        folderPath: String,
        fileCount: Int,
        proposedFolderCount: Int,
        instructions: String? = nil,
        cancelledAtStage: String,
        proposedFolderNames: [String]? = nil,
        proposedStructureSummary: String? = nil,
        fileExtensionCounts: [String: Int]? = nil,
        regenerationCount: Int = 0,
        regenerationInstructions: [String]? = nil,
        aiModel: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.folderPath = folderPath
        self.fileCount = fileCount
        self.proposedFolderCount = proposedFolderCount
        self.instructions = instructions
        self.cancelledAtStage = cancelledAtStage
        self.proposedFolderNames = proposedFolderNames
        self.proposedStructureSummary = proposedStructureSummary
        self.fileExtensionCounts = fileExtensionCounts
        self.regenerationCount = regenerationCount
        self.regenerationInstructions = regenerationInstructions
        self.aiModel = aiModel
    }
}

/// Represents a regenerated organization session
public struct RegeneratedOrganization: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let folderPath: String
    public let previousPlanSummary: String?
    public let guidingInstruction: String?
    public let regenerationCount: Int
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        folderPath: String,
        previousPlanSummary: String? = nil,
        guidingInstruction: String? = nil,
        regenerationCount: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.folderPath = folderPath
        self.previousPlanSummary = previousPlanSummary
        self.guidingInstruction = guidingInstruction
        self.regenerationCount = regenerationCount
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

public struct RenameFeedbackEvent: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let originalName: String
    public let suggestedName: String?
    public let finalName: String?
    public let folderPath: String?
    public let action: ExampleAction
    public let confidence: Double?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        originalName: String,
        suggestedName: String?,
        finalName: String?,
        folderPath: String? = nil,
        action: ExampleAction,
        confidence: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.originalName = originalName
        self.suggestedName = suggestedName
        self.finalName = finalName
        self.folderPath = folderPath
        self.action = action
        self.confidence = confidence
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

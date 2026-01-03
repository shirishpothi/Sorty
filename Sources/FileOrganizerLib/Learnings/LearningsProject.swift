//
//  LearningsProject.swift
//  FileOrganizer
//
//  Project persistence model for "The Learnings" feature
//

import Foundation

// MARK: - Project

/// A learnings project with all examples, rules, and history
public struct LearningsProject: Codable, Sendable {
    public var name: String
    public var rootPaths: [String]
    public var exampleFolders: [String]
    public var labeledExamples: [LabeledExample]
    public var inferredRules: [InferredRule]
    public var options: LearningsOptions
    public var jobHistory: [JobManifest]
    public let createdAt: Date
    public var modifiedAt: Date
    
    public init(
        name: String,
        rootPaths: [String] = [],
        exampleFolders: [String] = [],
        labeledExamples: [LabeledExample] = [],
        inferredRules: [InferredRule] = [],
        options: LearningsOptions = LearningsOptions(),
        jobHistory: [JobManifest] = []
    ) {
        self.name = name
        self.rootPaths = rootPaths
        self.exampleFolders = exampleFolders
        self.labeledExamples = labeledExamples
        self.inferredRules = inferredRules
        self.options = options
        self.jobHistory = jobHistory
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    /// Mark project as modified
    public mutating func touch() {
        modifiedAt = Date()
    }
    
    /// Add a labeled example
    public mutating func addExample(_ example: LabeledExample) {
        labeledExamples.append(example)
        touch()
    }
    
    /// Update inferred rules
    public mutating func updateRules(_ rules: [InferredRule]) {
        inferredRules = rules
        touch()
    }
    
    /// Add job to history
    public mutating func addJob(_ job: JobManifest) {
        jobHistory.append(job)
        touch()
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
        projectName: String,
        entries: [JobManifestEntry],
        backupMode: BackupMode,
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

// MARK: - Persistence

/// Manager for loading/saving learnings projects
public actor LearningsProjectStore {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Default directory for storing projects
    public var projectsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FileOrganizer/Learnings/Projects", isDirectory: true)
    }
    
    /// Ensure projects directory exists
    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: projectsDirectory.path) {
            try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Save project to disk
    public func save(_ project: LearningsProject) async throws {
        try ensureDirectoryExists()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(project)
        let filename = project.name.replacingOccurrences(of: " ", with: "_").lowercased() + ".json"
        let url = projectsDirectory.appendingPathComponent(filename)
        
        try data.write(to: url, options: .atomicWrite)
        DebugLogger.log("Saved project '\(project.name)' to \(url.path)")
    }
    
    /// Load project from disk
    public func load(name: String) async throws -> LearningsProject {
        let filename = name.replacingOccurrences(of: " ", with: "_").lowercased() + ".json"
        let url = projectsDirectory.appendingPathComponent(filename)
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode(LearningsProject.self, from: data)
    }
    
    /// List all projects
    public func listProjects() async throws -> [String] {
        try ensureDirectoryExists()
        
        let contents = try fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)
        return contents
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").capitalized }
    }
    
    /// Delete a project
    public func delete(name: String) async throws {
        let filename = name.replacingOccurrences(of: " ", with: "_").lowercased() + ".json"
        let url = projectsDirectory.appendingPathComponent(filename)
        try fileManager.removeItem(at: url)
    }
}

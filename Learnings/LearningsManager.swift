//
//  LearningsManager.swift
//  FileOrganizer
//
//  Observable manager coordinating all learnings functionality
//

import Foundation
import SwiftUI

/// Main manager for "The Learnings" feature
@MainActor
public class LearningsManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var currentProject: LearningsProject?
    @Published public var isLoading: Bool = false
    @Published public var error: String?
    @Published public var analysisResult: LearningsAnalysisResult?
    
    // MARK: - Dependencies
    
    public let analyzer = LearningsAnalyzer()
    private let projectStore = LearningsProjectStore()
    
    public init() {}
    
    // MARK: - Project Management
    
    /// Create a new project
    public func createProject(name: String, rootPaths: [String]) {
        currentProject = LearningsProject(
            name: name,
            rootPaths: rootPaths
        )
        analysisResult = nil
    }
    
    /// Load an existing project
    public func loadProject(name: String) async {
        isLoading = true
        error = nil
        
        do {
            currentProject = try await projectStore.load(name: name)
        } catch {
            self.error = "Failed to load project: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// Save current project
    public func saveProject() async {
        guard let project = currentProject else { return }
        
        isLoading = true
        error = nil
        
        do {
            try await projectStore.save(project)
        } catch {
            self.error = "Failed to save project: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// List all saved projects
    public func listProjects() async -> [String] {
        do {
            return try await projectStore.listProjects()
        } catch {
            self.error = "Failed to list projects: \(error.localizedDescription)"
            return []
        }
    }
    
    // MARK: - Example Management
    
    /// Add an example folder
    public func addExampleFolder(_ path: String) {
        currentProject?.exampleFolders.append(path)
        currentProject?.touch()
    }
    
    /// Remove an example folder
    public func removeExampleFolder(at index: Int) {
        currentProject?.exampleFolders.remove(at: index)
        currentProject?.touch()
    }
    
    /// Add a root path
    public func addRootPath(_ path: String) {
        currentProject?.rootPaths.append(path)
        currentProject?.touch()
    }
    
    /// Remove a root path
    public func removeRootPath(at index: Int) {
        currentProject?.rootPaths.remove(at: index)
        currentProject?.touch()
    }
    
    /// Add a labeled example from user action
    public func addLabeledExample(srcPath: String, dstPath: String, action: LabelAction) {
        let example = LabeledExample(
            srcPath: srcPath,
            dstPath: dstPath,
            action: action
        )
        currentProject?.addExample(example)
    }
    
    // MARK: - Analysis
    
    /// Run analysis on current project
    public func analyze() async {
        guard let project = currentProject else {
            error = "No project loaded"
            return
        }
        
        error = nil
        
        do {
            analysisResult = try await analyzer.analyze(project: project)
            
            // Update project with inferred rules
            if let result = analysisResult {
                currentProject?.updateRules(result.inferredRules)
            }
        } catch {
            self.error = "Analysis failed: \(error.localizedDescription)"
        }
    }
    
    /// Accept a proposed mapping
    public func acceptMapping(_ mapping: ProposedMapping) {
        addLabeledExample(
            srcPath: mapping.srcPath,
            dstPath: mapping.proposedDstPath,
            action: .accept
        )
    }
    
    /// Reject a proposed mapping
    public func rejectMapping(_ mapping: ProposedMapping) {
        addLabeledExample(
            srcPath: mapping.srcPath,
            dstPath: mapping.srcPath,  // Keep in place
            action: .reject
        )
    }
    
    /// Edit a proposed mapping
    public func editMapping(_ mapping: ProposedMapping, newDstPath: String) {
        addLabeledExample(
            srcPath: mapping.srcPath,
            dstPath: newDstPath,
            action: .edit
        )
    }
    
    // MARK: - Export
    
    /// Export preview to JSON file
    public func exportPreview(to url: URL) async throws {
        guard let result = analysisResult else {
            throw LearningsError.noAnalysisResult
        }
        
        let data = try result.toJSON()
        try data.write(to: url)
    }
    
    /// Export rules to JSON file
    public func exportRules(to url: URL) async throws {
        guard let project = currentProject else {
            throw LearningsError.noProject
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(project.inferredRules)
        try data.write(to: url)
    }
    
    // MARK: - Apply & Rollback
    
    @Published public var applyProgress: Double = 0
    @Published public var isApplying: Bool = false
    @Published public var lastJobId: String?
    
    /// Apply proposed mappings with optional backup
    public func applyMappings(backupDirectory: URL?, onlyHighConfidence: Bool = false) async {
        guard let project = currentProject, let result = analysisResult else {
            error = "No project or analysis result"
            return
        }
        
        isApplying = true
        applyProgress = 0
        error = nil
        
        let fm = FileManager.default
        let backupMode: BackupMode = backupDirectory != nil ? .copyToBackupDir : .none
        
        // Filter mappings based on confidence
        let mappingsToApply = result.proposedMappings.filter {
            !onlyHighConfidence || $0.confidenceLevel == .high
        }
        
        var entries: [JobManifestEntry] = []
        var successCount = 0
        var failCount = 0
        
        for (index, mapping) in mappingsToApply.enumerated() {
            do {
                var backupPath: String?
                
                // Create backup if needed
                if let backupDir = backupDirectory {
                    backupPath = backupDir.appendingPathComponent(
                        "\(UUID().uuidString)_\(URL(fileURLWithPath: mapping.srcPath).lastPathComponent)"
                    ).path
                    
                    try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                    try fm.copyItem(atPath: mapping.srcPath, toPath: backupPath!)
                }
                
                // Create destination directory
                let destDir = URL(fileURLWithPath: mapping.proposedDstPath).deletingLastPathComponent()
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                
                // Move file
                try fm.moveItem(atPath: mapping.srcPath, toPath: mapping.proposedDstPath)
                
                entries.append(JobManifestEntry(
                    originalPath: mapping.srcPath,
                    destinationPath: mapping.proposedDstPath,
                    backupPath: backupPath,
                    status: .success
                ))
                successCount += 1
            } catch {
                entries.append(JobManifestEntry(
                    originalPath: mapping.srcPath,
                    destinationPath: mapping.proposedDstPath,
                    status: .failed
                ))
                failCount += 1
            }
            
            applyProgress = Double(index + 1) / Double(mappingsToApply.count)
        }
        
        // Save job manifest
        let job = JobManifest(
            projectName: project.name,
            entries: entries,
            backupMode: backupMode,
            status: .completed
        )
        currentProject?.addJob(job)
        lastJobId = job.id
        
        await saveProject()
        
        isApplying = false
        applyProgress = 1.0
        
        if failCount > 0 {
            self.error = "Applied \(successCount) files, \(failCount) failed"
        }
    }
    
    /// Rollback a job by its ID
    public func rollbackJob(jobId: String) async {
        guard let project = currentProject else {
            error = "No project loaded"
            return
        }
        
        guard let job = project.jobHistory.first(where: { $0.id == jobId }) else {
            error = "Job not found: \(jobId)"
            return
        }
        
        isApplying = true
        applyProgress = 0
        error = nil
        
        let fm = FileManager.default
        var successCount = 0
        var failCount = 0
        
        for (index, entry) in job.entries.enumerated() {
            do {
                if let backupPath = entry.backupPath, fm.fileExists(atPath: backupPath) {
                    // Remove current destination
                    if fm.fileExists(atPath: entry.destinationPath) {
                        try fm.removeItem(atPath: entry.destinationPath)
                    }
                    // Restore from backup
                    try fm.moveItem(atPath: backupPath, toPath: entry.originalPath)
                } else if fm.fileExists(atPath: entry.destinationPath) {
                    // Move back without backup
                    try fm.moveItem(atPath: entry.destinationPath, toPath: entry.originalPath)
                }
                successCount += 1
            } catch {
                failCount += 1
            }
            
            applyProgress = Double(index + 1) / Double(job.entries.count)
        }
        
        // Update job status
        if let jobIndex = project.jobHistory.firstIndex(where: { $0.id == jobId }) {
            currentProject?.jobHistory[jobIndex].status = .rolledBack
            await saveProject()
        }
        
        isApplying = false
        applyProgress = 1.0
        
        if failCount > 0 {
            self.error = "Rolled back \(successCount) files, \(failCount) failed"
        }
    }
}

// MARK: - Errors

public enum LearningsError: LocalizedError {
    case noProject
    case noAnalysisResult
    case saveFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noProject:
            return "No project is currently loaded"
        case .noAnalysisResult:
            return "No analysis result available. Run analysis first."
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        }
    }
}

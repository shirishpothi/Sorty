//
//  LearningsManager.swift
//  FileOrganizer
//
//  Observable manager coordinating all learnings functionality
//  Enhanced with secure storage, consent management, and behavior tracking
//

import Foundation
import SwiftUI

/// Main manager for "The Learnings" feature
@MainActor
public class LearningsManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var currentProfile: LearningsProfile?
    @Published public var isLoading: Bool = false
    @Published public var error: String?
    @Published public var analysisResult: LearningsAnalysisResult?
    
    // Security & Consent
    @Published public var isLocked: Bool = true
    @Published public var requiresInitialSetup: Bool = false
    @Published public var showingImportPicker: Bool = false
    public let securityManager = SecurityManager()
    public let consentManager = LearningsConsentManager()
    
    // MARK: - Dependencies
    
    public let analyzer = LearningsAnalyzer()
    
    public init() {
        // Check if initial setup is required
        requiresInitialSetup = !consentManager.hasCompletedInitialSetup
    }
    
    public func configure(with config: AIConfig) {
        do {
            let client = try AIClientFactory.createClient(config: config)
            analyzer.configure(aiClient: client)
        } catch {
            self.error = "Failed to configure AI: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Security & Authentication
    
    /// Unlock with Touch ID / password (required after initial setup)
    public func unlock() async {
        // If initial setup not complete, skip authentication
        if requiresInitialSetup {
            isLocked = false
            await loadProfile()
            return
        }
        
        await securityManager.authenticateForLearningsAccess()
        isLocked = !securityManager.isUnlocked
        if !isLocked {
            await loadProfile()
        }
    }
    
    public func lock() {
        securityManager.lock()
        isLocked = true
        currentProfile = nil
        analysisResult = nil
    }
    
    /// Complete initial setup - future access will require Touch ID
    public func completeInitialSetup() {
        consentManager.completeInitialSetup()
        requiresInitialSetup = false
    }
    
    // MARK: - Consent Management
    
    /// Grant consent for data collection
    public func grantConsent() async {
        consentManager.grantConsent()
        
        if var profile = currentProfile {
            profile.consentGranted = true
            profile.consentDate = Date()
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Withdraw consent
    public func withdrawConsent() async {
        consentManager.withdrawConsent()
        
        if var profile = currentProfile {
            profile.consentGranted = false
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Delete all learning data securely
    public func clearAllData() async {
        guard !isLocked else { return }
        
        do {
            try await consentManager.deleteAllData()
            try LearningsFileManager.secureDelete()
            currentProfile = LearningsProfile() // Reset to empty
            analysisResult = nil
            requiresInitialSetup = true
        } catch {
            self.error = "Failed to clear data: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Secure Profile Storage
    
    private func loadProfile() async {
        isLoading = true
        do {
            if let profile = try LearningsFileManager.load() {
                currentProfile = profile
            } else {
                currentProfile = LearningsProfile()
            }
        } catch {
            self.error = "Failed to load profile: \(error.localizedDescription)"
            currentProfile = LearningsProfile()
        }
        isLoading = false
    }
    
    private func saveProfile() async {
        guard let profile = currentProfile else { return }
        do {
            try LearningsFileManager.save(profile: profile)
        } catch {
            self.error = "Failed to save profile: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Behavior Tracking
    
    /// Record additional instructions provided by user
    public func recordAdditionalInstruction(_ instruction: String, for folderPath: String) {
        guard consentManager.canCollectData, var profile = currentProfile else { return }
        
        let userInstruction = UserInstruction(
            instruction: instruction,
            context: folderPath
        )
        profile.additionalInstructionsHistory.append(userInstruction)
        currentProfile = profile
        Task { await saveProfile() }
    }
    
    /// Record guiding instructions for next attempt
    public func recordGuidingInstruction(_ instruction: String) {
        guard consentManager.canCollectData, var profile = currentProfile else { return }
        
        let userInstruction = UserInstruction(
            instruction: instruction,
            context: "guiding_instruction"
        )
        profile.guidingInstructionsHistory.append(userInstruction)
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a steering prompt (post-organization feedback)
    public func recordSteeringPrompt(_ prompt: String, folderPath: String?, sessionId: String?) {
        guard consentManager.canCollectData, var profile = currentProfile else { return }
        
        let steeringPrompt = SteeringPrompt(
            prompt: prompt,
            folderPath: folderPath,
            sessionId: sessionId
        )
        profile.steeringPrompts.append(steeringPrompt)
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a directory change made after AI organization
    public func recordDirectoryChange(from original: String, to new: String, wasAIOrganized: Bool, sessionId: String? = nil) {
        guard consentManager.canCollectData, var profile = currentProfile else { return }
        
        let change = DirectoryChange(
            originalPath: original,
            newPath: new,
            wasAIOrganized: wasAIOrganized,
            aiSessionId: sessionId
        )
        profile.postOrganizationChanges.append(change)
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a history revert event
    public func recordHistoryRevert(entryId: String, operationCount: Int, folderPath: String? = nil, revertReason: String? = nil) {
        guard consentManager.canCollectData, var profile = currentProfile else { return }
        
        let event = RevertEvent(
            entryId: entryId,
            operationCount: operationCount,
            folderPath: folderPath,
            reason: revertReason
        )
        profile.historyReverts.append(event)
        currentProfile = profile
        debouncedSave()
    }
    
    // MARK: - Debounced Saving
    
    private var saveDebounceTimer: Timer?
    private let saveDebounceInterval: TimeInterval = 2.0 // 2 seconds
    
    /// Debounced save to prevent rapid successive writes
    private func debouncedSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: saveDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.saveProfile()
            }
        }
    }
    
    /// Force immediate save (for critical operations)
    public func forceSave() async {
        saveDebounceTimer?.invalidate()
        await saveProfile()
    }
    
    // MARK: - Feedback Loop (Continuous Learning)
    
    /// Record a manual correction (File moved manually after AI organization)
    public func recordCorrection(originalPath: String, newPath: String) {
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: originalPath,
            dstPath: newPath,
            action: .edit
        )
        profile.corrections.append(example)
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a rejection (File reverted or explicitly rejected)
    public func recordRejection(originalPath: String) {
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: originalPath,
            dstPath: originalPath,
            action: .reject
        )
        profile.rejections.append(example)
        currentProfile = profile
        Task { await saveProfile() }
    }
    
    // MARK: - Legacy Project Method Removals
    // Removing createProject, loadProject, saveProject (replaced by saveProfile), listProjects
    
    // MARK: - Example Management
    
    // MARK: - Path Management
    // Removed legacy project folder paths. Learnings now operates globally on user behavior.
    
    /// Add a positive example (User organized correctly)
    public func addPositiveExample(srcPath: String, dstPath: String) {
        addLabeledExample(srcPath: srcPath, dstPath: dstPath, action: .accept)
    }
    
    /// Internal helper to add a labeled example
    public func addLabeledExample(srcPath: String, dstPath: String, action: ExampleAction) {
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: srcPath,
            dstPath: dstPath,
            action: action
        )
        
        switch action {
        case .accept:
            profile.positiveExamples.append(example)
        case .reject:
            profile.rejections.append(example)
        case .edit:
            profile.corrections.append(example)
        default:
            break
        }
        
        currentProfile = profile
        Task { await saveProfile() }
    }
    
    // MARK: - Analysis
    
    /// Run analysis on current profile and paths
    public func analyze(rootPaths: [String], examplePaths: [String]) async {
        guard let profile = currentProfile else {
            error = "No profile loaded"
            return
        }
        
        error = nil
        
        do {
            analysisResult = try await analyzer.analyze(
                profile: profile,
                rootPaths: rootPaths,
                examplePaths: examplePaths
            )
            
            // Update profile with inferred rules?
            // Maybe we only update profile rules if the user APPLIES the changes?
            // Or we treat "Inferred Rules" as a transient analysis artifact until confirmed?
            // For now, let's update them so they persist as "current understanding"
            if let result = analysisResult {
                var updatedProfile = profile
                updatedProfile.inferredRules = result.inferredRules
                currentProfile = updatedProfile
                await saveProfile()
            }
        } catch {
            self.error = "Analysis failed: \(error.localizedDescription)"
        }
    }
    
    /// Save results from a Honing Session
    public func saveHoningResults(_ answers: [HoningAnswer]) async {
        guard var profile = currentProfile else { return }
        
        var existing = profile.honingAnswers
        for newAns in answers {
            if let idx = existing.firstIndex(where: { $0.questionId == newAns.questionId }) {
                existing[idx] = newAns
            } else {
                existing.append(newAns)
            }
        }
        profile.honingAnswers = existing
        currentProfile = profile
        await saveProfile()
        
        // Trigger re-analysis or just update rules
        // For now, we just save. The UI might trigger re-analysis.
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
        guard let profile = currentProfile else {
            throw LearningsError.noProject
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(profile.inferredRules)
        try data.write(to: url)
    }
    
    // MARK: - Import
    
    /// Import profile from file
    public func importProfile(from url: URL) async throws {
        guard !isLocked else { return }
        
        // Start accessing security scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            throw LearningsError.saveFailed("Permission denied to access file")
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let profile = try decoder.decode(LearningsProfile.self, from: data)
        currentProfile = profile
        await saveProfile()
    }
    
    // MARK: - Apply & Rollback
    
    @Published public var applyProgress: Double = 0
    @Published public var isApplying: Bool = false
    @Published public var lastJobId: String?
    
    /// Apply proposed mappings with optional backup
    public func applyMappings(backupDirectory: URL?, onlyHighConfidence: Bool = false) async {
        guard var profile = currentProfile, let result = analysisResult else {
            error = "No profile or analysis result"
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
            projectName: "User Profile",
            entries: entries,
            backupMode: backupMode,
            status: .completed
        )
        
        // Append to profile history
        profile.jobHistory.append(job)
        currentProfile = profile
        lastJobId = job.id
        
        await saveProfile()
        
        isApplying = false
        applyProgress = 1.0
        
        if failCount > 0 {
            self.error = "Applied \(successCount) files, \(failCount) failed"
        }
    }
    
    /// Rollback a job by its ID
    public func rollbackJob(jobId: String) async {
        guard var profile = currentProfile else {
            error = "No profile loaded"
            return
        }
        
        guard let job = profile.jobHistory.first(where: { $0.id == jobId }) else {
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
        if let jobIndex = profile.jobHistory.firstIndex(where: { $0.id == jobId }) {
            profile.jobHistory[jobIndex].status = .rolledBack
            currentProfile = profile
            await saveProfile()
        }
        
        isApplying = false
        applyProgress = 1.0
        
        if failCount > 0 {
            self.error = "Rolled back \(successCount) files, \(failCount) failed"
        }
    }
    // MARK: - Prompt Context Generation
    
    /// Generates a prompt context string based on the current profile
    /// This is the bridge between learned data and the AI organization engine
    public func generatePromptContext() -> String {
        guard let profile = currentProfile, profile.consentGranted else {
            return ""
        }
        
        var context = "Based on the user's past behavior and explicit preferences, follow these rules:\n"
        var hasContent = false
        
        // 1. Honing Answers (High Priority - Explicit preferences)
        if !profile.honingAnswers.isEmpty {
            context += "\nPREFERENCES (User-confirmed philosophy):\n"
            for answer in profile.honingAnswers {
                context += "- \(answer.selectedOption)\n"
            }
            hasContent = true
        }
        
        // 2. Steering Prompts (High Priority - Post-organization feedback)
        // Weight recent prompts more heavily (last 10)
        let recentSteering = profile.steeringPrompts.suffix(10)
        if !recentSteering.isEmpty {
            context += "\nRECENT FEEDBACK (Apply these adjustments):\n"
            for prompt in recentSteering {
                context += "- \(prompt.prompt)\n"
            }
            hasContent = true
        }
        
        // 3. Additional Instructions (Explicit User Commands)
        // Take unique latest 5 instructions to keep context concise
        let uniqueInstructions = Array(Set(profile.additionalInstructionsHistory.map { $0.instruction })).suffix(5)
        if !uniqueInstructions.isEmpty {
            context += "\nUSER INSTRUCTIONS:\n"
            for instruction in uniqueInstructions {
                context += "- \(instruction)\n"
            }
            hasContent = true
        }
        
        // 4. Guiding Instructions (Pre-organization feedback)
        let uniqueGuidingInstructions = Array(Set(profile.guidingInstructionsHistory.map { $0.instruction })).suffix(5)
        if !uniqueGuidingInstructions.isEmpty {
            context += "\nGUIDING INSTRUCTIONS:\n"
            for instruction in uniqueGuidingInstructions {
                context += "- \(instruction)\n"
            }
            hasContent = true
        }
        
        // 5. Inferred Rules (Derived from analysis)
        // Only include high priority or recently validated rules
        let relevantRules = profile.inferredRules.sorted { $0.priority > $1.priority }.prefix(5)
        if !relevantRules.isEmpty {
            context += "\nLEARNED PATTERNS:\n"
            for rule in relevantRules {
                context += "- \(rule.explanation)\n"
            }
            hasContent = true
        }
        
        // 6. Recent Corrections (User explicitly corrected AI - weighted by recency)
        let recentCorrections = profile.postOrganizationChanges
            .filter { $0.wasAIOrganized }
            .suffix(10)
        if !recentCorrections.isEmpty {
            context += "\nRECENT CORRECTIONS (Avoid repeating these mistakes):\n"
            for change in recentCorrections {
                let srcFolder = URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent
                let dstFolder = URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
                let fileName = URL(fileURLWithPath: change.originalPath).lastPathComponent
                context += "- User moved '\(fileName)' from '\(srcFolder)/' to '\(dstFolder)/'\n"
            }
            hasContent = true
        }
        
        // 7. Revert Patterns (If many reverts, be more conservative)
        let recentReverts = profile.historyReverts.suffix(5)
        if recentReverts.count >= 3 {
            context += "\nNOTE: User has reverted \(recentReverts.count) recent organizations. Be more conservative and ask for confirmation on uncertain categorizations.\n"
            hasContent = true
        }
        
        return hasContent ? context : ""
    }
    
    /// Generate contextual honing questions based on recent learnings
    public func generateContextualHoningTopics() -> [String] {
        guard let profile = currentProfile else { return [] }
        
        var topics: [String] = []
        
        // Analyze recent corrections to find patterns
        let recentCorrections = profile.postOrganizationChanges.suffix(20)
        var folderTypes = Set<String>()
        
        for change in recentCorrections {
            let srcFolder = URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent
            let dstFolder = URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
            if srcFolder != dstFolder {
                folderTypes.insert(dstFolder)
            }
        }
        
        // Generate questions based on common patterns
        if folderTypes.contains(where: { $0.lowercased().contains("archive") }) {
            topics.append("archiving_strategy")
        }
        if folderTypes.contains(where: { $0.lowercased().contains("project") }) {
            topics.append("project_organization")
        }
        if folderTypes.count > 5 {
            topics.append("folder_depth_preference")
        }
        
        // Check for steering prompt patterns
        let steeringKeywords = profile.steeringPrompts.flatMap { $0.prompt.lowercased().components(separatedBy: " ") }
        if steeringKeywords.contains("date") || steeringKeywords.contains("year") {
            topics.append("date_based_organization")
        }
        if steeringKeywords.contains("type") || steeringKeywords.contains("extension") {
            topics.append("file_type_organization")
        }
        
        return topics
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

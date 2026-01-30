//
//  LearningsManager.swift
//  Sorty
//
//  Observable manager coordinating all learnings functionality
//  Enhanced with secure storage, consent management, and behavior tracking
//

import Foundation
import SwiftUI
import Combine

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
    
    // Learning Controls
    @Published public var learningStrength: Double = 0.5 {
        didSet {
            UserDefaults.standard.set(learningStrength, forKey: "learningStrength")
        }
    }
    @Published public var behaviorPreferences: BehaviorPreferences?
    
    // MARK: - Dependencies
    
    public let analyzer = LearningsAnalyzer()
    
    public init() {
        // Check if initial setup is required
        requiresInitialSetup = !consentManager.hasCompletedInitialSetup
        // Load learning strength from UserDefaults
        learningStrength = UserDefaults.standard.double(forKey: "learningStrength")
        if learningStrength == 0 { learningStrength = 0.5 } // Default if not set
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
    
    /// Load profile synchronously for background collection (without authentication)
    /// This allows data collection to work even when the UI is locked
    private func loadProfileIfNeededForCollection() {
        guard currentProfile == nil else { return }
        
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
    public func recordAdditionalInstruction(_ instruction: String, for folderPath: String, fileCount: Int? = nil) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let userInstruction = UserInstruction(
            instruction: instruction,
            context: "pre_organization",
            folderPath: folderPath,
            fileCount: fileCount,
            isRegeneration: false
        )
        profile.additionalInstructionsHistory.append(userInstruction)
        currentProfile = profile
        Task { await saveProfile() }
    }
    
    /// Record guiding instructions for next attempt
    public func recordGuidingInstruction(_ instruction: String, for folderPath: String? = nil, fileCount: Int? = nil) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let userInstruction = UserInstruction(
            instruction: instruction,
            context: "regeneration",
            folderPath: folderPath,
            fileCount: fileCount,
            isRegeneration: true
        )
        profile.guidingInstructionsHistory.append(userInstruction)
        currentProfile = profile
        debouncedSave()
    }

    /// Record a cancelled organization session with rich context for learning
    public func recordCancelledOrganization(
        folderPath: String,
        fileCount: Int,
        proposedFolderCount: Int,
        instructions: String? = nil,
        stage: String,
        proposedFolderNames: [String]? = nil,
        proposedStructureSummary: String? = nil,
        fileExtensionCounts: [String: Int]? = nil,
        regenerationCount: Int = 0,
        regenerationInstructions: [String]? = nil,
        aiModel: String? = nil
    ) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let cancelled = CancelledOrganization(
            folderPath: folderPath,
            fileCount: fileCount,
            proposedFolderCount: proposedFolderCount,
            instructions: instructions,
            cancelledAtStage: stage,
            proposedFolderNames: proposedFolderNames,
            proposedStructureSummary: proposedStructureSummary,
            fileExtensionCounts: fileExtensionCounts,
            regenerationCount: regenerationCount,
            regenerationInstructions: regenerationInstructions,
            aiModel: aiModel
        )
        profile.cancelledOrganizations.append(cancelled)
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a regenerated organization session
    public func recordRegeneratedOrganization(folderPath: String, previousPlanSummary: String? = nil, guidingInstruction: String? = nil, regenerationCount: Int) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let regenerated = RegeneratedOrganization(
            folderPath: folderPath,
            previousPlanSummary: previousPlanSummary,
            guidingInstruction: guidingInstruction,
            regenerationCount: regenerationCount
        )
        profile.regeneratedOrganizations.append(regenerated)
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a steering prompt (post-organization feedback)
    public func recordSteeringPrompt(_ prompt: String, folderPath: String?, sessionId: String?) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
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
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
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
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
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
    
    private var saveTask: Task<Void, Never>?
    private let saveDebounceInterval: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    
    /// Debounced save to prevent rapid successive writes
    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounceInterval)
            guard !Task.isCancelled else { return }
            await saveProfile()
        }
    }
    
    /// Force immediate save (for critical operations)
    public func forceSave() async {
        saveTask?.cancel()
        pruneOldData()
        await saveProfile()
    }
    
    /// Caps history arrays at 100 items to prevent bloat
    private func pruneOldData() {
        guard var profile = currentProfile else { return }
        
        let cap = 100
        if profile.additionalInstructionsHistory.count > cap {
            profile.additionalInstructionsHistory = Array(profile.additionalInstructionsHistory.suffix(cap))
        }
        if profile.guidingInstructionsHistory.count > cap {
            profile.guidingInstructionsHistory = Array(profile.guidingInstructionsHistory.suffix(cap))
        }
        if profile.steeringPrompts.count > cap {
            profile.steeringPrompts = Array(profile.steeringPrompts.suffix(cap))
        }
        if profile.postOrganizationChanges.count > cap {
            profile.postOrganizationChanges = Array(profile.postOrganizationChanges.suffix(cap))
        }
        if profile.historyReverts.count > cap {
            profile.historyReverts = Array(profile.historyReverts.suffix(cap))
        }
        if profile.positiveExamples.count > cap {
            profile.positiveExamples = Array(profile.positiveExamples.suffix(cap))
        }
        if profile.rejections.count > cap {
            profile.rejections = Array(profile.rejections.suffix(cap))
        }
        if profile.corrections.count > cap {
            profile.corrections = Array(profile.corrections.suffix(cap))
        }
        if profile.jobHistory.count > cap {
            profile.jobHistory = Array(profile.jobHistory.suffix(cap))
        }
        if profile.cancelledOrganizations.count > cap {
            profile.cancelledOrganizations = Array(profile.cancelledOrganizations.suffix(cap))
        }
        if profile.regeneratedOrganizations.count > cap {
            profile.regeneratedOrganizations = Array(profile.regeneratedOrganizations.suffix(cap))
        }
        
        currentProfile = profile
    }
    
    // MARK: - Feedback Loop (Continuous Learning)
    
    /// Record a manual correction (File moved manually after AI organization)
    public func recordCorrection(originalPath: String, newPath: String) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: originalPath,
            dstPath: newPath,
            action: .edit
        )
        profile.corrections.append(example)
        currentProfile = profile
        debouncedSave()
        
        // Trigger auto-inference check after recording correction
        Task { await checkAndTriggerAutoInference() }
    }
    
    /// Record a rejection (File reverted or explicitly rejected)
    public func recordRejection(originalPath: String) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: originalPath,
            dstPath: originalPath,
            action: .reject
        )
        profile.rejections.append(example)
        currentProfile = profile
        Task { 
            await saveProfile() 
            await checkAndTriggerAutoInference()
        }
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
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
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
        Task { 
            await saveProfile()
            // Trigger auto-inference check after adding example
            await checkAndTriggerAutoInference()
        }
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
    /// Uses weighted priorities: Explicit preferences > High-confidence rules > Recent feedback > General patterns
    public func generatePromptContext() -> String {
        guard let profile = currentProfile, profile.consentGranted else {
            return ""
        }
        
        var context = "Based on the user's past behavior and explicit preferences, follow these rules (sorted by priority):\n"
        var hasContent = false
        
        // Priority 1 (Weight: CRITICAL) - Honing Answers (Explicit user preferences)
        if !profile.honingAnswers.isEmpty {
            context += "\n## CRITICAL PREFERENCES (User-confirmed, always follow):\n"
            for answer in profile.honingAnswers {
                context += "- ✓ \(answer.selectedOption)\n"
            }
            hasContent = true
        }
        
        // Priority 1.5 (Weight: HIGH) - Behavior Preferences (Structural preferences from honing)
        extractBehaviorPreferences()
        if let prefs = behaviorPreferences {
            var prefsContent: [String] = []
            prefsContent.append("- Deletion policy: \(prefs.deletionVsArchive.displayName)")
            prefsContent.append("- Folder structure: \(prefs.folderDepthPreference.displayName)")
            prefsContent.append("- Primary organization: \(prefs.dateVsContentPreference.displayName)")
            prefsContent.append("- Duplicate handling: \(prefs.duplicateKeeperStrategy.displayName)")
            
            // Only add if we have meaningful (non-default) preferences
            if prefs != BehaviorPreferences() {
                context += "\n## STRUCTURAL PREFERENCES (User's organization philosophy):\n"
                for pref in prefsContent {
                    context += "\(pref)\n"
                }
                hasContent = true
            }
        }
        
        // Priority 2 (Weight: HIGH) - High-confidence inferred rules
        let highConfidenceRules = getActiveRules().filter { 
            $0.confidenceLevel == .high && $0.successRate > 0.7 
        }
        if !highConfidenceRules.isEmpty {
            context += "\n## HIGH-CONFIDENCE RULES (Proven patterns, strongly follow):\n"
            for rule in highConfidenceRules.prefix(5) {
                let successPct = Int(rule.successRate * 100)
                context += "- [\(successPct)% success] \(rule.explanation)\n"
            }
            hasContent = true
        }
        
        // Priority 3 (Weight: MEDIUM-HIGH) - Recent steering prompts (post-org feedback)
        let recentSteering = profile.steeringPrompts.suffix(5)
        if !recentSteering.isEmpty {
            context += "\n## RECENT FEEDBACK (Apply these adjustments):\n"
            for prompt in recentSteering {
                context += "- \(prompt.prompt)\n"
            }
            hasContent = true
        }
        
        // Priority 4 (Weight: MEDIUM) - Additional Instructions (Explicit user commands)
        let uniqueInstructions = profile.additionalInstructionsHistory
            .map { $0.instruction }
            .orderedDeduplicated()
            .suffix(3)
        if !uniqueInstructions.isEmpty {
            context += "\n## USER INSTRUCTIONS:\n"
            for instruction in uniqueInstructions {
                context += "- \(instruction)\n"
            }
            hasContent = true
        }
        
        // Priority 5 (Weight: MEDIUM) - Guiding Instructions (Pre-organization feedback)
        let uniqueGuidingInstructions = profile.guidingInstructionsHistory
            .map { $0.instruction }
            .orderedDeduplicated()
            .suffix(3)
        if !uniqueGuidingInstructions.isEmpty {
            context += "\n## GUIDING INSTRUCTIONS:\n"
            for instruction in uniqueGuidingInstructions {
                context += "- \(instruction)\n"
            }
            hasContent = true
        }
        
        // Priority 5.5 (Weight: MEDIUM) - Patterns from Regenerations
        let recentRegenerations = profile.regeneratedOrganizations.suffix(5)
        if !recentRegenerations.isEmpty {
            context += "\n## REGENERATION PATTERNS (User requested changes previously):\n"
            for regen in recentRegenerations {
                if let guide = regen.guidingInstruction, !guide.isEmpty {
                    context += "- When seeing '\(regen.previousPlanSummary ?? "previous structure")', user preferred: \(guide)\n"
                }
            }
            hasContent = true
        }

        // Priority 5.6 (Weight: MEDIUM) - Patterns from Cancellations
        let recentCancellations = profile.cancelledOrganizations.suffix(5)
        if !recentCancellations.isEmpty {
            context += "\n## AVOID THESE STRUCTURES (User cancelled these types of plans):\n"
            var cancelledSummaries: [String] = []
            for cancel in recentCancellations {
                if let instr = cancel.instructions, !instr.isEmpty {
                    cancelledSummaries.append("Plan with instructions '\(instr)' at stage \(cancel.cancelledAtStage)")
                }
            }
            for summary in Set(cancelledSummaries).prefix(3) {
                context += "- AVOID: \(summary)\n"
            }
            hasContent = true
        }
        
        // Priority 6 (Weight: LOW-MEDIUM) - Medium-confidence rules
        let mediumConfidenceRules = getActiveRules().filter { 
            $0.confidenceLevel == .medium || ($0.confidenceLevel == .high && $0.successRate <= 0.7)
        }
        if !mediumConfidenceRules.isEmpty {
            context += "\n## LEARNED PATTERNS (Consider these tendencies):\n"
            for rule in mediumConfidenceRules.prefix(5) {
                let confidence = rule.confidenceLevel.rawValue.capitalized
                context += "- [\(confidence)] \(rule.explanation)\n"
            }
            hasContent = true
        }
        
        // Priority 6.5 (Weight: MEDIUM) - Positive Examples (What user explicitly likes)
        let recentPositives = profile.positiveExamples.suffix(15)
        if !recentPositives.isEmpty {
            context += "\n## POSITIVE PATTERNS (User explicitly approves these placements):\n"
            // Group by destination folder for cleaner output
            var positivePatterns: [String: [(file: String, ext: String)]] = [:]
            for example in recentPositives {
                let srcFile = URL(fileURLWithPath: example.srcPath).lastPathComponent
                let dstFolder = URL(fileURLWithPath: example.dstPath).deletingLastPathComponent().lastPathComponent
                let ext = URL(fileURLWithPath: example.srcPath).pathExtension.lowercased()
                positivePatterns[dstFolder, default: []].append((file: srcFile, ext: ext))
            }
            
            for (folder, files) in positivePatterns.prefix(5) {
                // Group by extension within folder
                let extCounts = Dictionary(grouping: files) { $0.ext }.mapValues { $0.count }
                let topExtensions = extCounts.sorted { $0.value > $1.value }.prefix(2)
                let extList = topExtensions.map { ".\($0.key)" }.joined(separator: ", ")
                if !extList.isEmpty {
                    context += "- '\(folder)/' is good for: \(extList) files (\(files.count) examples)\n"
                } else {
                    context += "- '\(folder)/' is an approved destination (\(files.count) examples)\n"
                }
            }
            hasContent = true
        }
        
        // Priority 7 (Weight: HIGH for corrections) - Recent corrections (MUST avoid repeating)
        let recentCorrections = profile.postOrganizationChanges
            .filter { $0.wasAIOrganized }
            .suffix(10)
        if !recentCorrections.isEmpty {
            context += "\n## CORRECTIONS (IMPORTANT - Avoid repeating these mistakes):\n"
            // Group corrections by pattern for clearer guidance
            var correctionPatterns: [String: [(from: String, to: String)]] = [:]
            for change in recentCorrections {
                let srcFolder = URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent
                let dstFolder = URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
                let ext = URL(fileURLWithPath: change.originalPath).pathExtension.lowercased()
                let key = ext.isEmpty ? "misc" : ext
                correctionPatterns[key, default: []].append((from: srcFolder, to: dstFolder))
            }
            
            for (fileType, moves) in correctionPatterns.prefix(5) {
                let uniqueMoves = Dictionary(grouping: moves) { "\($0.from)->\($0.to)" }
                for (_, group) in uniqueMoves.prefix(2) {
                    if let move = group.first {
                        context += "- .\(fileType) files: User prefers '\(move.to)/' over '\(move.from)/'\n"
                    }
                }
            }
            hasContent = true
        }
        
        // Priority 7.5 (Weight: HIGH) - Rejection Patterns (AVOID these placements)
        let recentRejections = profile.rejections.suffix(10)
        if !recentRejections.isEmpty {
            context += "\n## REJECTION PATTERNS (AVOID these - user explicitly rejected):\n"
            var rejectionPatterns: [String: Int] = [:]
            for rejection in recentRejections {
                let ext = URL(fileURLWithPath: rejection.srcPath).pathExtension.lowercased()
                let folder = URL(fileURLWithPath: rejection.dstPath).deletingLastPathComponent().lastPathComponent
                if !folder.isEmpty {
                    let pattern = ext.isEmpty ? "files → \(folder)" : ".\(ext) → \(folder)"
                    rejectionPatterns[pattern, default: 0] += 1
                }
            }
            for (pattern, count) in rejectionPatterns.sorted(by: { $0.value > $1.value }).prefix(5) {
                context += "- DO NOT place \(pattern) (rejected \(count)x)\n"
            }
            hasContent = true
        }
        
        // Priority 8 (Weight: ADVISORY) - Revert patterns
        let recentReverts = profile.historyReverts.suffix(5)
        if recentReverts.count >= 2 {
            context += "\n## CAUTION: User has reverted \(recentReverts.count) recent organizations. Be more conservative.\n"
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
    
    // MARK: - Impact Metrics
    
    /// Compute a summary of how learnings have affected organization results
    public func computeImpactSummary(lastNRuns: Int = 10) -> LearningsImpactSummary? {
        guard let profile = currentProfile else { return nil }
        
        // Count runs with learnings (based on whether we had rules/preferences at the time)
        let totalRuns = profile.jobHistory.count
        let runsWithLearnings = profile.jobHistory.filter { $0.status == .completed }.count
        
        // Files routed by learnings (estimate from successful rule applications)
        let filesRoutedByLearnings = profile.inferredRules.reduce(0) { $0 + $1.successCount }
        
        // Corrections after AI
        let correctionsAfterAI = profile.postOrganizationChanges.filter { $0.wasAIOrganized }.count
        
        // Reverts
        let reverts = profile.historyReverts.count
        
        return LearningsImpactSummary(
            runsWithLearnings: runsWithLearnings,
            totalRuns: totalRuns,
            filesRoutedByLearnings: filesRoutedByLearnings,
            correctionsAfterAI: correctionsAfterAI,
            reverts: reverts
        )
    }
    
    // MARK: - Rule Management
    
    /// Enable or disable a specific inferred rule
    public func setRuleEnabled(ruleId: String, enabled: Bool) async {
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].isEnabled = enabled
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Record a rule success (applied and no correction followed)
    public func recordRuleSuccess(ruleId: String) {
        guard consentManager.canCollectData else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].successCount += 1
            profile.inferredRules[index].lastAppliedAt = Date()
            currentProfile = profile
            debouncedSave()
        }
    }
    
    /// Record a rule failure (applied but user corrected)
    public func recordRuleFailure(ruleId: String) {
        guard consentManager.canCollectData else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].failureCount += 1
            
            // Auto-disable rules with high failure rate
            let rule = profile.inferredRules[index]
            if rule.failureRate > 0.3 && (rule.successCount + rule.failureCount) >= 5 {
                profile.inferredRules[index].isEnabled = false
                DebugLogger.log("Auto-disabled rule '\(rule.explanation)' due to high failure rate")
            }
            
            currentProfile = profile
            debouncedSave()
        }
    }
    
    /// Get active rules filtered by learning strength
    public func getActiveRules() -> [InferredRule] {
        guard let profile = currentProfile else { return [] }
        
        // Filter enabled rules
        var activeRules = profile.inferredRules.filter { $0.isEnabled }
        
        // Sort by priority
        activeRules.sort { $0.priority > $1.priority }
        
        // Apply learning strength to limit number of rules
        let maxRules = Int(Double(activeRules.count) * learningStrength) + 1
        return Array(activeRules.prefix(maxRules))
    }
    
    /// Extract behavior preferences from honing answers
    public func extractBehaviorPreferences() {
        guard let profile = currentProfile else { return }
        
        var prefs = BehaviorPreferences()
        
        for answer in profile.honingAnswers {
            let option = answer.selectedOption.lowercased()
            
            // Map answers to preferences based on keywords
            if option.contains("archive") && option.contains("year") {
                prefs.deletionVsArchive = .archiveByYear
            } else if option.contains("archive") {
                prefs.deletionVsArchive = .archive
            } else if option.contains("delete") {
                prefs.deletionVsArchive = .delete
            }
            
            if option.contains("flat") {
                prefs.folderDepthPreference = .flat
            } else if option.contains("deep") || option.contains("hierarchy") {
                prefs.folderDepthPreference = .deep
            }
            
            if option.contains("date") || option.contains("year") || option.contains("month") {
                prefs.dateVsContentPreference = .date
            } else if option.contains("project") {
                prefs.dateVsContentPreference = .project
            } else if option.contains("content") || option.contains("type") {
                prefs.dateVsContentPreference = .content
            }
            
            if option.contains("newest") || option.contains("recent") {
                prefs.duplicateKeeperStrategy = .keepNewest
            } else if option.contains("oldest") || option.contains("original") {
                prefs.duplicateKeeperStrategy = .keepOldest
            }
        }
        
        behaviorPreferences = prefs
    }
}

// MARK: - Errors

public enum LearningsError: LocalizedError {
    case noProject
    case noAnalysisResult
    case emptyRootPaths
    case saveFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noProject:
            return "No project is currently loaded"
        case .noAnalysisResult:
            return "No analysis result available. Run analysis first."
        case .emptyRootPaths:
            return "No root paths provided for analysis"
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        }
    }
}

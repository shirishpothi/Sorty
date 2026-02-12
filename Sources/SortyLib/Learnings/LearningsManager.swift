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
            userDefaults.set(learningStrength, forKey: "learningStrength")
        }
    }
    @Published public var useAIForLearnings: Bool = true {
        didSet {
            userDefaults.set(useAIForLearnings, forKey: "useAIForLearnings")
        }
    }
    @Published public var sessionLearningPaused: Bool = false
    @Published public var behaviorPreferences: BehaviorPreferences?

    /// Suggestions for files that should be added to exceptions (e.g., related project files)
    @Published public var pendingExceptionSuggestions: [ExceptionSuggestion] = []

    public struct ExceptionSuggestion: Identifiable {
        public let id = UUID()
        public let message: String
        public let fileNames: [String]
        public let groupName: String
    }
    
    @Published public var dataRetentionDays: Int = 0 {
        didSet {
            userDefaults.set(dataRetentionDays, forKey: "learningDataRetentionDays")
        }
    }
    
    // MARK: - Dependencies
    
    private let userDefaults: UserDefaults
    public let analyzer = LearningsAnalyzer()
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        requiresInitialSetup = !consentManager.hasCompletedInitialSetup
        learningStrength = userDefaults.object(forKey: "learningStrength") as? Double ?? 0.5
        dataRetentionDays = userDefaults.integer(forKey: "learningDataRetentionDays")
        useAIForLearnings = userDefaults.object(forKey: "useAIForLearnings") as? Bool ?? true
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
        
        loadProfileIfNeededForCollection()
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
    public func loadProfileIfNeededForCollection() {
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
        
        // Prune before saving to keep file size manageable
        pruneOldData()
        
        do {
            try LearningsFileManager.save(profile: currentProfile ?? profile)
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
        
        // Trigger auto-inference check after recording change
        Task { await checkAndTriggerAutoInference() }
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
    
    /// Record a successfully completed organization run
    public func recordSuccessfulRun(folderPath: String, fileCount: Int, ruleIdsUsed: Set<String>) {
        guard consentManager.canCollectData else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        // Use the actual file count if 0 was passed
        let count = fileCount > 0 ? fileCount : 0
        
        let job = JobManifest(
            projectName: "Automated Run",
            entries: Array(repeating: JobManifestEntry(originalPath: "", destinationPath: "", status: .success), count: count),
            status: .completed
        )
        profile.jobHistory.append(job)
        
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
        guard useAIForLearnings else {
            error = "AI analysis is disabled. Enable 'Use AI for analysis' in Learnings settings."
            return
        }
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
    /// Returns XML-structured output for better AI parsing
    public func generatePromptContext(forFolder folderPath: String? = nil) -> String {
        loadProfileIfNeededForCollection()
        
        guard let profile = currentProfile, (profile.consentGranted || consentManager.hasConsented) else {
            return ""
        }
        
        if !profile.consentGranted && !consentManager.hasConsented {
            return ""
        }
        
        var sections: [LearningsSection] = []
        let now = Date()
        
        // SECTION 1: REJECTION PATTERNS - Most important, show first
        let recentRejections = profile.rejections
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(15)
        if !recentRejections.isEmpty {
            var items: [LearningsItem] = []
            var rejectionPatterns: [String: (count: Int, lastSeen: Date)] = [:]
            for rejection in recentRejections {
                let ext = URL(fileURLWithPath: rejection.srcPath).pathExtension.lowercased()
                let folder = URL(fileURLWithPath: rejection.dstPath).deletingLastPathComponent().lastPathComponent
                if !folder.isEmpty {
                    let pattern = ext.isEmpty ? "files → \(folder)" : ".\(ext) → \(folder)"
                    let existing = rejectionPatterns[pattern]
                    rejectionPatterns[pattern] = (
                        count: (existing?.count ?? 0) + 1,
                        lastSeen: max(existing?.lastSeen ?? .distantPast, rejection.timestamp)
                    )
                }
            }
            for (pattern, data) in rejectionPatterns.sorted(by: { $0.value.count > $1.value.count }).prefix(8) {
                let recency = recencyWeight(from: data.lastSeen, to: now)
                let weight = min(100, 70 + data.count * 10 + Int(recency * 20))
                items.append(LearningsItem(
                    content: "DO NOT place \(pattern)",
                    weight: weight,
                    occurrences: data.count,
                    recency: recencyLabel(data.lastSeen, now: now)
                ))
            }
            if !items.isEmpty {
                sections.append(LearningsSection(
                    id: "rejections",
                    title: "REJECTION PATTERNS",
                    priority: "CRITICAL",
                    instruction: "NEVER use these placements - user explicitly rejected them",
                    items: items
                ))
            }
        }
        
        // SECTION 2: CRITICAL PREFERENCES - Honing Answers
        if !profile.honingAnswers.isEmpty {
            let answerDate = profile.consentDate ?? profile.createdAt
            let items = profile.honingAnswers.prefix(10).map { answer in
                let recency = recencyWeight(from: answerDate, to: now)
                return LearningsItem(
                    content: answer.selectedOption,
                    weight: 95 + Int(recency * 5),
                    recency: recencyLabel(answerDate, now: now)
                )
            }
            sections.append(LearningsSection(
                id: "preferences",
                title: "USER PREFERENCES",
                priority: "CRITICAL",
                instruction: "These are explicit user preferences - always follow them",
                items: Array(items)
            ))
        }
        
        // SECTION 3: BEHAVIOR PREFERENCES
        extractBehaviorPreferences()
        if let prefs = behaviorPreferences, prefs != BehaviorPreferences() {
            var items: [LearningsItem] = []
            items.append(LearningsItem(content: "Deletion policy: \(prefs.deletionVsArchive.displayName)", weight: 90))
            items.append(LearningsItem(content: "Folder structure: \(prefs.folderDepthPreference.displayName)", weight: 90))
            items.append(LearningsItem(content: "Primary organization: \(prefs.dateVsContentPreference.displayName)", weight: 90))
            items.append(LearningsItem(content: "Duplicate handling: \(prefs.duplicateKeeperStrategy.displayName)", weight: 90))
            sections.append(LearningsSection(
                id: "structure",
                title: "STRUCTURAL PREFERENCES",
                priority: "HIGH",
                instruction: "User's organization philosophy - use these to guide folder structure decisions",
                items: items
            ))
        }

        // SECTION 3B: USER INSTRUCTIONS
        let recentInstructions = profile.additionalInstructionsHistory
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(8)
        if !recentInstructions.isEmpty {
            let items = recentInstructions.map { instruction in
                let recency = recencyWeight(from: instruction.timestamp, to: now)
                return LearningsItem(
                    content: instruction.instruction,
                    weight: 80 + Int(recency * 15),
                    recency: recencyLabel(instruction.timestamp, now: now)
                )
            }
            sections.append(LearningsSection(
                id: "instructions",
                title: "USER INSTRUCTIONS",
                priority: "HIGH",
                instruction: "Direct user instructions that must be followed",
                items: Array(items)
            ))
        }
        
        // SECTION 4: CORRECTIONS - Avoid repeating mistakes
        let recentCorrections = profile.postOrganizationChanges
            .filter { $0.wasAIOrganized }
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(15)
        if !recentCorrections.isEmpty {
            var items: [LearningsItem] = []
            var correctionPatterns: [String: (from: String, to: String, count: Int, lastSeen: Date)] = [:]
            for change in recentCorrections {
                let originalURL = URL(fileURLWithPath: change.originalPath)
                let newURL = URL(fileURLWithPath: change.newPath)
                let srcFolder = originalURL.deletingLastPathComponent().lastPathComponent
                let dstFolder = newURL.deletingLastPathComponent().lastPathComponent
                let srcDisplay = (srcFolder.isEmpty || srcFolder == "/") ? "root" : srcFolder
                let dstDisplay = (dstFolder.isEmpty || dstFolder == "/") ? "root" : dstFolder
                let ext = originalURL.pathExtension.lowercased()
                let key = "\(ext.isEmpty ? "misc" : ext):\(srcDisplay)->\(dstDisplay)"
                let existing = correctionPatterns[key]
                correctionPatterns[key] = (
                    from: srcDisplay,
                    to: dstDisplay,
                    count: (existing?.count ?? 0) + 1,
                    lastSeen: max(existing?.lastSeen ?? .distantPast, change.timestamp)
                )
            }
            for (key, data) in correctionPatterns.sorted(by: { $0.value.count > $1.value.count }).prefix(8) {
                let ext = key.components(separatedBy: ":").first ?? "files"
                let recency = recencyWeight(from: data.lastSeen, to: now)
                let weight = min(95, 60 + data.count * 15 + Int(recency * 20))
                items.append(LearningsItem(
                    content: ".\(ext) files: prefer '\(data.to)/' over '\(data.from)/'",
                    weight: weight,
                    occurrences: data.count,
                    recency: recencyLabel(data.lastSeen, now: now)
                ))
            }
            if !items.isEmpty {
                sections.append(LearningsSection(
                    id: "corrections",
                    title: "PAST CORRECTIONS",
                    priority: "HIGH",
                    instruction: "User corrected these placements - avoid repeating the same mistakes",
                    items: items
                ))
            }
        }
        
        // SECTION 5: HIGH-CONFIDENCE RULES
        let highConfidenceRules = getActiveRules(forFolder: folderPath)
            .filter { $0.confidenceLevel == .high && $0.successRate > 0.7 }
            .sorted(by: { ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast) })
        if !highConfidenceRules.isEmpty {
            let items = highConfidenceRules.prefix(8).map { rule in
                let recency = recencyWeight(from: rule.lastAppliedAt ?? profile.createdAt, to: now)
                let successPct = Int(rule.successRate * 100)
                return LearningsItem(
                    content: rule.explanation,
                    weight: min(90, 70 + successPct / 5 + Int(recency * 10)),
                    confidence: successPct,
                    recency: recencyLabel(rule.lastAppliedAt ?? profile.createdAt, now: now)
                )
            }
            sections.append(LearningsSection(
                id: "high_confidence_rules",
                title: "PROVEN PATTERNS",
                priority: "HIGH",
                instruction: "These patterns have high success rates - follow them unless user instructions conflict",
                items: Array(items)
            ))
        }
        
        // SECTION 6: RECENT FEEDBACK (Steering prompts)
        let recentSteering = profile.steeringPrompts.sorted(by: { $0.timestamp > $1.timestamp }).prefix(8)
        if !recentSteering.isEmpty {
            let items = recentSteering.map { prompt in
                let recency = recencyWeight(from: prompt.timestamp, to: now)
                return LearningsItem(
                    content: prompt.prompt,
                    weight: 60 + Int(recency * 30),
                    recency: recencyLabel(prompt.timestamp, now: now)
                )
            }
            sections.append(LearningsSection(
                id: "feedback",
                title: "RECENT FEEDBACK",
                priority: "MEDIUM-HIGH",
                instruction: "Apply these adjustments from recent user feedback",
                items: Array(items)
            ))
        }
        
        // SECTION 7: CANCELLED ORGANIZATIONS - What NOT to do
        let recentCancellations = profile.cancelledOrganizations.sorted(by: { $0.timestamp > $1.timestamp }).prefix(5)
        if !recentCancellations.isEmpty {
            var items: [LearningsItem] = []
            for cancel in recentCancellations {
                if let instr = cancel.instructions, !instr.isEmpty {
                    let recency = recencyWeight(from: cancel.timestamp, to: now)
                    items.append(LearningsItem(
                        content: "Avoid plan style: '\(instr)' (cancelled at \(cancel.cancelledAtStage))",
                        weight: 50 + Int(recency * 30),
                        recency: recencyLabel(cancel.timestamp, now: now)
                    ))
                }
            }
            if !items.isEmpty {
                sections.append(LearningsSection(
                    id: "cancellations",
                    title: "CANCELLED PATTERNS",
                    priority: "MEDIUM",
                    instruction: "User cancelled these organization approaches - avoid similar structures",
                    items: items
                ))
            }
        }
        
        // SECTION 8: POSITIVE EXAMPLES
        let recentPositives = profile.positiveExamples.sorted(by: { $0.timestamp > $1.timestamp }).prefix(20)
        if !recentPositives.isEmpty {
            var positivePatterns: [String: (files: [(file: String, ext: String)], lastSeen: Date)] = [:]
            for example in recentPositives {
                let srcFile = URL(fileURLWithPath: example.srcPath).lastPathComponent
                let dstFolder = URL(fileURLWithPath: example.dstPath).deletingLastPathComponent().lastPathComponent
                let ext = URL(fileURLWithPath: example.srcPath).pathExtension.lowercased()
                let existing = positivePatterns[dstFolder]
                positivePatterns[dstFolder] = (
                    files: (existing?.files ?? []) + [(file: srcFile, ext: ext)],
                    lastSeen: max(existing?.lastSeen ?? .distantPast, example.timestamp)
                )
            }
            var items: [LearningsItem] = []
            for (folder, data) in positivePatterns.sorted(by: { $0.value.files.count > $1.value.files.count }).prefix(6) {
                let extCounts = Dictionary(grouping: data.files) { $0.ext }.mapValues { $0.count }
                let topExtensions = extCounts.sorted(by: { $0.value > $1.value }).prefix(3)
                let extList = topExtensions.map { ".\($0.key)" }.joined(separator: ", ")
                let recency = recencyWeight(from: data.lastSeen, to: now)
                let weight = 40 + data.files.count * 5 + Int(recency * 20)
                if !extList.isEmpty {
                    items.append(LearningsItem(
                        content: "'\(folder)/' is good for: \(extList) files",
                        weight: min(80, weight),
                        occurrences: data.files.count,
                        recency: recencyLabel(data.lastSeen, now: now)
                    ))
                }
            }
            if !items.isEmpty {
                sections.append(LearningsSection(
                    id: "positive_patterns",
                    title: "APPROVED DESTINATIONS",
                    priority: "MEDIUM",
                    instruction: "User explicitly approved these folder placements",
                    items: items
                ))
            }
        }
        
        // SECTION 9: MEDIUM-CONFIDENCE RULES
        let mediumConfidenceRules = getActiveRules(forFolder: folderPath)
            .filter { $0.confidenceLevel == .medium || ($0.confidenceLevel == .high && $0.successRate <= 0.7) }
            .sorted(by: { ($0.lastAppliedAt ?? .distantPast) > ($1.lastAppliedAt ?? .distantPast) })
        if !mediumConfidenceRules.isEmpty {
            let items = mediumConfidenceRules.prefix(5).map { rule in
                let confidence = Int(rule.successRate * 100)
                return LearningsItem(
                    content: rule.explanation,
                    weight: 40 + confidence / 3,
                    confidence: confidence
                )
            }
            sections.append(LearningsSection(
                id: "learned_patterns",
                title: "LEARNED PATTERNS",
                priority: "LOW",
                instruction: "Consider these tendencies but they may be overridden by explicit preferences",
                items: Array(items)
            ))
        }
        
        // SECTION 10: REVERT WARNING
        let recentReverts = profile.historyReverts.suffix(5)
        if recentReverts.count >= 2 {
            sections.append(LearningsSection(
                id: "caution",
                title: "CAUTION",
                priority: "ADVISORY",
                instruction: "User has reverted \(recentReverts.count) recent organizations - be more conservative with changes",
                items: []
            ))
        }
        
        guard !sections.isEmpty else { return "" }
        
        return formatAsXML(sections: sections, folderPath: folderPath)
    }
    
    // MARK: - Prompt Context Helpers
    
    private struct LearningsSection {
        let id: String
        let title: String
        let priority: String
        let instruction: String
        let items: [LearningsItem]
    }
    
    private struct LearningsItem {
        let content: String
        var weight: Int = 50
        var confidence: Int? = nil
        var occurrences: Int? = nil
        var recency: String? = nil
    }
    
    private func recencyWeight(from date: Date, to now: Date) -> Double {
        let daysSince = now.timeIntervalSince(date) / 86400
        if daysSince < 1 { return 1.0 }
        if daysSince < 7 { return 0.8 }
        if daysSince < 30 { return 0.5 }
        if daysSince < 90 { return 0.3 }
        return 0.1
    }
    
    private func recencyLabel(_ date: Date, now: Date) -> String {
        let daysSince = Int(now.timeIntervalSince(date) / 86400)
        if daysSince == 0 { return "today" }
        if daysSince == 1 { return "yesterday" }
        if daysSince < 7 { return "\(daysSince) days ago" }
        if daysSince < 30 { return "\(daysSince / 7) weeks ago" }
        if daysSince < 365 { return "\(daysSince / 30) months ago" }
        return "over a year ago"
    }
    
    private func formatAsXML(sections: [LearningsSection], folderPath: String?) -> String {
        var xml = "<learnings_context>\n"
        xml += "  <preamble>\n"
        xml += "    <instruction>IMPORTANT: The following learnings represent this user's organization preferences, corrections, and patterns. "
        xml += "Pay close attention to rejection patterns and corrections - these indicate what NOT to do. "
        xml += "Items with higher weights (closer to 100) are more important. Recent items should be prioritized.</instruction>\n"
        if let folder = folderPath {
            let folderName = URL(fileURLWithPath: folder).lastPathComponent
            xml += "    <context folder=\"\(escapeXML(folderName))\">\(escapeXML(folder))</context>\n"
        }
        xml += "  </preamble>\n\n"
        
        for section in sections {
            xml += "  <section id=\"\(section.id)\" priority=\"\(section.priority)\">\n"
            xml += "    <title>\(escapeXML(section.title))</title>\n"
            xml += "    <instruction>\(escapeXML(section.instruction))</instruction>\n"
            if !section.items.isEmpty {
                xml += "    <items>\n"
                for item in section.items {
                    var attrs = "weight=\"\(item.weight)\""
                    if let conf = item.confidence { attrs += " confidence=\"\(conf)%\"" }
                    if let occ = item.occurrences { attrs += " occurrences=\"\(occ)\"" }
                    if let rec = item.recency { attrs += " recency=\"\(rec)\"" }
                    xml += "      <item \(attrs)>\(escapeXML(item.content))</item>\n"
                }
                xml += "    </items>\n"
            }
            xml += "  </section>\n\n"
        }
        
        xml += "</learnings_context>"
        return xml
    }
    
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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
        
        let totalRuns = profile.jobHistory.count
        let completedRuns = profile.jobHistory.filter { $0.status == .completed }.count
        
        let filesRoutedByLearnings = profile.inferredRules.reduce(0) { $0 + $1.successCount }
        let correctionsAfterAI = profile.postOrganizationChanges.filter { $0.wasAIOrganized }.count
        
        let reverts = profile.historyReverts.count
        let cancelled = profile.cancelledOrganizations.count
        let regenerated = profile.regeneratedOrganizations.count

        let accepted = max(0, completedRuns - reverts)
        let rejected = min(completedRuns, reverts)
        
        let runsWithLearnings = completedRuns
        
        return LearningsImpactSummary(
            runsWithLearnings: runsWithLearnings,
            totalRuns: totalRuns,
            filesRoutedByLearnings: filesRoutedByLearnings,
            correctionsAfterAI: correctionsAfterAI,
            reverts: reverts,
            acceptedOrganizations: accepted,
            rejectedOrganizations: rejected,
            cancelledOrganizations: cancelled,
            regeneratedOrganizations: regenerated
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
    
    /// Get active rules filtered by learning strength and optionally by scope
    public func getActiveRules(forFolder folderPath: String? = nil, forPersona personaId: UUID? = nil) -> [InferredRule] {
        guard let profile = currentProfile else { return [] }
        
        // Filter enabled rules that are active (not pending/rejected/cooldown)
        var activeRules = profile.inferredRules.filter { rule in
            rule.isEnabled && rule.status == .active
        }
        
        // Filter by scope if provided
        if let folderPath = folderPath {
            activeRules = activeRules.filter { rule in
                switch rule.scope {
                case .global:
                    return true
                case .folder(let rulePath):
                    return folderPath.hasPrefix(rulePath) || rulePath == folderPath
                case .activePersona:
                    return false
                }
            }
        }
        
        if let personaId = personaId {
            activeRules = activeRules.filter { rule in
                switch rule.scope {
                case .global:
                    return true
                case .activePersona(let rulePersonaId):
                    return rulePersonaId == personaId
                case .folder:
                    return true
                }
            }
        }
        
        // Sort by priority
        activeRules.sort { $0.priority > $1.priority }
        
        // Apply learning strength to limit number of rules
        let maxRules = Int(Double(activeRules.count) * learningStrength) + 1
        return Array(activeRules.prefix(maxRules))
    }
    
    // MARK: - Rule Suggestion Inbox
    
    /// Get pending approval rules
    public func getPendingRules() -> [InferredRule] {
        guard let profile = currentProfile else { return [] }
        return profile.inferredRules.filter { $0.status == .pendingApproval }
    }
    
    /// Approve a pending rule
    public func approveRule(ruleId: String) async {
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].status = .active
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Reject a pending rule with cooling-off period
    public func rejectRule(ruleId: String, cooldownDays: Int = 30) async {
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].status = .rejected
            profile.inferredRules[index].rejectedAt = Date()
            profile.inferredRules[index].cooldownUntil = Date().addingTimeInterval(Double(cooldownDays) * 86400)
            profile.inferredRules[index].isEnabled = false
            
            // Track cooldown
            profile.rejectedRuleCooldowns[ruleId] = Date().addingTimeInterval(Double(cooldownDays) * 86400)
            
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Edit a pending rule's explanation and approve it
    public func editAndApproveRule(ruleId: String, newExplanation: String? = nil, newPriority: Int? = nil, newScope: RuleScope? = nil) async {
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].status = .active
            if let explanation = newExplanation {
                let rule = profile.inferredRules[index]
                let updatedRule = InferredRule(
                    id: rule.id,
                    pattern: rule.pattern,
                    template: rule.template,
                    metadataCues: rule.metadataCues,
                    priority: newPriority ?? rule.priority,
                    exampleIds: rule.exampleIds,
                    explanation: explanation,
                    successCount: rule.successCount,
                    failureCount: rule.failureCount,
                    isEnabled: true,
                    lastAppliedAt: rule.lastAppliedAt,
                    supportCount: rule.supportCount,
                    initialConfidence: rule.initialConfidence,
                    scope: newScope ?? rule.scope,
                    status: .active,
                    evidenceIds: rule.evidenceIds,
                    evidenceDescription: rule.evidenceDescription,
                    rejectedAt: rule.rejectedAt,
                    cooldownUntil: rule.cooldownUntil
                )
                profile.inferredRules[index] = updatedRule
            } else {
                if let priority = newPriority {
                    profile.inferredRules[index].priority = priority
                }
                if let scope = newScope {
                    profile.inferredRules[index].scope = scope
                }
            }
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Check if a rule pattern is in cooldown (was recently rejected)
    public func isRuleInCooldown(pattern: String) -> Bool {
        guard let profile = currentProfile else { return false }
        let now = Date()
        
        return profile.inferredRules.contains { rule in
            rule.pattern == pattern && rule.status == .rejected &&
            (rule.cooldownUntil ?? .distantPast) > now
        }
    }
    
    // MARK: - Learning Exclusion Patterns
    
    /// Add a path exclusion pattern (learning will be skipped for matching paths)
    public func addLearningExclusion(_ pattern: String) async {
        guard var profile = currentProfile else { return }
        if !profile.learningExclusionPatterns.contains(pattern) {
            profile.learningExclusionPatterns.append(pattern)
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Remove a learning exclusion pattern
    public func removeLearningExclusion(_ pattern: String) async {
        guard var profile = currentProfile else { return }
        profile.learningExclusionPatterns.removeAll { $0 == pattern }
        currentProfile = profile
        await saveProfile()
    }
    
    /// Check if a path should be excluded from learning
    public func isPathExcludedFromLearning(_ path: String) -> Bool {
        guard let profile = currentProfile else { return false }
        let loweredPath = path.lowercased()
        return profile.learningExclusionPatterns.contains { pattern in
            let loweredPattern = pattern.lowercased()
            return loweredPath.contains(loweredPattern) ||
                   loweredPath.hasSuffix(loweredPattern) ||
                   URL(fileURLWithPath: path).lastPathComponent.lowercased().contains(loweredPattern)
        }
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

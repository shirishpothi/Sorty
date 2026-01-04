//
//  FolderOrganizer.swift
//  FileOrganizer
//
//  Main orchestrator for organization workflow with streaming support
//  Fixed: Auto-start prevention, reliable cancellation, and accurate progress tracking
//

import Foundation
import SwiftUI
import Combine

public enum OrganizationState: Equatable, Sendable {
    case idle
    case scanning
    case organizing
    case ready
    case applying
    case completed
    case error(Error)

    public static func == (lhs: OrganizationState, rhs: OrganizationState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.scanning, .scanning),
             (.organizing, .organizing),
             (.ready, .ready),
             (.applying, .applying),
             (.completed, .completed):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

public enum OrganizationError: LocalizedError, Equatable {
    case clientNotConfigured
    case noCurrentPlan
    case fileMoveFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .clientNotConfigured:
            return "AI Client not configured. Please check your settings."
        case .noCurrentPlan:
            return "No organization plan available to apply."
        case .fileMoveFailed(let details):
            return "Failed to move file: \(details)"
        case .cancelled:
            return "Operation was cancelled."
        }
    }
}

/// Progress update for real-time UI feedback
public struct OrganizationProgress: Sendable {
    public let phase: Phase
    public let current: Int
    public let total: Int
    public let detail: String?

    public enum Phase: String, Sendable {
        case scanning = "Scanning"
        case analyzing = "Analyzing"
        case aiProcessing = "AI Processing"
        case validating = "Validating"
        case applying = "Applying"
        case complete = "Complete"
    }

    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    public var phaseWeight: Double {
        switch phase {
        case .scanning: return 0.15
        case .analyzing: return 0.15
        case .aiProcessing: return 0.50
        case .validating: return 0.10
        case .applying: return 0.10
        case .complete: return 1.0
        }
    }

    public var phaseBaseProgress: Double {
        switch phase {
        case .scanning: return 0.0
        case .analyzing: return 0.15
        case .aiProcessing: return 0.30
        case .validating: return 0.80
        case .applying: return 0.90
        case .complete: return 1.0
        }
    }

    public var overallProgress: Double {
        if phase == .complete { return 1.0 }
        return phaseBaseProgress + (percentage * (phaseWeight - phaseBaseProgress.truncatingRemainder(dividingBy: 1.0)))
    }
}

@MainActor
public class FolderOrganizer: ObservableObject, StreamingDelegate {
    @Published public var state: OrganizationState = .idle
    @Published public var progress: Double = 0.0
    @Published public var currentPlan: OrganizationPlan?
    @Published public var errorMessage: String?
    @Published public var customInstructions: String = ""

    // Streaming support
    @Published public var streamingContent: String = ""
    @Published public var organizationStage: String = ""
    @Published public var isStreaming: Bool = false

    // Timeout messaging
    @Published public var elapsedTime: TimeInterval = 0
    @Published public var showTimeoutMessage: Bool = false
    private var startTime: Date?
    private var timeoutTask: Task<Void, Never>?

    // Track current directory for status checks
    @Published public var currentDirectory: URL?

    // CRITICAL: Cancellation token - must be checked frequently
    private var currentTask: Task<Void, Error>?
    private var isCancellationRequested: Bool = false

    // Prevent auto-start by tracking explicit user actions
    private var userInitiatedAction: Bool = false

    var scanner = DirectoryScanner()
    var aiClient: AIClientProtocol?
    private let fileSystemManager = FileSystemManager()
    private var aiConfig: AIConfig?
    private let validator = FileOrganizationValidator.self
    public let history = OrganizationHistory()
    public var exclusionRules: ExclusionRulesManager?
    public var personaManager: PersonaManager?
    public var customPersonaStore: CustomPersonaStore?
    public var learningsManager: LearningsManager?
    
    public init() {}

    public func configure(with config: AIConfig) async throws {
        var client = try AIClientFactory.createClient(config: config)

        // Set up streaming delegate
        client.streamingDelegate = self

        self.aiClient = client
        self.aiConfig = config
    }

    // MARK: - StreamingDelegate

    public nonisolated func didReceiveChunk(_ chunk: String) {
        Task { @MainActor in
            guard !self.isCancellationRequested else { return }

            self.streamingContent += chunk

            // Increment progress asymptotically towards 0.8 during streaming
            // Use content length as a proxy for progress
            let contentLength = self.streamingContent.count
            let estimatedTotal = 5000 // Estimated total characters
            let streamProgress = min(0.8, 0.3 + (Double(contentLength) / Double(estimatedTotal)) * 0.5)

            if self.progress < streamProgress {
                self.progress = streamProgress
            }
        }
    }

    public nonisolated func didComplete(content: String) {
        Task { @MainActor in
            self.isStreaming = false
            self.organizationStage = "Processing response..."
            self.stopTimeoutTimer()
        }
    }

    public nonisolated func didFail(error: Error) {
        Task { @MainActor in
            self.isStreaming = false
            self.errorMessage = error.localizedDescription
            self.stopTimeoutTimer()
        }
    }

    // MARK: - Timeout Timer

    private func startTimeoutTimer() {
        startTime = Date()
        elapsedTime = 0
        showTimeoutMessage = false

        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            while !Task.isCancelled && !isCancellationRequested {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled && !isCancellationRequested else { break }

                if let start = self.startTime {
                    self.elapsedTime = Date().timeIntervalSince(start)

                    if self.elapsedTime >= 30 && !self.showTimeoutMessage {
                        self.showTimeoutMessage = true
                    }
                }
            }
        }
    }

    private func stopTimeoutTimer() {
        timeoutTask?.cancel()
        timeoutTask = nil
        startTime = nil
    }

    // MARK: - Main Organization Methods

    /// Start organization - MUST be explicitly called by user action
    public func organize(directory: URL, customPrompt: String? = nil, temperature: Double? = nil) async throws {
        // Guard against auto-start
        guard !isOperationInProgress() else {
            DebugLogger.log("Organization blocked: Already in progress")
            return
        }

        // Cancel any existing task first
        cancelInternal()

        // Reset cancellation flag
        isCancellationRequested = false
        userInitiatedAction = true

        currentTask = Task {
            try await performOrganization(directory: directory, customPrompt: customPrompt, temperature: temperature)
        }

        do {
            try await currentTask?.value
        } catch is CancellationError {
            // Handle cancellation gracefully
            await MainActor.run {
                resetToIdle()
            }
        } catch {
            throw error
        }
    }

    private func performOrganization(directory: URL, customPrompt: String?, temperature: Double?) async throws {
        guard let client = aiClient else {
            throw OrganizationError.clientNotConfigured
        }

        do {
            currentDirectory = directory

            updateState(.scanning, stage: "Scanning directory...", progress: 0.05)

            // Check cancellation frequently
            try checkCancellation()

            var files = try await scanner.scanDirectory(at: directory)

            updateProgress(0.15, stage: "Found \(files.count) files")

            try checkCancellation()

            if let exclusionRules = exclusionRules {
                files = exclusionRules.filterFiles(files)
                updateProgress(0.20, stage: "Filtered to \(files.count) files")
            }

            try checkCancellation()

            updateState(.organizing, stage: "Organizing with AI...", progress: 0.25)
            await MainActor.run {
                isStreaming = true
            }

            startTimeoutTimer()

            try checkCancellation()

            let personaPrompt = personaManager?.getEffectivePrompt(customStore: customPersonaStore ?? CustomPersonaStore())
            
            // Add exclusion context to prompt
            var instructions = customPrompt ?? customInstructions
            if let activeRules = exclusionRules?.rules.filter({ $0.isEnabled }), !activeRules.isEmpty {
                let excludedPatterns = activeRules.map { "- \($0.displayDescription)" }.joined(separator: "\n")
                instructions += "\n\nIMPORTANT: The following patterns are STRICTLY EXCLUDED and must NOT be moved, renamed, or modified:\n\(excludedPatterns)\nEnsure your organization plan completely respects these exclusions."
            }
            
            // Add Learnings context (User preferences, past corrections, etc.)
            if let learnedContext = learningsManager?.generatePromptContext(), !learnedContext.isEmpty {
                instructions += "\n\n" + learnedContext
                DebugLogger.log("Injected Learnings context into prompt")
            }

            let plan = try await client.analyze(files: files, customInstructions: instructions, personaPrompt: personaPrompt, temperature: temperature)

            try checkCancellation()

            stopTimeoutTimer()

            updateState(.organizing, stage: "Validating plan...", progress: 0.85)
            await MainActor.run {
                isStreaming = false
            }

            try validator.validate(plan, at: directory)

            try checkCancellation()

            updateState(.ready, stage: "Ready!", progress: 1.0)
            await MainActor.run {
                currentPlan = plan
            }

        } catch is CancellationError {
            stopTimeoutTimer()
            resetToIdle()
            throw CancellationError()
        } catch let error as OrganizationError where error == .cancelled {
            stopTimeoutTimer()
            resetToIdle()
            throw CancellationError()
        } catch {
            stopTimeoutTimer()
            handleOrganizationError(error, directory: directory)
            throw error
        }
    }

    // MARK: - Cancellation

    /// Cancel any ongoing operation - RELIABLE cancellation
    public func cancel() {
        DebugLogger.log("Cancel requested by user")
        cancelInternal()
        resetToIdle()
    }

    private func cancelInternal() {
        isCancellationRequested = true
        currentTask?.cancel()
        currentTask = nil
        stopTimeoutTimer()
    }

    private func checkCancellation() throws {
        if isCancellationRequested || Task.isCancelled {
            throw OrganizationError.cancelled
        }
    }

    private func isOperationInProgress() -> Bool {
        switch state {
        case .scanning, .organizing, .applying:
            return true
        default:
            return false
        }
    }

    private func resetToIdle() {
        state = .idle
        organizationStage = "Cancelled"
        isStreaming = false
        isCancellationRequested = false
        userInitiatedAction = false
    }

    @MainActor
    private func handleOrganizationError(_ error: Error, directory: URL) {
        let failedEntry = OrganizationHistoryEntry(
            directoryPath: directory.path,
            filesOrganized: 0,
            foldersCreated: 0,
            plan: nil,
            success: false,
            status: .failed,
            errorMessage: error.localizedDescription,
            rawAIResponse: streamingContent.isEmpty ? nil : streamingContent
        )
        history.addEntry(failedEntry)

        state = .error(error)
        errorMessage = error.localizedDescription
    }

    // MARK: - State Updates with Progress

    @MainActor
    private func updateState(_ newState: OrganizationState, stage: String, progress: Double) {
        guard !isCancellationRequested else { return }
        self.state = newState
        self.organizationStage = stage
        self.progress = progress
    }

    @MainActor
    private func updateProgress(_ progress: Double, stage: String? = nil) {
        guard !isCancellationRequested else { return }
        self.progress = progress
        if let stage = stage {
            self.organizationStage = stage
        }
    }

    // MARK: - Incremental Organization (for watched folders)

    public func organizeIncremental(directory: URL, specificFiles: [String]? = nil, customPrompt: String? = nil, temperature: Double? = nil) async throws {
        guard !isOperationInProgress() else {
            DebugLogger.log("Incremental organization blocked: Already in progress")
            return
        }

        cancelInternal()
        isCancellationRequested = false

        currentTask = Task {
            try await performIncrementalOrganization(directory: directory, specificFiles: specificFiles, customPrompt: customPrompt, temperature: temperature)
        }

        do {
            try await currentTask?.value
        } catch is CancellationError {
            resetToIdle()
        }
    }

    private func performIncrementalOrganization(directory: URL, specificFiles: [String]?, customPrompt: String?, temperature: Double?) async throws {
        guard let client = aiClient else {
            throw OrganizationError.clientNotConfigured
        }

        currentDirectory = directory
        
        var files: [FileItem] = []
        
        if let specificFiles = specificFiles {
            // Processing specific files
            updateState(.scanning, stage: "Processing \(specificFiles.count) new files...", progress: 0.1)
            try checkCancellation()
            
            // map file names to FileItems
            // We assume specificFiles are filenames or relative paths
            for filename in specificFiles {
                let fileURL = directory.appendingPathComponent(filename)
                if let item = try? await scanner.scanFile(at: fileURL, root: directory) {
                    files.append(item)
                }
            }
        } else {
            // Fallback to scanning root
            updateState(.scanning, stage: "Scanning for new files...", progress: 0.1)
            try checkCancellation()
            
            let allFiles = try await scanner.scanDirectory(at: directory)
            
            // Filter: Only top-level files (no folders, no deep scan) for incremental drop
            files = allFiles.filter {
                let relativePath = $0.path.replacingOccurrences(of: directory.path + "/", with: "")
                return !relativePath.contains("/") // Only files in root
            }
        }

        if let exclusionRules = exclusionRules {
            files = exclusionRules.filterFiles(files)
        }

        if files.isEmpty {
            await MainActor.run {
                state = .idle
                organizationStage = "No new files to organize"
            }
            return
        }

        updateState(.organizing, stage: "Sorting \(files.count) new files...", progress: 0.3)
        await MainActor.run {
            isStreaming = true
        }

        startTimeoutTimer()

        do {
            try checkCancellation()

            // Get existing folders to use as context
            let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            let existingFolders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
                .map { $0.lastPathComponent }
                .filter { !$0.hasPrefix(".") }

            let contextPrompt = """
            The following folders already exist: \(existingFolders.joined(separator: ", ")).
            
            RULES for Organization:
            1. You MUST prioritize placing files into these existing folders if they are relevant.
            2. Do NOT create new folders unless the file is completely unrelated to any existing folder.
            3. If a file does not fit well into any existing folder, you may leave it in the root (do not move it).
            4. This is a "Smart Drop" operation: we want to maintain the existing structure, not reinvent it.
            """

            let prompt = (customPrompt ?? customInstructions) + "\n\n" + contextPrompt
            
            // Add Learnings context
            var finalPrompt = prompt
            if let learnedContext = learningsManager?.generatePromptContext(), !learnedContext.isEmpty {
                finalPrompt += "\n\n" + learnedContext
            }
            
            let personaPrompt = personaManager?.getPrompt(for: personaManager?.selectedPersona ?? .general)

            let plan = try await client.analyze(files: files, customInstructions: finalPrompt, personaPrompt: personaPrompt, temperature: temperature)

            stopTimeoutTimer()

            try checkCancellation()

            await MainActor.run {
                isStreaming = false
                currentPlan = plan
            }

            // Auto-apply for incremental
            try await apply(at: directory, dryRun: false, enableTagging: true)

        } catch {
            stopTimeoutTimer()
            handleOrganizationError(error, directory: directory)
            throw error
        }
    }

    // MARK: - Apply Organization

    public func apply(at baseURL: URL, dryRun: Bool = false, enableTagging: Bool = true) async throws {
        guard let plan = currentPlan else {
            throw OrganizationError.noCurrentPlan
        }

        try checkCancellation()

        updateState(.applying, stage: "Applying changes...", progress: 0.0)

        do {
            let operations = try await fileSystemManager.applyOrganization(
                plan, 
                at: baseURL, 
                dryRun: dryRun, 
                enableTagging: enableTagging,
                strictExclusions: aiConfig?.strictExclusions ?? true,
                exclusionManager: exclusionRules
            )

            try checkCancellation()

            let historyEntry = OrganizationHistoryEntry(
                directoryPath: baseURL.path,
                filesOrganized: plan.totalFiles,
                foldersCreated: plan.totalFolders,
                plan: plan,
                success: true,
                status: .completed,
                rawAIResponse: streamingContent.isEmpty ? nil : streamingContent,
                operations: operations
            )

            await MainActor.run {
                history.addEntry(historyEntry)
                organizationStage = "Complete!"
                progress = 1.0
                state = .completed
            }

            NotificationCenter.default.post(
                name: .organizationDidFinish,
                object: nil,
                userInfo: [
                    "url": baseURL,
                    "entry": historyEntry,
                    "operations": operations
                ]
            )

        } catch {
            let failedEntry = OrganizationHistoryEntry(
                directoryPath: baseURL.path,
                filesOrganized: 0,
                foldersCreated: 0,
                plan: plan,
                success: false,
                status: .failed,
                errorMessage: error.localizedDescription,
                rawAIResponse: streamingContent.isEmpty ? nil : streamingContent
            )

            await MainActor.run {
                history.addEntry(failedEntry)
            }

            throw error
        }
    }

    // MARK: - Regenerate Preview

    public func regeneratePreview() async throws {
        guard let currentPlan = currentPlan else {
            throw OrganizationError.noCurrentPlan
        }

        guard !isOperationInProgress() else {
            return
        }

        isCancellationRequested = false

        // Reset streaming state
        await MainActor.run {
            streamingContent = ""
            isStreaming = false
            showTimeoutMessage = false
        }

        // Get original files from current plan
        var allFiles: [FileItem] = []
        func collectFiles(_ suggestion: FolderSuggestion) {
            allFiles.append(contentsOf: suggestion.files)
            for subfolder in suggestion.subfolders {
                collectFiles(subfolder)
            }
        }
        for suggestion in currentPlan.suggestions {
            collectFiles(suggestion)
        }
        allFiles.append(contentsOf: currentPlan.unorganizedFiles)

        updateState(.organizing, stage: "Regenerating organization...", progress: 0.3)
        await MainActor.run {
            isStreaming = true
        }

        startTimeoutTimer()

        do {
            guard let client = aiClient else {
                throw OrganizationError.clientNotConfigured
            }

            try checkCancellation()

            // Log the previous attempt as skipped/superseded
            if let directory = currentDirectory {
                let skippedEntry = OrganizationHistoryEntry(
                    directoryPath: directory.path,
                    filesOrganized: 0,
                    foldersCreated: 0,
                    plan: currentPlan,
                    success: false,
                    status: .skipped,
                    errorMessage: "User requested different organization",
                    rawAIResponse: streamingContent.isEmpty ? nil : streamingContent
                )
                history.addEntry(skippedEntry)
            }

            // Generate new plan
            let personaPrompt = personaManager?.getPrompt(for: personaManager?.selectedPersona ?? .general)
            
            var instructions = customInstructions
            if let learnedContext = learningsManager?.generatePromptContext(), !learnedContext.isEmpty {
                instructions += "\n\n" + learnedContext
            }
            
            var newPlan = try await client.analyze(files: allFiles, customInstructions: instructions, personaPrompt: personaPrompt, temperature: nil)
            newPlan.version = (currentPlan.version) + 1

            stopTimeoutTimer()

            try checkCancellation()

            await MainActor.run {
                isStreaming = false
                organizationStage = "Ready!"
                progress = 1.0
                self.currentPlan = newPlan
                state = .ready
            }

        } catch {
            stopTimeoutTimer()

            // Record failed attempt
            if let directory = currentDirectory {
                let failedEntry = OrganizationHistoryEntry(
                    directoryPath: directory.path,
                    filesOrganized: 0,
                    foldersCreated: 0,
                    plan: nil,
                    success: false,
                    status: .failed,
                    errorMessage: error.localizedDescription,
                    rawAIResponse: streamingContent.isEmpty ? nil : streamingContent
                )
                history.addEntry(failedEntry)
            }

            throw error
        }
    }

    // MARK: - Multi-State Undo/Redo

    /// Undoes a specific historical session
    public func undoHistoryEntry(_ entry: OrganizationHistoryEntry) async throws {
        guard let operations = entry.operations, !entry.isUndone else { return }

        updateState(.applying, stage: "Undoing changes...", progress: 0.3)

        do {
            try await fileSystemManager.reverseOperations(operations)

            var updatedEntry = entry
            updatedEntry.isUndone = true
            updatedEntry.status = .undo
            history.updateEntry(updatedEntry)

            await MainActor.run {
                organizationStage = "Undo complete"
                progress = 1.0
                state = .idle
            }

            NotificationCenter.default.post(
                name: .organizationDidRevert,
                object: nil,
                userInfo: [
                    "url": URL(fileURLWithPath: entry.directoryPath),
                    "entry": entry
                ]
            )

        } catch {
            await MainActor.run {
                state = .error(error)
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// Restores to a previous state by undoing all intermediate sessions
    public func restoreToState(targetEntry: OrganizationHistoryEntry) async throws {
        // Find all sessions on the same path that are after this one and not undone
        let path = targetEntry.directoryPath
        let entriesToUndo = history.entries.filter {
            $0.directoryPath == path &&
            $0.timestamp > targetEntry.timestamp &&
            $0.status == .completed &&
            !$0.isUndone
        }.sorted { $0.timestamp > $1.timestamp } // Undo most recent first

        updateState(.applying, stage: "Rolling back states...", progress: 0.1)

        let total = Double(entriesToUndo.count)

        for (index, entry) in entriesToUndo.enumerated() {
            updateProgress(Double(index) / total, stage: "Undoing session from \(entry.timestamp.formatted())...")

            try await undoHistoryEntry(entry)
        }

        await MainActor.run {
            organizationStage = "Restoration complete"
            progress = 1.0
            state = .idle
        }
    }

    public func redoOrganization(from entry: OrganizationHistoryEntry) async throws {
        guard let plan = entry.plan else { return }
        // To "redo" an undone version, we just apply its plan again
        currentPlan = plan
        try await apply(at: URL(fileURLWithPath: entry.directoryPath))
    }

    // MARK: - Reset

    public func reset() {
        cancelInternal()

        state = .idle
        progress = 0.0
        currentPlan = nil
        errorMessage = nil
        streamingContent = ""
        organizationStage = ""
        isStreaming = false
        showTimeoutMessage = false
        elapsedTime = 0
        currentDirectory = nil
        isCancellationRequested = false
        userInitiatedAction = false
    }
}

//
//  FolderOrganizer.swift
//  Sorty
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

/// AI reasoning insight extracted from streaming content
public struct AIInsight: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let category: Category
    public let timestamp: Date
    
    public enum Category: String, Sendable {
        case file = "File"
        case folder = "Folder"
        case constraint = "Constraint"
        case decision = "Decision"
        case pattern = "Pattern"
        case general = "Analyzing"
        
        public var icon: String {
            switch self {
            case .file: return "doc"
            case .folder: return "folder"
            case .constraint: return "exclamationmark.triangle"
            case .decision: return "arrow.right"
            case .pattern: return "circle.grid.3x3"
            case .general: return "brain"
            }
        }
        
        public var color: String {
            switch self {
            case .file: return "blue"
            case .folder: return "orange"
            case .constraint: return "yellow"
            case .decision: return "green"
            case .pattern: return "purple"
            case .general: return "secondary"
            }
        }
    }
    
    public init(text: String, category: Category) {
        self.text = text
        self.category = category
        self.timestamp = Date()
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
    
    // Proactive AI Validation
    @Published public var isAIConfigured: Bool = false

    // Streaming support
    @Published public var streamingContent: String = ""
    @Published public var displayStreamingContent: String = "" // Throttled version for UI to prevent layout loops
    @Published public var organizationStage: String = ""
    @Published public var isStreaming: Bool = false
    
    // Throttle timer for display content updates (prevents layout thrashing)
    private var displayUpdateTask: Task<Void, Never>?
    private var lastDisplayUpdate: Date = .distantPast
    private let displayUpdateInterval: TimeInterval = 0.1 // 100ms throttle
    
    // Steady progress animation during streaming
    private var steadyProgressTask: Task<Void, Never>?
    private var lastChunkTime: Date = .distantPast
    
    // AI reasoning insights - extracted from streaming content
    @Published public var currentInsight: String = ""
    @Published public var insightHistory: [AIInsight] = []
    private var lastInsightExtraction: Date = .distantPast
    private let insightExtractionInterval: TimeInterval = 0.8 // Throttle to avoid too frequent updates

    // Timeout messaging
    @Published public var elapsedTime: TimeInterval = 0
    @Published public var showTimeoutMessage: Bool = false
    private var startTime: Date?
    private var timeoutTask: Task<Void, Never>?

    // Track current directory for status checks
    @Published public var currentDirectory: URL?
    
    // Track file count for better progress estimation
    public var scannedFileCount: Int = 0

    // CRITICAL: Cancellation token - must be checked frequently
    private var currentTask: Task<Void, Error>?
    private var isCancellationRequested: Bool = false

    // Prevent auto-start by tracking explicit user actions
    private var userInitiatedAction: Bool = false

    var scanner = DirectoryScanner()
    public private(set) var aiClient: AIClientProtocol?
    private let fileSystemManager = FileSystemManager()
    private var aiConfig: AIConfig?
    private let validator = FileOrganizationValidator.self
    public let history = OrganizationHistory()
    public var exclusionRules: ExclusionRulesManager?
    public var personaManager: PersonaManager?
    public var customPersonaStore: CustomPersonaStore?
    public var learningsManager: LearningsManager?
    public var storageLocationsManager: StorageLocationsManager?
    
    public init() {}
    
    #if DEBUG
    /// Test-only method to inject a mock AI client for unit testing
    public func setAIClientForTesting(_ client: AIClientProtocol?) {
        self.aiClient = client
        if client != nil {
            self.isAIConfigured = true
        }
    }
    #endif

    public func configure(with config: AIConfig) async throws {
        do {
            var client = try AIClientFactory.createClient(config: config)

            // Set up streaming delegate
            client.streamingDelegate = self

            self.aiClient = client
            self.aiConfig = config
            
            await MainActor.run {
                self.isAIConfigured = true
            }
        } catch {
            self.aiClient = nil
            self.aiConfig = config
            await MainActor.run {
                self.isAIConfigured = false
            }
            throw error
        }
    }

    // MARK: - StreamingDelegate

    public nonisolated func didReceiveChunk(_ chunk: String) {
        Task { @MainActor in
            guard !self.isCancellationRequested else { return }
            
            let isFirstChunk = self.streamingContent.isEmpty
            self.streamingContent += chunk
            self.lastChunkTime = Date()

            if isFirstChunk {
                self.isStreaming = true
                self.organizationStage = "Receiving AI response..."
                self.progress = 0.30
                self.displayStreamingContent = self.streamingContent
                
                // Start steady progress task for smooth animation
                self.startSteadyProgressTask()
            }

            // Throttle display updates to prevent layout loops (100ms)
            let now = Date()
            if now.timeIntervalSince(self.lastDisplayUpdate) >= self.displayUpdateInterval {
                self.displayStreamingContent = self.streamingContent
                self.lastDisplayUpdate = now
            }

            // Increment progress based on content received
            // Estimate total based on file count (~100 chars per file in JSON output)
            let contentLength = self.streamingContent.count
            let estimatedTotal = max(3000, self.scannedFileCount * 100)
            let contentProgress = min(0.80, 0.30 + (Double(contentLength) / Double(estimatedTotal)) * 0.50)

            if self.progress < contentProgress {
                self.progress = contentProgress
            }
            
            // Extract insights from streaming content (throttled)
            self.extractInsightsIfNeeded()
        }
    }
    
    /// Starts a background task that ensures progress keeps moving even during pauses
    private func startSteadyProgressTask() {
        steadyProgressTask?.cancel()
        steadyProgressTask = Task { @MainActor in
            while !Task.isCancelled && !isCancellationRequested && isStreaming {
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                guard !Task.isCancelled && !isCancellationRequested && isStreaming else { break }
                
                // If we haven't reached 0.82 and no recent chunk, nudge progress
                if self.progress < 0.82 {
                    let timeSinceLastChunk = Date().timeIntervalSince(self.lastChunkTime)
                    
                    // If it's been more than 1 second since last chunk, nudge progress
                    if timeSinceLastChunk > 1.0 {
                        // Small increment to keep progress moving (0.5% every 500ms)
                        self.progress = min(0.82, self.progress + 0.005)
                    }
                }
            }
        }
    }
    
    /// Stops the steady progress task
    private func stopSteadyProgressTask() {
        steadyProgressTask?.cancel()
        steadyProgressTask = nil
    }
    
    /// Extract meaningful insights from the streaming AI response
    /// This is throttled to avoid performance impact
    private func extractInsightsIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastInsightExtraction) >= insightExtractionInterval else { return }
        lastInsightExtraction = now
        
        // Get the last portion of content for analysis
        let content = streamingContent
        guard content.count > 50 else { return }
        
        // Look for meaningful patterns in the content
        let insight = extractInsight(from: content)
        if let insight = insight, insight.text != currentInsight {
            currentInsight = insight.text
            
            // Keep history limited to last 5 insights
            if insightHistory.count >= 5 {
                insightHistory.removeFirst()
            }
            insightHistory.append(insight)
        }
    }
    
    /// Parse streaming content to find meaningful insights
    private func extractInsight(from content: String) -> AIInsight? {
        // Get the last ~500 characters for analysis
        let analysisWindow = String(content.suffix(500))
        
        // Look for file-related insights
        if let fileMatch = extractFileInsight(from: analysisWindow) {
            return fileMatch
        }
        
        // Look for folder/destination insights
        if let folderMatch = extractFolderInsight(from: analysisWindow) {
            return folderMatch
        }
        
        // Look for constraint/consideration insights
        if let constraintMatch = extractConstraintInsight(from: analysisWindow) {
            return constraintMatch
        }
        
        // Look for decision/action insights
        if let decisionMatch = extractDecisionInsight(from: analysisWindow) {
            return decisionMatch
        }
        
        // Fallback: extract any recent meaningful text
        return extractGeneralInsight(from: analysisWindow)
    }
    
    private func extractFileInsight(from text: String) -> AIInsight? {
        // Look for patterns like "file: X", "processing X.pdf", "analyzing document.txt"
        let patterns = [
            #"(?:file|document|processing|analyzing)[:\s]+["']?([^"'\n,]{3,40})["']?"#,
            #""([^"]{3,40}\.[a-zA-Z]{2,5})""#,
            #"'([^']{3,40}\.[a-zA-Z]{2,5})'"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let fileName = String(text[range]).trimmingCharacters(in: .whitespaces)
                if !fileName.isEmpty && fileName.count < 50 {
                    return AIInsight(text: "Analyzing \(fileName)", category: .file)
                }
            }
        }
        return nil
    }
    
    private func extractFolderInsight(from text: String) -> AIInsight? {
        // Look for folder/destination patterns
        let patterns = [
            #"(?:folder|directory|destination|move to|into)[:\s]+["']?([^"'\n,/]{3,30})["']?"#,
            #"→\s*["']?([^"'\n,]{3,30})["']?"#,
            #"creating folder[:\s]+["']?([^"'\n,]{3,30})["']?"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let folderName = String(text[range]).trimmingCharacters(in: .whitespaces)
                if !folderName.isEmpty && folderName.count < 40 {
                    return AIInsight(text: "Organizing into \(folderName)", category: .folder)
                }
            }
        }
        return nil
    }
    
    private func extractConstraintInsight(from text: String) -> AIInsight? {
        // Look for constraint/consideration patterns
        let patterns = [
            #"(?:considering|constraint|rule|preference)[:\s]+([^.\n]{10,60})"#,
            #"(?:because|since|due to)[:\s]+([^.\n]{10,50})"#,
            #"(?:based on|according to)[:\s]+([^.\n]{10,50})"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let constraint = String(text[range]).trimmingCharacters(in: .whitespaces)
                if constraint.count > 10 && constraint.count < 70 {
                    return AIInsight(text: constraint.prefix(60) + (constraint.count > 60 ? "..." : ""), category: .constraint)
                }
            }
        }
        return nil
    }
    
    private func extractDecisionInsight(from text: String) -> AIInsight? {
        // Look for decision/action patterns
        let patterns = [
            #"(?:will move|moving|placing|organizing)[:\s]+([^.\n]{10,50})"#,
            #"(?:grouped with|categorized as|belongs to)[:\s]+([^.\n]{5,40})"#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let decision = String(text[range]).trimmingCharacters(in: .whitespaces)
                if decision.count > 5 && decision.count < 60 {
                    return AIInsight(text: decision, category: .decision)
                }
            }
        }
        return nil
    }
    
    private func extractGeneralInsight(from text: String) -> AIInsight? {
        // Look for any meaningful recent text segment
        // Find the last complete sentence or phrase
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        
        // Get the last meaningful sentence
        for sentence in sentences.reversed() {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 15 && trimmed.count <= 80 {
                // Skip if it looks like JSON or code
                if !trimmed.contains("{") && !trimmed.contains("}") && !trimmed.contains("[") {
                    return AIInsight(text: trimmed, category: .general)
                }
            }
        }
        return nil
    }

    public nonisolated func didComplete(content: String) {
        Task { @MainActor in
            self.isStreaming = false
            self.organizationStage = "Processing response..."
            self.stopTimeoutTimer()
            self.stopSteadyProgressTask()
        }
    }

    public nonisolated func didFail(error: Error) {
        Task { @MainActor in
            self.isStreaming = false
            self.errorMessage = error.localizedDescription
            self.stopTimeoutTimer()
            self.stopSteadyProgressTask()
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
            scannedFileCount = files.count

            updateProgress(0.15, stage: "Found \(files.count) files")

            try checkCancellation()

            if let exclusionRules = exclusionRules {
                files = exclusionRules.filterFiles(files)
                updateProgress(0.20, stage: "Filtered to \(files.count) files")
            }

            try checkCancellation()

            updateState(.organizing, stage: "Establishing connection...", progress: 0.22)
            await MainActor.run {
                isStreaming = false
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
            
            // Add Storage Locations context (external destinations for files)
            if let storageContext = storageLocationsManager?.generatePromptContext(), !storageContext.isEmpty {
                instructions += "\n\n" + storageContext
                DebugLogger.log("Injected Storage Locations context into prompt")
            }

            let plan = try await client.analyze(files: files, customInstructions: instructions, personaPrompt: personaPrompt, temperature: temperature)

            try checkCancellation()

            stopTimeoutTimer()

            updateState(.organizing, stage: "Validating plan...", progress: 0.85)
            await MainActor.run {
                isStreaming = false
            }

            try validator.validate(plan, at: directory, maxTopLevelFolders: aiConfig?.maxTopLevelFolders ?? 10)

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
        displayStreamingContent = streamingContent // Sync final content
        isCancellationRequested = false
        userInitiatedAction = false
        stopSteadyProgressTask()
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
                if let item = try? await scanner.scanFile(at: fileURL) {
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
            
            // Add Storage Locations context
            if let storageContext = storageLocationsManager?.generatePromptContext(), !storageContext.isEmpty {
                finalPrompt += "\n\n" + storageContext
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
            
            // Add Storage Locations context
            if let storageContext = storageLocationsManager?.generatePromptContext(), !storageContext.isEmpty {
                instructions += "\n\n" + storageContext
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
    /// Returns the RestoreResult with details about any skipped files
    @discardableResult
    public func undoHistoryEntry(_ entry: OrganizationHistoryEntry) async throws -> FileSystemManager.RestoreResult {
        guard let operations = entry.operations, !entry.isUndone else { 
            return FileSystemManager.RestoreResult(successfulOperations: 0, missingFiles: [])
        }

        updateState(.applying, stage: "Undoing changes...", progress: 0.3)

        do {
            let result = try await fileSystemManager.reverseOperations(operations)

            var updatedEntry = entry
            updatedEntry.isUndone = true
            updatedEntry.status = .undo
            history.updateEntry(updatedEntry)

            await MainActor.run {
                organizationStage = result.hasIssues ? "Undo complete (some files skipped)" : "Undo complete"
                progress = 1.0
                state = .idle
            }

            NotificationCenter.default.post(
                name: .organizationDidRevert,
                object: nil,
                userInfo: [
                    "url": URL(fileURLWithPath: entry.directoryPath),
                    "entry": entry,
                    "restoreResult": result
                ]
            )
            
            return result

        } catch {
            await MainActor.run {
                state = .error(error)
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// Restores to a previous state by undoing all intermediate sessions
    /// Returns a combined RestoreResult with totals from all undone entries
    @discardableResult
    public func restoreToState(targetEntry: OrganizationHistoryEntry) async throws -> FileSystemManager.RestoreResult {
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
        var combinedSuccessCount = 0
        var combinedMissingFiles: [String] = []

        for (index, entry) in entriesToUndo.enumerated() {
            updateProgress(Double(index) / total, stage: "Undoing session from \(entry.timestamp.formatted())...")

            let result = try await undoHistoryEntry(entry)
            combinedSuccessCount += result.successfulOperations
            combinedMissingFiles.append(contentsOf: result.missingFiles)
        }

        let combinedResult = FileSystemManager.RestoreResult(
            successfulOperations: combinedSuccessCount,
            missingFiles: combinedMissingFiles
        )

        await MainActor.run {
            organizationStage = combinedResult.hasIssues ? "Restoration complete (some files skipped)" : "Restoration complete"
            progress = 1.0
            state = .idle
        }
        
        return combinedResult
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
        displayStreamingContent = ""
        organizationStage = ""
        isStreaming = false
        showTimeoutMessage = false
        elapsedTime = 0
        currentDirectory = nil
        scannedFileCount = 0
        isCancellationRequested = false
        userInitiatedAction = false
        lastDisplayUpdate = .distantPast
        lastChunkTime = .distantPast
        
        // Stop background tasks
        stopSteadyProgressTask()
        
        // Clear AI insights
        currentInsight = ""
        insightHistory = []
        lastInsightExtraction = .distantPast
    }
}

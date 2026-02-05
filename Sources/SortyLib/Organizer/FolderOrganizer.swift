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
    
    /// Returns true if a transition from `from` state to `to` state is valid
    public static func canTransition(from: OrganizationState, to: OrganizationState) -> Bool {
        // Same state is always valid (no-op)
        if from == to {
            return true
        }
        
        // From idle: can go to scanning or error
        if from == .idle {
            switch to {
            case .idle, .scanning, .error:
                return true
            default:
                return false
            }
        }
        
        // From scanning: can go to organizing, idle (cancel), or error
        if from == .scanning {
            switch to {
            case .scanning, .organizing, .idle, .error:
                return true
            default:
                return false
            }
        }
        
        // From organizing: can go to ready, idle (cancel), or error
        if from == .organizing {
            switch to {
            case .organizing, .ready, .idle, .error:
                return true
            default:
                return false
            }
        }
        
        // From ready: can go to applying, idle (cancel), organizing (regenerate), or error
        if from == .ready {
            switch to {
            case .ready, .applying, .idle, .organizing, .error:
                return true
            default:
                return false
            }
        }
        
        // From applying: can go to completed, idle (cancel), or error
        if from == .applying {
            switch to {
            case .applying, .completed, .idle, .error:
                return true
            default:
                return false
            }
        }
        
        // From completed: can only go to idle (reset)
        if from == .completed {
            switch to {
            case .completed, .idle:
                return true
            default:
                return false
            }
        }
        
        // From error: can go to idle (retry/reset), or retry the previous operation
        if case .error = from {
            switch to {
            case .error, .idle, .scanning, .organizing:
                return true
            default:
                return false
            }
        }
        
        return false
    }
    
    /// Human-readable description of the state
    public var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .scanning:
            return "Scanning"
        case .organizing:
            return "Organizing"
        case .ready:
            return "Ready"
        case .applying:
            return "Applying"
        case .completed:
            return "Completed"
        case .error(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
}

public enum OrganizationError: LocalizedError, Equatable {
    case clientNotConfigured
    case automationNotConfigured
    case noCurrentPlan
    case fileMoveFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .clientNotConfigured:
            return "AI Client not configured. Please check your settings."
        case .automationNotConfigured:
            return "Automation permission not granted. Please enable it in System Settings > Privacy & Security > Automation."
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
    public let filePath: String? // Optional path for thumbnails
    
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
    
    public init(text: String, category: Category, filePath: String? = nil) {
        self.text = text
        self.category = category
        self.timestamp = Date()
        self.filePath = filePath
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
    
    // MARK: - AI Insights Cache
    
    /// Cache for pre-computed AI insights to avoid re-parsing during UI rendering
    private var insightsCache: InsightsCache?
    
    /// Structure to hold cached insights data
    private struct InsightsCache {
        let streamingContentHash: Int
        let insights: [AIInsight]
        let currentInsight: String
        let timestamp: Date
        
        var isValid: Bool {
            Date().timeIntervalSince(timestamp) < 2.0 // Cache valid for 2 seconds
        }
    }

    // Timeout messaging
    @Published public var elapsedTime: TimeInterval = 0
    @Published public var showTimeoutMessage: Bool = false
    private var startTime: Date?
    private var timeoutTask: Task<Void, Never>?
    
    // MARK: - Batch Update Mechanism
    
    /// Batches multiple @Published property updates into a single objectWillChange.send()
    /// This prevents multiple UI refresh cycles when updating related properties
    @MainActor
    public func withBatchUpdates(_ updates: () -> Void) {
        objectWillChange.send()
        updates()
    }
    
    /// Perform batch updates asynchronously
    @MainActor
    public func withBatchUpdatesAsync(_ updates: () async -> Void) async {
        objectWillChange.send()
        await updates()
    }
    
    // MARK: - State Transition Validation
    
    /// Validates and performs a state transition
    /// - Parameters:
    ///   - newState: The target state to transition to
    ///   - force: If true, bypasses validation (use with caution)
    /// - Returns: True if the transition was successful
    @MainActor
    @discardableResult
    public func transition(to newState: OrganizationState, force: Bool = false) -> Bool {
        let currentState = state
        
        // Always allow same state (no-op)
        if currentState == newState {
            state = newState
            return true
        }
        
        // Validate transition
        let isValid = force || OrganizationState.canTransition(from: currentState, to: newState)
        
        if isValid {
            state = newState
            return true
        } else {
            // Log invalid transition attempt
            LogManager.shared.log(
                "Invalid state transition attempted: \(currentState.description) -> \(newState.description)",
                level: .warning,
                category: "FolderOrganizer"
            )
            return false
        }
    }
    
    /// Convenience method to reset to idle state
    @MainActor
    public func resetToIdleState() {
        _ = transition(to: .idle)
    }

    // Track current directory for status checks
    @Published public var currentDirectory: URL?
    
    // Track detected duplicates for the current session
    @Published public var detectedDuplicates: [DuplicateGroup] = []
    
    // Track file count for better progress estimation
    public var scannedFileCount: Int = 0
    @Published public var scannedFiles: [FileItem] = []
    private var scannedFilePathLookup: [String: [String]] = [:]

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
    public var automationManager: AutomationManager?

    /// Exclusion enforcer for post-AI validation (lazily initialized)
    private var exclusionEnforcer: ExclusionEnforcer?

    /// Learning observer reference for rule tracking
    public var learningsObserver: ContinuousLearningObserver?
    
    private let visionAnalyzer = ImageVisionAnalyzer()
    
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
                // Batch all initial state updates together
                self.withBatchUpdates {
                    self.isStreaming = true
                    self.organizationStage = "Receiving AI response..."
                    self.progress = 0.30
                    self.displayStreamingContent = self.streamingContent
                }
                
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
            
            // Extract insights from streaming content (throttled and cached)
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
    /// This is throttled and uses caching to avoid performance impact
    private func extractInsightsIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastInsightExtraction) >= insightExtractionInterval else { return }
        lastInsightExtraction = now
        
        // Get the last portion of content for analysis
        let content = streamingContent
        guard content.count > 50 else { return }
        
        // Check cache first
        let contentHash = content.hashValue
        if let cache = insightsCache, 
           cache.streamingContentHash == contentHash,
           cache.isValid {
            // Use cached insights
            withBatchUpdates {
                self.currentInsight = cache.currentInsight
                self.insightHistory = cache.insights
            }
            return
        }
        
        // Look for meaningful patterns in the content
        let insight = extractInsight(from: content)
        if let insight = insight, insight.text != currentInsight {
            // Batch update all insight-related properties at once
            withBatchUpdates {
                self.currentInsight = insight.text
                
                // Keep history limited to last 5 insights
                if self.insightHistory.count >= 5 {
                    self.insightHistory.removeFirst()
                }
                self.insightHistory.append(insight)
            }
            
            // Update cache
            insightsCache = InsightsCache(
                streamingContentHash: contentHash,
                insights: insightHistory,
                currentInsight: insight.text,
                timestamp: Date()
            )
        }
    }
    
    /// Get cached insights if available, otherwise returns current insights
    /// Use this from UI to avoid re-parsing during render
    public func getCachedInsights() -> (current: String, history: [AIInsight]) {
        if let cache = insightsCache, cache.isValid {
            return (cache.currentInsight, cache.insights)
        }
        return (currentInsight, insightHistory)
    }
    
    /// Invalidate the insights cache (call when streaming content significantly changes)
    public func invalidateInsightsCache() {
        insightsCache = nil
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
                    // Try to match with an actual file path from the scan if possible
                    let filePath = findScannedFilePath(for: fileName)
                    return AIInsight(text: "Analyzing \(fileName)", category: .file, filePath: filePath)
                }
            }
        }
        return nil
    }

    private func findScannedFilePath(for fileName: String) -> String? {
        guard currentDirectory != nil else { return nil }
        let sanitized = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        let lastComponent = sanitized.contains("/")
            ? URL(fileURLWithPath: sanitized).lastPathComponent
            : sanitized
        let key = lastComponent.lowercased()
        if let matches = scannedFilePathLookup[key], !matches.isEmpty {
            if matches.count == 1 {
                return matches[0]
            }
            if let basePath = currentDirectory?.path,
               let preferred = matches.first(where: { $0.hasPrefix(basePath + "/") }) {
                return preferred
            }
            return matches[0]
        }
        return nil
    }
    
    private func setScannedFiles(_ files: [FileItem]) {
        scannedFiles = files
        scannedFilePathLookup = Dictionary(grouping: files, by: { $0.displayName.lowercased() })
            .mapValues { $0.map { $0.path } }
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
            
            // Refined JSON/Code detection
            guard trimmed.count >= 15 && trimmed.count <= 80 else { continue }
            
            // Skip if it looks like JSON or code
            let isProbablyJSON = trimmed.contains("{") || 
                                 trimmed.contains("}") || 
                                 trimmed.contains("[") || 
                                 trimmed.contains("]") ||
                                 trimmed.contains("\":") ||
                                 trimmed.contains("':") ||
                                 (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            
            if !isProbablyJSON {
                return AIInsight(text: trimmed, category: .general)
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

            let filesFound = try await scanner.scanDirectory(
                at: directory,
                deepScan: (aiConfig?.enableDeepScan ?? false) && (aiConfig?.provider.supportsDeepScan ?? true)
            )
            scannedFileCount = filesFound.count
            setScannedFiles(filesFound)

            updateProgress(0.15, stage: "Found \(filesFound.count) files")

            try checkCancellation()

            var files = filesFound
            if let exclusionRules = exclusionRules {
                files = exclusionRules.filterFiles(files)
                updateProgress(0.20, stage: "Filtered to \(files.count) files")
            }

            try checkCancellation()
            
            // Phase 1.5: Duplicate Detection
            var duplicateContext: String = ""
            if aiConfig?.detectDuplicates ?? false {
                updateProgress(0.21, stage: "Checking for duplicates...")
                let duplicates = await DuplicateDetector().findDuplicates(in: files)
                await MainActor.run {
                    self.detectedDuplicates = duplicates
                }
                if !duplicates.isEmpty {
                    duplicateContext = "\n\nDUPLICATE FILES DETECTED:\n"
                    for group in duplicates {
                        duplicateContext += "- The following files are identical (SHA-256 hash: \(group.hash)):\n"
                        for file in group.files {
                            duplicateContext += "  • \(file.displayName) (\(file.path))\n"
                        }
                    }
                    duplicateContext += "\nRECOMMENDATION FOR DUPLICATES:\n"
                    duplicateContext += "1. If you suggest moving duplicates, try to consolidate them or use a 'Duplicates' folder.\n"
                    duplicateContext += "2. You can suggest better names for them, but keep them in mind for organization.\n"
                }
            } else {
                await MainActor.run {
                    self.detectedDuplicates = []
                }
            }

            updateState(.organizing, stage: "Establishing connection...", progress: 0.22)
            await MainActor.run {
                isStreaming = false
            }

            startTimeoutTimer()

            try checkCancellation()

            let personaPrompt = personaManager?.getEffectivePrompt(customStore: customPersonaStore ?? CustomPersonaStore())
            
            // Add exclusion context to prompt
            var instructions = customPrompt ?? customInstructions
            if !duplicateContext.isEmpty {
                instructions += duplicateContext
            }
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
            
            // Add Existing Folders context (prefer reusing existing structure)
            if let existingFoldersContext = PromptBuilder.buildExistingFoldersContext(at: directory) {
                instructions += "\n\n" + existingFoldersContext
                DebugLogger.log("Injected Existing Folders context into prompt")
            }

            // Phase 2: Vision Integration
            var imagePayload: [String: Data] = [:]
            if aiConfig?.enableVision ?? false,
               let modelId = aiConfig?.model,
               let provider = aiConfig?.provider,
               ModelCatalog.shared.supportsVision(modelId: modelId, provider: provider) {
                
                let imageFiles = files.filter { ["jpg", "jpeg", "png", "heic", "webp"].contains($0.extension.lowercased()) }
                if !imageFiles.isEmpty {
                    updateProgress(0.25, stage: "Analyzing \(imageFiles.count) images with Vision AI...")
                    let batch = Array(imageFiles.prefix(aiConfig?.visionBatchSize ?? 5))
                    let urlPayload = await visionAnalyzer.prepareImagesForVision(urls: batch.compactMap { $0.url })
                    // Convert URL keys to filename strings
                    for (url, data) in urlPayload {
                        imagePayload[url.lastPathComponent] = data
                    }
                    DebugLogger.log("Prepared \(imagePayload.count) images for multimodal analysis")
                }
            }

            let plan: OrganizationPlan
            if !imagePayload.isEmpty {
                plan = try await client.analyzeWithImages(
                    files: files,
                    imageData: imagePayload,
                    customInstructions: instructions,
                    personaPrompt: personaPrompt,
                    temperature: temperature
                )
            } else {
                plan = try await client.analyze(
                    files: files, 
                    customInstructions: instructions, 
                    personaPrompt: personaPrompt, 
                    temperature: temperature
                )
            }

            try checkCancellation()

            stopTimeoutTimer()

            updateState(.organizing, stage: "Validating plan...", progress: 0.85)
            await MainActor.run {
                isStreaming = false
            }

            // In rename-only mode, we don't need to validate folder depth limits strictly
            // but we still validate the overall JSON structure.
            let maxFolders = aiConfig?.mode == .renameOnly ? 100 : (aiConfig?.maxTopLevelFolders ?? 10)
            let allowedLocations = storageLocationsManager?.enabledLocations ?? []
            
            var validatedPlanFromRetry: OrganizationPlan? = nil
            do {
                try validator.validate(plan, at: directory, allowedStorageLocations: allowedLocations, maxTopLevelFolders: maxFolders)
            } catch let validationError as ValidationError {
                // Attempt one retry for recoverable validation errors
                if let retryPlan = await retryWithValidationEnhancement(
                    files: files,
                    client: client,
                    validationError: validationError,
                    directory: directory,
                    instructions: instructions,
                    personaPrompt: personaPrompt,
                    temperature: temperature,
                    imagePayload: imagePayload,
                    maxTopLevelFolders: maxFolders,
                    allowedStorageLocations: allowedLocations
                ) {
                    validatedPlanFromRetry = retryPlan
                } else {
                    throw validationError
                }
            }
            
            let planAfterValidation = validatedPlanFromRetry ?? plan

            try checkCancellation()
            
            // Post-AI exclusion validation
            var validatedPlan = planAfterValidation
            if let exclusionRules = exclusionRules {
                let enforcer = ExclusionEnforcer(exclusionManager: exclusionRules)
                self.exclusionEnforcer = enforcer
                
                let validationResult = enforcer.validate(planAfterValidation)
                
                if validationResult.hasViolations {
                    LogManager.shared.log("Exclusion violations detected: \(validationResult.violationCount) files", category: "FolderOrganizer")
                    
                    // Try to retry once with enhanced prompt
                    if let retryPlan = await retryWithExclusionEnhancement(
                        files: files,
                        client: client,
                        violations: validationResult.violations,
                        instructions: instructions,
                        personaPrompt: personaPrompt,
                        temperature: temperature,
                        imagePayload: imagePayload
                    ) {
                        // Validate retry result
                        let retryValidation = enforcer.validate(retryPlan)
                        if retryValidation.hasViolations {
                            // Still violations, strip them and proceed with warning
                            LogManager.shared.log("Retry still has \(retryValidation.violationCount) violations, stripping", category: "FolderOrganizer")
                            validatedPlan = retryValidation.cleanedPlan ?? retryPlan
                        } else {
                            validatedPlan = retryPlan
                        }
                    } else {
                        // Retry failed, use cleaned plan
                        validatedPlan = validationResult.cleanedPlan ?? planAfterValidation
                    }
                }
            }

            updateState(.ready, stage: "Ready!", progress: 1.0)
            await MainActor.run {
                currentPlan = validatedPlan
            }

            // Send notification when preview is ready
            NotificationManager.shared.show(.previewReady(folderName: directory.lastPathComponent))
            
            // Start learning session for the new plan
            if let learningsObserver = learningsObserver {
                learningsObserver.startSession(folderPath: directory.path, historyEntryId: nil)
                
                // Track which rules were applied to each file
                recordPlanRules(plan, observer: learningsObserver)
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
        // Record cancellation in history if we were in a meaningful state
        if state == .organizing || state == .ready {
            if let directory = currentDirectory {
                let cancelledEntry = OrganizationHistoryEntry(
                    directoryPath: directory.path,
                    filesOrganized: 0,
                    foldersCreated: 0,
                    plan: currentPlan,
                    success: false,
                    status: .cancelled,
                    errorMessage: "User cancelled the operation",
                    rawAIResponse: streamingContent.isEmpty ? nil : streamingContent
                )
                history.addEntry(cancelledEntry)
                DebugLogger.log("Saved cancelled operation to history")

                // Record to learnings with rich context
                let fileCount = (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
                let proposedFolders = currentPlan?.suggestions.count ?? 0
                
                // Extract folder names from current plan
                let folderNames = currentPlan?.suggestions.map { $0.folderName }
                
                // Build a compressed structure summary
                let structureSummary = currentPlan.map { plan -> String in
                    let summary = plan.suggestions.prefix(10).map { folder -> String in
                        let fileCount = folder.files.count
                        let subfolderCount = folder.subfolders.count
                        return "\(folder.folderName)(\(fileCount)f\(subfolderCount > 0 ? ",\(subfolderCount)sf" : ""))"
                    }.joined(separator: ";")
                    return plan.suggestions.count > 10 ? "\(summary);+\(plan.suggestions.count - 10)more" : summary
                }
                
                // Extract file extension counts from directory
                var extensionCounts: [String: Int]?
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
                    var counts: [String: Int] = [:]
                    for item in contents {
                        let ext = (item as NSString).pathExtension.lowercased()
                        let key = ext.isEmpty ? "other" : ext
                        counts[key, default: 0] += 1
                    }
                    extensionCounts = counts
                }
                
                learningsManager?.recordCancelledOrganization(
                    folderPath: directory.path,
                    fileCount: fileCount,
                    proposedFolderCount: proposedFolders,
                    instructions: customInstructions.isEmpty ? nil : customInstructions,
                    stage: organizationStage,
                    proposedFolderNames: folderNames,
                    proposedStructureSummary: structureSummary,
                    fileExtensionCounts: extensionCounts,
                    regenerationCount: currentPlan?.version ?? 0,
                    regenerationInstructions: nil,
                    aiModel: aiConfig?.model
                )
            }
        }

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
        
        // Show error notification (unless cancelled)
        if case .cancelled = error as? OrganizationError {
            // Don't show notification for user-initiated cancellation
        } else {
            NotificationManager.shared.showError(
                message: error.localizedDescription,
                isCritical: true
            )
        }
    }

    // MARK: - Exclusion Retry
    
    /// Retry AI call with enhanced exclusion prompt after violations
    private func retryWithExclusionEnhancement(
        files: [FileItem],
        client: AIClientProtocol,
        violations: [ExclusionViolation],
        instructions: String,
        personaPrompt: String?,
        temperature: Double?,
        imagePayload: [String: Data]
    ) async -> OrganizationPlan? {
        guard let enforcer = exclusionEnforcer else { return nil }
        
        LogManager.shared.log("Retrying with enhanced exclusion prompt", category: "FolderOrganizer")
        updateProgress(0.87, stage: "Correcting exclusions...")
        
        // Generate enhanced prompt with violation details
        let enhancedPrompt = instructions + enforcer.generateRetryPromptEnhancement(for: violations)
        
        do {
            let retryPlan: OrganizationPlan
            if !imagePayload.isEmpty {
                retryPlan = try await client.analyzeWithImages(
                    files: files,
                    imageData: imagePayload,
                    customInstructions: enhancedPrompt,
                    personaPrompt: personaPrompt,
                    temperature: temperature
                )
            } else {
                retryPlan = try await client.analyze(
                    files: files,
                    customInstructions: enhancedPrompt,
                    personaPrompt: personaPrompt,
                    temperature: temperature
                )
            }
            return retryPlan
        } catch {
            LogManager.shared.log("Exclusion retry failed: \(error.localizedDescription)", category: "FolderOrganizer")
            return nil
        }
    }
    
    private func retryWithValidationEnhancement(
        files: [FileItem],
        client: AIClientProtocol,
        validationError: ValidationError,
        directory: URL,
        instructions: String,
        personaPrompt: String?,
        temperature: Double?,
        imagePayload: [String: Data],
        maxTopLevelFolders: Int,
        allowedStorageLocations: [StorageLocation]
    ) async -> OrganizationPlan? {
        let enhancement: String
        switch validationError {
        case .tooManyFolders(let count, let max):
            LogManager.shared.log("Retrying: too many folders (\(count) > \(max))", category: "FolderOrganizer")
            updateProgress(0.87, stage: "Too many folders, retrying...")
            enhancement = """
            
            CRITICAL CORRECTION REQUIRED:
            Your previous response created \(count) top-level folders, but the maximum allowed is \(max).
            You MUST consolidate categories to produce at most \(max) top-level folders.
            Merge related categories together. For example, combine "Work Documents" and "Reports" into "Work", or group smaller categories into a single "Misc" folder.
            """
        case .pathExists(let path):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            LogManager.shared.log("Retrying: path exists conflict (\(fileName))", category: "FolderOrganizer")
            updateProgress(0.87, stage: "Folder name conflict, retrying...")
            enhancement = """
            
            CRITICAL CORRECTION REQUIRED:
            You suggested a folder named "\(fileName)", but a FILE with that exact name already exists in the directory.
            You MUST NOT use "\(fileName)" as a folder name.
            Choose a different folder name that does not conflict with existing files. For example, add a suffix like "\(fileName) Files" or use a different category name.
            """
        default:
            return nil
        }
        
        let enhancedPrompt = instructions + enhancement
        
        do {
            let retryPlan: OrganizationPlan
            if !imagePayload.isEmpty {
                retryPlan = try await client.analyzeWithImages(
                    files: files,
                    imageData: imagePayload,
                    customInstructions: enhancedPrompt,
                    personaPrompt: personaPrompt,
                    temperature: temperature
                )
            } else {
                retryPlan = try await client.analyze(
                    files: files,
                    customInstructions: enhancedPrompt,
                    personaPrompt: personaPrompt,
                    temperature: temperature
                )
            }
            
            // Validate the retry plan
            try validator.validate(retryPlan, at: directory, allowedStorageLocations: allowedStorageLocations, maxTopLevelFolders: maxTopLevelFolders)
            LogManager.shared.log("Validation retry succeeded", category: "FolderOrganizer")
            return retryPlan
        } catch {
            LogManager.shared.log("Validation retry failed: \(error.localizedDescription)", category: "FolderOrganizer")
            return nil
        }
    }
    
    // MARK: - State Updates with Progress

    @MainActor
    private func updateState(_ newState: OrganizationState, stage: String, progress: Double) {
        guard !isCancellationRequested else { return }
        
        // Validate state transition
        let didTransition = transition(to: newState)
        guard didTransition else { return }
        
        // Update other properties
        organizationStage = stage
        self.progress = progress
    }

    @MainActor
    private func updateProgress(_ progress: Double, stage: String? = nil) {
        guard !isCancellationRequested else { return }
        if let stage = stage {
            // Batch when updating both progress and stage
            withBatchUpdates {
                self.progress = progress
                self.organizationStage = stage
            }
        } else {
            self.progress = progress
        }
    }

    // MARK: - Incremental Organization (for watched folders)

    public func organizeIncremental(directory: URL, specificFiles: [String]? = nil, customPrompt: String? = nil, temperature: Double? = nil, providerOverride: AIProvider? = nil, modelOverride: String? = nil) async throws {
        guard !isOperationInProgress() else {
            DebugLogger.log("Incremental organization blocked: Already in progress")
            return
        }

        cancelInternal()
        isCancellationRequested = false

        currentTask = Task {
            try await performIncrementalOrganization(directory: directory, specificFiles: specificFiles, customPrompt: customPrompt, temperature: temperature, providerOverride: providerOverride, modelOverride: modelOverride)
        }

        do {
            try await currentTask?.value
        } catch is CancellationError {
            resetToIdle()
        }
    }

    private func performIncrementalOrganization(directory: URL, specificFiles: [String]?, customPrompt: String?, temperature: Double?, providerOverride: AIProvider? = nil, modelOverride: String? = nil) async throws {
        // Use override client if specified, otherwise use default
        let client: AIClientProtocol
        if let providerOverride = providerOverride, let modelOverride = modelOverride {
            var overrideConfig = self.aiConfig ?? AIConfig.default
            overrideConfig.provider = providerOverride
            overrideConfig.model = modelOverride
            if let apiKey = KeychainManager.get(key: providerOverride.keychainKey) {
                overrideConfig.apiKey = apiKey
            }
            overrideConfig.apiURL = providerOverride.defaultAPIURL
            client = try AIClientFactory.createClient(config: overrideConfig)
        } else {
            guard let defaultClient = aiClient else {
                throw OrganizationError.clientNotConfigured
            }
            client = defaultClient
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
            setScannedFiles(files)
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
            setScannedFiles(files)
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

    // MARK: - Organize Selected Files from Finder

    /// Organize only the files currently selected in Finder
    /// This uses Automation permission to get the selection from Finder
    /// - Parameters:
    ///   - customPrompt: Optional custom instructions for the AI
    ///   - temperature: Optional temperature override for AI generation
    /// - Returns: The number of files organized, or nil if no selection available
    @discardableResult
    public func organizeSelectedFiles(customPrompt: String? = nil, temperature: Double? = nil) async throws -> Int {
        guard let automationManager = automationManager else {
            throw OrganizationError.automationNotConfigured
        }

        // Check if we have automation permission
        guard automationManager.automationStatus == .granted else {
            throw NSError(domain: "Sorty", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Automation permission not granted. Please enable it in System Settings to organize selected files."
            ])
        }

        // Get the selected files from Finder
        guard let selectedFiles = FinderAutomation.getSelectedFiles(), !selectedFiles.isEmpty else {
            await MainActor.run {
                state = .idle
                organizationStage = "No files selected in Finder"
            }
            return 0
        }

        // Get the directory of the first selected file (assume all are in same folder)
        let firstFile = selectedFiles[0]
        let directory = firstFile.deletingLastPathComponent()

        // Convert URLs to FileItems
        var files: [FileItem] = []
        for url in selectedFiles {
            if let item = try? await scanner.scanFile(at: url) {
                files.append(item)
            }
        }
        setScannedFiles(files)

        guard !files.isEmpty else {
            await MainActor.run {
                state = .idle
                organizationStage = "Could not scan selected files"
            }
            return 0
        }

        // Filter with exclusion rules
        if let exclusionRules = exclusionRules {
            files = exclusionRules.filterFiles(files)
        }

        guard !files.isEmpty else {
            await MainActor.run {
                state = .idle
                organizationStage = "Selected files filtered by exclusion rules"
            }
            return 0
        }

        // Set the current directory
        currentDirectory = directory

        // Start the organization process
        guard !isOperationInProgress() else {
            DebugLogger.log("Selected files organization blocked: Already in progress")
            return 0
        }

        cancelInternal()
        isCancellationRequested = false
        userInitiatedAction = true

        currentTask = Task {
            try await performOrganizationOfSelectedFiles(
                directory: directory,
                files: files,
                customPrompt: customPrompt,
                temperature: temperature
            )
        }

        do {
            try await currentTask?.value
            return files.count
        } catch is CancellationError {
            resetToIdle()
            return 0
        }
    }

    private func performOrganizationOfSelectedFiles(
        directory: URL,
        files: [FileItem],
        customPrompt: String?,
        temperature: Double?
    ) async throws {
        guard let client = aiClient else {
            throw OrganizationError.clientNotConfigured
        }

        updateState(.organizing, stage: "Organizing \(files.count) selected files...", progress: 0.3)
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
            SELECTED FILES ONLY: You are organizing only the files currently selected in Finder.

            Existing folders in this directory: \(existingFolders.joined(separator: ", ")).

            RULES for Selected File Organization:
            1. Prioritize placing files into existing folders if relevant.
            2. Only create new folders if the files don't fit existing structure.
            3. Files that don't fit anywhere can remain in the root.
            4. Focus only on the selected files - do not touch other files in the folder.
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

            // Apply the organization
            try await apply(at: directory, dryRun: false, enableTagging: aiConfig?.enableFileTagging ?? true)

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

        updateState(.applying, stage: "Preparing organization...", progress: 0.0)
        
        // Start learning session for rule tracking
        if let learningsObserver = learningsObserver {
            learningsObserver.startSession(folderPath: baseURL.path, historyEntryId: nil)
        }

        do {
            let operations = try await fileSystemManager.applyOrganization(
                plan, 
                at: baseURL, 
                dryRun: dryRun, 
                enableTagging: enableTagging,
                strictExclusions: aiConfig?.strictExclusions ?? true,
                exclusionManager: exclusionRules,
                progress: { [weak self] percent, message in
                    Task { @MainActor in
                        self?.progress = percent
                        self?.organizationStage = message
                    }
                }
            )

            try checkCancellation()
            
            // Track rule applications for learning feedback
            if let learningsObserver = learningsObserver, !dryRun {
                // Pre-start the session so rule applications can be recorded
                learningsObserver.startSession(folderPath: baseURL.path, historyEntryId: nil, operations: operations)
                recordRuleApplications(for: plan, operations: operations, observer: learningsObserver)
            }

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
            
            // End learning session
            if let learningsObserver = learningsObserver {
                learningsObserver.endSession()
            }

            // Use AutomationManager for Finder integration if available
            if let automationManager = automationManager {
                // Refresh Finder windows
                automationManager.refreshFinder(at: baseURL)

                // Select organized folders in Finder
                let folderURLs = plan.suggestions.map { baseURL.appendingPathComponent($0.folderName) }
                automationManager.selectOrganizedFolders(folderURLs: folderURLs)
            } else {
                // Fallback to legacy refresh method
                Task.detached(priority: .background) {
                    self.refreshFinder(at: baseURL)
                }
            }

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

    @MainActor
    public func redoOrganization(from entry: OrganizationHistoryEntry) async throws {
        guard let _ = entry.plan, let baseURL = currentDirectory ?? URL(string: "file://" + entry.directoryPath) else {
            throw OrganizationError.noCurrentPlan
        }

        updateState(.applying, stage: "Re-applying organization...", progress: 0.3)

        do {
            try await apply(at: baseURL, dryRun: false, enableTagging: aiConfig?.enableFileTagging ?? true)
            
            var updatedEntry = entry
            updatedEntry.isUndone = false
            updatedEntry.status = .completed
            history.updateEntry(updatedEntry)
            
            await MainActor.run {
                organizationStage = "Redo complete"
                progress = 1.0
                state = .completed
            }
        } catch {
            await MainActor.run {
                state = .error(error)
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// Generate organization plan with a specific provider
    /// Returns a plan without updating the organizer's state
    private func generatePlanWithProvider(
        files: [FileItem],
        provider: AIProvider,
        model: String? = nil,
        customInstructions: String? = nil
    ) async throws -> OrganizationPlan {
        var tempConfig = aiConfig ?? AIConfig.default
        tempConfig.provider = provider
        tempConfig.model = model ?? provider.defaultModel
        
        let isSameProvider = aiConfig?.provider == provider
        let hasCustomURL = !(aiConfig?.apiURL ?? "").isEmpty
        
        if !isSameProvider || !hasCustomURL {
            tempConfig.apiURL = provider.defaultAPIURL
        }
        
        let tempClient = try AIClientFactory.createClient(config: tempConfig)
        
        let personaPrompt = personaManager?.getPrompt(for: personaManager?.selectedPersona ?? .general)
        
        var instructions = customInstructions ?? self.customInstructions
        if let learnedContext = learningsManager?.generatePromptContext(), !learnedContext.isEmpty {
            instructions += "\n\n" + learnedContext
        }
        if let storageContext = storageLocationsManager?.generatePromptContext(), !storageContext.isEmpty {
            instructions += "\n\n" + storageContext
        }
        
        let plan = try await tempClient.analyze(
            files: files,
            customInstructions: instructions,
            personaPrompt: personaPrompt,
            temperature: nil
        )
        
        return plan
    }

    /// Get files from current plan for regeneration
    public func getFilesFromCurrentPlan() -> [FileItem] {
        guard let currentPlan = currentPlan else { return [] }
        
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
        
        return allFiles
    }
    
    /// Record which files were moved by which inferred rules (for learning feedback)
    private func recordRuleApplications(for plan: OrganizationPlan, operations: [FileSystemManager.FileOperation], observer: ContinuousLearningObserver) {
        learningsManager?.loadProfileIfNeededForCollection()
        guard let profile = learningsManager?.currentProfile else { return }
        
        let activeRules = profile.inferredRules.filter { $0.isEnabled }
        guard !activeRules.isEmpty else { return }
        
        // Build a map of filename to ruleId from the plan suggestions
        var fileToRuleMap: [String: String] = [:]
        
        func traverseSuggestions(_ suggestions: [FolderSuggestion]) {
            for suggestion in suggestions {
                for file in suggestion.files {
                    if let ruleId = suggestion.ruleId {
                        fileToRuleMap[file.displayName] = ruleId
                    }
                }
                traverseSuggestions(suggestion.subfolders)
            }
        }
        
        traverseSuggestions(plan.suggestions)
        
        for operation in operations {
            guard operation.type == .moveFile || operation.type == .renameFile else { continue }
            guard let destPath = operation.destinationPath else { continue }
            
            let fileName = URL(fileURLWithPath: operation.sourcePath).lastPathComponent
            
            // Priority 1: Use specific rule mapping from the AI plan if available
            if let ruleId = fileToRuleMap[fileName] {
                observer.recordRuleApplication(destinationPath: destPath, ruleId: ruleId)
                continue
            }
            
            // Priority 2: Try to match the rule's regex pattern against the filename (heuristic backup)
            for rule in activeRules {
                // Try to match the rule's regex pattern against the filename
                if let regex = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive) {
                    let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
                    if regex.firstMatch(in: fileName, options: [], range: range) != nil {
                        observer.recordRuleApplication(destinationPath: destPath, ruleId: rule.id)
                        break
                    }
                }
            }
        }
    }
    
    /// Regenerate preview with a specific provider
    public func regenerateWithProvider(_ provider: AIProvider) async throws {
        let files = getFilesFromCurrentPlan()
        guard !files.isEmpty else {
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
        
        updateState(.organizing, stage: "Regenerating with \(provider.displayName)...", progress: 0.3)
        
        do {
            var newPlan = try await generatePlanWithProvider(files: files, provider: provider)
            newPlan.version = (currentPlan?.version ?? 0) + 1
            
            try checkCancellation()
            
            await MainActor.run {
                isStreaming = false
                organizationStage = "Ready!"
                progress = 1.0
                self.currentPlan = newPlan
                state = .ready
            }
        } catch {
            await MainActor.run {
                state = .error(error)
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }
    
    /// Regenerate preview with a specific provider and model
    public func regenerateWithModel(provider: AIProvider, model: String) async throws {
        let files = getFilesFromCurrentPlan()
        guard !files.isEmpty else {
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
        
        updateState(.organizing, stage: "Regenerating with \(provider.displayName) (\(model))...", progress: 0.3)
        
        do {
            var newPlan = try await generatePlanWithProvider(files: files, provider: provider, model: model)
            newPlan.version = (currentPlan?.version ?? 0) + 1
            
            try checkCancellation()
            
            await MainActor.run {
                isStreaming = false
                organizationStage = "Ready!"
                progress = 1.0
                self.currentPlan = newPlan
                state = .ready
            }
        } catch {
            await MainActor.run {
                state = .error(error)
                errorMessage = error.localizedDescription
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

            // Record to learnings
            if let directory = currentDirectory {
                let summary = currentPlan.suggestions.map { "\($0.folderName) (\($0.files.count) files)" }.joined(separator: ", ")
                learningsManager?.recordRegeneratedOrganization(
                    folderPath: directory.path,
                    previousPlanSummary: summary,
                    guidingInstruction: customInstructions, // FolderOrganizer uses customInstructions for the prompt
                    regenerationCount: currentPlan.version
                )
                
                // Also record as a guiding instruction for pattern analysis
                learningsManager?.recordGuidingInstruction(
                    customInstructions,
                    for: directory.path,
                    fileCount: allFiles.count
                )
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

    // MARK: - Reset

    public func reset() {
        cancelInternal()

        // Batch all reset operations into a single UI update cycle
        withBatchUpdates {
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
            
            // Clear AI insights and cache
            currentInsight = ""
            insightHistory = []
            lastInsightExtraction = .distantPast
            insightsCache = nil
        }
        
        // Stop background tasks (outside batch as it's not a @Published property)
        stopSteadyProgressTask()
    }
    private func recordPlanRules(_ plan: OrganizationPlan, observer: ContinuousLearningObserver) {
        // Recursively record rules
        let rootPath = currentDirectory?.path ?? ""
        
        func processSuggestion(_ suggestion: FolderSuggestion, currentPath: String) {
            let folderPath = (currentPath as NSString).appendingPathComponent(suggestion.folderName)
            
            // Record rules for files in this folder
            for _ in suggestion.files {
                let destinationPath = folderPath // Approximate destination path for the file
                
                // If the suggestion has a rule ID (from Learnings analysis), record it
                if let ruleId = suggestion.semanticTags.first(where: { $0.hasPrefix("rule:") })?.replacingOccurrences(of: "rule:", with: "") {
                    observer.recordRuleApplication(destinationPath: destinationPath, ruleId: ruleId)
                }
            }
            
            // Recurse
            for subfolder in suggestion.subfolders {
                processSuggestion(subfolder, currentPath: folderPath)
            }
        }
        
        for suggestion in plan.suggestions {
            processSuggestion(suggestion, currentPath: rootPath)
        }
    }
}

    // MARK: - Finder Refresh
    extension FolderOrganizer {
    nonisolated private func refreshFinder(at url: URL) {
        let scriptSource = """
        tell application "Finder"
            try
                set theFolder to POSIX file "\(url.path)" as alias
                repeat with theWindow in (every window)
                    if (target of theWindow as alias) is theFolder then
                        update theWindow
                    end if
                end repeat
            end try
        end tell
        """
        
        if let script = NSAppleScript(source: scriptSource) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let err = error {
                DebugLogger.log("Finder refresh AppleScript error: \(err)")
            }
        }
    }
}

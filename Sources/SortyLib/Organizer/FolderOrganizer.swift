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

    /// Whether the organizer is actively performing work and should not be interrupted
    public var isOperationInProgress: Bool {
        switch self {
        case .scanning, .organizing, .ready, .applying:
            return true
        case .idle, .completed, .error:
            return false
        }
    }

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
    case revertAlreadyInProgress(String)

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
        case .revertAlreadyInProgress(let path):
            return "A revert is already in progress for \(path)."
        }
    }
}

private actor RevertOperationTracker {
    private var activeEntryIDs: Set<UUID> = []
    private var activePaths: Set<String> = []

    func begin(entryIDs: [UUID], path: String) -> Bool {
        let normalizedIDs = Set(entryIDs)
        guard activePaths.contains(path) == false,
              activeEntryIDs.isDisjoint(with: normalizedIDs) else {
            return false
        }

        activePaths.insert(path)
        activeEntryIDs.formUnion(normalizedIDs)
        return true
    }

    func end(entryIDs: [UUID], path: String) {
        activePaths.remove(path)
        for id in entryIDs {
            activeEntryIDs.remove(id)
        }
    }
}

/// AI reasoning insight extracted from streaming content
public struct AIInsight: Identifiable, Equatable, Sendable {
    public let id: String
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
    
    public init(text: String, category: Category, filePath: String? = nil, stableSeed: String? = nil) {
        self.text = text
        self.category = category
        self.timestamp = Date()
        self.filePath = filePath
        self.id = Self.makeStableID(text: text, category: category, filePath: filePath, stableSeed: stableSeed)
    }

    private static func makeStableID(
        text: String,
        category: Category,
        filePath: String?,
        stableSeed: String?
    ) -> String {
        let normalizedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedPath = filePath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let normalizedSeed = stableSeed?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        let base = "\(category.rawValue.lowercased())|\(normalizedPath)|\(normalizedText)|\(normalizedSeed)"
        var hash: UInt64 = 1469598103934665603
        for byte in base.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "insight-\(String(hash, radix: 16))"
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

public struct VisionAnalysisSummary: Equatable, Sendable {
    public let analyzedCount: Int
    public let totalImageCount: Int
    public let skippedCount: Int
    public let failedCount: Int
    public let warningMessage: String?

    public var hasWarning: Bool {
        warningMessage != nil
    }

    public var summaryText: String {
        var text = "Analyzed \(analyzedCount) of \(totalImageCount) images with AI Vision"
        if skippedCount > 0 {
            text += " (\(skippedCount) skipped)"
        }
        if failedCount > 0 {
            text += " (\(failedCount) failed to preprocess)"
        }
        return text
    }
}

@MainActor
public final class RunningOrganizationActivity: ObservableObject {
    @Published public fileprivate(set) var count = 0

    public var isRunning: Bool {
        count > 0
    }
}

@MainActor
public class FolderOrganizer: ObservableObject, StreamingDelegate {
    nonisolated(unsafe) private static var runningOrganizerIDs: Set<ObjectIdentifier> = []
    @MainActor public static let runningActivity = RunningOrganizationActivity()

    public nonisolated static var runningOrganizationCount: Int {
        runningOrganizerIDs.count
    }

    public nonisolated static var hasRunningOrganizations: Bool {
        !runningOrganizerIDs.isEmpty
    }

    private nonisolated static func isTrackedRunningState(_ state: OrganizationState) -> Bool {
        switch state {
        case .scanning, .organizing, .applying:
            return true
        case .idle, .ready, .completed, .error:
            return false
        }
    }

    private var isRegisteredAsRunningOrganizer = false

    @Published public var state: OrganizationState = .idle {
        didSet {
            // Request user attention for any error state
            if case .error = state {
                NotificationManager.shared.requestAttention()
            }

            syncRunningOrganizationRegistrationIfNeeded(from: oldValue, to: state)
        }
    }
    @Published public var progress: Double = 0.0
    @Published public var currentPlan: OrganizationPlan?
    @Published public var planHistory: [OrganizationPlan] = []
    @Published public var errorMessage: String?
    @Published public var customInstructions: String = ""

    /// When true, callers (such as OrganizeView) should keep showing the OrganizationCompleteView
    /// even if `state` momentarily transitions through `.applying`/`.idle` during an in-place
    /// undo or redo action performed from that screen.
    @Published public var pinsCompletionView: Bool = false
    
    // Proactive AI Validation
    @Published public var isAIConfigured: Bool = false

    // Streaming support
    /// Internal backing storage for streaming content (not @Published to avoid high-frequency redraws)
    public var streamingContent: String = ""
    @Published public var displayStreamingContent: String = "" // Throttled version for UI to prevent layout loops
    @Published public var truncatedDisplayStreamingContent: String = "" // UI-ready preview text (pre-computed off render path)
    @Published public var organizationStage: String = ""
    @Published public var isStreaming: Bool = false
    @Published public var liveInsightsEnabled: Bool = true
    @Published public var deepScanProgress: (current: Int, total: Int)?
    @Published public var visionAnalysisSummary: VisionAnalysisSummary?
    
    // Throttle timer for display content updates (prevents layout thrashing)
    private var displayUpdateTask: Task<Void, Never>?
    private var lastDisplayUpdate: Date = .distantPast
    private let displayUpdateInterval: TimeInterval = 0.55 // Slightly slower cadence to reduce dropped frames during generation
    nonisolated private static let streamPreviewCharacterLimit = 1000
    nonisolated private static let assignmentDestinationRegex =
        try? NSRegularExpression(
            pattern: #"\b(?:assigning|moving|mapping)\b.+?\bto\b\s+(.+)$"#,
            options: [.caseInsensitive]
        )
    nonisolated private static let blockedLiveFolderNames: Set<String> = [
        "a", "an", "and", "as", "at", "be", "by", "for", "from", "gets", "in", "into",
        "is", "it", "name", "of", "on", "or", "that", "the", "this", "to", "value",
        "with", "folder", "folders", "file", "files", "filename", "json", "reasoning",
        "notes", "unorganized", "data", "content", "description", "type", "rule_id",
        "semantic_tags", "suggested_name", "rename_reason", "tags", "comment", "true",
        "false", "null"
    ]
    nonisolated private static let quotedFileMentionRegex =
        try? NSRegularExpression(
            pattern: #"(?:\"|')([^\"'\n]{2,220}\.[a-zA-Z0-9]{1,12})(?:\"|')"#,
            options: []
        )
    nonisolated private static let bareFileMentionRegex =
        try? NSRegularExpression(
            pattern: #"\b([A-Za-z0-9_\-\(\)]+\.[a-zA-Z0-9]{1,12})\b"#,
            options: []
        )
    
    // Steady progress animation during streaming
    private let steadyProgressTimer = SteadyProgressTimer()
    private var lastChunkTime: Date = .distantPast
    
    // AI reasoning insights - extracted from streaming content
    @Published public var currentInsight: String = ""
    @Published public var insightHistory: [AIInsight] = []
    private var lastInsightExtraction: Date = .distantPast
    private let insightExtractionInterval: TimeInterval = 0.9 // Lower extraction frequency to cut parser pressure while streaming
    private let insightExtractor = AIInsightExtractor()
    private var insightExtractionTask: Task<Void, Never>?
    
    // Progress line streaming support
    private var progressLineBuffer: String = ""
    private var receivedProgressLines: Bool = false
    private var jsonStartedInStream: Bool = false
    private var progressLineCount: Int = 0
    private let progressLineLimit = 12
    
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
    private var suppressCancellationReset = false
    
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
    private let scannedFilesUIPublishLimit = 200

    // CRITICAL: Cancellation token - must be checked frequently
    private var currentTask: Task<Void, Error>?
    private var isCancellationRequested: Bool = false

    // Prevent auto-start by tracking explicit user actions
    private var userInitiatedAction: Bool = false

    var scanner = DirectoryScanner()
    public private(set) var aiClient: AIClientProtocol?
    private let fileSystemManager: FileSystemManager
    private var aiConfig: AIConfig?
    private let validator = FileOrganizationValidator.self
    public let history: OrganizationHistory
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
    private let revertOperationTracker = RevertOperationTracker()
    
    private let visionAnalyzer = ImageVisionAnalyzer()
    private let visionImageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "webp"]

    #if DEBUG
    private var revertOperationTestHook: (@Sendable () async -> Void)?
    #endif
    
    public init(
        history: OrganizationHistory = OrganizationHistory(),
        fileSystemManager: FileSystemManager = FileSystemManager()
    ) {
        self.history = history
        self.fileSystemManager = fileSystemManager
        syncRunningOrganizationRegistrationIfNeeded(from: .idle, to: state)
    }

    deinit {
        if isRegisteredAsRunningOrganizer {
            Self.runningOrganizerIDs.remove(ObjectIdentifier(self))
            Task { @MainActor in
                Self.runningActivity.count = Self.runningOrganizationCount
            }
        }
    }

    @MainActor
    private func syncRunningOrganizationRegistrationIfNeeded(from oldState: OrganizationState, to newState: OrganizationState) {
        let wasTracked = Self.isTrackedRunningState(oldState)
        let shouldTrack = Self.isTrackedRunningState(newState)
        guard wasTracked != shouldTrack else { return }

        let id = ObjectIdentifier(self)
        if shouldTrack {
            Self.runningOrganizerIDs.insert(id)
            isRegisteredAsRunningOrganizer = true
        } else {
            Self.runningOrganizerIDs.remove(id)
            isRegisteredAsRunningOrganizer = false
        }

        Self.runningActivity.count = Self.runningOrganizationCount
    }

    #if DEBUG
    /// Test-only method to inject a mock AI client for unit testing
    public func setAIClientForTesting(_ client: AIClientProtocol?) {
        self.aiClient = client
        if client != nil {
            self.isAIConfigured = true
        }
    }

    func setRevertOperationHookForTesting(_ hook: (@Sendable () async -> Void)?) {
        revertOperationTestHook = hook
    }
    #endif

    public func configure(with config: AIConfig) async throws {
        do {
            var client = try AIClientFactory.createClient(config: config)

            // Set up streaming delegate
            client.streamingDelegate = self

            self.aiClient = client
            self.aiConfig = config
            await scanner.setOCRLanguages(config.ocrLanguages)
            
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

    private struct StreamPresentationPayload: Sendable {
        let fullContent: String
        let truncatedContent: String
    }

    nonisolated private static func makeStreamPresentationPayload(from content: String) -> StreamPresentationPayload {
        let truncatedContent: String
        if content.count > streamPreviewCharacterLimit {
            let start = content.index(content.endIndex, offsetBy: -streamPreviewCharacterLimit)
            truncatedContent = "..." + String(content[start...])
        } else {
            truncatedContent = content
        }
        return StreamPresentationPayload(fullContent: content, truncatedContent: truncatedContent)
    }

    @MainActor
    private func scheduleDisplayUpdate(for contentSnapshot: String, force: Bool = false) {
        guard liveInsightsEnabled else { return }

        let now = Date()
        if !force && now.timeIntervalSince(lastDisplayUpdate) < displayUpdateInterval {
            return
        }
        lastDisplayUpdate = now

        let estimatedTotal = estimatedStreamingCharacterTarget()
        let contentLength = contentSnapshot.count

        displayUpdateTask?.cancel()
        displayUpdateTask = Task { @MainActor [weak self] in
            let payload = Self.makeStreamPresentationPayload(from: contentSnapshot)
            guard let self, !Task.isCancelled, !self.isCancellationRequested else { return }
            guard self.streamingContent.count >= contentLength else { return }

            self.withBatchUpdates {
                self.displayStreamingContent = payload.fullContent
                self.truncatedDisplayStreamingContent = payload.truncatedContent
                self.updateProgressFromStreamLength(contentLength, estimatedTotal: estimatedTotal)
            }
        }
    }

    @MainActor
    private func updateProgressFromStreamLength(_ contentLength: Int, estimatedTotal: Int? = nil) {
        let target = estimatedTotal ?? estimatedStreamingCharacterTarget()
        let contentProgress = min(0.80, 0.30 + (Double(contentLength) / Double(target)) * 0.50)
        if progress < contentProgress {
            progress = contentProgress
        }
    }

    @MainActor
    private func syncDisplayContentImmediately() {
        let payload = Self.makeStreamPresentationPayload(from: streamingContent)
        displayStreamingContent = payload.fullContent
        truncatedDisplayStreamingContent = payload.truncatedContent
    }

    @MainActor
    private func clearStreamingDisplayState() {
        displayUpdateTask?.cancel()
        displayUpdateTask = nil
        streamingContent = ""
        displayStreamingContent = ""
        truncatedDisplayStreamingContent = ""
        lastDisplayUpdate = .distantPast
        progressLineBuffer = ""
        receivedProgressLines = false
        jsonStartedInStream = false
        progressLineCount = 0
    }

    @MainActor
    private func restartPlanGenerationForRetry() {
        clearStreamingDisplayState()
        withBatchUpdates {
            isStreaming = false
            progress = 0.30
            organizationStage = "AI is analyzing your files..."
        }
        startTimeoutTimer()
    }

    public nonisolated func didReceiveChunk(_ chunk: String) {
        Task { @MainActor in
            guard !self.isCancellationRequested else { return }

            // If a prior stream already completed, treat this as a brand-new stream session.
            if !self.isStreaming, !self.streamingContent.isEmpty {
                self.clearStreamingDisplayState()
            }
            
            let isFirstChunk = self.streamingContent.isEmpty
            self.streamingContent += chunk
            self.lastChunkTime = Date()

            if isFirstChunk {
                // Batch all initial state updates together
                self.withBatchUpdates {
                    self.isStreaming = true
                    self.organizationStage = "AI is analyzing your files..."
                    self.progress = 0.30
                    if self.liveInsightsEnabled {
                        self.syncDisplayContentImmediately()
                    }
                }
                
                // Start steady progress task for smooth animation
                self.startSteadyProgressTask()
            }

            if self.liveInsightsEnabled {
                // Try to extract progress lines from the stream before JSON starts
                if !self.jsonStartedInStream {
                    self.processProgressLines(from: chunk)
                }
                
                // Throttle UI-impacting updates to prevent layout thrashing and main actor congestion
                self.scheduleDisplayUpdate(for: self.streamingContent)
                
                // Fall back to regex extractor only if no progress lines were received
                if !self.receivedProgressLines {
                    self.extractInsightsIfNeeded()
                }
            } else {
                let now = Date()
                if now.timeIntervalSince(self.lastDisplayUpdate) >= self.displayUpdateInterval {
                    self.lastDisplayUpdate = now
                    self.updateProgressFromStreamLength(self.streamingContent.count)
                }
            }
        }
    }
    
    // MARK: - Progress Line Parsing
    
    /// Parse progress lines (>> category: text) from streaming chunks
    @MainActor
    private func processProgressLines(from chunk: String) {
        progressLineBuffer += chunk
        
        // Process complete lines from the buffer
        while let newlineIndex = progressLineBuffer.firstIndex(of: "\n") {
            let line = String(progressLineBuffer[progressLineBuffer.startIndex..<newlineIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            progressLineBuffer = String(progressLineBuffer[progressLineBuffer.index(after: newlineIndex)...])
            
            // Check if JSON has started (line contains opening brace)
            if line.contains("{") {
                jsonStartedInStream = true
                return
            }
            
            // Skip empty lines
            guard !line.isEmpty else { continue }
            
            // Parse progress lines starting with ">> "
            guard line.hasPrefix(">> "), progressLineCount < progressLineLimit else { continue }
            
            let content = String(line.dropFirst(3))
            guard let insight = parseProgressLine(content) else { continue }
            
            progressLineCount += 1
            receivedProgressLines = true
            
            withBatchUpdates {
                self.currentInsight = insight.text
                if let existingIndex = self.insightHistory.firstIndex(where: { $0.id == insight.id }) {
                    self.insightHistory.remove(at: existingIndex)
                }
                if self.insightHistory.count >= 12 {
                    self.insightHistory.removeFirst()
                }
                self.insightHistory.append(insight)
            }
        }
        
        // Check if remaining buffer contains start of JSON (e.g., chunk ended mid-line with "{")
        if progressLineBuffer.contains("{") {
            jsonStartedInStream = true
        }
    }

    /// Rebuild insight timeline from the already-buffered stream text.
    /// Used when users re-enable Live Insights during an active generation.
    @MainActor
    private func rebuildInsightsFromStreamingSnapshot() {
        let snapshot = streamingContent
        guard !snapshot.isEmpty else {
            withBatchUpdates {
                currentInsight = ""
                insightHistory = []
            }
            progressLineBuffer = ""
            receivedProgressLines = false
            jsonStartedInStream = false
            progressLineCount = 0
            return
        }

        let rawLines = snapshot.components(separatedBy: .newlines)
        var rebuiltInsights: [AIInsight] = []
        var sawJSON = false
        var trailingPartialBuffer = ""

        for (index, rawLine) in rawLines.enumerated() {
            let isLastLine = index == rawLines.count - 1
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.contains("{") {
                sawJSON = true
                trailingPartialBuffer = ""
                break
            }

            if isLastLine, !snapshot.hasSuffix("\n") {
                trailingPartialBuffer = rawLine
            }

            guard !trimmedLine.isEmpty else { continue }
            guard trimmedLine.hasPrefix(">> "), rebuiltInsights.count < progressLineLimit else { continue }

            let lineContent = String(trimmedLine.dropFirst(3))
            guard let insight = parseProgressLine(lineContent) else { continue }

            if let existingIndex = rebuiltInsights.firstIndex(where: { $0.id == insight.id }) {
                rebuiltInsights.remove(at: existingIndex)
            }
            rebuiltInsights.append(insight)
        }

        progressLineBuffer = sawJSON ? "" : trailingPartialBuffer
        receivedProgressLines = !rebuiltInsights.isEmpty
        jsonStartedInStream = sawJSON || progressLineBuffer.contains("{")
        progressLineCount = rebuiltInsights.count

        withBatchUpdates {
            currentInsight = rebuiltInsights.last?.text ?? ""
            insightHistory = rebuiltInsights
        }
    }
    
    /// Parse a progress line like "file: Assigning invoice.pdf to Finances" into an AIInsight
    private func parseProgressLine(_ content: String) -> AIInsight? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return nil }
        
        var category: AIInsight.Category = .general
        var text = trimmed
        
        // Try to extract "category: text" format
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let prefix = String(trimmed[trimmed.startIndex..<colonIndex])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            let remainder = String(trimmed[trimmed.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespaces)
            
            switch prefix {
            case "file", "folder", "pattern", "decision", "constraint", "general":
                switch prefix {
                case "file": category = .file
                case "folder": category = .folder
                case "pattern": category = .pattern
                case "decision": category = .decision
                case "constraint": category = .constraint
                default: category = .general
                }
                guard !remainder.isEmpty else { return nil }
                text = remainder
            default:
                category = .general
            }
        }

        if let destination = Self.extractAssignmentDestination(from: text),
           !Self.isLikelyLiveFolderName(destination) {
            return nil
        }
        if category == .file && Self.isLowSignalFileProgressInsight(text) {
            return nil
        }
        let clipped = String(text.prefix(120))
        let resolvedFilePath = (category == .file) ? resolveScannedFilePathForMention(in: text) : nil
        return AIInsight(text: clipped, category: category, filePath: resolvedFilePath, stableSeed: text)
    }

    private func resolveScannedFilePathForMention(in text: String) -> String? {
        guard let fileName = Self.extractMentionedFileName(from: text) else { return nil }
        return Self.resolveScannedFilePath(
            for: fileName,
            scannedFilePathLookup: scannedFilePathLookup,
            currentDirectoryPath: currentDirectory?.path
        )
    }

    nonisolated private static func extractMentionedFileName(from text: String) -> String? {
        if let quotedRegex = quotedFileMentionRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = quotedRegex.matches(in: text, options: [], range: range)
            for match in matches.reversed() {
                guard let fileRange = Range(match.range(at: 1), in: text) else { continue }
                let fileName = normalizeCandidateFileName(String(text[fileRange]))
                if isLikelyFileName(fileName) {
                    return URL(fileURLWithPath: fileName).lastPathComponent
                }
            }
        }

        if let bareRegex = bareFileMentionRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = bareRegex.matches(in: text, options: [], range: range)
            for match in matches.reversed() {
                guard let fileRange = Range(match.range(at: 1), in: text) else { continue }
                let fileName = normalizeCandidateFileName(String(text[fileRange]))
                if isLikelyFileName(fileName) {
                    return URL(fileURLWithPath: fileName).lastPathComponent
                }
            }
        }

        return nil
    }

    nonisolated private static func resolveScannedFilePath(
        for fileName: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> String? {
        let key = fileName.lowercased()
        guard let matches = scannedFilePathLookup[key], !matches.isEmpty else { return nil }

        if matches.count == 1 {
            return matches[0]
        }

        if let currentDirectoryPath,
           let preferredPath = matches.first(where: { $0.hasPrefix(currentDirectoryPath + "/") }) {
            return preferredPath
        }

        return matches[0]
    }

    nonisolated private static func normalizeFolderName(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    nonisolated private static func isLikelyLiveFolderName(_ input: String) -> Bool {
        let candidate = normalizeFolderName(input)
        guard candidate.count >= 2, candidate.count <= 80 else { return false }
        guard !candidate.contains("{"), !candidate.contains("}"), !candidate.contains("\"") else { return false }
        guard !candidate.contains("/"), !candidate.contains("\\") else { return false }
        guard URL(fileURLWithPath: candidate).pathExtension.isEmpty else { return false }

        let lower = candidate.lowercased()
        guard !blockedLiveFolderNames.contains(lower) else { return false }
        guard !lower.contains("top-level"),
              !lower.contains("top level"),
              !lower.contains("preferred"),
              !lower.contains("constraint"),
              !lower.contains("response format"),
              !lower.contains("system prompt") else {
            return false
        }
        return true
    }

    nonisolated private static func normalizeCandidateFileName(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}"))
    }

    nonisolated private static func isLikelyFileName(_ input: String) -> Bool {
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.count <= 220 else { return false }
        let ext = URL(fileURLWithPath: candidate).pathExtension
        return !ext.isEmpty
    }

    nonisolated private static func isLowSignalFileProgressInsight(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return true }

        if lowered.contains("response format") || lowered.contains("json schema") || lowered.contains("system prompt") {
            return true
        }

        if let destination = extractAssignmentDestination(from: text),
           !isLikelyLiveFolderName(destination) {
            return true
        }

        return false
    }

    nonisolated private static func extractAssignmentDestination(from text: String) -> String? {
        guard let regex = assignmentDestinationRegex else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let destinationRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let destination = normalizeFolderName(String(text[destinationRange]))
        return destination.isEmpty ? nil : destination
    }

    /// Starts a background task that ensures progress keeps moving even during pauses
    private func startSteadyProgressTask() {
        steadyProgressTimer.start(interval: .milliseconds(500)) { [weak self] in
            guard let self = self, !self.isCancellationRequested, self.isStreaming else { return }
            guard self.progress < 0.82 else { return }

            let timeSinceLastChunk = Date().timeIntervalSince(self.lastChunkTime)
            if timeSinceLastChunk > 1.0 {
                self.progress = min(0.82, self.progress + 0.005)
            }
        }
    }
    
    /// Stops the steady progress task
    private func stopSteadyProgressTask() {
        steadyProgressTimer.stop()
    }
    
    /// Extract meaningful insights from the streaming AI response
    /// This is throttled and uses caching to avoid performance impact
    private func extractInsightsIfNeeded(force: Bool = false) {
        guard liveInsightsEnabled else { return }

        let now = Date()
        if !force {
            guard now.timeIntervalSince(lastInsightExtraction) >= insightExtractionInterval else { return }
        }
        lastInsightExtraction = now
        
        // Get the last portion of content for analysis
        let content = streamingContent
        guard content.count > 20 else { return }
        
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

        let fileLookup = scannedFilePathLookup
        let currentDirectoryPath = currentDirectory?.path

        insightExtractionTask?.cancel()
        insightExtractionTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            let insight = await self.insightExtractor.extractInsight(
                from: content,
                scannedFilePathLookup: fileLookup,
                currentDirectoryPath: currentDirectoryPath
            )

            guard !Task.isCancelled,
                  self.liveInsightsEnabled,
                  let insight,
                  insight.text != self.currentInsight else { return }

            self.withBatchUpdates {
                self.currentInsight = insight.text
                if let existingIndex = self.insightHistory.firstIndex(where: { $0.id == insight.id }) {
                    self.insightHistory.remove(at: existingIndex)
                }
                if self.insightHistory.count >= 5 {
                    self.insightHistory.removeFirst()
                }
                self.insightHistory.append(insight)
            }

            self.insightsCache = InsightsCache(
                streamingContentHash: contentHash,
                insights: self.insightHistory,
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

    @MainActor
    public func setLiveInsightsEnabled(_ enabled: Bool) {
        guard liveInsightsEnabled != enabled else { return }
        liveInsightsEnabled = enabled

        if enabled {
            if !streamingContent.isEmpty {
                rebuildInsightsFromStreamingSnapshot()
                syncDisplayContentImmediately()
                scheduleDisplayUpdate(for: streamingContent, force: true)
                if !receivedProgressLines {
                    extractInsightsIfNeeded(force: true)
                }
            }
            return
        }

        displayUpdateTask?.cancel()
        displayUpdateTask = nil
        displayStreamingContent = ""
        truncatedDisplayStreamingContent = ""

        insightExtractionTask?.cancel()
        insightExtractionTask = nil
        lastInsightExtraction = .distantPast
        insightsCache = nil
    }
    
    private func estimatedStreamingCharacterTarget() -> Int {
        let fileCount = max(1, scannedFileCount)
        let provider = aiConfig?.provider

        let base = 1200
        let perFile = min(220, max(70, 80 + Int(log2(Double(fileCount) + 1.0) * 14)))
        let complexityBoost = min(2500, fileCount * 18)

        let providerMultiplier: Double
        switch provider {
        case .anthropic:
            providerMultiplier = 1.15
        case .ollama, .openAICompatible:
            providerMultiplier = 1.05
        default:
            providerMultiplier = 1.0
        }

        let estimated = Int(Double(base + (fileCount * perFile) + complexityBoost) * providerMultiplier)
        return min(24_000, max(2_000, estimated))
    }
    
    private func setScannedFiles(_ files: [FileItem]) {
        scannedFiles = Array(files.prefix(scannedFilesUIPublishLimit))
        scannedFilePathLookup = Dictionary(grouping: files, by: { $0.displayName.lowercased() })
            .mapValues { $0.map { $0.path } }
    }
    
    public nonisolated func didComplete(content: String) {
        Task { @MainActor in
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Prefer the provider's finalized completion payload so history stores full output.
                self.streamingContent = content
                if self.liveInsightsEnabled {
                    self.syncDisplayContentImmediately()
                }
            }
            self.isStreaming = false
            self.organizationStage = self.aiConfig?.mode == .renameOnly ? "Building rename preview..." : "Building organization plan..."
            self.stopTimeoutTimer()
            self.stopSteadyProgressTask()
        }
    }

    public nonisolated func didFail(error: Error) {
        Task { @MainActor in
            self.isStreaming = false
            self.errorMessage = self.userFacingErrorMessage(for: error)
            self.stopTimeoutTimer()
            self.stopSteadyProgressTask()
            
            // Request user attention for streaming failure
            NotificationManager.shared.requestAttention()
        }
    }

    // MARK: - Timeout Timer

    private func startTimeoutTimer() {
        startTime = Date()
        elapsedTime = 0
        showTimeoutMessage = false

        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            while let self = self, !Task.isCancelled, !self.isCancellationRequested {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled || self.isCancellationRequested { break }

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
        try await runOrganizationTask(directory: directory, customPrompt: customPrompt, temperature: temperature)
    }

    private func runOrganizationTask(
        directory: URL,
        customPrompt: String?,
        temperature: Double?
    ) async throws {
        isCancellationRequested = false
        userInitiatedAction = true
        visionAnalysisSummary = nil

        currentTask = Task {
            try await performOrganization(
                directory: directory,
                customPrompt: customPrompt,
                temperature: temperature
            )
        }
        defer { currentTask = nil }

        do {
            try await currentTask?.value
        } catch is CancellationError {
            if suppressCancellationReset {
                suppressCancellationReset = false
                return
            }
            resetToIdle()
        } catch {
            throw error
        }
    }

    private func performOrganization(directory: URL, customPrompt: String?, temperature: Double?) async throws {
        guard let client = aiClient else {
            throw OrganizationError.clientNotConfigured
        }

        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Organizing folder: \(directory.lastPathComponent)"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        do {
            currentDirectory = directory

            let files = try await scanPhase(directory: directory)

            if files.isEmpty {
                stopTimeoutTimer()

                await MainActor.run {
                    currentPlan = OrganizationPlan(
                        notes: "This folder is empty. Add files and try again."
                    )
                    updateState(.ready, stage: "No files found to organize", progress: 1.0)
                }

                NotificationManager.shared.show(
                    .previewReady(
                        folderName: directory.lastPathComponent,
                        folderPath: directory.path
                    )
                )

                return
            }

            let (filesWithHashes, duplicateContext) = try await duplicateDetectionPhase(files: files)
            let (plan, instructions, personaPrompt, imagePayload) = try await aiAnalysisPhase(
                files: filesWithHashes,
                directory: directory,
                customPrompt: customPrompt,
                temperature: temperature,
                duplicateContext: duplicateContext
            )
            let validatedPlan = try await validationPhase(
                plan: plan,
                files: filesWithHashes,
                directory: directory,
                instructions: instructions,
                personaPrompt: personaPrompt,
                temperature: temperature,
                imagePayload: imagePayload
            )

            await MainActor.run {
                currentPlan = validatedPlan
                updateState(.ready, stage: "Ready!", progress: 1.0)
            }

            NotificationManager.shared.show(
                .previewReady(
                    folderName: directory.lastPathComponent,
                    folderPath: directory.path
                )
            )

            if let learningsObserver = learningsObserver {
                learningsObserver.startSession(folderPath: directory.path, historyEntryId: nil)
                recordPlanRules(plan, observer: learningsObserver)
            }

        } catch is CancellationError {
            stopTimeoutTimer()
            resetToIdleUnlessCancellationResetIsSuppressed()
            throw CancellationError()
        } catch let error as OrganizationError where error == .cancelled {
            stopTimeoutTimer()
            resetToIdleUnlessCancellationResetIsSuppressed()
            throw CancellationError()
        } catch let error as AIClientError where error.isCancellation {
            stopTimeoutTimer()
            resetToIdleUnlessCancellationResetIsSuppressed()
            throw CancellationError()
        } catch where (error as NSError).code == NSURLErrorCancelled || 
                      error.localizedDescription.lowercased().contains("cancelled") ||
                      error.localizedDescription.lowercased().contains("canceled") {
            stopTimeoutTimer()
            resetToIdleUnlessCancellationResetIsSuppressed()
            throw CancellationError()
        } catch {
            stopTimeoutTimer()
            handleOrganizationError(error, directory: directory)
            throw error
        }
    }

    // MARK: - Organization Phases

    private func scanPhase(directory: URL) async throws -> [FileItem] {
        updateState(.scanning, stage: "Scanning directory...", progress: 0.05)

        try checkCancellation()

        // Set up deep scan progress reporting
        await scanner.setDeepScanProgressCallback { [weak self] current, _ in
            Task { @MainActor in
                self?.deepScanProgress = (current: current, total: 0)
                if current % 5 == 0 {
                    self?.organizationStage = "Analyzing file content: \(current) files..."
                }
            }
        }

        if let keywords = aiConfig?.customOCRKeywords {
            await scanner.setCustomOCRKeywords(keywords)
        }
        await scanner.setOCRLanguages(aiConfig?.ocrLanguages ?? ["en-US"])

        let filesFound = try await scanner.scanDirectory(
            at: directory,
            deepScan: (aiConfig?.enableDeepScan ?? false) && (aiConfig?.provider.supportsDeepScan ?? true)
        )
        scannedFileCount = filesFound.count
        setScannedFiles(filesFound)

        deepScanProgress = nil

        // Check if scan was degraded due to memory pressure
        if await scanner.lastScanWasDegraded, let reason = await scanner.degradationReason {
            updateProgress(0.12, stage: "⚠️ \(reason)")
            try? await Task.sleep(for: .seconds(1.5))
        }

        updateProgress(0.15, stage: "Found \(filesFound.count) files")

        try checkCancellation()

        var files = filesFound
        if let exclusionRules = exclusionRules {
            files = exclusionRules.filterFiles(files)
            updateProgress(0.20, stage: "Filtered to \(files.count) files")
        }

        try checkCancellation()

        return files
    }

    private func duplicateDetectionPhase(files: [FileItem]) async throws -> ([FileItem], String) {
        guard aiConfig?.detectDuplicates ?? false else {
            detectedDuplicates = []
            return (files, "")
        }

        updateProgress(0.21, stage: "Checking for duplicates...")

        let detector = DuplicateDetector()
        var updatedFiles = files
        if updatedFiles.contains(where: { $0.sha256Hash == nil }) {
            await detector.computeHashes(for: &updatedFiles)
        }

        let duplicates = await detector.findDuplicates(in: updatedFiles)
        await MainActor.run {
            self.detectedDuplicates = duplicates
        }

        return (updatedFiles, PromptContextHelper.duplicateContext(from: duplicates))
    }

    private func aiAnalysisPhase(
        files: [FileItem],
        directory: URL,
        customPrompt: String?,
        temperature: Double?,
        duplicateContext: String
    ) async throws -> (OrganizationPlan, String, String?, [String: Data]) {
        updateState(.organizing, stage: "Connecting to AI provider...", progress: 0.22)
        await MainActor.run {
            isStreaming = false
        }

        startTimeoutTimer()

        try checkCancellation()

        let personaPrompt = personaManager?.getEffectivePrompt(customStore: customPersonaStore ?? CustomPersonaStore())

        var instructions = customPrompt ?? customInstructions
        if !duplicateContext.isEmpty {
            instructions += duplicateContext
        }
        if let activeRules = exclusionRules?.rules.filter({ $0.isEnabled }), !activeRules.isEmpty {
            let excludedPatterns = activeRules.map { "- \($0.displayDescription)" }.joined(separator: "\n")
            let object = aiConfig?.mode == .renameOnly ? "rename suggestions" : "organization plan"
            instructions += "\n\nIMPORTANT: The following patterns are STRICTLY EXCLUDED and must NOT be moved, renamed, or modified:\n\(excludedPatterns)\nEnsure your \(object) completely respects these exclusions."
        }

        if let nlExceptions = exclusionRules?.sanitizedExceptionsForPrompt, !nlExceptions.isEmpty {
            let exceptionsList = nlExceptions.map { "- \($0)" }.joined(separator: "\n")
            instructions += "\n\nUSER EXCEPTIONS (must be respected):\n\(exceptionsList)"
        }

        let isRenameOnly = aiConfig?.mode == .renameOnly

        if !isRenameOnly, let learnedContext = learningsManager?.generatePromptContext(), !learnedContext.isEmpty {
            instructions += "\n\n" + learnedContext
            DebugLogger.log("Injected Learnings context into prompt")
        }

        if !isRenameOnly, let modelDirContext = learningsManager?.generateModelDirectoryContext(), !modelDirContext.isEmpty {
            instructions += "\n\n" + modelDirContext
            DebugLogger.log("Injected Model Directory reference context into prompt")
        }

        if !isRenameOnly, let directoryManifest = PromptBuilder.buildDirectoryManifestContext(baseDirectoryURL: directory, files: files) {
            instructions += "\n\n" + directoryManifest
            DebugLogger.log("Injected source folder context into prompt")
        }

        if !isRenameOnly, let storageContext = storageLocationsManager?.generatePromptContext(), !storageContext.isEmpty {
            let sourceDir = StorageLocationPathResolver.canonicalPath(directory.path)
            let enabledLocations = storageLocationsManager?.enabledLocations ?? []

            var sourceDirClause = """
            11. The source directory you are organizing is: "\(sourceDir)".
                CRITICAL: The source directory and storage locations are completely separate filesystem locations.
                To route a file to storage, copy the EXACT path from VALID_STORAGE_PATHS or KNOWN_STORAGE_SUBFOLDERS.
                Do NOT build storage paths by appending folder names to the source directory.
                Non-storage destinations must use short relative names (no leading /).
            """

            if let firstLocation = enabledLocations.first {
                let storagePath = StorageLocationPathResolver.canonicalPath(firstLocation.path)
                let storageName = URL(fileURLWithPath: storagePath).lastPathComponent
                sourceDirClause += """

                ✗ WRONG: "\(sourceDir)/\(storageName)" — this is inside the source, NOT a storage location.
                ✓ RIGHT: "\(storagePath)" — copy the exact path from VALID_STORAGE_PATHS.
                """
            }

            instructions += "\n\n" + storageContext + "\n" + sourceDirClause
            DebugLogger.log("Injected Storage Locations context into prompt")
        }

        if !isRenameOnly, let existingFoldersContext = PromptBuilder.buildExistingFoldersContext(at: directory) {
            instructions += "\n\n" + existingFoldersContext
            DebugLogger.log("Injected Existing Folders context into prompt")
        }

        let imageFiles = files.filter { visionImageExtensions.contains($0.extension.lowercased()) }
        var imagePayload: [String: Data] = [:]

        let visionEnabled = aiConfig?.enableVision ?? false
        let currentModel = aiConfig?.model ?? ""
        let currentProvider = aiConfig?.provider ?? .openAICompatible
        let modelSupportsVision = ModelCatalog.shared.supportsVision(modelId: currentModel, provider: currentProvider)

        if !imageFiles.isEmpty && visionEnabled && modelSupportsVision {
            let shouldLimitVisionImages = aiConfig?.limitVisionImages ?? true
            let configuredBatchSize = max(1, aiConfig?.visionBatchSize ?? 5)
            let strategy = aiConfig?.visionBatchStrategy ?? .firstN
            let selectedBatch: [FileItem]
            if shouldLimitVisionImages {
                selectedBatch = selectVisionBatch(from: imageFiles, batchSize: configuredBatchSize, strategy: strategy)
            } else {
                selectedBatch = imageFiles
            }
            updateProgress(0.25, stage: "Analyzing \(selectedBatch.count) of \(imageFiles.count) images with Vision AI...")

            let urlPayload = await visionAnalyzer.prepareImagesForVision(urls: selectedBatch.compactMap { $0.url })
            var analyzedNames: [String] = []
            for file in selectedBatch {
                guard let fileURL = file.url else { continue }
                if let data = urlPayload[fileURL] {
                    imagePayload[file.displayName] = data
                    analyzedNames.append(file.displayName)
                }
            }

            let failedCount = max(0, selectedBatch.count - analyzedNames.count)
            let skippedCount = max(0, imageFiles.count - analyzedNames.count)
            visionAnalysisSummary = VisionAnalysisSummary(
                analyzedCount: analyzedNames.count,
                totalImageCount: imageFiles.count,
                skippedCount: skippedCount,
                failedCount: failedCount,
                warningMessage: nil
            )

            if !analyzedNames.isEmpty {
                instructions += visionPromptInstructions(for: analyzedNames)
            }
            DebugLogger.log("Prepared \(imagePayload.count) images for multimodal analysis (total: \(imageFiles.count), failed preprocess: \(failedCount))")
        } else if !imageFiles.isEmpty && visionEnabled && !modelSupportsVision {
            let warning = "Vision is enabled but \(currentProvider.displayName) (\(currentModel)) doesn't support multimodal analysis. Results will use text-only analysis."
            visionAnalysisSummary = VisionAnalysisSummary(
                analyzedCount: 0,
                totalImageCount: imageFiles.count,
                skippedCount: imageFiles.count,
                failedCount: 0,
                warningMessage: warning
            )
            DebugLogger.log(warning)
        } else {
            visionAnalysisSummary = nil
        }

        guard let client = aiClient else {
            throw OrganizationError.clientNotConfigured
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

        return (plan, instructions, personaPrompt, imagePayload)
    }

    private func selectVisionBatch(from imageFiles: [FileItem], batchSize: Int, strategy: VisionBatchStrategy) -> [FileItem] {
        let safeBatchSize = max(1, batchSize)
        switch strategy {
        case .firstN:
            return Array(imageFiles.prefix(safeBatchSize))
        case .random:
            return Array(imageFiles.shuffled().prefix(safeBatchSize))
        case .noText:
            let prioritized = imageFiles.sorted { lhs, rhs in
                let lhsHasOCR = !(lhs.contentMetadata?.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let rhsHasOCR = !(rhs.contentMetadata?.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                if lhsHasOCR != rhsHasOCR {
                    return !lhsHasOCR
                }
                let lhsDate = lhs.modificationDate ?? lhs.creationDate ?? .distantPast
                let rhsDate = rhs.modificationDate ?? rhs.creationDate ?? .distantPast
                return lhsDate > rhsDate
            }
            return Array(prioritized.prefix(safeBatchSize))
        }
    }

    private func visionPromptInstructions(for analyzedImageFilenames: [String]) -> String {
        let fileList = analyzedImageFilenames
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        return """

        ## AI VISION CONTEXT
        I've attached \(analyzedImageFilenames.count) images from this folder.
        For each image, describe what you see and use that context to determine the best folder categorization.
        Attached image order:
        \(fileList)
        """
    }

    private func validationPhase(
        plan: OrganizationPlan,
        files: [FileItem],
        directory: URL,
        instructions: String,
        personaPrompt: String?,
        temperature: Double?,
        imagePayload: [String: Data]
    ) async throws -> OrganizationPlan {
        updateState(
            .organizing,
            stage: aiConfig?.mode == .renameOnly ? "Checking name suggestions..." : "Checking organization plan...",
            progress: 0.85
        )
        await MainActor.run {
            isStreaming = false
        }

        guard let client = aiClient else {
            throw OrganizationError.clientNotConfigured
        }

        let maxFolders = aiConfig?.mode == .renameOnly ? 100 : (aiConfig?.maxTopLevelFolders ?? 10)
        let allowedLocations = storageLocationsManager?.enabledLocations ?? []
        let normalizedInputPlan = normalizeStorageDestinations(in: plan, allowedLocations: allowedLocations, sourceDirectoryURL: directory)

        var validatedPlanFromRetry: OrganizationPlan? = nil
        do {
            try validator.validate(normalizedInputPlan, at: directory, allowedStorageLocations: allowedLocations, maxTopLevelFolders: maxFolders)
        } catch let validationError as ValidationError {
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

        let planAfterValidation = validatedPlanFromRetry ?? normalizedInputPlan

        try checkCancellation()

        var validatedPlan = planAfterValidation
        if let exclusionRules = exclusionRules {
            let enforcer = ExclusionEnforcer(exclusionManager: exclusionRules)
            self.exclusionEnforcer = enforcer

            let validationResult = enforcer.validate(planAfterValidation)

            if validationResult.hasViolations {
                LogManager.shared.log("Exclusion violations detected: \(validationResult.violationCount) files", category: "FolderOrganizer")

                if let retryPlan = await retryWithExclusionEnhancement(
                    files: files,
                    client: client,
                    violations: validationResult.violations,
                    instructions: instructions,
                    personaPrompt: personaPrompt,
                    temperature: temperature,
                    imagePayload: imagePayload
                ) {
                    let retryValidation = enforcer.validate(retryPlan)
                    if retryValidation.hasViolations {
                        LogManager.shared.log("Retry still has \(retryValidation.violationCount) violations, stripping", category: "FolderOrganizer")
                        validatedPlan = retryValidation.cleanedPlan ?? retryPlan
                    } else {
                        validatedPlan = retryPlan
                    }
                } else {
                    validatedPlan = validationResult.cleanedPlan ?? planAfterValidation
                }
            }
        }

        return normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: validatedPlan))
    }

    private func applyRenameRuleConfiguration(to plan: OrganizationPlan) -> OrganizationPlan {
        guard let config = aiConfig else { return plan }
        guard config.mode == .renameOnly || config.mode == .organizeAndRename else { return plan }
        guard !config.renameRules.isEmpty else { return plan }

        var updatedPlan = plan
        updatedPlan.suggestions = updatedPlan.suggestions.map {
            applyRenameRules(in: $0, rules: config.renameRules, mode: config.renameRuleMode)
        }
        return updatedPlan
    }

    private func normalizeRenameSuggestions(in plan: OrganizationPlan) -> OrganizationPlan {
        guard let config = aiConfig else { return plan }
        guard config.mode == .renameOnly || config.mode == .organizeAndRename else { return plan }

        var updatedPlan = plan
        updatedPlan.suggestions = updatedPlan.suggestions.map {
            normalizeRenameSuggestions(in: $0, options: config.renameNamingOptions)
        }
        return updatedPlan
    }

    private func normalizeRenameSuggestions(
        in folder: FolderSuggestion,
        options: RenameNamingOptions
    ) -> FolderSuggestion {
        var updated = folder
        var existingNames = Set(updated.files.map(\.displayName))

        for mapping in updated.fileRenameMappings {
            guard mapping.hasRename, let suggestedName = mapping.suggestedName else { continue }
            guard let normalized = FilenameNormalizer.normalize(
                suggestedName,
                originalFilename: mapping.originalFile.displayName,
                options: options
            ) else {
                updated.updateRename(
                    for: mapping.originalFile,
                    newName: nil,
                    reason: mapping.renameReason,
                    confidence: mapping.renameConfidence
                )
                continue
            }

            existingNames.remove(mapping.originalFile.displayName)
            let uniqueName = FilenameNormalizer.uniqued(normalized, against: &existingNames)
            updated.updateRename(
                for: mapping.originalFile,
                newName: uniqueName,
                reason: mapping.renameReason,
                confidence: mapping.renameConfidence
            )
        }

        updated.subfolders = updated.subfolders.map {
            normalizeRenameSuggestions(in: $0, options: options)
        }
        return updated
    }

    private func applyRenameRules(
        in folder: FolderSuggestion,
        rules: [RenameRule],
        mode: RenameRuleApplicationMode
    ) -> FolderSuggestion {
        var updated = folder

        for file in updated.files {
            let existing = updated.renameMapping(for: file)
            let transformed = RenameRuleEngine.applyRules(to: file.displayName, rules: rules)
            let sanitization = FilenameSanitizer.sanitize(
                transformed,
                preservingExtension: file.extension,
                enforceExtension: true
            )
            let ruleCandidate = sanitization.sanitizedName
            let shouldUseRule = ruleCandidate != nil && ruleCandidate != file.displayName

            switch mode {
            case .rulesOnly:
                if let ruleCandidate, shouldUseRule {
                    updated.updateRename(for: file, newName: ruleCandidate, reason: "Applied custom rename rule")
                } else {
                    updated.updateRename(for: file, newName: nil)
                }
            case .beforeAI:
                if existing?.hasRename == true {
                    continue
                }
                if let ruleCandidate, shouldUseRule {
                    updated.updateRename(for: file, newName: ruleCandidate, reason: "Applied custom rename rule")
                }
            }
        }

        updated.subfolders = updated.subfolders.map {
            applyRenameRules(in: $0, rules: rules, mode: mode)
        }
        return updated
    }

    private func normalizeStorageDestinations(
        in plan: OrganizationPlan,
        allowedLocations: [StorageLocation],
        sourceDirectoryURL: URL? = nil
    ) -> OrganizationPlan {
        let knownSubfolders = storageLocationsManager?.discoverAllSubfolders() ?? [:]

        if !allowedLocations.isEmpty {
            let originalFolders = plan.suggestions.map(\.folderName)
            DebugLogger.log("[StorageNorm] Before normalization — folders: \(originalFolders)")
            DebugLogger.log("[StorageNorm] Allowed locations: \(allowedLocations.map { "\($0.name) → \($0.path)" })")
            if let srcDir = sourceDirectoryURL {
                DebugLogger.log("[StorageNorm] Source directory: \(srcDir.path)")
            }
        }

        let normalizedPlan = StorageDestinationNormalizer.normalize(
            plan: plan,
            allowedStorageLocations: allowedLocations,
            knownSubfolders: knownSubfolders,
            sourceDirectoryURL: sourceDirectoryURL
        )

        if normalizedPlan != plan {
            let changedFolders = zip(plan.suggestions, normalizedPlan.suggestions)
                .filter { $0.0.folderName != $0.1.folderName }
                .map { "\"\($0.0.folderName)\" → \"\($0.1.folderName)\"" }
            LogManager.shared.log(
                "Normalized storage destination aliases: \(changedFolders.joined(separator: ", "))",
                category: "FolderOrganizer"
            )
            DebugLogger.log("[StorageNorm] After normalization — changed: \(changedFolders)")
        } else if !allowedLocations.isEmpty {
            DebugLogger.log("[StorageNorm] No changes after normalization")
        }

        return normalizedPlan
    }

    private func resolvePlanFolderURL(folderName: String, baseURL: URL) -> URL {
        if let absoluteURL = StorageLocationPathResolver.absoluteURL(from: folderName) {
            return absoluteURL
        }
        return baseURL.appendingPathComponent(folderName, isDirectory: true)
    }

    // MARK: - Cancellation

    /// Cancel any ongoing operation - RELIABLE cancellation
    public func cancel() {
        DebugLogger.log("Cancel requested by user")
        AISessionManager.shared.clearErrors()
        cancelInternal()
        resetToIdle()
    }

    /// Stop live work immediately while a caller owns the visual return-to-start transition.
    /// The caller should finish the cancellation with `cancel()` after the outgoing view has faded.
    public func prepareForReturnToStartTransition() {
        guard state == .scanning || state == .organizing || state == .applying else { return }
        DebugLogger.log("Preparing return-to-start cancellation")
        AISessionManager.shared.clearErrors()
        suppressCancellationReset = true
        cancelInternal()
        isStreaming = false
        stopSteadyProgressTask()
    }

    private func cancelInternal() {
        isCancellationRequested = true
        currentTask?.cancel()
        currentTask = nil
        displayUpdateTask?.cancel()
        displayUpdateTask = nil
        insightExtractionTask?.cancel()
        insightExtractionTask = nil
        stopTimeoutTimer()
    }

    private func cancelCurrentOperationForRestart() async {
        suppressCancellationReset = true
        isCancellationRequested = true

        let taskToCancel = currentTask
        currentTask?.cancel()
        currentTask = nil
        displayUpdateTask?.cancel()
        displayUpdateTask = nil
        insightExtractionTask?.cancel()
        insightExtractionTask = nil
        stopTimeoutTimer()
        stopSteadyProgressTask()

        _ = await taskToCancel?.result
        suppressCancellationReset = false
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

    private func resetToIdle(source: OrganizationEntrySource = .manual) {
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
                    rawAIResponse: streamingContent.isEmpty ? nil : streamingContent,
                    source: source
                )
                history.addEntry(cancelledEntry)

                // Record to learnings with available context (avoiding expensive directory re-scans)
                let fileCount = max(scannedFileCount, currentPlan?.totalFiles ?? 0)
                let proposedFolders = currentPlan?.suggestions.count ?? 0
                let folderNames = currentPlan?.suggestions.map { $0.folderName }
                
                learningsManager?.recordCancelledOrganization(
                    folderPath: directory.path,
                    fileCount: fileCount,
                    proposedFolderCount: proposedFolders,
                    instructions: customInstructions.isEmpty ? nil : customInstructions,
                    stage: organizationStage.isEmpty ? "analysis" : organizationStage,
                    proposedFolderNames: folderNames,
                    proposedStructureSummary: nil,
                    fileExtensionCounts: nil,
                    regenerationCount: currentPlan?.version ?? 0,
                    regenerationInstructions: nil,
                    aiModel: aiConfig?.model
                )
            }
        }

        transition(to: .idle, force: true)
        organizationStage = "" // Clear instead of "Organization cancelled" to avoid "doing too much"
        isStreaming = false
        
        stopSteadyProgressTask()
    }

    private func resetToIdleUnlessCancellationResetIsSuppressed(source: OrganizationEntrySource = .manual) {
        guard !suppressCancellationReset else { return }
        resetToIdle(source: source)
    }

    @MainActor
    private func handleOrganizationError(_ error: Error, directory: URL, source: OrganizationEntrySource = .manual) {
        let displayMessage = userFacingErrorMessage(for: error)
        let failedEntry = OrganizationHistoryEntry(
            directoryPath: directory.path,
            filesOrganized: 0,
            foldersCreated: 0,
            plan: nil,
            success: false,
            status: .failed,
            errorMessage: displayMessage,
            rawAIResponse: streamingContent.isEmpty ? nil : streamingContent,
            source: source
        )
        history.addEntry(failedEntry)

        // Don't show anything for cancellation errors
        let isCancellation = (error is CancellationError) ||
                             ((error as? OrganizationError) == .cancelled) ||
                             ((error as? AIClientError)?.isCancellation ?? false) ||
                             (error as NSError).code == NSURLErrorCancelled ||
                             error.localizedDescription.lowercased().contains("cancelled") ||
                             error.localizedDescription.lowercased().contains("canceled")
        
        if isCancellation {
            resetToIdle()
            return
        }

        transition(to: .error(error), force: true)
        errorMessage = displayMessage
        
        // Show error notification
        NotificationManager.shared.showError(
            message: displayMessage,
            folderPath: currentDirectory?.path,
            isCritical: true
        )
    }

    @MainActor
    private func userFacingErrorMessage(for error: Error) -> String {
        if let clientError = error as? AIClientError {
            return clientError.failureReason ?? clientError.errorDescription ?? clientError.localizedDescription
        }
        if let localized = error as? LocalizedError {
            if let reason = localized.failureReason, !reason.isEmpty {
                return reason
            }
            if let description = localized.errorDescription, !description.isEmpty {
                return description
            }
        }
        return error.localizedDescription
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
        restartPlanGenerationForRetry()
        
        // Generate enhanced prompt with violation details
        let enhancedPrompt = instructions + enforcer.generateRetryPromptEnhancement(for: violations)
        
        do {
            defer { stopTimeoutTimer() }
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
            enhancement = """
            
            CRITICAL CORRECTION REQUIRED:
            Your previous response created \(count) top-level folders, but the maximum allowed is \(max).
            You MUST consolidate categories to produce at most \(max) top-level folders.
            Merge related categories together. For example, combine "Work Documents" and "Reports" into "Work", or group smaller categories into a single "Misc" folder.
            """
        case .pathExists(let path):
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            LogManager.shared.log("Retrying: path exists conflict (\(fileName))", category: "FolderOrganizer")
            enhancement = """
            
            CRITICAL CORRECTION REQUIRED:
            You suggested a folder named "\(fileName)", but a FILE with that exact name already exists in the directory.
            You MUST NOT use "\(fileName)" as a folder name.
            Choose a different folder name that does not conflict with existing files. For example, add a suffix like "\(fileName) Files" or use a different category name.
            """
        case .invalidStorageLocation(let path):
            LogManager.shared.log("Retrying: invalid storage location (\(path))", category: "FolderOrganizer")
            let allowedList: String
            if allowedStorageLocations.isEmpty {
                allowedList = "- No storage locations are currently enabled. Use only relative folder names."
            } else {
                allowedList = allowedStorageLocations
                    .map { "  - \($0.path) (\($0.name))" }
                    .joined(separator: "\n")
            }

            enhancement = """
            
            CRITICAL CORRECTION REQUIRED:
            You used an invalid storage location path: "\(path)".
            If you choose a storage destination, the folder name MUST be an absolute path within one of these approved storage roots:
            \(allowedList)
            You may use a root path itself or a subfolder inside that root (for example: /Archive/Excel Sheets).
            Never use relative placeholders like "storage" or "storage/anything".
            If none of the approved roots fit, organize files with relative folders under the source directory instead.
            """
        case .sourceInStorageLocation(let file, let location):
            LogManager.shared.log("Retrying: source in storage location (\(file) in \(location))", category: "FolderOrganizer")
            enhancement = """
            
            CRITICAL CORRECTION REQUIRED:
            "\(file)" is already inside storage location "\(location)".
            Files already inside storage locations MUST NOT be moved to non-storage destinations.
            Keep that file inside the same storage location (you may use subfolders there), or leave it unorganized.
            """
        default:
            return nil
        }

        restartPlanGenerationForRetry()
        
        let enhancedPrompt = instructions + enhancement
        
        do {
            defer { stopTimeoutTimer() }
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
            
            let normalizedRetryPlan = normalizeStorageDestinations(in: retryPlan, allowedLocations: allowedStorageLocations, sourceDirectoryURL: directory)

            // Validate the retry plan
            try validator.validate(
                normalizedRetryPlan,
                at: directory,
                allowedStorageLocations: allowedStorageLocations,
                maxTopLevelFolders: maxTopLevelFolders
            )
            LogManager.shared.log("Validation retry succeeded", category: "FolderOrganizer")
            return normalizedRetryPlan
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

    public func organizeIncremental(
        directory: URL,
        specificFiles: [String]? = nil,
        customPrompt: String? = nil,
        temperature: Double? = nil,
        providerOverride: AIProvider? = nil,
        modelOverride: String? = nil,
        historySource: OrganizationEntrySource = .manual
    ) async throws {
        guard !isOperationInProgress() else {
            DebugLogger.log("Incremental organization blocked: Already in progress")
            return
        }

        cancelInternal()
        isCancellationRequested = false

        currentTask = Task {
            try await performIncrementalOrganization(
                directory: directory,
                specificFiles: specificFiles,
                customPrompt: customPrompt,
                temperature: temperature,
                providerOverride: providerOverride,
                modelOverride: modelOverride,
                historySource: historySource
            )
        }
        defer { currentTask = nil }

        do {
            try await currentTask?.value
        } catch is CancellationError {
            resetToIdle(source: historySource)
        }
    }

    private func performIncrementalOrganization(
        directory: URL,
        specificFiles: [String]?,
        customPrompt: String?,
        temperature: Double?,
        providerOverride: AIProvider? = nil,
        modelOverride: String? = nil,
        historySource: OrganizationEntrySource = .manual
    ) async throws {
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
            updateState(.scanning, stage: "Scanning \(specificFiles.count) new files...", progress: 0.1)
            try checkCancellation()
            
            // Enable deep scan for small batches
            let shouldDeepScan = (aiConfig?.enableDeepScan ?? false) && specificFiles.count <= 20
            
            // map file names to FileItems
            // We assume specificFiles are filenames or relative paths
            for filename in specificFiles {
                let fileURL = directory.appendingPathComponent(filename)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
                    continue
                }

                if isDirectory.boolValue {
                    if let nestedFiles = try? await scanner.scanDirectory(at: fileURL, deepScan: shouldDeepScan) {
                        files.append(contentsOf: nestedFiles)
                    }
                } else if let item = try? await scanner.scanFile(at: fileURL, deepScan: shouldDeepScan) {
                    files.append(item)
                }
            }
            files = Array(Set(files))
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
                transition(to: .idle, force: true)
                organizationStage = "No new files to organize"
            }
            return
        }

        updateState(.organizing, stage: "Organizing \(files.count) new files...", progress: 0.3)
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

            if let modelDirContext = learningsManager?.generateModelDirectoryContext(), !modelDirContext.isEmpty {
                finalPrompt += "\n\n" + modelDirContext
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
                currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: plan))
            }

            // Validate plan before auto-apply (with a targeted retry for common validation failures)
            let allowedLocations = storageLocationsManager?.enabledLocations ?? []
            let maxTopLevelFolders = aiConfig?.maxTopLevelFolders ?? 10
            var planAfterValidation = normalizeStorageDestinations(in: plan, allowedLocations: allowedLocations, sourceDirectoryURL: directory)
            do {
                try validator.validate(
                    planAfterValidation,
                    at: directory,
                    allowedStorageLocations: allowedLocations,
                    maxTopLevelFolders: maxTopLevelFolders
                )
            } catch let validationError as ValidationError {
                if let retryPlan = await retryWithValidationEnhancement(
                    files: files,
                    client: client,
                    validationError: validationError,
                    directory: directory,
                    instructions: finalPrompt,
                    personaPrompt: personaPrompt,
                    temperature: temperature,
                    imagePayload: [:],
                    maxTopLevelFolders: maxTopLevelFolders,
                    allowedStorageLocations: allowedLocations
                ) {
                    planAfterValidation = retryPlan
                } else {
                    throw validationError
                }
            }

            // Post-AI exclusion validation
            var validatedPlan = planAfterValidation
            if let exclusionRules = exclusionRules {
                let enforcer = ExclusionEnforcer(exclusionManager: exclusionRules)
                let validationResult = enforcer.validate(planAfterValidation)
                if validationResult.hasViolations {
                    LogManager.shared.log("Exclusion violations in incremental plan: \(validationResult.violationCount)", category: "FolderOrganizer")
                    validatedPlan = validationResult.cleanedPlan ?? planAfterValidation
                }
            }

            await MainActor.run {
                currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: validatedPlan))
            }

            // Auto-apply for incremental
            try await apply(at: directory, dryRun: false, enableTagging: true, source: historySource)

        } catch {
            stopTimeoutTimer()
            handleOrganizationError(error, directory: directory, source: historySource)
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
                transition(to: .idle, force: true)
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
                transition(to: .idle, force: true)
                organizationStage = "No files found to organize"
            }
            return 0
        }

        // Filter with exclusion rules
        if let exclusionRules = exclusionRules {
            files = exclusionRules.filterFiles(files)
        }

        guard !files.isEmpty else {
            await MainActor.run {
                transition(to: .idle, force: true)
                organizationStage = "All selected files are excluded by your rules"
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
        defer { currentTask = nil }

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

        updateState(.organizing, stage: "Analyzing \(files.count) selected files...", progress: 0.3)
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

            if let modelDirContext = learningsManager?.generateModelDirectoryContext(), !modelDirContext.isEmpty {
                finalPrompt += "\n\n" + modelDirContext
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
                currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: plan))
            }

            // Validate selected-files plan before apply.
            let allowedLocations = storageLocationsManager?.enabledLocations ?? []
            let maxTopLevelFolders = aiConfig?.maxTopLevelFolders ?? 10
            var validatedPlan = normalizeStorageDestinations(in: plan, allowedLocations: allowedLocations, sourceDirectoryURL: directory)
            do {
                try validator.validate(
                    validatedPlan,
                    at: directory,
                    allowedStorageLocations: allowedLocations,
                    maxTopLevelFolders: maxTopLevelFolders
                )
            } catch let validationError as ValidationError {
                if let retryPlan = await retryWithValidationEnhancement(
                    files: files,
                    client: client,
                    validationError: validationError,
                    directory: directory,
                    instructions: finalPrompt,
                    personaPrompt: personaPrompt,
                    temperature: temperature,
                    imagePayload: [:],
                    maxTopLevelFolders: maxTopLevelFolders,
                    allowedStorageLocations: allowedLocations
                ) {
                    validatedPlan = retryPlan
                    await MainActor.run {
                        currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: retryPlan))
                    }
                } else {
                    throw validationError
                }
            }

            await MainActor.run {
                currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: validatedPlan))
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

    public func apply(at baseURL: URL, dryRun: Bool = false, enableTagging: Bool = true, source: OrganizationEntrySource = .manual) async throws {
        guard let currentPlan else {
            throw OrganizationError.noCurrentPlan
        }

        // Reset cancellation flag for new apply operation
        isCancellationRequested = false

        try checkCancellation()

        // Re-validate at apply time to protect all entry points, including regenerated previews.
        let maxFolders = aiConfig?.mode == .renameOnly ? 100 : (aiConfig?.maxTopLevelFolders ?? 10)
        let allowedLocations = storageLocationsManager?.enabledLocations ?? []
        let normalizedPlan = normalizeStorageDestinations(in: currentPlan, allowedLocations: allowedLocations, sourceDirectoryURL: baseURL)
        let planToApply = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: normalizedPlan))
        self.currentPlan = planToApply
        try validator.validate(
            planToApply,
            at: baseURL,
            allowedStorageLocations: allowedLocations,
            maxTopLevelFolders: maxFolders
        )

        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Applying organization to: \(baseURL.lastPathComponent)"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }

        updateState(.applying, stage: "Applying changes to your files...", progress: 0.0)
        
        // Start learning session for rule tracking
        if let learningsObserver = learningsObserver {
            learningsObserver.startSession(folderPath: baseURL.path, historyEntryId: nil)
        }

        do {
            let operations = try await fileSystemManager.applyOrganization(
                planToApply,
                at: baseURL, 
                dryRun: dryRun, 
                enableTagging: enableTagging,
                strictExclusions: aiConfig?.strictExclusions ?? true,
                exclusionManager: exclusionRules,
                progress: { [weak self] percent, message in
                    Task { @MainActor in
                        self?.progress = min(percent, 1.0)
                        self?.organizationStage = message
                    }
                }
            )

            try checkCancellation()
            
            // Track rule applications for learning feedback
            if let learningsObserver = learningsObserver, !dryRun {
                // Pre-start the session so rule applications can be recorded
                learningsObserver.startSession(folderPath: baseURL.path, historyEntryId: nil, operations: operations)
                recordRuleApplications(for: planToApply, operations: operations, observer: learningsObserver)
            }

            let historyEntry = OrganizationHistoryEntry(
                directoryPath: baseURL.path,
                filesOrganized: planToApply.totalFiles,
                foldersCreated: planToApply.totalFolders,
                plan: planToApply,
                success: true,
                status: .completed,
                rawAIResponse: streamingContent.isEmpty ? nil : streamingContent,
                operations: operations,
                source: source
            )

            await MainActor.run {
                history.addEntry(historyEntry)
                organizationStage = "Complete!"
                progress = 1.0
                transition(to: .completed)
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

            // Auto-reveal in Finder is opt-in.
            let shouldAutoRevealInFinder = automationManager?.autoSelectOrganizedFolders ?? false

            if let automationManager = automationManager, automationManager.automationStatus == .granted {
                automationManager.refreshFinder(at: baseURL)

                if shouldAutoRevealInFinder {
                    let folderURLs = planToApply.suggestions.map { resolvePlanFolderURL(folderName: $0.folderName, baseURL: baseURL) }
                    automationManager.selectOrganizedFolders(folderURLs: folderURLs)
                }
            } else if shouldAutoRevealInFinder {
                let folderURLs = planToApply.suggestions.compactMap { suggestion -> URL? in
                    let url = resolvePlanFolderURL(folderName: suggestion.folderName, baseURL: baseURL)
                    return FileManager.default.fileExists(atPath: url.path) ? url : nil
                }
                if !folderURLs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(folderURLs)
                }
            }

        } catch {
            let failedEntry = OrganizationHistoryEntry(
                directoryPath: baseURL.path,
                filesOrganized: 0,
                foldersCreated: 0,
                plan: planToApply,
                success: false,
                status: .failed,
                errorMessage: error.localizedDescription,
                rawAIResponse: streamingContent.isEmpty ? nil : streamingContent,
                source: source
            )

            await MainActor.run {
                history.addEntry(failedEntry)
            }

            throw error
        }
    }

    @MainActor
    public func redoOrganization(from entry: OrganizationHistoryEntry) async throws {
        guard let plan = entry.plan else {
            throw OrganizationError.noCurrentPlan
        }
        let baseURL = currentDirectory ?? URL(fileURLWithPath: entry.directoryPath)
        currentDirectory = baseURL
        currentPlan = plan

        updateState(.applying, stage: "Re-applying organization...", progress: 0.3)

        do {
            try await apply(at: baseURL, dryRun: false, enableTagging: aiConfig?.enableFileTagging ?? true)
            
            if entry.isUndone {
                var updatedEntry = entry
                updatedEntry.isUndone = false
                updatedEntry.status = .completed
                history.updateEntry(updatedEntry)
            }
            
            await MainActor.run {
                organizationStage = "Redo complete"
                progress = 1.0
                transition(to: .completed)
            }
        } catch {
            await MainActor.run {
                transition(to: .error(error), force: true)
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
        
        let isRenameOnly = tempConfig.mode == .renameOnly
        var instructions = customInstructions ?? self.customInstructions
        if !isRenameOnly, let learnedContext = learningsManager?.generatePromptContext(), !learnedContext.isEmpty {
            instructions += "\n\n" + learnedContext
        }
        if !isRenameOnly, let modelDirContext = learningsManager?.generateModelDirectoryContext(), !modelDirContext.isEmpty {
            instructions += "\n\n" + modelDirContext
        }
        if !isRenameOnly, let storageContext = storageLocationsManager?.generatePromptContext(), !storageContext.isEmpty {
            instructions += "\n\n" + storageContext
        }
        if let activeRules = exclusionRules?.rules.filter({ $0.isEnabled }), !activeRules.isEmpty {
            let excludedPatterns = activeRules.map { "- \($0.displayDescription)" }.joined(separator: "\n")
            let object = isRenameOnly ? "rename suggestions" : "organization plan"
            instructions += "\n\nIMPORTANT: The following patterns are STRICTLY EXCLUDED and must NOT be moved, renamed, or modified:\n\(excludedPatterns)\nEnsure your \(object) completely respects these exclusions."
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
        var files = getFilesFromCurrentPlan()
        guard !files.isEmpty else {
            throw OrganizationError.noCurrentPlan
        }
        
        guard !isOperationInProgress() else {
            return
        }
        
        if let exclusionRules = exclusionRules {
            files = exclusionRules.filterFiles(files)
        }
        
        isCancellationRequested = false
        
        // Reset streaming state
        await MainActor.run {
            clearStreamingDisplayState()
            isStreaming = false
            showTimeoutMessage = false
            currentInsight = ""
            insightHistory = []
            insightsCache = nil
        }
        
        let providerStage = aiConfig?.mode == .renameOnly
            ? "Getting new names from \(provider.displayName)..."
            : "Getting a new plan from \(provider.displayName)..."
        updateState(.organizing, stage: providerStage, progress: 0.3)
        
        do {
            var newPlan = try await generatePlanWithProvider(files: files, provider: provider)
            newPlan.version = (currentPlan?.version ?? 0) + 1
            
            if let exclusionRules = exclusionRules {
                let enforcer = ExclusionEnforcer(exclusionManager: exclusionRules)
                let validationResult = enforcer.validate(newPlan)
                if validationResult.hasViolations {
                    LogManager.shared.log("Exclusion violations in regenerated preview: \(validationResult.violationCount)", category: "FolderOrganizer")
                    newPlan = validationResult.cleanedPlan ?? newPlan
                }
            }
            
            try checkCancellation()
            
            await MainActor.run {
                isStreaming = false
                organizationStage = "Ready!"
                progress = 1.0
                if let existingPlan = self.currentPlan {
                    self.planHistory.append(existingPlan)
                    if self.planHistory.count > Constants.maxPreviewVersions {
                        self.planHistory.removeFirst()
                    }
                }
                self.currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: newPlan))
                transition(to: .ready)
            }
        } catch {
            await MainActor.run {
                transition(to: .error(error), force: true)
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// Regenerate preview with a specific provider and model
    public func regenerateWithModel(provider: AIProvider, model: String) async throws {
        if state == .scanning || state == .organizing {
            guard let directory = currentDirectory else {
                throw OrganizationError.noCurrentPlan
            }

            await cancelCurrentOperationForRestart()

            withBatchUpdates {
                clearStreamingDisplayState()
                isStreaming = false
                showTimeoutMessage = false
                currentInsight = ""
                insightHistory = []
                insightsCache = nil
                errorMessage = nil
                elapsedTime = 0
                let noun = aiConfig?.mode == .renameOnly ? "rename analysis" : "analysis"
                organizationStage = "Restarting \(noun) with \(provider.displayName) (\(model))..."
                progress = 0.08
            }

            try await runOrganizationTask(directory: directory, customPrompt: nil, temperature: nil)
            return
        }

        var files = getFilesFromCurrentPlan()
        
        if files.isEmpty, let directory = currentDirectory {
            files = try await scanPhase(directory: directory)
        }
        
        guard !files.isEmpty else {
            throw OrganizationError.noCurrentPlan
        }
        
        guard !isOperationInProgress() else {
            return
        }
        
        if let exclusionRules = exclusionRules {
            files = exclusionRules.filterFiles(files)
        }
        
        isCancellationRequested = false
        
        // Reset streaming state
        await MainActor.run {
            clearStreamingDisplayState()
            isStreaming = false
            showTimeoutMessage = false
            currentInsight = ""
            insightHistory = []
            insightsCache = nil
        }
        
        let modelStage = aiConfig?.mode == .renameOnly
            ? "Getting new names from \(provider.displayName) (\(model))..."
            : "Getting a new plan from \(provider.displayName) (\(model))..."
        updateState(.organizing, stage: modelStage, progress: 0.3)
        await MainActor.run {
            isStreaming = true
        }
        
        startTimeoutTimer()
        
        do {
            var newPlan = try await generatePlanWithProvider(files: files, provider: provider, model: model)
            newPlan.version = (currentPlan?.version ?? 0) + 1
            
            if let exclusionRules = exclusionRules {
                let enforcer = ExclusionEnforcer(exclusionManager: exclusionRules)
                let validationResult = enforcer.validate(newPlan)
                if validationResult.hasViolations {
                    LogManager.shared.log("Exclusion violations in regenerated preview: \(validationResult.violationCount)", category: "FolderOrganizer")
                    newPlan = validationResult.cleanedPlan ?? newPlan
                }
            }
            
            try checkCancellation()
            
            stopTimeoutTimer()
            
            await MainActor.run {
                isStreaming = false
                organizationStage = "Ready!"
                progress = 1.0
                if let existingPlan = self.currentPlan {
                    self.planHistory.append(existingPlan)
                    if self.planHistory.count > Constants.maxPreviewVersions {
                        self.planHistory.removeFirst()
                    }
                }
                self.currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: newPlan))
                transition(to: .ready)
            }
        } catch {
            stopTimeoutTimer()
            await MainActor.run {
                transition(to: .error(error), force: true)
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
            clearStreamingDisplayState()
            isStreaming = false
            showTimeoutMessage = false
            currentInsight = ""
            insightHistory = []
            insightsCache = nil
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
        
        if let exclusionRules = exclusionRules {
            allFiles = exclusionRules.filterFiles(allFiles)
        }

        let isRenameOnly = aiConfig?.mode == .renameOnly
        updateState(
            .organizing,
            stage: isRenameOnly ? "Generating new filename suggestions..." : "Generating a new organization plan...",
            progress: 0.3
        )
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
                    errorMessage: isRenameOnly ? "User requested different filename suggestions" : "User requested different organization",
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
            if !isRenameOnly, let learnedContext = learningsManager?.generatePromptContext(), !learnedContext.isEmpty {
                instructions += "\n\n" + learnedContext
            }

            if !isRenameOnly, let modelDirContext = learningsManager?.generateModelDirectoryContext(), !modelDirContext.isEmpty {
                instructions += "\n\n" + modelDirContext
            }
            
            // Add Storage Locations context
            if !isRenameOnly, let storageContext = storageLocationsManager?.generatePromptContext(), !storageContext.isEmpty {
                instructions += "\n\n" + storageContext
            }
            if let activeRules = exclusionRules?.rules.filter({ $0.isEnabled }), !activeRules.isEmpty {
                let excludedPatterns = activeRules.map { "- \($0.displayDescription)" }.joined(separator: "\n")
                let object = isRenameOnly ? "rename suggestions" : "organization plan"
                instructions += "\n\nIMPORTANT: The following patterns are STRICTLY EXCLUDED and must NOT be moved, renamed, or modified:\n\(excludedPatterns)\nEnsure your \(object) completely respects these exclusions."
            }
            
            var newPlan = try await client.analyze(files: allFiles, customInstructions: instructions, personaPrompt: personaPrompt, temperature: nil)
            newPlan.version = (currentPlan.version) + 1
            
            if let exclusionRules = exclusionRules {
                let enforcer = ExclusionEnforcer(exclusionManager: exclusionRules)
                let validationResult = enforcer.validate(newPlan)
                if validationResult.hasViolations {
                    LogManager.shared.log("Exclusion violations in regenerated preview: \(validationResult.violationCount)", category: "FolderOrganizer")
                    newPlan = validationResult.cleanedPlan ?? newPlan
                }
            }

            stopTimeoutTimer()

            try checkCancellation()

            await MainActor.run {
                isStreaming = false
                organizationStage = "Ready!"
                progress = 1.0
                if let existingPlan = self.currentPlan {
                    self.planHistory.append(existingPlan)
                    if self.planHistory.count > Constants.maxPreviewVersions {
                        self.planHistory.removeFirst()
                    }
                }
                self.currentPlan = normalizeRenameSuggestions(in: applyRenameRuleConfiguration(to: newPlan))
                transition(to: .ready)
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

    private func normalizedRevertPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func retainedOperations(
        from operations: [FileSystemManager.FileOperation]?,
        retryableFailedOperationIDs: [UUID]
    ) -> [FileSystemManager.FileOperation]? {
        guard let operations, !operations.isEmpty else {
            return nil
        }

        let failedIDs = Set(retryableFailedOperationIDs)
        guard !failedIDs.isEmpty else {
            return nil
        }

        let remaining = operations.filter { failedIDs.contains($0.id) }
        return remaining.isEmpty ? nil : remaining
    }

    private func withRevertGuard<T>(
        entryIDs: [UUID],
        path: String,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let normalizedPath = normalizedRevertPath(path)
        let didAcquire = await revertOperationTracker.begin(entryIDs: entryIDs, path: normalizedPath)
        guard didAcquire else {
            throw OrganizationError.revertAlreadyInProgress(normalizedPath)
        }

        #if DEBUG
        if let revertOperationTestHook {
            await revertOperationTestHook()
        }
        #endif

        do {
            let result = try await operation()
            await revertOperationTracker.end(entryIDs: entryIDs, path: normalizedPath)
            return result
        } catch {
            await revertOperationTracker.end(entryIDs: entryIDs, path: normalizedPath)
            throw error
        }
    }

    @discardableResult
    private func performUndoHistoryEntry(
        _ entry: OrganizationHistoryEntry,
        shouldPostNotification: Bool
    ) async throws -> FileSystemManager.RestoreResult {
        guard let operations = entry.operations, !operations.isEmpty, !entry.isUndone else {
            return FileSystemManager.RestoreResult(successfulOperations: 0, missingFiles: [])
        }

        updateState(.applying, stage: "Verifying files before undo...", progress: 0.1)

        let moveOps = operations.filter { $0.type == .moveFile || $0.type == .renameFile }
        var preCheckMissing: [String] = []
        for op in moveOps {
            if let dest = op.destinationPath, !FileManager.default.fileExists(atPath: dest) {
                let filename = URL(fileURLWithPath: dest).lastPathComponent
                preCheckMissing.append(filename)
                DebugLogger.log("Pre-check: file missing at \(dest)")
            }
        }

        if !preCheckMissing.isEmpty {
            let totalMoves = moveOps.count
            DebugLogger.log("Pre-check: \(preCheckMissing.count)/\(totalMoves) files missing before undo")
        }

        updateProgress(0.3, stage: "Undoing changes...")

        do {
            let result = try await fileSystemManager.reverseOperations(operations)

            var updatedEntry = entry
            let remainingOperations = retainedOperations(
                from: updatedEntry.operations,
                retryableFailedOperationIDs: result.retryableFailedOperationIDs
            )

            updatedEntry.operations = remainingOperations
            updatedEntry.isUndone = !result.hasIssues && remainingOperations == nil
            updatedEntry.undoRestoredCount = (entry.undoRestoredCount ?? 0) + result.successfulOperations
            updatedEntry.undoFailedFiles = result.hasIssues ? result.missingFiles : nil
            updatedEntry.status = remainingOperations == nil && !result.hasIssues ? .undo : .partiallyUndone

            history.updateEntry(updatedEntry)

            await MainActor.run {
                if result.hasIssues {
                    organizationStage = "Undo complete: \(result.successfulOperations) restored, \(result.missingFiles.count) skipped"
                } else {
                    organizationStage = "Undo complete"
                }
                progress = 1.0
                transition(to: .idle, force: true)
            }

            if shouldPostNotification {
                NotificationCenter.default.post(
                    name: .organizationDidRevert,
                    object: nil,
                    userInfo: [
                        "url": URL(fileURLWithPath: entry.directoryPath),
                        "entry": updatedEntry,
                        "restoreResult": result
                    ]
                )
            }

            return result

        } catch {
            await MainActor.run {
                transition(to: .error(error), force: true)
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    /// Undoes a specific historical session
    /// Pre-checks file existence, recovers from per-file errors, and tracks partial success
    @discardableResult
    public func undoHistoryEntry(_ entry: OrganizationHistoryEntry) async throws -> FileSystemManager.RestoreResult {
        try await withRevertGuard(entryIDs: [entry.id], path: entry.directoryPath) {
            try await self.performUndoHistoryEntry(entry, shouldPostNotification: true)
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
            !$0.isUndone &&
            ($0.status == .completed || $0.status == .partiallyUndone) &&
            !($0.operations?.isEmpty ?? true)
        }.sorted { $0.timestamp > $1.timestamp } // Undo most recent first

        return try await withRevertGuard(
            entryIDs: entriesToUndo.map(\.id),
            path: path
        ) {
            self.updateState(.applying, stage: "Rolling back states...", progress: 0.1)

            let total = Double(max(entriesToUndo.count, 1))
            var combinedSuccessCount = 0
            var combinedMissingFiles: [String] = []
            var combinedRetryableFailures: [UUID] = []

            for (index, entry) in entriesToUndo.enumerated() {
                self.updateProgress(Double(index) / total, stage: "Undoing session from \(entry.timestamp.formatted())...")

                let result = try await self.performUndoHistoryEntry(entry, shouldPostNotification: true)
                combinedSuccessCount += result.successfulOperations
                combinedMissingFiles.append(contentsOf: result.missingFiles)
                combinedRetryableFailures.append(contentsOf: result.retryableFailedOperationIDs)
            }

            let combinedResult = FileSystemManager.RestoreResult(
                successfulOperations: combinedSuccessCount,
                missingFiles: combinedMissingFiles,
                retryableFailedOperationIDs: combinedRetryableFailures
            )

            await MainActor.run { [self] in
                self.organizationStage = combinedResult.hasIssues ? "Restoration complete (some files skipped)" : "Restoration complete"
                self.progress = 1.0
                self.transition(to: .idle, force: true)
            }

            return combinedResult
        }
    }

    /// Undoes a single file operation within a history entry
    @discardableResult
    public func undoSingleOperation(from entry: OrganizationHistoryEntry, operation: FileSystemManager.FileOperation) async throws -> FileSystemManager.RestoreResult {
        try await withRevertGuard(entryIDs: [entry.id], path: entry.directoryPath) {
            let siblingOperations = (entry.operations ?? []).filter { $0.id != operation.id }
            let result = try await self.fileSystemManager.restoreSingleOperation(
                operation,
                protectedSiblingOperations: siblingOperations
            )

            await MainActor.run {
                var updatedEntry = entry
                let shouldRetainOperation = result.retryableFailedOperationIDs.contains(operation.id)
                if !shouldRetainOperation {
                    updatedEntry.operations?.removeAll { $0.id == operation.id }
                    if updatedEntry.operations?.isEmpty == true {
                        updatedEntry.operations = nil
                    }
                }

                let fullyUndone = updatedEntry.operations == nil && !result.hasIssues
                updatedEntry.isUndone = fullyUndone
                updatedEntry.status = fullyUndone ? .undo : .partiallyUndone
                updatedEntry.undoRestoredCount = (entry.undoRestoredCount ?? 0) + result.successfulOperations
                updatedEntry.undoFailedFiles = result.hasIssues ? result.missingFiles : nil

                self.history.updateEntry(updatedEntry)
            }

            return result
        }
    }

    // MARK: - Reset

    public func reset() {
        cancelInternal()
        
        // Clear transient AI session errors on manual reset
        AISessionManager.shared.clearErrors()

        // Batch all reset operations into a single UI update cycle
        withBatchUpdates {
            transition(to: .idle, force: true)
            progress = 0.0
            currentPlan = nil
            planHistory = []
            errorMessage = nil
            clearStreamingDisplayState()
            organizationStage = ""
            isStreaming = false
            showTimeoutMessage = false
            elapsedTime = 0
            currentDirectory = nil
            scannedFileCount = 0
            scannedFiles = []
            detectedDuplicates = []
            visionAnalysisSummary = nil
            isCancellationRequested = false
            userInitiatedAction = false
            lastChunkTime = .distantPast
            
            // Clear AI insights and cache
            insightExtractionTask?.cancel()
            insightExtractionTask = nil
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
        DispatchQueue.main.async {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

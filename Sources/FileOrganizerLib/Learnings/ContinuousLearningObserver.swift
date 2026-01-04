//
//  ContinuousLearningObserver.swift
//  FileOrganizer
//
//  Watches for user actions that contradict or refine AI decisions:
//  1. Manual Moves (Correction)
//  2. Deletions/Re-organization (Rejection)
//  3. History Reverts
//  4. User Instructions (Additional and Guiding)
//  5. Steering Prompts (Post-organization instructions)
//  6. Session Linking (Correlate all behaviors to AI sessions)
//
//  Enhanced with consent checking - no data collected without opt-in
//

import Foundation
import Combine

/// Represents an organization session for correlation
public struct OrganizationSession: Codable, Identifiable, Sendable {
    public let id: String
    public let timestamp: Date
    public let folderPath: String
    public let historyEntryId: String?
    public var steeringPrompts: [String]
    public var userCorrections: [DirectoryChange]
    public var wasReverted: Bool
    
    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        folderPath: String,
        historyEntryId: String? = nil,
        steeringPrompts: [String] = [],
        userCorrections: [DirectoryChange] = [],
        wasReverted: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.folderPath = folderPath
        self.historyEntryId = historyEntryId
        self.steeringPrompts = steeringPrompts
        self.userCorrections = userCorrections
        self.wasReverted = wasReverted
    }
}

@MainActor
public class ContinuousLearningObserver: ObservableObject {
    private var learningsManager: LearningsManager
    private var historyFn: () -> OrganizationHistory // Closure to access history to avoid retain cycles/init order issues
    
    private var cancellables = Set<AnyCancellable>()
    private var recentlyMovedFiles: [String: Date] = [:] // Path -> Time
    
    /// Current active session (started when organization is applied)
    @Published public private(set) var currentSession: OrganizationSession?
    
    /// Recent sessions for correlation (last 24 hours)
    private var recentSessions: [OrganizationSession] = []
    
    /// Observation window for correlating user changes with AI sessions (default 30 minutes)
    public var correlationWindowMinutes: Double = 30
    
    /// Quick access to consent status
    private var canCollect: Bool {
        learningsManager.consentManager.canCollectData
    }
    
    public init(learningsManager: LearningsManager, historyProvider: @escaping () -> OrganizationHistory) {
        self.learningsManager = learningsManager
        self.historyFn = historyProvider
    }
    
    public convenience init(history: OrganizationHistory, learningsManager: LearningsManager) {
        self.init(learningsManager: learningsManager, historyProvider: { history })
    }
    
    public func startObserving() {
        NotificationCenter.default.publisher(for: .organizationDidRevert)
            .sink { [weak self] notification in
                self?.handleRevertNotification(notification)
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .organizationDidFinish)
            .sink { [weak self] notification in
                self?.handleFinishNotification(notification)
            }
            .store(in: &cancellables)
        
        // Listen for steering prompts
        NotificationCenter.default.publisher(for: .steeringPromptProvided)
            .sink { [weak self] notification in
                self?.handleSteeringPrompt(notification)
            }
            .store(in: &cancellables)
        
        // Clean up old sessions periodically
        cleanupOldSessions()
    }
    
    /// Start a new organization session (called when organization is applied)
    public func startSession(folderPath: String, historyEntryId: String?) {
        guard canCollect else { return }
        
        let session = OrganizationSession(
            folderPath: folderPath,
            historyEntryId: historyEntryId
        )
        currentSession = session
        recentSessions.append(session)
        
        print("ContinuousLearning: Started session \(session.id) for \(folderPath)")
    }
    
    /// End the current session
    public func endSession() {
        if let session = currentSession {
            print("ContinuousLearning: Ended session \(session.id)")
        }
        currentSession = nil
    }
    
    // MARK: - Steering Prompts
    
    /// Track a steering prompt (post-organization instruction)
    public func trackSteeringPrompt(_ prompt: String, forFolder folderPath: String? = nil) {
        guard canCollect, !learningsManager.isLocked, !prompt.isEmpty else { return }
        
        // Add to current session if active
        if var session = currentSession {
            session.steeringPrompts.append(prompt)
            currentSession = session
            
            // Update in recentSessions array
            if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
                recentSessions[idx] = session
            }
        }
        
        // Record as guiding instruction for future use
        learningsManager.recordGuidingInstruction(prompt)
        learningsManager.recordSteeringPrompt(prompt, folderPath: folderPath ?? currentSession?.folderPath, sessionId: currentSession?.id)
        
        print("ContinuousLearning: Recorded steering prompt: \(prompt.prefix(50))...")
    }
    
    private func handleSteeringPrompt(_ notification: Notification) {
        guard let prompt = notification.userInfo?["prompt"] as? String else { return }
        let folderPath = notification.userInfo?["folderPath"] as? String
        
        trackSteeringPrompt(prompt, forFolder: folderPath)
    }
    
    private func cleanupOldSessions() {
        let cutoff = Date().addingTimeInterval(-86400) // 24 hours
        recentSessions = recentSessions.filter { $0.timestamp > cutoff }
    }
    
    /// Find the most relevant session for a given path
    private func findRelevantSession(for path: String) -> OrganizationSession? {
        let cutoff = Date().addingTimeInterval(-correlationWindowMinutes * 60)
        
        // Find sessions that:
        // 1. Are within the correlation window
        // 2. Have a matching folder path (the file is within the session's folder)
        return recentSessions
            .filter { $0.timestamp > cutoff }
            .filter { path.hasPrefix($0.folderPath) }
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }
    
    // MARK: - File Move Tracking
    
    /// Called by FolderWatcher delegate or FileSystemManager when a move occurs
    public func handleFileMove(from src: String, to dst: String) {
        guard canCollect, !learningsManager.isLocked else { return }
        
        // 1. Check if this file was recently organized by AI
        // Look back 24 hours (or configurable window)
        let history = historyFn()
        let recentEntries = history.entries.prefix(50) // Check last 50 sessions
        
        var foundMatch = false
        var matchedSession: OrganizationSession?
        
        // First try to find a relevant session
        matchedSession = findRelevantSession(for: src) ?? findRelevantSession(for: dst)
        
        for entry in recentEntries {
            guard let operations = entry.operations else { continue }
            
            // Check if this file (src) was the DESTINATION of an AI move
            // i.e. AI moved X -> src.
            // Now User moves src -> dst.
            // This implies Correction: X -> dst is the better rule.
            
            if let aiOp = operations.first(where: { $0.destinationPath == src }) {
                // Found the AI action that put the file here
                print("ContinuousLearning: Detected correction for \(aiOp.sourcePath)")
                print("AI put it at: \(src)")
                print("User moved it to: \(dst)")
                
                learningsManager.recordCorrection(originalPath: aiOp.sourcePath, newPath: dst)
                
                let change = DirectoryChange(
                    originalPath: src, 
                    newPath: dst, 
                    wasAIOrganized: true,
                    aiSessionId: matchedSession?.id ?? entry.id.uuidString
                )
                learningsManager.recordDirectoryChange(
                    from: src, 
                    to: dst, 
                    wasAIOrganized: true,
                    sessionId: matchedSession?.id ?? entry.id.uuidString
                )
                
                // Track correction in the session
                if var session = matchedSession {
                    session.userCorrections.append(change)
                    if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
                        recentSessions[idx] = session
                    }
                }
                
                foundMatch = true
                break
            }
        }
        
        if !foundMatch {
            // General learning (even if not correcting specific AI action)
            // Just assume user likes files of this type in this destination
            learningsManager.addPositiveExample(srcPath: src, dstPath: dst)
            learningsManager.recordDirectoryChange(
                from: src, 
                to: dst, 
                wasAIOrganized: false,
                sessionId: matchedSession?.id
            )
            
            // Still track in session if within correlation window
            if var session = matchedSession {
                let change = DirectoryChange(
                    originalPath: src, 
                    newPath: dst, 
                    wasAIOrganized: false,
                    aiSessionId: session.id
                )
                session.userCorrections.append(change)
                if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
                    recentSessions[idx] = session
                }
            }
        }
    }
    
    // MARK: - User Instructions Tracking
    
    /// Track when user provides additional instructions for organization
    public func trackAdditionalInstruction(_ instruction: String, forFolder folderPath: String) {
        guard canCollect, !learningsManager.isLocked else { return }
        
        learningsManager.recordAdditionalInstruction(instruction, for: folderPath)
        print("ContinuousLearning: Recorded additional instruction for \(folderPath)")
    }
    
    /// Track when user provides guiding instructions for next attempt
    public func trackGuidingInstruction(_ instruction: String) {
        guard canCollect, !learningsManager.isLocked else { return }
        
        learningsManager.recordGuidingInstruction(instruction)
        print("ContinuousLearning: Recorded guiding instruction")
    }
    
    // MARK: - History Revert Tracking
    
    private func handleRevertNotification(_ notification: Notification) {
        guard canCollect, !learningsManager.isLocked,
              let entry = notification.userInfo?["entry"] as? OrganizationHistoryEntry,
              let operations = entry.operations else { return }
        
        print("ContinuousLearning: Learning from Revert of session")
        
        // Find and update the relevant session
        if let idx = recentSessions.firstIndex(where: { $0.historyEntryId == entry.id.uuidString }) {
            recentSessions[idx].wasReverted = true
        }
        
        // Record revert event with enhanced context
        learningsManager.recordHistoryRevert(
            entryId: entry.id.uuidString,
            operationCount: operations.count,
            folderPath: entry.directoryPath,
            revertReason: notification.userInfo?["reason"] as? String
        )
        
        for op in operations {
            // AI moved A -> B.
            // User reverted (B -> A).
            // Learn: A -> B is BAD. (Rejection)
            learningsManager.recordRejection(originalPath: op.sourcePath)
        }
    }
    
    private func handleFinishNotification(_ notification: Notification) {
        // Track "pending" moves to correlate later
        // This helps us know "AI just put file X at Y" without querying history immediately
        if let entry = notification.userInfo?["entry"] as? OrganizationHistoryEntry,
           let operations = entry.operations {
            
            // Start a new session
            startSession(folderPath: entry.directoryPath, historyEntryId: entry.id.uuidString)
            
            for op in operations {
                if let destPath = op.destinationPath {
                    recentlyMovedFiles[destPath] = Date()
                }
            }
            
            // Clean up old entries (older than 24 hours)
            let cutoff = Date().addingTimeInterval(-86400)
            recentlyMovedFiles = recentlyMovedFiles.filter { $0.value > cutoff }
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let steeringPromptProvided = Notification.Name("steeringPromptProvided")
    
    // Learnings menu actions
    static let startHoningSession = Notification.Name("startHoningSession")
    static let showLearningsStats = Notification.Name("showLearningsStats")
    static let pauseLearning = Notification.Name("pauseLearning")
    static let exportLearningsProfile = Notification.Name("exportLearningsProfile")
    static let importLearningsProfile = Notification.Name("importLearningsProfile")
}

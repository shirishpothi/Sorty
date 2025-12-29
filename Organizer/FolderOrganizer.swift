//
//  FolderOrganizer.swift
//  FileOrganizer
//
//  Main orchestrator for organization workflow with streaming support
//

import Foundation
import SwiftUI

public enum OrganizationState: Equatable {
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
    
    public var errorDescription: String? {
        switch self {
        case .clientNotConfigured:
            return "AI Client not configured. Please check your settings."
        case .noCurrentPlan:
            return "No organization plan available to apply."
        case .fileMoveFailed(let details):
            return "Failed to move file: \(details)"
        }
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
    private var timeoutTimer: Timer?
    
    // Track current directory for failed history
    private var currentDirectory: URL?
    
    var scanner = DirectoryScanner()
    var aiClient: AIClientProtocol?
    private let fileSystemManager = FileSystemManager()
    private let validator = FileOrganizationValidator.self
    public let history = OrganizationHistory()
    public var exclusionRules: ExclusionRulesManager?
    public var personaManager: PersonaManager?
    
    public init() {}
    
    public func configure(with config: AIConfig) throws {
        let client = try AIClientFactory.createClient(config: config)
        aiClient = client
        
        // Set up streaming delegate if available
        if let openAIClient = client as? OpenAIClient {
            openAIClient.streamingDelegate = self
        }
    }
    
    // MARK: - StreamingDelegate
    
    nonisolated func didReceiveChunk(_ chunk: String) {
        Task { @MainActor in
            self.streamingContent += chunk
        }
    }
    
    nonisolated func didComplete(content: String) {
        Task { @MainActor in
            self.isStreaming = false
            self.organizationStage = "Processing response..."
            self.stopTimeoutTimer()
        }
    }
    
    nonisolated func didFail(error: Error) {
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
        
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let strongSelf = self, let start = strongSelf.startTime else { return }
                strongSelf.elapsedTime = Date().timeIntervalSince(start)
                
                if strongSelf.elapsedTime >= 30 && !strongSelf.showTimeoutMessage {
                    strongSelf.showTimeoutMessage = true
                }
            }
        }
    }
    
    private func stopTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        startTime = nil
    }
    
    public func organize(directory: URL, customPrompt: String? = nil, temperature: Double? = nil) async throws {
        guard let client = aiClient else {
            throw OrganizationError.clientNotConfigured
        }
        
        currentDirectory = directory
        streamingContent = ""
        isStreaming = false
        showTimeoutMessage = false
        
        state = .scanning
        organizationStage = "Scanning directory..."
        progress = 0.1
        
        var files = try await scanner.scanDirectory(at: directory)
        progress = 0.3
        
        if let exclusionRules = exclusionRules {
            files = exclusionRules.filterFiles(files)
        }
        
        state = .organizing
        organizationStage = "Organizing with AI..."
        isStreaming = true
        progress = 0.5
        
        startTimeoutTimer()
        
        do {
            let personaPrompt = personaManager?.getPrompt(for: personaManager?.selectedPersona ?? .general)
            // Use watched folder custom prompt if provided, otherwise generic customInstructions
            let instructions = customPrompt ?? customInstructions
            
            let plan = try await client.analyze(files: files, customInstructions: instructions, personaPrompt: personaPrompt, temperature: temperature)
            
            stopTimeoutTimer()
            isStreaming = false
            organizationStage = "Validating plan..."
            progress = 0.8
            
            try validator.validate(plan, at: directory)
            
            organizationStage = "Ready!"
            progress = 1.0
            
            currentPlan = plan
            state = .ready
        } catch {
            stopTimeoutTimer()
            
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
            
            throw error
        }
    }
    
    public func apply(at baseURL: URL, dryRun: Bool = false) async throws {
        guard let plan = currentPlan else {
            throw OrganizationError.noCurrentPlan
        }
        
        state = .applying
        organizationStage = "Applying changes..."
        progress = 0.0
        
        do {
            let operations = try await fileSystemManager.applyOrganization(plan, at: baseURL, dryRun: dryRun)
            
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
            history.addEntry(historyEntry)
            
            organizationStage = "Complete!"
            progress = 1.0
            state = .completed
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
            history.addEntry(failedEntry)
            
            throw error
        }
    }
    
    public func regeneratePreview() async throws {
        guard let currentPlan = currentPlan else {
            throw OrganizationError.noCurrentPlan
        }
        
        // Reset streaming state
        streamingContent = ""
        isStreaming = false
        showTimeoutMessage = false
        
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
        
        state = .organizing
        organizationStage = "Regenerating organization..."
        isStreaming = true
        progress = 0.5
        
        startTimeoutTimer()
        
        do {
            guard let client = aiClient else {
                throw OrganizationError.clientNotConfigured
            }
            
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
            var newPlan = try await client.analyze(files: allFiles, customInstructions: customInstructions, personaPrompt: personaPrompt, temperature: nil)
            newPlan.version = (currentPlan.version) + 1
            
            stopTimeoutTimer()
            isStreaming = false
            organizationStage = "Ready!"
            progress = 1.0
            self.currentPlan = newPlan
            state = .ready
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
        
        state = .applying
        organizationStage = "Undoing changes..."
        progress = 0.5
        
        try await fileSystemManager.reverseOperations(operations)
        
        var updatedEntry = entry
        updatedEntry.isUndone = true
        history.updateEntry(updatedEntry)
        
        organizationStage = "Undo complete"
        progress = 1.0
        state = .idle
    }
    
    /// Restores to a previous state by undoing all intermediate sessions
    public func restoreToState(targetEntry: OrganizationHistoryEntry) async throws {
        // Find all sessions on the same path that are after this one and not undone
        let path = targetEntry.directoryPath
        let entriesToUndo = history.entries.filter { 
            $0.directoryPath == path && 
            $0.timestamp > targetEntry.timestamp && 
            $0.success && 
            !$0.isUndone 
        }.sorted { $0.timestamp > $1.timestamp } // Undo most recent first
        
        state = .applying
        organizationStage = "Rolling back states..."
        let total = Double(entriesToUndo.count)
        
        for (index, entry) in entriesToUndo.enumerated() {
            organizationStage = "Undoing session from \(entry.timestamp.formatted())..."
            progress = Double(index) / total
            
            try await undoHistoryEntry(entry)
        }
        
        organizationStage = "Restoration complete"
        progress = 1.0
        state = .ready // Set to ready so user can see what they are back to (though files are back)
    }
    
    public func redoOrganization(from entry: OrganizationHistoryEntry) async throws {
        guard let plan = entry.plan else { return }
        // To "redo" an undone version, we just apply its plan again
        currentPlan = plan
        try await apply(at: URL(fileURLWithPath: entry.directoryPath))
    }
    
    public func reset() {
        stopTimeoutTimer()
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
    }
}

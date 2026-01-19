//
//  GenerationOrchestrator.swift
//  Sorty
//
//  Parallel generation system for managing multiple AI generation runs
//

import Foundation
import Combine

// MARK: - GenerationSpec

public struct GenerationSpec: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let provider: AIProvider
    public let model: String
    public let personaID: String?
    public let customInstructions: String
    public let enableReasoning: Bool
    public let enableDeepScan: Bool
    public let enableStreamingPreview: Bool
    
    public init(
        id: UUID = UUID(),
        provider: AIProvider,
        model: String,
        personaID: String? = nil,
        customInstructions: String = "",
        enableReasoning: Bool = false,
        enableDeepScan: Bool = false,
        enableStreamingPreview: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.model = model
        self.personaID = personaID
        self.customInstructions = customInstructions
        self.enableReasoning = enableReasoning
        self.enableDeepScan = enableDeepScan
        self.enableStreamingPreview = enableStreamingPreview
    }
}

// MARK: - GenerationStatus

public enum GenerationStatus: Equatable, Sendable {
    case queued
    case running(progress: Double, stage: String?)
    case finished(plan: OrganizationPlan)
    case failed(message: String)
    case canceled
    
    public static func == (lhs: GenerationStatus, rhs: GenerationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.queued, .queued):
            return true
        case (.running(let lProgress, let lStage), .running(let rProgress, let rStage)):
            return lProgress == rProgress && lStage == rStage
        case (.finished(let lPlan), .finished(let rPlan)):
            return lPlan.id == rPlan.id
        case (.failed(let lMsg), .failed(let rMsg)):
            return lMsg == rMsg
        case (.canceled, .canceled):
            return true
        default:
            return false
        }
    }
}

// MARK: - GenerationRun

public struct GenerationRun: Identifiable, Sendable {
    public let id: UUID
    public var spec: GenerationSpec
    public var status: GenerationStatus
    public var startTime: Date?
    public var endTime: Date?
    public var generatedPlan: OrganizationPlan?
    public var streamingContent: String
    public var didCompleteStreaming: Bool
    
    public init(
        id: UUID = UUID(),
        spec: GenerationSpec,
        status: GenerationStatus = .queued,
        startTime: Date? = nil,
        endTime: Date? = nil,
        generatedPlan: OrganizationPlan? = nil,
        streamingContent: String = "",
        didCompleteStreaming: Bool = false
    ) {
        self.id = id
        self.spec = spec
        self.status = status
        self.startTime = startTime
        self.endTime = endTime
        self.generatedPlan = generatedPlan
        self.streamingContent = streamingContent
        self.didCompleteStreaming = didCompleteStreaming
    }
}

// MARK: - GenerationOrchestrator

@MainActor
public class GenerationOrchestrator: ObservableObject {
    @Published public var runs: [GenerationRun] = []
    @Published public var selectedRunID: UUID?
    @Published public var isAnyRunning: Bool = false
    
    private var runTasks: [UUID: Task<Void, Never>] = [:]
    private var lastProgressUpdate: [UUID: Date] = [:]
    private var streamingDelegates: [UUID: AnyObject] = [:]
    private let progressThrottleInterval: TimeInterval = 0.1
    
    public init() {}
    
    // MARK: - Computed Properties
    
    public var selectedRun: GenerationRun? {
        guard let id = selectedRunID else { return nil }
        return runs.first { $0.id == id }
    }
    
    public var completedRuns: [GenerationRun] {
        runs.filter { run in
            if case .finished = run.status {
                return true
            }
            return false
        }
    }
    
    public var failedRuns: [GenerationRun] {
        runs.filter { run in
            if case .failed = run.status {
                return true
            }
            return false
        }
    }
    
    // MARK: - Spec Management
    
    @discardableResult
    public func addSpec(_ spec: GenerationSpec) -> UUID {
        let run = GenerationRun(id: spec.id, spec: spec)
        runs.append(run)
        return run.id
    }
    
    public func removeSpec(id: UUID) {
        cancelRun(id: id)
        runs.removeAll { $0.id == id }
        if selectedRunID == id {
            selectedRunID = nil
        }
    }
    
    public func updateSpec(id: UUID, with spec: GenerationSpec) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        
        if case .running = runs[index].status {
            return
        }
        
        runs[index].spec = spec
        runs[index].status = .queued
        runs[index].startTime = nil
        runs[index].endTime = nil
        runs[index].generatedPlan = nil
        runs[index].streamingContent = ""
        runs[index].didCompleteStreaming = false
    }
    
    // MARK: - Run Execution
    
    public func startAll(
        files: [FileItem],
        baseURL: URL,
        config: AIConfig,
        using organizer: FolderOrganizer
    ) async {
        let queuedRuns = runs.filter { run in
            if case .queued = run.status { return true }
            if case .failed = run.status { return true }
            return false
        }
        
        await withTaskGroup(of: Void.self) { group in
            for run in queuedRuns {
                group.addTask { @MainActor in
                    await self.startRun(
                        id: run.id,
                        files: files,
                        baseURL: baseURL,
                        config: config,
                        using: organizer
                    )
                }
            }
        }
    }
    
    public func startRun(
        id: UUID,
        files: [FileItem],
        baseURL: URL,
        config: AIConfig,
        using organizer: FolderOrganizer
    ) async {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        
        if case .running = runs[index].status {
            return
        }
        
        runs[index].status = .running(progress: 0, stage: "Starting...")
        runs[index].startTime = Date()
        runs[index].streamingContent = ""
        runs[index].didCompleteStreaming = false
        updateIsAnyRunning()
        
        let spec = runs[index].spec
        
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            do {
                // Create a fresh config and client for this run to avoid shared state issues
                var runConfig = config
                runConfig.provider = spec.provider
                runConfig.model = spec.model
                runConfig.enableReasoning = spec.enableReasoning
                runConfig.enableDeepScan = spec.enableDeepScan
                runConfig.enableStreaming = spec.enableStreamingPreview
                
                // Create a dedicated client for this run (not shared with organizer)
                var client = try AIClientFactory.createClient(config: runConfig)
                
                self.updateProgress(for: id, progress: 0.1, stage: "Configured AI client")
                
                if Task.isCancelled {
                    self.markCanceled(id: id)
                    return
                }
                
                self.updateProgress(for: id, progress: 0.2, stage: "Analyzing files...")

                if Task.isCancelled {
                    self.markCanceled(id: id)
                    return
                }

                // Set up streaming delegate for this run's client
                let delegate: StreamingDelegate? = spec.enableStreamingPreview
                    ? OrchestrationStreamingDelegate(runID: id, orchestrator: self)
                    : nil
                streamingDelegates[id] = delegate as AnyObject?
                client.streamingDelegate = delegate

                self.updateProgress(for: id, progress: 0.5, stage: "Generating organization plan...")

                let personaPrompt = self.resolvePersonaPrompt(for: spec, organizer: organizer)
                let plan = try await self.generatePlan(
                    with: client,
                    files: files,
                    customInstructions: spec.customInstructions,
                    personaPrompt: personaPrompt
                )

                if spec.enableStreamingPreview {
                    self.markStreamingComplete(for: id, content: runs.first(where: { $0.id == id })?.streamingContent ?? "")
                }
                
                if Task.isCancelled {
                    self.markCanceled(id: id)
                    return
                }
                
                self.markFinished(id: id, plan: plan)
                
            } catch {
                if Task.isCancelled {
                    self.markCanceled(id: id)
                } else {
                    self.markFailed(id: id, message: error.localizedDescription)
                }
            }
        }
        
        runTasks[id] = task
    }
    
    // MARK: - Run Control
    
    public func cancelRun(id: UUID) {
        runTasks[id]?.cancel()
        runTasks[id] = nil
        markCanceled(id: id)
    }
    
    public func cancelAll() {
        for (id, task) in runTasks {
            task.cancel()
            markCanceled(id: id)
        }
        runTasks.removeAll()
    }
    
    public func retryFailed() {
        for index in runs.indices {
            if case .failed = runs[index].status {
                runs[index].status = .queued
                runs[index].startTime = nil
                runs[index].endTime = nil
                runs[index].generatedPlan = nil
            }
        }
    }
    
    public func selectRun(id: UUID) {
        selectedRunID = id
    }
    
    public func clearCompleted() {
        runs.removeAll { run in
            if case .finished = run.status {
                return true
            }
            return false
        }
        
        if let selectedID = selectedRunID,
           !runs.contains(where: { $0.id == selectedID }) {
            selectedRunID = nil
        }
    }
    
    // MARK: - Progress Updates
    
    public func updateProgress(for id: UUID, progress: Double, stage: String?) {
        let now = Date()
        if let lastUpdate = lastProgressUpdate[id],
           now.timeIntervalSince(lastUpdate) < progressThrottleInterval {
            return
        }
        
        lastProgressUpdate[id] = now
        
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].status = .running(progress: progress, stage: stage)
    }
    
    // MARK: - Private Helpers
    
    private func markFinished(id: UUID, plan: OrganizationPlan) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].status = .finished(plan: plan)
        runs[index].endTime = Date()
        runs[index].generatedPlan = plan
        runTasks[id] = nil
        lastProgressUpdate[id] = nil
        updateIsAnyRunning()
    }
    
    private func markFailed(id: UUID, message: String) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].status = .failed(message: message)
        runs[index].endTime = Date()
        runTasks[id] = nil
        lastProgressUpdate[id] = nil
        updateIsAnyRunning()
    }
    
    private func markCanceled(id: UUID) {
        guard let index = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[index].status = .canceled
        runs[index].endTime = Date()
        runTasks[id] = nil
        lastProgressUpdate[id] = nil
        streamingDelegates[id] = nil
        updateIsAnyRunning()
    }

    @MainActor
    private final class OrchestrationStreamingDelegate: NSObject, StreamingDelegate {
        private let runID: UUID
        private weak var orchestrator: GenerationOrchestrator?

        init(runID: UUID, orchestrator: GenerationOrchestrator) {
            self.runID = runID
            self.orchestrator = orchestrator
        }

        func didReceiveChunk(_ chunk: String) {
            orchestrator?.appendStreamingChunk(chunk, for: runID)
        }

        func didComplete(content: String) {
            orchestrator?.markStreamingComplete(for: runID, content: content)
        }

        func didFail(error: Error) {
            orchestrator?.markStreamingFailed(for: runID, error: error)
        }
    }

    private func generatePlan(
        with client: AIClientProtocol,
        files: [FileItem],
        customInstructions: String,
        personaPrompt: String?
    ) async throws -> OrganizationPlan {
        return try await client.analyze(
            files: files,
            customInstructions: customInstructions,
            personaPrompt: personaPrompt,
            temperature: nil
        )
    }

    private func resolvePersonaPrompt(for spec: GenerationSpec, organizer: FolderOrganizer) -> String? {
        guard let personaManager = organizer.personaManager else { return nil }
        if let personaID = spec.personaID {
            if let personaType = PersonaType(rawValue: personaID) {
                return personaManager.getPrompt(for: personaType)
            }
            if let customStore = organizer.customPersonaStore,
               let custom = customStore.customPersonas.first(where: { $0.id == personaID }) {
                return custom.promptModifier
            }
        }
        return personaManager.getEffectivePrompt(customStore: organizer.customPersonaStore ?? CustomPersonaStore())
    }

    func appendStreamingChunk(_ chunk: String, for runID: UUID) {
        guard let index = runs.firstIndex(where: { $0.id == runID }) else { return }
        runs[index].streamingContent += chunk
        runs[index].didCompleteStreaming = false
    }

    func markStreamingComplete(for runID: UUID, content: String) {
        guard let index = runs.firstIndex(where: { $0.id == runID }) else { return }
        if !content.isEmpty {
            runs[index].streamingContent = content
        }
        runs[index].didCompleteStreaming = true
        streamingDelegates[runID] = nil
    }

    func markStreamingFailed(for runID: UUID, error: Error) {
        guard let index = runs.firstIndex(where: { $0.id == runID }) else { return }
        runs[index].streamingContent = "Streaming failed: \(error.localizedDescription)"
        runs[index].didCompleteStreaming = true
        streamingDelegates[runID] = nil
    }
    
    private func updateIsAnyRunning() {
        isAnyRunning = runs.contains { run in
            if case .running = run.status {
                return true
            }
            return false
        }
    }
}

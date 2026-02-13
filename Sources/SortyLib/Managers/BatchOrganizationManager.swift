//
//  BatchOrganizationManager.swift
//  Sorty
//
//  Manages batch organization of multiple folders
//

import Foundation
import Combine
import SwiftUI

public enum BatchStatus: String, Sendable {
    case pending
    case processing
    case previewed
    case completed
    case failed
    case skipped
}

public enum BatchRunMode: String, Sendable {
    case preview
    case apply
}

public struct BatchResult: Identifiable, Sendable {
    public let id: UUID
    public let folderURL: URL
    public let filesOrganized: Int
    public let status: BatchStatus
    public let error: String?
    public let plan: OrganizationPlan?
    public let historyEntry: OrganizationHistoryEntry?

    public init(
        id: UUID = UUID(),
        folderURL: URL,
        filesOrganized: Int,
        status: BatchStatus,
        error: String? = nil,
        plan: OrganizationPlan? = nil,
        historyEntry: OrganizationHistoryEntry? = nil
    ) {
        self.id = id
        self.folderURL = folderURL
        self.filesOrganized = filesOrganized
        self.status = status
        self.error = error
        self.plan = plan
        self.historyEntry = historyEntry
    }
}

@MainActor
public final class BatchOrganizationManager: ObservableObject {
    @Published public var selectedFolders: [URL] = []
    @Published public var isProcessing: Bool = false
    @Published public var results: [BatchResult] = []
    @Published public var overallProgress: Double = 0.0
    @Published public var maxConcurrentFolders: Int = 3
    @Published public var currentMode: BatchRunMode?

    private var batchTask: Task<Void, Never>?
    private var isCancelled: Bool = false
    private var activeOrganizers: [URL: FolderOrganizer] = [:]
    private var dependencies: BatchDependencies?
    private var aiConfig: AIConfig?
    private var currentBatchFolders: Set<URL> = []
    private var lastBatchEntries: [OrganizationHistoryEntry] = []

    public init() {
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] _ in
            self?.reset()
        }
    }

    public var totalFolders: Int {
        selectedFolders.count
    }

    public var processedFolders: Int {
        let targets = currentBatchFolders.isEmpty ? Set(selectedFolders) : currentBatchFolders
        return results.filter {
            targets.contains($0.folderURL) && ($0.status == .completed || $0.status == .failed || $0.status == .skipped || $0.status == .previewed)
        }.count
    }

    public var activeFolders: [URL] {
        let targets = currentBatchFolders.isEmpty ? Set(selectedFolders) : currentBatchFolders
        return results.filter { targets.contains($0.folderURL) && $0.status == .processing }.map { $0.folderURL }
    }

    public var completedFolders: Int {
        results.filter { $0.status == .completed }.count
    }

    public var failedFolders: Int {
        results.filter { $0.status == .failed }.count
    }

    public var previewedFolders: Int {
        results.filter { $0.status == .previewed }.count
    }

    public var canApplyPreview: Bool {
        results.contains { $0.status == .previewed && $0.plan != nil }
    }

    public var canUndoBatch: Bool {
        !lastBatchEntries.isEmpty
    }

    public var hasAnyOutcome: Bool {
        results.contains { $0.status != .pending }
    }

    public func reset() {
        guard !isProcessing else { return }
        selectedFolders = []
        results = []
        overallProgress = 0.0
        currentMode = nil
        currentBatchFolders = []
        lastBatchEntries = []
        activeOrganizers = [:]
        dependencies = nil
        aiConfig = nil
    }

    public func addFolder(_ url: URL, expandSubfolders: Bool = false) {
        if expandSubfolders {
            addFolders([url] + immediateSubfolders(of: url))
            return
        }
        addFolders([url])
    }

    public func addFolders(_ urls: [URL]) {
        for url in urls {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard !selectedFolders.contains(url) else { continue }
            selectedFolders.append(url)
            results.append(BatchResult(folderURL: url, filesOrganized: 0, status: .pending))
        }
        updateProgress()
    }

    public func removeFolder(_ url: URL) {
        guard !isProcessing else { return }
        selectedFolders.removeAll { $0 == url }
        results.removeAll { $0.folderURL == url }
        currentBatchFolders.remove(url)
        updateProgress()
    }

    public func startPreviewBatch(config: AIConfig, sharedOrganizer: FolderOrganizer) async {
        await startBatchRun(mode: .preview, config: config, sharedOrganizer: sharedOrganizer, folders: selectedFolders)
    }

    public func applyPreviewedBatch(config: AIConfig, sharedOrganizer: FolderOrganizer) async {
        let folders = results.filter { $0.status == .previewed && $0.plan != nil }.map { $0.folderURL }
        await startBatchRun(mode: .apply, config: config, sharedOrganizer: sharedOrganizer, folders: folders)
    }

    public func retryFolder(_ folder: URL) async {
        guard !isProcessing else { return }
        guard selectedFolders.contains(folder) else { return }
        guard aiConfig != nil else {
            updateResult(for: folder, status: .failed, filesOrganized: 0, error: "No AI configuration available. Run a preview first.", plan: nil, historyEntry: nil)
            return
        }

        updateResult(for: folder, status: .pending, filesOrganized: 0, error: nil, plan: nil, historyEntry: nil)
        isProcessing = true
        isCancelled = false
        currentMode = .preview
        currentBatchFolders = [folder]

        batchTask = Task { [weak self] in
            guard let self else { return }
            await self.processFolder(folder, mode: .preview)
            await MainActor.run {
                self.isProcessing = false
                self.batchTask = nil
                self.currentMode = nil
                self.currentBatchFolders = []
                self.overallProgress = 1.0
            }
        }

        await batchTask?.value
    }

    public func undoLastBatch(using organizer: FolderOrganizer) async {
        guard !isProcessing else { return }
        guard !lastBatchEntries.isEmpty else { return }

        isProcessing = true
        isCancelled = false

        let entries = lastBatchEntries.reversed()
        batchTask = Task { [weak self] in
            guard let self else { return }
            for entry in entries {
                if self.isCancelled { break }
                try? await organizer.undoHistoryEntry(entry)
            }

            await MainActor.run {
                self.isProcessing = false
                self.batchTask = nil
                self.lastBatchEntries = []
            }
        }

        await batchTask?.value
    }

    public func cancelBatch() {
        isCancelled = true
        batchTask?.cancel()
        batchTask = nil
        for organizer in activeOrganizers.values {
            organizer.cancel()
        }
        for i in results.indices {
            if results[i].status == .processing {
                results[i] = BatchResult(
                    id: results[i].id,
                    folderURL: results[i].folderURL,
                    filesOrganized: 0,
                    status: .skipped,
                    error: "Cancelled by user",
                    plan: results[i].plan,
                    historyEntry: results[i].historyEntry
                )
            }
        }
        activeOrganizers = [:]
        isProcessing = false
        currentMode = nil
        currentBatchFolders = []
    }

    private func startBatchRun(mode: BatchRunMode, config: AIConfig, sharedOrganizer: FolderOrganizer, folders: [URL]) async {
        guard !folders.isEmpty else { return }

        isProcessing = true
        isCancelled = false
        currentMode = mode
        overallProgress = 0.0
        activeOrganizers = [:]
        dependencies = BatchDependencies(from: sharedOrganizer)
        aiConfig = config
        currentBatchFolders = Set(folders)

        if mode == .preview {
            lastBatchEntries = []
            results = selectedFolders.map { BatchResult(folderURL: $0, filesOrganized: 0, status: .pending) }
        } else {
            lastBatchEntries = []
            for folder in folders {
                updateResult(for: folder, status: .pending, filesOrganized: 0, error: nil, plan: resultPlan(for: folder), historyEntry: nil)
            }
        }

        let semaphore = AsyncSemaphore(value: max(1, maxConcurrentFolders))

        batchTask = Task { [weak self] in
            guard let self else { return }

            await withTaskGroup(of: Void.self) { group in
                for folder in folders {
                    if self.isCancelled { break }
                    await semaphore.acquire()
                    group.addTask { [weak self] in
                        defer { Task { await semaphore.release() } }
                        guard let self else { return }
                        await self.processFolder(folder, mode: mode)
                    }
                }
                await group.waitForAll()
            }

            await MainActor.run {
                self.overallProgress = 1.0
                self.isProcessing = false
                self.batchTask = nil
                self.currentMode = nil
                self.currentBatchFolders = []
            }
        }

        await batchTask?.value
    }

    private func processFolder(_ folder: URL, mode: BatchRunMode) async {
        guard !isCancelled else { return }
        guard let dependencies else { return }
        guard let aiConfig else { return }

        if mode == .apply, resultPlan(for: folder) == nil {
            await MainActor.run {
                self.updateResult(for: folder, status: .failed, filesOrganized: 0, error: "No preview available", plan: nil, historyEntry: nil)
            }
            return
        }

        await MainActor.run {
            self.updateResult(for: folder, status: .processing, filesOrganized: 0, error: nil, plan: self.resultPlan(for: folder), historyEntry: nil)
        }

        do {
            let organizer = try await makeOrganizer(config: aiConfig, dependencies: dependencies)
            await MainActor.run {
                self.activeOrganizers[folder] = organizer
            }

            switch mode {
            case .preview:
                try await organizer.organize(directory: folder)
                if isCancelled { return }

                if organizer.state == .ready, let plan = organizer.currentPlan {
                    let fileCount = plan.suggestions.reduce(0) { $0 + $1.totalFileCount }
                    await MainActor.run {
                        self.updateResult(for: folder, status: .previewed, filesOrganized: fileCount, error: nil, plan: plan, historyEntry: nil)
                    }
                } else if case .error(let error) = organizer.state {
                    await MainActor.run {
                        self.updateResult(for: folder, status: .failed, filesOrganized: 0, error: error.localizedDescription, plan: nil, historyEntry: nil)
                    }
                } else {
                    await MainActor.run {
                        self.updateResult(for: folder, status: .skipped, filesOrganized: 0, error: "No files to organize", plan: nil, historyEntry: nil)
                    }
                }

            case .apply:
                guard let plan = resultPlan(for: folder) else {
                    await MainActor.run {
                        self.updateResult(for: folder, status: .failed, filesOrganized: 0, error: "No preview available", plan: nil, historyEntry: nil)
                    }
                    return
                }

                await MainActor.run {
                    organizer.currentPlan = plan
                }

                try await organizer.apply(at: folder, dryRun: false, enableTagging: aiConfig.enableFileTagging)

                let fileCount = plan.suggestions.reduce(0) { $0 + $1.totalFileCount }
                let historyEntry = organizer.history.entries.first(where: { $0.directoryPath == folder.path })
                await MainActor.run {
                    self.updateResult(for: folder, status: .completed, filesOrganized: fileCount, error: nil, plan: plan, historyEntry: historyEntry)
                    if let entry = historyEntry {
                        self.dependencies?.history?.addEntry(entry)
                        self.lastBatchEntries.append(entry)
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.updateResult(for: folder, status: .failed, filesOrganized: 0, error: error.localizedDescription, plan: nil, historyEntry: nil)
            }
        }

        await MainActor.run {
            self.activeOrganizers[folder] = nil
        }
    }

    private func updateResult(
        for folder: URL,
        status: BatchStatus,
        filesOrganized: Int,
        error: String?,
        plan: OrganizationPlan?,
        historyEntry: OrganizationHistoryEntry?
    ) {
        if let index = results.firstIndex(where: { $0.folderURL == folder }) {
            let existing = results[index]
            results[index] = BatchResult(
                id: existing.id,
                folderURL: folder,
                filesOrganized: filesOrganized,
                status: status,
                error: error,
                plan: plan ?? existing.plan,
                historyEntry: historyEntry ?? existing.historyEntry
            )
        } else {
            results.append(BatchResult(
                folderURL: folder,
                filesOrganized: filesOrganized,
                status: status,
                error: error,
                plan: plan,
                historyEntry: historyEntry
            ))
        }

        updateProgress()
    }

    private func updateProgress() {
        let total = max(1, currentBatchFolders.isEmpty ? totalFolders : currentBatchFolders.count)
        overallProgress = Double(processedFolders) / Double(total)
    }

    private func resultPlan(for folder: URL) -> OrganizationPlan? {
        results.first(where: { $0.folderURL == folder })?.plan
    }

    private func immediateSubfolders(of folder: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func makeOrganizer(config: AIConfig, dependencies: BatchDependencies) async throws -> FolderOrganizer {
        let organizer = FolderOrganizer()
        organizer.exclusionRules = dependencies.exclusionRules
        organizer.personaManager = dependencies.personaManager
        organizer.customPersonaStore = dependencies.customPersonaStore
        organizer.learningsManager = dependencies.learningsManager
        organizer.storageLocationsManager = dependencies.storageLocationsManager
        organizer.automationManager = dependencies.automationManager
        organizer.learningsObserver = dependencies.learningsObserver
        organizer.customInstructions = dependencies.customInstructions
        try await organizer.configure(with: config)
        return organizer
    }
}

private struct BatchDependencies {
    let exclusionRules: ExclusionRulesManager?
    let personaManager: PersonaManager?
    let customPersonaStore: CustomPersonaStore?
    let learningsManager: LearningsManager?
    let storageLocationsManager: StorageLocationsManager?
    let automationManager: AutomationManager?
    let learningsObserver: ContinuousLearningObserver?
    let history: OrganizationHistory?
    let customInstructions: String

    @MainActor init(from organizer: FolderOrganizer) {
        self.exclusionRules = organizer.exclusionRules
        self.personaManager = organizer.personaManager
        self.customPersonaStore = organizer.customPersonaStore
        self.learningsManager = organizer.learningsManager
        self.storageLocationsManager = organizer.storageLocationsManager
        self.automationManager = organizer.automationManager
        self.learningsObserver = organizer.learningsObserver
        self.history = organizer.history
        self.customInstructions = organizer.customInstructions
    }
}

private actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.permits = value
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            permits += 1
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}

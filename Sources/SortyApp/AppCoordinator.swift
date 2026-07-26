//
//  AppCoordinator.swift
//  Sorty
//
//  Coordinates background tasks and watched folder automation
//

@preconcurrency import Foundation
import Combine
import SwiftUI
import UserNotifications
#if canImport(SortyLib)
import SortyLib
#endif

@MainActor
class AppCoordinator: ObservableObject, FolderWatcherDelegate {
    private struct PendingWatchBatch {
        var folder: WatchedFolder
        var files: Set<String>
        var resolvedURL: URL
        var stabilityRetryAttempt: Int
        var operationRetryAttempt: Int
        var nextAttemptAt: Date
    }

    private struct PersistedPendingWatchBatch: Codable {
        var folderID: UUID
        var files: Set<String>
        var stabilityRetryAttempt: Int
        var operationRetryAttempt: Int
        var nextAttemptAt: Date
    }

    let folderWatcher = FolderWatcher()
    let organizer: FolderOrganizer
    let watchedFoldersManager: WatchedFoldersManager
    let learningsManager: LearningsManager
    let continuousLearningObserver: ContinuousLearningObserver
    let learningsFSMonitor: LearningsFSMonitor
    private let notificationManager = NotificationManager.shared
    private var watchedFoldersSubscription: AnyCancellable?
    private var organizerConfigurationSubscription: AnyCancellable?
    private var exclusionMatcherSubscription: AnyCancellable?
    private var pendingFiles: [UUID: PendingWatchBatch] = [:]
    private var activeWatchBatches: [UUID: PendingWatchBatch] = [:]
    private var ignoredWatchEventsUntil: [UUID: Date] = [:]
    private var manualOrganizationFolders: [UUID: WatchedFolder] = [:]
    private var autoOrganizeTasks: [UUID: Task<Void, Never>] = [:]
    private var autoOrganizeTaskIDs: [UUID: UUID] = [:]
    private var retryTask: Task<Void, Never>?
    private let candidateStabilityDelay: TimeInterval = 1.5
    private let retryBaseDelay: TimeInterval = 3
    private let maximumStabilityRetryDelay: TimeInterval = 60
    private let maximumOperationRetryCount = 2
    private let maximumPendingFilesPerFolder = 512
    private let maximumPendingFolderCount = 32
    private lazy var pendingWorkURL: URL? = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sorty", isDirectory: true)
            .appendingPathComponent("WatcherPendingWork.json")
    }()
    nonisolated(unsafe) private var notificationObservers: [NSObjectProtocol] = []
    
    init(
        organizer: FolderOrganizer,
        watchedFoldersManager: WatchedFoldersManager,
        learningsManager: LearningsManager,
        exclusionRules: ExclusionRulesManager
    ) {
        self.organizer = organizer
        self.watchedFoldersManager = watchedFoldersManager
        self.learningsManager = learningsManager
        self.continuousLearningObserver = ContinuousLearningObserver(
            history: organizer.history,
            learningsManager: learningsManager
        )
        self.learningsFSMonitor = LearningsFSMonitor()
        self.folderWatcher.delegate = self
        
        // Inject observer into organizer
        organizer.learningsObserver = self.continuousLearningObserver

        self.folderWatcher.updateExclusionMatcher(exclusionRules.matcherSnapshot())
        self.exclusionMatcherSubscription = exclusionRules.$compiledMatcher
            .dropFirst()
            .sink { [weak self] matcher in
                self?.folderWatcher.updateExclusionMatcher(matcher)
            }

        // Initial sync
        self.folderWatcher.syncWithFolders(watchedFoldersManager.folders)
        self.watchedFoldersSubscription = watchedFoldersManager.$monitoringRevision
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                let folders = self.watchedFoldersManager.folders
                self.folderWatcher.syncWithFolders(folders)
                self.reconcilePendingWork(with: folders)
            }
        restorePendingWatchWork()
        self.organizerConfigurationSubscription = organizer.$isAIConfigured
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.resumePendingWorkAfterConfiguration()
            }
        if organizer.aiClient != nil {
            resumePendingWorkAfterConfiguration()
        }
        
        setupNotifications()
        requestNotificationPermission()
        
        // Start observing
        self.continuousLearningObserver.startObserving()
        
        // Wire up FSMonitor to ContinuousLearningObserver
        self.learningsFSMonitor.onFileMoveDetected = { [weak self] move in
            Task { @MainActor in
                self?.continuousLearningObserver.handleFileMove(from: move.fromPath, to: move.toPath)
            }
        }
        
        self.learningsFSMonitor.onFileRemoved = { [weak self] path in
            Task { @MainActor in
                self?.continuousLearningObserver.handleFileRemoval(at: path)
            }
        }

        self.learningsFSMonitor.onMonitoringWindowExpired = { [weak self] directoryURL in
            Task { @MainActor in
                self?.continuousLearningObserver.handleMonitoringWindowExpired(for: directoryURL.path)
            }
        }
        
    }
    
    deinit {
        retryTask?.cancel()
        autoOrganizeTasks.values.forEach { $0.cancel() }
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
    }
    
    private func setupNotifications() {
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .organizationDidRevert, object: nil, queue: .main) { [weak self] notification in
            guard let self = self,
                  let url = notification.userInfo?["url"] as? URL else { return }
            
            Task {
                guard let folder = await self.watchedFoldersManager.folder(matchingPath: url.path) else {
                    return
                }
                
                // Just reverted, so we must update snapshot to avoid re-triggering
                print("Coordinator: Revert detected for \(folder.name), updating snapshot to ignore reverted files")

                self.folderWatcher.refreshSnapshot(for: folder)
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(forName: .autoOrganizeDisabledGlobally, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let reason = notification.userInfo?["reason"] as? String ?? "Unknown reason"
            
            Task { @MainActor in
                self.notificationManager.showError(message: "Auto-organization paused: \(reason)", isCritical: true)
            }
        })
        
        // Listen for organization completion
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .organizationDidFinish, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            guard let entry = notification.userInfo?["entry"] as? OrganizationHistoryEntry else { return }
            
            Task { @MainActor in
                // If the user manually organized a watched folder, treat that run as
                // the new baseline and ignore the immediate filesystem event burst.
                if entry.source == .manual {
                    let completedPath = URL(fileURLWithPath: entry.directoryPath).standardizedFileURL.path
                    if let watchedFolder = self.watchedFoldersManager.folder(matchingPath: completedPath) {
                        self.pendingFiles.removeValue(forKey: watchedFolder.id)
                        self.persistOutstandingWatchWork()
                        self.ignoredWatchEventsUntil[watchedFolder.id] = Date().addingTimeInterval(2.0)
                        self.folderWatcher.refreshSnapshot(for: watchedFolder)
                    }
                }

                if entry.source != .watchedFolder {
                    let stats = self.extractBatchStats(from: entry)
                    self.notificationManager.showBatchSummary(stats: stats)
                }
                
                // Start FSMonitor for learning from user corrections
                let folderURL = URL(fileURLWithPath: entry.directoryPath)
                self.learningsFSMonitor.startMonitoring(directory: folderURL)
            }
        })
        
        // Handle "Undo" action from notification
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .undoLastOrganization, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String
            
            Task { @MainActor in
                await self.handleUndoAction(folderPath: folderPath)
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(forName: .requestUndoOrganizationConfirmation, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String

            Task { @MainActor in
                await self.handleUndoConfirmationRequest(folderPath: folderPath)
            }
        })
        
        // Handle "Open Folder" action from notification
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .openOrganizedFolder, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String
            
            Task { @MainActor in
                self.handleOpenFolderAction(folderPath: folderPath)
            }
        })
        
        // Handle "Retry" action from notification
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .retryLastOrganization, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String
            
            Task { @MainActor in
                await self.handleRetryAction(folderPath: folderPath)
            }
        })

        notificationObservers.append(NotificationCenter.default.addObserver(forName: .requestRetryOrganizationConfirmation, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String

            Task { @MainActor in
                await self.handleRetryConfirmationRequest(folderPath: folderPath)
            }
        })
        
        // Handle "Show Details" action from notification
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .showOrganizationDetails, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.handleShowDetailsAction()
            }
        })

        // Handle "Review/Preview" action from notification
        notificationObservers.append(NotificationCenter.default.addObserver(forName: .showOrganizationPreview, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.handleShowDetailsAction()
            }
        })
    }
    
    // MARK: - Notification Action Handlers
    
    /// Handle undo action from notification
    private func handleUndoAction(folderPath: String?) async {
        notificationManager.recordActionLifecycle("undo", stage: "executing", detail: folderPath ?? "latest")
        
        // Find the entry to undo
        guard let entryToUndo = findEntryToUndo(folderPath: folderPath) else {
            print("Coordinator: No entry found to undo")
            notificationManager.recordActionLifecycle("undo", stage: "no-op", failed: true, detail: folderPath ?? "latest")
            notificationManager.showError(message: "Nothing to undo", isCritical: false)
            return
        }
        
        guard !entryToUndo.isUndone else {
            print("Coordinator: Entry already undone")
            notificationManager.recordActionLifecycle("undo", stage: "already-undone", failed: true, detail: entryToUndo.directoryPath)
            notificationManager.showError(message: "Already undone", isCritical: false)
            return
        }
        
        print("Coordinator: Undoing organization for \(entryToUndo.directoryPath)")
        
        do {
            let result = try await organizer.undoHistoryEntry(entryToUndo)
            
            let message: String
            if result.hasIssues {
                message = "Undo complete (\(result.successfulOperations) restored, \(result.missingFiles.count) skipped)"
            } else {
                message = "Undo complete - \(result.successfulOperations) files restored"
            }
            
            notificationManager.showInfo(
                title: "Undo Successful",
                message: message
            )
            notificationManager.recordActionLifecycle("undo", stage: "completed", detail: entryToUndo.directoryPath)
            
        } catch {
            print("Coordinator: Undo failed: \(error)")
            notificationManager.recordActionLifecycle("undo", stage: "failed", failed: true, detail: error.localizedDescription)
            notificationManager.showError(message: "Undo failed: \(error.localizedDescription)", isCritical: false)
        }
    }
    
    /// Find the most recent entry to undo, optionally filtered by folder path
    private func findEntryToUndo(folderPath: String?) -> OrganizationHistoryEntry? {
        let entries = organizer.history.entries
        
        if let path = folderPath {
            // Find the most recent non-undone entry for this specific folder
            return entries.first { $0.directoryPath == path && !$0.isUndone && $0.success }
        } else {
            // Find the most recent non-undone entry
            return entries.first { !$0.isUndone && $0.success }
        }
    }
    
    /// Handle open folder action from notification
    private func handleOpenFolderAction(folderPath: String?) {
        // Get folder path from parameter or last history entry
        let path: String?
        if let fp = folderPath {
            path = fp
        } else if let lastEntry = organizer.history.entries.first {
            path = lastEntry.directoryPath
        } else {
            path = nil
        }
        
        guard let path = path else {
            print("Coordinator: No folder path to open")
            return
        }
        
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        print("Coordinator: Opened folder \(path)")
    }
    
    /// Handle retry action from notification
    private func handleRetryAction(folderPath: String?) async {
        notificationManager.recordActionLifecycle("retry", stage: "executing", detail: folderPath ?? "latestFailed")
        // Get folder path from parameter or last failed entry
        let path: String?
        if let fp = folderPath {
            path = fp
        } else if let lastFailedEntry = organizer.history.entries.first(where: { $0.status == .failed }) {
            path = lastFailedEntry.directoryPath
        } else {
            path = nil
        }
        
        guard let path = path else {
            print("Coordinator: No folder path to retry")
            notificationManager.recordActionLifecycle("retry", stage: "no-op", failed: true, detail: "missing folder path")
            notificationManager.showError(message: "No failed operation to retry", isCritical: false)
            return
        }
        
        // Check if we're already busy
        guard organizer.state == .idle else {
            print("Coordinator: Cannot retry - organizer is busy")
            notificationManager.recordActionLifecycle("retry", stage: "busy", failed: true, detail: path)
            notificationManager.showError(message: "Organizer is busy, try again later", isCritical: false)
            return
        }
        
        print("Coordinator: Retrying organization for \(path)")
        
        do {
            let url = URL(fileURLWithPath: path)
            try await organizer.organize(directory: url, customPrompt: nil, temperature: nil)
            try await organizer.apply(at: url, dryRun: false)
            
            notificationManager.showInfo(
                title: "Retry Successful",
                message: "Organization completed for \(url.lastPathComponent)"
            )
            notificationManager.recordActionLifecycle("retry", stage: "completed", detail: path)
            
        } catch {
            print("Coordinator: Retry failed: \(error)")
            notificationManager.recordActionLifecycle("retry", stage: "failed", failed: true, detail: error.localizedDescription)
            notificationManager.showError(message: "Retry failed: \(error.localizedDescription)", isCritical: false)
        }
    }

    private func handleUndoConfirmationRequest(folderPath: String?) async {
        let targetName = notificationFolderName(for: folderPath) ?? "your last organization"
        notificationManager.recordActionLifecycle("undo", stage: "confirmation_shown", detail: targetName)

        let confirmed = presentNotificationConfirmation(
            title: "Undo Organization?",
            message: "Restore the previous organization for \(targetName)?",
            confirmButtonTitle: "Undo"
        )

        if confirmed {
            notificationManager.recordActionLifecycle("undo", stage: "confirmed", detail: targetName)
            await handleUndoAction(folderPath: folderPath)
        } else {
            notificationManager.recordActionLifecycle("undo", stage: "cancelled", detail: targetName)
        }
    }

    private func handleRetryConfirmationRequest(folderPath: String?) async {
        let targetName = notificationFolderName(for: folderPath) ?? "the failed organization"
        notificationManager.recordActionLifecycle("retry", stage: "confirmation_shown", detail: targetName)

        let confirmed = presentNotificationConfirmation(
            title: "Retry Organization?",
            message: "Run Sorty again for \(targetName)?",
            confirmButtonTitle: "Retry"
        )

        if confirmed {
            notificationManager.recordActionLifecycle("retry", stage: "confirmed", detail: targetName)
            await handleRetryAction(folderPath: folderPath)
        } else {
            notificationManager.recordActionLifecycle("retry", stage: "cancelled", detail: targetName)
        }
    }

    private func presentNotificationConfirmation(
        title: String,
        message: String,
        confirmButtonTitle: String
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmButtonTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func notificationFolderName(for folderPath: String?) -> String? {
        guard let folderPath, !folderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: folderPath).lastPathComponent
    }
    
    /// Handle show details action from notifications by activating the app.
    /// The originating notification already carries navigation intent.
    private func handleShowDetailsAction() {
        // Activate the app and bring it to front
        NSApplication.shared.activate(ignoringOtherApps: true)

        print("Coordinator: Activated app for details view")
    }
    
    /// Extract detailed batch statistics from an organization history entry
    private func extractBatchStats(
        from entry: OrganizationHistoryEntry,
        duration: TimeInterval = 0
    ) -> BatchSummaryStats {
        let folderName = URL(fileURLWithPath: entry.directoryPath).lastPathComponent
        let folderPath = entry.directoryPath
        
        // Count operations by type
        var filesMoved = 0
        var filesRenamed = 0
        var filesTagged = 0
        var foldersCreated = 0
        
        if let operations = entry.operations {
            for op in operations {
                switch op.type {
                case .moveFile:
                    filesMoved += 1
                    if op.metadata?.newFilename != nil {
                        filesRenamed += 1
                    }
                case .renameFile:
                    filesRenamed += 1
                case .tagFile:
                    filesTagged += 1
                case .createFolder:
                    foldersCreated += 1
                case .deleteFile, .copyFile:
                    break
                }
            }
        } else {
            // Fallback to entry-level stats if operations not available
            filesMoved = entry.filesOrganized
            foldersCreated = entry.foldersCreated
        }
        
        // Determine errors
        let errors = entry.status == .failed ? 1 : 0
        
        // Check if undo is possible (has operations to undo)
        let canUndo = (entry.operations?.isEmpty == false)
        
        return BatchSummaryStats(
            filesMoved: filesMoved,
            foldersCreated: foldersCreated,
            filesRenamed: filesRenamed,
            filesTagged: filesTagged,
            duplicatesFound: entry.duplicatesDeleted ?? 0,
            errorsEncountered: errors,
            duration: duration,
            folderName: folderName,
            folderPath: folderPath,
            canUndo: canUndo
        )
    }
    
    private func requestNotificationPermission() {
        // Notification authorization is requested lazily when sending native notifications.
    }
    
    func folderWatcher(_ watcher: FolderWatcher, didDetectStaleBookmarkFor folder: WatchedFolder, newBookmarkData: Data) {
        guard var updatedFolder = watchedFoldersManager.folder(withID: folder.id) else {
            return
        }
        updatedFolder.bookmarkData = newBookmarkData
        // Also ensure status is valid
        updatedFolder.accessStatus = .valid
        watchedFoldersManager.updateFolder(updatedFolder)
        print("Coordinator: Updated stale bookmark for \(folder.name)")
    }
    
    @discardableResult
    func folderWatcher(
        _ watcher: FolderWatcher,
        didDetectChangesIn folder: WatchedFolder,
        newFiles: Set<String>,
        resolvedURL: URL
    ) -> Bool {
        // FolderWatcher already resolves nested roots with its path index. Doing
        // that work again here used to scan every watched folder for every file,
        // which made event routing quadratic as either dimension grew.
        let routedFiles = newFiles
        guard !routedFiles.isEmpty else { return true }

        guard !isManualOrganizationActive(for: folder.id) else {
            print("Coordinator: Ignoring watcher changes for \(folder.name) during manual organization")
            return true
        }

        if let ignoreUntil = ignoredWatchEventsUntil[folder.id] {
            if ignoreUntil > Date() {
                print("Coordinator: Ignoring watcher burst for \(folder.name) after manual apply")
                return true
            }
            ignoredWatchEventsUntil.removeValue(forKey: folder.id)
        }
        
        if isOrganizerBusyForAutomation() {
            let existingFileCount = pendingFiles[folder.id]?.files.count ?? 0
            let isNewPendingFolder = pendingFiles[folder.id] == nil
            guard existingFileCount + routedFiles.count <= maximumPendingFilesPerFolder,
                  !isNewPendingFolder || pendingFiles.count < maximumPendingFolderCount else {
                return false
            }

            print("Coordinator: Organizer busy, queueing \(routedFiles.count) files for \(folder.name)")
            mergePendingFiles(folder: folder, files: routedFiles, resolvedURL: resolvedURL)
            scheduleRetry()
            return true
        }
        
        startAutoOrganize(folder: folder, files: routedFiles, resolvedURL: resolvedURL)
        return true
    }

    @discardableResult
    private func startAutoOrganize(
        folder: WatchedFolder,
        files: Set<String>,
        resolvedURL: URL,
        stabilityRetryAttempt: Int = 0,
        operationRetryAttempt: Int = 0
    ) -> Task<Void, Never> {
        if let existingTask = autoOrganizeTasks[folder.id] {
            mergePendingFiles(folder: folder, files: files, resolvedURL: resolvedURL)
            return existingTask
        }

        let taskID = UUID()
        autoOrganizeTaskIDs[folder.id] = taskID
        activeWatchBatches[folder.id] = PendingWatchBatch(
            folder: folder,
            files: files,
            resolvedURL: resolvedURL,
            stabilityRetryAttempt: stabilityRetryAttempt,
            operationRetryAttempt: operationRetryAttempt,
            nextAttemptAt: Date()
        )
        persistOutstandingWatchWork()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.autoOrganize(
                folder: folder,
                files: files,
                resolvedURL: resolvedURL,
                stabilityRetryAttempt: stabilityRetryAttempt,
                operationRetryAttempt: operationRetryAttempt
            )
            if self.autoOrganizeTaskIDs[folder.id] == taskID {
                self.autoOrganizeTasks.removeValue(forKey: folder.id)
                self.autoOrganizeTaskIDs.removeValue(forKey: folder.id)
                self.activeWatchBatches.removeValue(forKey: folder.id)
                self.persistOutstandingWatchWork()
            }
            if !Task.isCancelled, !self.isOrganizerBusyForAutomation(), !self.pendingFiles.isEmpty {
                self.processPendingFiles()
            }
        }
        autoOrganizeTasks[folder.id] = task
        return task
    }
    
    private func autoOrganize(
        folder: WatchedFolder,
        files: Set<String>,
        resolvedURL: URL,
        stabilityRetryAttempt: Int,
        operationRetryAttempt: Int
    ) async {
        guard !isManualOrganizationActive(for: folder.id),
              let currentFolder = watchedFoldersManager.folder(withID: folder.id),
              currentFolder.isEnabled else { return }

        guard organizer.aiClient != nil else {
            print("Coordinator: Cannot auto-organize \(folder.name) - provider not configured")
            mergePendingFiles(
                folder: currentFolder,
                files: files,
                resolvedURL: resolvedURL,
                stabilityRetryAttempt: stabilityRetryAttempt,
                operationRetryAttempt: operationRetryAttempt,
                nextAttemptAt: .distantFuture
            )
            notificationManager.showError(message: "Could not auto-organize \"\(folder.name)\" - no provider configured", isCritical: false)
            return
        }

        let candidateAudit = await Self.auditStableCandidates(
            files: files,
            rootURL: resolvedURL,
            stabilityDelay: candidateStabilityDelay
        )

        guard !Task.isCancelled,
              !isManualOrganizationActive(for: folder.id),
              let executionFolder = watchedFoldersManager.folder(withID: folder.id),
              executionFolder.isEnabled else { return }

        if !candidateAudit.unsettled.isEmpty {
            print("Coordinator: Deferring \(candidateAudit.unsettled.count) unsettled files for \(folder.name)")
            let nextRetryAttempt = stabilityRetryAttempt + 1
            mergePendingFiles(
                folder: executionFolder,
                files: candidateAudit.unsettled,
                resolvedURL: resolvedURL,
                stabilityRetryAttempt: nextRetryAttempt,
                operationRetryAttempt: operationRetryAttempt,
                nextAttemptAt: Date().addingTimeInterval(stabilityRetryDelay(for: nextRetryAttempt))
            )
            scheduleRetry()
        }

        guard !candidateAudit.stable.isEmpty else {
            if !candidateAudit.gone.isEmpty {
                print("Coordinator: Dropping \(candidateAudit.gone.count) vanished files for \(folder.name)")
            }
            return
        }

        guard !isOrganizerStateBusy else {
            mergePendingFiles(
                folder: executionFolder,
                files: candidateAudit.stable,
                resolvedURL: resolvedURL,
                stabilityRetryAttempt: stabilityRetryAttempt,
                operationRetryAttempt: operationRetryAttempt,
                nextAttemptAt: Date().addingTimeInterval(retryBaseDelay)
            )
            scheduleRetry()
            return
        }
        
        let startTime = Date()
        let existingHistoryEntryIDs = Set(organizer.history.entries.map(\.id))
        
        do {
            watchedFoldersManager.markTriggered(executionFolder)
            
            print("Coordinator: Auto-organizing \(candidateAudit.stable.count) stable new files in \(folder.name): \(candidateAudit.stable)")
            
            try await organizer.organizeIncremental(
                directory: resolvedURL,
                specificFiles: Array(candidateAudit.stable),
                customPrompt: executionFolder.customPrompt,
                temperature: executionFolder.temperature,
                providerOverride: executionFolder.providerOverride,
                modelOverride: executionFolder.modelOverride,
                mode: executionFolder.effectiveOrganizationMode,
                historySource: .watchedFolder
            )

            guard !Task.isCancelled, !isManualOrganizationActive(for: folder.id) else {
                organizer.state = .idle
                return
            }

            organizer.state = .idle
            folderWatcher.refreshSnapshot(for: executionFolder)
            
            let duration = Date().timeIntervalSince(startTime)
            print("Coordinator: Auto-organize completed for \(folder.name) in \(String(format: "%.1f", duration))s")
            if let historyEntry = organizer.history.entries.first(where: {
                $0.source == .watchedFolder && !existingHistoryEntryIDs.contains($0.id)
            }) {
                let stats = extractBatchStats(from: historyEntry, duration: duration)
                notificationManager.showBatchSummary(stats: stats, isAutomated: true)
            }
            
        } catch is CancellationError {
            organizer.state = .idle
        } catch {
            print("Coordinator: Auto-organize failed for \(folder.name): \(error)")
            organizer.state = .idle
            folderWatcher.refreshSnapshot(for: executionFolder)

            if operationRetryAttempt < maximumOperationRetryCount {
                let nextRetryAttempt = operationRetryAttempt + 1
                mergePendingFiles(
                    folder: executionFolder,
                    files: candidateAudit.stable,
                    resolvedURL: resolvedURL,
                    stabilityRetryAttempt: stabilityRetryAttempt,
                    operationRetryAttempt: nextRetryAttempt,
                    nextAttemptAt: Date().addingTimeInterval(stabilityRetryDelay(for: nextRetryAttempt))
                )
                scheduleRetry()
            } else {
                mergePendingFiles(
                    folder: executionFolder,
                    files: candidateAudit.stable,
                    resolvedURL: resolvedURL,
                    stabilityRetryAttempt: stabilityRetryAttempt,
                    operationRetryAttempt: operationRetryAttempt,
                    nextAttemptAt: .distantFuture
                )
                notificationManager.showError(
                    message: "Failed to organize \"\(folder.name)\" after retrying: \(error.localizedDescription)",
                    folderPath: resolvedURL.path,
                    isCritical: false,
                    isAutomated: true
                )
            }
        }
    }

    private func mergePendingFiles(
        folder: WatchedFolder,
        files: Set<String>,
        resolvedURL: URL,
        stabilityRetryAttempt: Int = 0,
        operationRetryAttempt: Int = 0,
        nextAttemptAt: Date = Date()
    ) {
        guard !files.isEmpty else { return }

        if var existing = pendingFiles[folder.id] {
            existing.files.formUnion(files)
            existing.folder = folder
            existing.resolvedURL = resolvedURL
            existing.stabilityRetryAttempt = min(existing.stabilityRetryAttempt, stabilityRetryAttempt)
            existing.operationRetryAttempt = min(existing.operationRetryAttempt, operationRetryAttempt)
            existing.nextAttemptAt = min(existing.nextAttemptAt, nextAttemptAt)
            pendingFiles[folder.id] = existing
        } else {
            pendingFiles[folder.id] = PendingWatchBatch(
                folder: folder,
                files: files,
                resolvedURL: resolvedURL,
                stabilityRetryAttempt: stabilityRetryAttempt,
                operationRetryAttempt: operationRetryAttempt,
                nextAttemptAt: nextAttemptAt
            )
        }
        persistOutstandingWatchWork()
    }

    private var isOrganizerStateBusy: Bool {
        switch organizer.state {
        case .scanning, .organizing, .applying:
            return true
        case .idle, .ready, .completed, .error:
            return false
        }
    }

    private func stabilityRetryDelay(for retryAttempt: Int) -> TimeInterval {
        min(retryBaseDelay * pow(2, Double(max(retryAttempt - 1, 0))), maximumStabilityRetryDelay)
    }

    private func reconcilePendingWork(with folders: [WatchedFolder]) {
        let enabledFolders = Dictionary(uniqueKeysWithValues: folders.filter(\.isEnabled).map { ($0.id, $0) })
        var changed = false

        for folderID in Array(pendingFiles.keys) where enabledFolders[folderID] == nil {
            pendingFiles.removeValue(forKey: folderID)
            changed = true
        }

        for (folderID, task) in Array(autoOrganizeTasks) where enabledFolders[folderID] == nil {
            task.cancel()
            autoOrganizeTasks.removeValue(forKey: folderID)
            autoOrganizeTaskIDs.removeValue(forKey: folderID)
            activeWatchBatches.removeValue(forKey: folderID)
            organizer.cancel(source: .watchedFolder)
            changed = true
        }

        for (folderID, folder) in enabledFolders {
            if var pending = pendingFiles[folderID] {
                pending.folder = folder
                pending.resolvedURL = folder.url
                pendingFiles[folderID] = pending
                changed = true
            }
        }

        if changed {
            persistOutstandingWatchWork()
        }
        scheduleRetry()
    }

    private func resumePendingWorkAfterConfiguration() {
        let now = Date()
        for folderID in Array(pendingFiles.keys) {
            pendingFiles[folderID]?.nextAttemptAt = now
            pendingFiles[folderID]?.operationRetryAttempt = 0
        }
        persistOutstandingWatchWork()
        scheduleRetry()
    }

    private func restorePendingWatchWork() {
        guard let pendingWorkURL,
              let data = try? Data(contentsOf: pendingWorkURL),
              let batches = try? JSONDecoder().decode([PersistedPendingWatchBatch].self, from: data) else {
            return
        }

        let enabledFolders = Dictionary(
            uniqueKeysWithValues: watchedFoldersManager.folders.filter(\.isEnabled).map { ($0.id, $0) }
        )
        for batch in batches {
            guard let currentFolder = enabledFolders[batch.folderID] else { continue }
            let restored = PendingWatchBatch(
                folder: currentFolder,
                files: batch.files,
                resolvedURL: currentFolder.url,
                stabilityRetryAttempt: batch.stabilityRetryAttempt,
                operationRetryAttempt: 0,
                nextAttemptAt: Date()
            )
            if var existing = pendingFiles[currentFolder.id] {
                existing.files.formUnion(restored.files)
                existing.stabilityRetryAttempt = min(existing.stabilityRetryAttempt, restored.stabilityRetryAttempt)
                existing.operationRetryAttempt = min(existing.operationRetryAttempt, restored.operationRetryAttempt)
                existing.nextAttemptAt = min(existing.nextAttemptAt, restored.nextAttemptAt)
                pendingFiles[currentFolder.id] = existing
            } else {
                pendingFiles[currentFolder.id] = restored
            }
        }
        persistOutstandingWatchWork()
    }

    private func persistOutstandingWatchWork() {
        guard let pendingWorkURL else { return }

        var outstanding = pendingFiles
        for (folderID, active) in activeWatchBatches {
            if var existing = outstanding[folderID] {
                existing.files.formUnion(active.files)
                existing.stabilityRetryAttempt = min(existing.stabilityRetryAttempt, active.stabilityRetryAttempt)
                existing.operationRetryAttempt = min(existing.operationRetryAttempt, active.operationRetryAttempt)
                existing.nextAttemptAt = min(existing.nextAttemptAt, active.nextAttemptAt)
                outstanding[folderID] = existing
            } else {
                outstanding[folderID] = active
            }
        }

        do {
            if outstanding.isEmpty {
                if FileManager.default.fileExists(atPath: pendingWorkURL.path) {
                    try FileManager.default.removeItem(at: pendingWorkURL)
                }
                return
            }

            try FileManager.default.createDirectory(
                at: pendingWorkURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let persisted = outstanding.map { folderID, batch in
                PersistedPendingWatchBatch(
                    folderID: folderID,
                    files: batch.files,
                    stabilityRetryAttempt: batch.stabilityRetryAttempt,
                    operationRetryAttempt: batch.operationRetryAttempt,
                    nextAttemptAt: batch.nextAttemptAt
                )
            }
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: pendingWorkURL, options: .atomic)
        } catch {
            print("Coordinator: Failed to persist watched-folder pending work: \(error)")
        }
    }

    private struct CandidateAudit: Sendable {
        var stable: Set<String>
        var unsettled: Set<String>
        var gone: Set<String>
    }

    private struct CandidateSnapshot: Equatable, Sendable {
        var exists: Bool
        var isDirectory: Bool
        var fileCount: Int
        var byteSize: Int64
        var latestModification: Date?
        var rootModification: Date?
        var isTruncated: Bool

        static let missing = CandidateSnapshot(
            exists: false,
            isDirectory: false,
            fileCount: 0,
            byteSize: 0,
            latestModification: nil,
            rootModification: nil,
            isTruncated: false
        )
    }

    private nonisolated static func auditStableCandidates(
        files: Set<String>,
        rootURL: URL,
        stabilityDelay: TimeInterval
    ) async -> CandidateAudit {
        let firstSnapshot = await snapshotCandidates(files: files, rootURL: rootURL)
        let delayNanoseconds = UInt64(stabilityDelay * 1_000_000_000)
        do {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        } catch {
            return CandidateAudit(stable: [], unsettled: files, gone: [])
        }
        let secondSnapshot = await snapshotCandidates(files: files, rootURL: rootURL)

        var stable = Set<String>()
        var unsettled = Set<String>()
        var gone = Set<String>()

        for file in files {
            let first = firstSnapshot[file] ?? CandidateSnapshot.missing
            let second = secondSnapshot[file] ?? CandidateSnapshot.missing

            if second.exists, first == second {
                stable.insert(file)
            } else if !first.exists && !second.exists {
                gone.insert(file)
            } else {
                unsettled.insert(file)
            }
        }

        return CandidateAudit(stable: stable, unsettled: unsettled, gone: gone)
    }

    private nonisolated static func snapshotCandidates(
        files: Set<String>,
        rootURL: URL
    ) async -> [String: CandidateSnapshot] {
        await Task.detached(priority: .utility) {
            var snapshots: [String: CandidateSnapshot] = [:]
            snapshots.reserveCapacity(files.count)

            for file in files {
                let url = rootURL.appendingPathComponent(file)
                guard url.standardizedFileURL.path.hasPrefix(rootURL.standardizedFileURL.path + "/") else {
                    snapshots[file] = .missing
                    continue
                }

                snapshots[file] = snapshotCandidate(at: url)
            }

            return snapshots
        }.value
    }

    private nonisolated static func snapshotCandidate(at url: URL) -> CandidateSnapshot {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }

        let rootValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard isDirectory.boolValue else {
            return CandidateSnapshot(
                exists: true,
                isDirectory: false,
                fileCount: 1,
                byteSize: Int64(rootValues?.fileSize ?? 0),
                latestModification: rootValues?.contentModificationDate,
                rootModification: rootValues?.contentModificationDate,
                isTruncated: false
            )
        }

        let maxEntriesToAudit = 5_000
        var fileCount = 0
        var byteSize: Int64 = 0
        var latestModification = rootValues?.contentModificationDate
        var isTruncated = false

        if let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let childURL as URL in enumerator {
                guard fileCount < maxEntriesToAudit else {
                    isTruncated = true
                    break
                }

                guard let values = try? childURL.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
                ), values.isRegularFile == true else {
                    continue
                }

                fileCount += 1
                byteSize += Int64(values.fileSize ?? 0)
                if let modificationDate = values.contentModificationDate,
                   latestModification.map({ modificationDate > $0 }) ?? true {
                    latestModification = modificationDate
                }
            }
        }

        return CandidateSnapshot(
            exists: true,
            isDirectory: true,
            fileCount: fileCount,
            byteSize: byteSize,
            latestModification: latestModification,
            rootModification: rootValues?.contentModificationDate,
            isTruncated: isTruncated
        )
    }
    
    private func processPendingFiles() {
        guard organizer.aiClient != nil, !isOrganizerBusyForAutomation() else {
            scheduleRetry()
            return
        }

        let now = Date()
        guard let (folderID, pending) = pendingFiles
            .filter({ $0.value.nextAttemptAt <= now })
            .min(by: { $0.value.nextAttemptAt < $1.value.nextAttemptAt }) else {
            scheduleRetry()
            return
        }

        pendingFiles.removeValue(forKey: folderID)
        guard !isManualOrganizationActive(for: folderID),
              let currentFolder = watchedFoldersManager.folder(withID: folderID),
              currentFolder.isEnabled else {
            persistOutstandingWatchWork()
            scheduleRetry()
            return
        }

        startAutoOrganize(
            folder: currentFolder,
            files: pending.files,
            resolvedURL: currentFolder.url,
            stabilityRetryAttempt: pending.stabilityRetryAttempt,
            operationRetryAttempt: pending.operationRetryAttempt
        )
    }
    
    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = nil
        guard organizer.aiClient != nil,
              let earliestAttempt = pendingFiles.values.map(\.nextAttemptAt).min(),
              earliestAttempt != .distantFuture else { return }

        let stateDelay = isOrganizerBusyForAutomation() ? retryBaseDelay : 0
        let delay = max(max(earliestAttempt.timeIntervalSinceNow, stateDelay), 0.05)
        let delayNanoseconds = UInt64(delay * 1_000_000_000)
        retryTask = Task {
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            processPendingFiles()
        }
    }

    private func isOrganizerBusyForAutomation() -> Bool {
        if !autoOrganizeTasks.isEmpty {
            return true
        }

        switch organizer.state {
        case .scanning, .organizing, .applying:
            return true
        case .idle, .ready, .completed, .error:
            return false
        }
    }

    func beginManualOrganization(in directory: URL, sessionID: UUID) async {
        guard let folder = watchedFolder(matching: directory), folder.isEnabled else {
            finishManualOrganization(sessionID: sessionID)
            return
        }

        if let existing = manualOrganizationFolders[sessionID], existing.id != folder.id {
            finishManualOrganization(sessionID: sessionID)
        }

        manualOrganizationFolders[sessionID] = folder
        pendingFiles.removeValue(forKey: folder.id)
        activeWatchBatches.removeValue(forKey: folder.id)
        persistOutstandingWatchWork()
        ignoredWatchEventsUntil.removeValue(forKey: folder.id)
        folderWatcher.pause(folder)

        guard let automaticTask = autoOrganizeTasks[folder.id] else { return }

        print("Coordinator: Prioritizing manual organization for \(folder.name)")
        automaticTask.cancel()
        organizer.cancel(source: .watchedFolder)
        await automaticTask.value
    }

    func finishManualOrganization(sessionID: UUID) {
        guard let folder = manualOrganizationFolders.removeValue(forKey: sessionID) else { return }
        guard !isManualOrganizationActive(for: folder.id) else { return }

        pendingFiles.removeValue(forKey: folder.id)
        persistOutstandingWatchWork()
        ignoredWatchEventsUntil[folder.id] = Date().addingTimeInterval(2.0)
        if let currentFolder = watchedFoldersManager.folder(withID: folder.id),
           currentFolder.isEnabled {
            folderWatcher.resume(currentFolder)
            print("Coordinator: Resumed watching \(currentFolder.name) after manual organization")
        }
    }

    private func isManualOrganizationActive(for folderID: UUID) -> Bool {
        manualOrganizationFolders.values.contains { $0.id == folderID }
    }

    private func watchedFolder(matching directory: URL) -> WatchedFolder? {
        let directoryPath = canonicalPath(directory)
        return watchedFoldersManager.folders.first {
            canonicalPath($0.url) == directoryPath
        }
    }

    private func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
    
    func calibrateFolder(_ folder: WatchedFolder) {
        Task {
            defer {
                folderWatcher.refreshSnapshot(for: folder)
            }
            do {
                try await organizer.organize(directory: folder.url, customPrompt: folder.customPrompt, temperature: folder.temperature)
                try await organizer.apply(at: folder.url, dryRun: false)
            } catch {
                // Ignore calibrate failures; caller surface is non-blocking.
            }
        }
    }
    
}

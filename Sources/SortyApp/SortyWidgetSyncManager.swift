import Foundation
import WidgetKit
#if canImport(SortyLib)
import SortyLib
#endif

@MainActor
final class SortyWidgetSyncManager {
    static let shared = SortyWidgetSyncManager()

    private var observers: [NSObjectProtocol] = []
    private var scheduledSyncTask: Task<Void, Never>?
    private var scheduledSyncRequiresReload = false

    private init() {}

    func startIfNeeded(
        watchedFoldersManager: WatchedFoldersManager,
        storageLocationsManager: StorageLocationsManager
    ) {
        guard observers.isEmpty else { return }

        let center = NotificationCenter.default
        let notificationNames: [Notification.Name] = [
            .organizationDidFinish,
            .organizationDidRevert,
            .clearAllUsageData
        ]

        observers = notificationNames.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }

                Task { @MainActor in
                    if name == .clearAllUsageData {
                        await Task.yield()
                    }

                    self.scheduleSync(
                        watchedFoldersManager: watchedFoldersManager,
                        storageLocationsManager: storageLocationsManager,
                        forceReload: name == .clearAllUsageData
                    )
                }
            }
        }

        sync(
            watchedFoldersManager: watchedFoldersManager,
            storageLocationsManager: storageLocationsManager
        )
    }

    func sync(
        watchedFoldersManager: WatchedFoldersManager,
        storageLocationsManager: StorageLocationsManager,
        forceReload: Bool = false
    ) {
        let snapshot = SortyWidgetSnapshotStore.makeSnapshot(
            entries: OrganizationHistory.loadPersistedEntries(),
            watchedFolders: watchedFoldersManager.folders,
            storageLocations: storageLocationsManager.locations,
            activeWatchedFolderCount: watchedFoldersManager.activeFolderCount
        )

        do {
            let persistedSnapshot = SortyWidgetSnapshotStore.load()
            guard !snapshot.hasSameWidgetContent(as: persistedSnapshot) else {
                if forceReload {
                    WidgetCenter.shared.reloadTimelines(ofKind: SortyWidgetSnapshotStore.widgetKind)
                }
                return
            }

            try SortyWidgetSnapshotStore.save(snapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: SortyWidgetSnapshotStore.widgetKind)
        } catch {
            LogManager.shared.log(
                "Failed to sync widget snapshot: \(error.localizedDescription)",
                level: .warning,
                category: "Widgets"
            )
        }
    }

    /// Coalesces bursts from manager publishing and organization notifications so a
    /// single logical update does not repeatedly read history, write disk, and reload WidgetKit.
    func scheduleSync(
        watchedFoldersManager: WatchedFoldersManager,
        storageLocationsManager: StorageLocationsManager,
        forceReload: Bool = false
    ) {
        scheduledSyncRequiresReload = scheduledSyncRequiresReload || forceReload
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { @MainActor [weak self, weak watchedFoldersManager, weak storageLocationsManager] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled,
                  let self,
                  let watchedFoldersManager,
                  let storageLocationsManager else { return }

            let forceReload = self.scheduledSyncRequiresReload
            self.scheduledSyncRequiresReload = false
            self.sync(
                watchedFoldersManager: watchedFoldersManager,
                storageLocationsManager: storageLocationsManager,
                forceReload: forceReload
            )
            self.scheduledSyncTask = nil
        }
    }
}

private extension SortyWidgetSnapshot {
    func hasSameWidgetContent(as other: SortyWidgetSnapshot) -> Bool {
        totalSessions == other.totalSessions
            && totalFilesOrganized == other.totalFilesOrganized
            && successCount == other.successCount
            && failedCount == other.failedCount
            && activeWatchedFolderCount == other.activeWatchedFolderCount
            && enabledStorageLocationCount == other.enabledStorageLocationCount
            && lastRunDate == other.lastRunDate
            && lastRunFolderName == other.lastRunFolderName
            && lastRunFilesOrganized == other.lastRunFilesOrganized
            && lastRunStatus == other.lastRunStatus
    }
}

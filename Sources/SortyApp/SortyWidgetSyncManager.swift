import Foundation
import WidgetKit
#if canImport(SortyLib)
import SortyLib
#endif

@MainActor
final class SortyWidgetSyncManager {
    static let shared = SortyWidgetSyncManager()

    private var observers: [NSObjectProtocol] = []

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

                    self.sync(
                        watchedFoldersManager: watchedFoldersManager,
                        storageLocationsManager: storageLocationsManager
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
        storageLocationsManager: StorageLocationsManager
    ) {
        let snapshot = SortyWidgetSnapshotStore.makeSnapshot(
            entries: OrganizationHistory.loadPersistedEntries(),
            watchedFolders: watchedFoldersManager.folders,
            storageLocations: storageLocationsManager.locations
        )

        do {
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
}

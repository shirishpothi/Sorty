import AppKit
import FinderSync

/// Retained as an inert migration shell for app bundles that still contain the
/// legacy Finder Sync extension. Sorty's global Finder commands now use macOS
/// Quick Actions, which do not require monitoring the filesystem.
final class SortyFinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = []
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        nil
    }
}

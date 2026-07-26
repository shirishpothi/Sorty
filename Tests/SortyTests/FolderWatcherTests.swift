import XCTest
@testable import SortyLib

final class FolderWatcherTests: XCTestCase {
    func testIgnoresICloudAndOneDrivePlaceholderFiles() {
        let iCloudPlaceholder = URL(fileURLWithPath: "/tmp/.Document.pdf.icloud")
        let oneDrivePlaceholder = URL(fileURLWithPath: "/tmp/Document.cloud")

        XCTAssertTrue(FolderWatcher.shouldIgnoreCloudPlaceholder(at: iCloudPlaceholder))
        XCTAssertTrue(FolderWatcher.shouldIgnoreCloudPlaceholder(at: oneDrivePlaceholder))
    }

    func testKeepsGoogleDriveNativeDocumentsActionable() {
        let googleDocument = URL(fileURLWithPath: "/tmp/Planning.gdoc")

        XCTAssertFalse(FolderWatcher.shouldIgnoreCloudPlaceholder(at: googleDocument))
    }

    func testCoalescesNestedMonitoringRootsWithoutCollapsingSiblingPrefixes() {
        let roots = FolderWatcher.minimalMonitoringRoots(from: [
            "/Users/example/Documents",
            "/Users/example/Documents/Projects",
            "/Users/example/Documents/Projects/Sorty",
            "/Users/example/Documents-Archive",
        ])

        XCTAssertEqual(roots, [
            "/Users/example/Documents",
            "/Users/example/Documents-Archive",
        ])
    }

    func testLargeNestedWatchSetUsesOnlyTopLevelMonitoringRoots() {
        let paths = (0..<10_000).map { index in
            "/Volumes/Archive-\(index % 10)/group-\(index % 100)/folder-\(index)"
        }

        let roots = FolderWatcher.coalescedMonitoringRoots(from: paths)

        XCTAssertEqual(roots.count, 10)
        XCTAssertEqual(Set(roots), Set((0..<10).map { "/Volumes/Archive-\($0)" }))
    }

    func testWatcherDoesNotAllocatePerFileMetadataAtRest() {
        let watcher = FolderWatcher()

        XCTAssertEqual(watcher.scaleSnapshot().trackedFileMetadataCount, 0)
    }

    @MainActor
    func testWatchedFolderJournalRoundTripsIndexedConfiguration() {
        let firstManager = WatchedFoldersManager()
        firstManager.clearAll()
        defer { firstManager.clearAll() }

        let folder = WatchedFolder(
            path: "/tmp/Sorty-Watched-Journal",
            isEnabled: true,
            triggerDelay: 2
        )
        firstManager.addFolder(folder)

        let reloadedManager = WatchedFoldersManager()
        XCTAssertEqual(reloadedManager.folder(withID: folder.id)?.path, folder.path)
        XCTAssertEqual(reloadedManager.folder(matchingPath: folder.path)?.id, folder.id)
        XCTAssertEqual(reloadedManager.activeFolderCount, 1)
    }
}

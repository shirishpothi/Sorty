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
}

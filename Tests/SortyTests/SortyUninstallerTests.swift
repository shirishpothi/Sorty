import XCTest
@testable import SortyLib

final class SortyUninstallerTests: XCTestCase {
    private var temporaryHomes: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryHomes {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryHomes.removeAll()
        try super.tearDownWithError()
    }

    func testCleanupPathCandidatesIncludeKnownSortyStateLocations() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        let paths = SortyUninstaller.cleanupPathCandidates(homeDirectory: home).map(\.path)

        XCTAssertTrue(paths.contains("/Users/test/Library/Application Support/Sorty"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Application Support/com.sorty.app"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Caches/com.sorty.app"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Logs/Sorty"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Containers/com.sorty.app"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Group Containers/group.com.sorty.app"))
        XCTAssertTrue(paths.contains("/Users/test/Library/LaunchAgents/com.sorty.app.background-agent.plist"))
        XCTAssertTrue(paths.contains("/Users/test/Library/LaunchAgents/com.sorty.app.plist"))
        XCTAssertTrue(paths.contains("/Users/test/Library/Preferences/com.sorty.app.plist"))
    }

    func testDefaultsRequestKeyIsStableForDocumentation() {
        XCTAssertEqual(SortyUninstaller.requestDefaultsKey, "runUninstallerOnNextLaunch")
    }

    func testFilesystemCleanupRemovesSortyStateUnderHomeDirectory() throws {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory
            .appendingPathComponent("SortyUninstallerTests-\(UUID().uuidString)", isDirectory: true)
        temporaryHomes.append(home)

        let pathsToCreate = [
            "Library/Application Support/Sorty",
            "Library/Application Support/com.sorty.app",
            "Library/Caches/com.sorty.app",
            "Library/Logs/Sorty",
            "Library/Containers/com.sorty.app",
            "Library/Group Containers/group.com.sorty.app",
            "Library/LaunchAgents",
            "Library/Preferences",
        ]

        for relativePath in pathsToCreate {
            try fileManager.createDirectory(
                at: home.appendingPathComponent(relativePath, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        let filesToCreate = [
            "Library/LaunchAgents/com.sorty.app.background-agent.plist",
            "Library/LaunchAgents/com.sorty.app.plist",
            "Library/Preferences/com.sorty.app.plist",
        ]

        for relativePath in filesToCreate {
            fileManager.createFile(
                atPath: home.appendingPathComponent(relativePath).path,
                contents: Data("sorty".utf8)
            )
        }

        let result = SortyUninstaller.removeFilesystemState(
            homeDirectory: home,
            fileManager: fileManager
        )

        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertTrue(result.removed.contains(home.appendingPathComponent("Library/Application Support/Sorty").path))
        XCTAssertTrue(result.removed.contains(home.appendingPathComponent("Library/Preferences/com.sorty.app.plist").path))

        for path in result.removed {
            XCTAssertFalse(fileManager.fileExists(atPath: path), "Expected removed path to be gone: \(path)")
        }
    }
}

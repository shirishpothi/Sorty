import XCTest
@testable import SortyLib

final class CacheMaintenanceTests: XCTestCase {
    private var sandbox: URL!
    private var caches: URL!
    private var appSupport: URL!
    private var temporary: URL!

    override func setUp() async throws {
        let fileManager = FileManager.default
        sandbox = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        caches = sandbox.appendingPathComponent("Caches", isDirectory: true)
        appSupport = sandbox.appendingPathComponent("Application Support", isDirectory: true)
        temporary = sandbox.appendingPathComponent("Temporary", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let sandbox {
            try? FileManager.default.removeItem(at: sandbox)
        }
    }

    func testClearRemovesCacheContentsAndRecreatesRoots() throws {
        let fileManager = FileManager.default
        let bundleIdentifier = "com.sorty.app"
        let directories = CacheMaintenance.cacheDirectories(
            bundleIdentifier: bundleIdentifier,
            cachesDirectory: caches,
            appSupportDirectory: appSupport
        )
        XCTAssertEqual(directories.count, 4)

        for directory in directories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 1024).write(to: directory.appendingPathComponent("cached.bin"))
        }
        let ownedTemporaryFile = temporary.appendingPathComponent("sorty-preview-123.tmp")
        let unrelatedTemporaryFile = temporary.appendingPathComponent("unrelated.txt")
        try Data("temp".utf8).write(to: ownedTemporaryFile)
        try Data("keep".utf8).write(to: unrelatedTemporaryFile)

        let measured = CacheMaintenance.totalSize(
            of: directories,
            temporaryDirectory: temporary
        )
        XCTAssertGreaterThanOrEqual(measured, 4 * 1024)

        let failures = CacheMaintenance.clear(
            bundleIdentifier: bundleIdentifier,
            cachesDirectory: caches,
            appSupportDirectory: appSupport,
            temporaryDirectory: temporary
        )

        XCTAssertTrue(failures.isEmpty)
        for directory in directories {
            XCTAssertTrue(fileManager.fileExists(atPath: directory.path))
            XCTAssertEqual(
                try fileManager.contentsOfDirectory(atPath: directory.path).count,
                0
            )
        }
        XCTAssertFalse(fileManager.fileExists(atPath: ownedTemporaryFile.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedTemporaryFile.path))
        XCTAssertEqual(
            CacheMaintenance.totalSize(of: directories, temporaryDirectory: temporary),
            0
        )
    }
}

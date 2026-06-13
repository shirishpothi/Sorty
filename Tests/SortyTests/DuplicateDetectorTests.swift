
import XCTest
@testable import SortyLib

class DuplicateDetectorTests: XCTestCase {
    
    var detector: DuplicateDetector!
    
    override func setUp() {
        super.setUp()
        detector = DuplicateDetector()
    }
    
    func testDuplicateFinding() async {
        let file1 = FileItem(path: "/path/1", name: "a", extension: "txt", size: 10, isDirectory: false, sha256Hash: "hash1")
        let file2 = FileItem(path: "/path/2", name: "b", extension: "txt", size: 10, isDirectory: false, sha256Hash: "hash1")
        let file3 = FileItem(path: "/path/3", name: "c", extension: "txt", size: 20, isDirectory: false, sha256Hash: "hash2")
        
        let groups = await detector.findDuplicates(in: [file1, file2, file3])
        
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.hash, "hash1")
        XCTAssertEqual(groups.first?.files.count, 2)
        XCTAssertEqual(groups.first?.potentialSavings, 10)
    }
    
    func testSavingsCalculation() async {
        let file1 = FileItem(path: "/path/1", name: "a", extension: "txt", size: 100, isDirectory: false, sha256Hash: "h1")
        let file2 = FileItem(path: "/path/2", name: "b", extension: "txt", size: 100, isDirectory: false, sha256Hash: "h1")
        let file3 = FileItem(path: "/path/3", name: "c", extension: "txt", size: 100, isDirectory: false, sha256Hash: "h1")
        
        let groups = await detector.findDuplicates(in: [file1, file2, file3])
        let totalSavings = await detector.totalPotentialSavings(in: groups)
        
        XCTAssertEqual(totalSavings, 200)
    }

    @MainActor
    func testManagerCompletesEmptyScanWithoutInvalidProgress() async {
        let manager = DuplicateDetectionManager()

        await manager.scanForDuplicates(files: [], settings: DuplicateSettings())

        XCTAssertEqual(manager.state, .completed(count: 0))
        XCTAssertEqual(manager.scanProgress, 1.0)
        XCTAssertFalse(manager.isScanning)
        XCTAssertTrue(manager.duplicateGroups.isEmpty)
        XCTAssertTrue(manager.semanticGroups.isEmpty)
    }

    @MainActor
    func testManagerRequiresMatchingContentEvenWhenFastModeIsSelected() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("DuplicateExactnessTests-\(UUID().uuidString)", isDirectory: true)
        let firstURL = directory.appendingPathComponent("First/report.txt")
        let secondURL = directory.appendingPathComponent("Second/report.txt")

        defer {
            try? fileManager.removeItem(at: directory)
        }

        try fileManager.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: secondURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("ABCD".utf8).write(to: firstURL)
        try Data("WXYZ".utf8).write(to: secondURL)

        let timestamp = Date()
        let files = [
            FileItem(
                path: firstURL.path,
                name: "report",
                extension: "txt",
                size: 4,
                modificationDate: timestamp
            ),
            FileItem(
                path: secondURL.path,
                name: "report",
                extension: "txt",
                size: 4,
                modificationDate: timestamp
            )
        ]
        var settings = DuplicateSettings()
        settings.comparisonMethod = .fast
        settings.includeSemanticDuplicates = false
        let manager = DuplicateDetectionManager()

        await manager.scanForDuplicates(files: files, settings: settings)

        XCTAssertTrue(manager.duplicateGroups.isEmpty)
        XCTAssertEqual(manager.hashCandidateCount, 2)
        XCTAssertEqual(manager.hashedFileCount, 2)
    }

    @MainActor
    func testManagerGroupsAllExactCopiesAndReusesCachedHashes() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("DuplicateGroupingTests-\(UUID().uuidString)", isDirectory: true)
        let exactURLs = [
            directory.appendingPathComponent("original.txt"),
            directory.appendingPathComponent("renamed-copy.txt"),
            directory.appendingPathComponent("Nested/another-name.txt")
        ]
        let uniqueURL = directory.appendingPathComponent("unique.txt")

        defer {
            try? fileManager.removeItem(at: directory)
        }

        for url in exactURLs {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("same-content".utf8).write(to: url)
        }
        try Data("unique".utf8).write(to: uniqueURL)

        let timestamp = Date()
        let files = exactURLs.enumerated().map { index, url in
            FileItem(
                path: url.path,
                name: "file-\(index)",
                extension: "txt",
                size: 12,
                modificationDate: timestamp
            )
        } + [
            FileItem(
                path: uniqueURL.path,
                name: "unique",
                extension: "txt",
                size: 6,
                modificationDate: timestamp
            )
        ]
        var settings = DuplicateSettings()
        settings.includeSemanticDuplicates = false
        let manager = DuplicateDetectionManager()

        await manager.scanForDuplicates(files: files, settings: settings)

        XCTAssertEqual(manager.duplicateGroups.count, 1)
        XCTAssertEqual(manager.duplicateGroups.first?.files.count, 3)
        XCTAssertEqual(manager.hashCandidateCount, 3)
        XCTAssertEqual(manager.hashedFileCount, 3)
        XCTAssertEqual(manager.hashCacheHitCount, 0)

        await manager.scanForDuplicates(files: files, settings: settings)

        XCTAssertEqual(manager.duplicateGroups.first?.files.count, 3)
        XCTAssertEqual(manager.hashedFileCount, 0)
        XCTAssertEqual(manager.hashCacheHitCount, 3)
    }

    @MainActor
    func testManagerPromotesSemanticCandidatesWithIdenticalContentToExactDuplicates() async throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("DuplicatePromotionTests-\(UUID().uuidString)", isDirectory: true)
        let firstURL = directory.appendingPathComponent("proposal-v1.txt")
        let secondURL = directory.appendingPathComponent("proposal-v2.txt")

        defer {
            try? fileManager.removeItem(at: directory)
        }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("same proposal content".utf8).write(to: firstURL)
        try Data("same proposal content".utf8).write(to: secondURL)

        let files = [
            FileItem(
                path: firstURL.path,
                name: "proposal-v1",
                extension: "txt",
                size: 21
            ),
            FileItem(
                path: secondURL.path,
                name: "proposal-v2",
                extension: "txt",
                size: 21
            )
        ]
        var settings = DuplicateSettings()
        settings.includeSemanticDuplicates = true
        let manager = DuplicateDetectionManager()

        await manager.scanForDuplicates(files: files, settings: settings)

        XCTAssertEqual(manager.duplicateGroups.count, 1)
        XCTAssertEqual(manager.duplicateGroups.first?.files.count, 2)
        XCTAssertTrue(manager.semanticGroups.isEmpty)
    }
}


import XCTest
@testable import SortyLib

class WorkspaceHealthQuickActionTests: XCTestCase {
    var healthManager: WorkspaceHealthManager!
    var tempDirectory: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        healthManager = WorkspaceHealthManager()
        
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        healthManager = nil
        super.tearDown()
    }
    
    @MainActor
    func testArchiveOldDownloads() async throws {
        // Setup: Create old files
        let oldFile = tempDirectory.appendingPathComponent("old_download.zip")
        try "content".write(to: oldFile, atomically: true, encoding: .utf8)
        let oldDate = Date().addingTimeInterval(-31 * 86400) // 31 days old
        try FileManager.default.setAttributes([.creationDate: oldDate], ofItemAtPath: oldFile.path)
        
        // Setup: Create new files
        let newFile = tempDirectory.appendingPathComponent("new_download.zip")
        try "content".write(to: newFile, atomically: true, encoding: .utf8)
        
        // Act: Perform action
        // Directly calling the private helper would be hard, so we use the public API
        // First we simulate an opportunity
        let opportunity = CleanupOpportunity(
            type: .downloadClutter,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 100,
            fileCount: 1,
            action: .archiveOldDownloads
        )
        
        try await healthManager.performAction(.archiveOldDownloads, for: opportunity)
        
        // Assert: Old file moved to Archive/YYYY-MM
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        let expectedFolder = tempDirectory.appendingPathComponent("Archive").appendingPathComponent(dateFormatter.string(from: oldDate))
        let expectedPath = expectedFolder.appendingPathComponent("old_download.zip")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path)) // New file should stay
    }
    
    @MainActor
    func testGroupScreenshots() async throws {
        // Setup: Create screenshot files
        let screenshot1 = tempDirectory.appendingPathComponent("Screen Shot 2023-01-01.png")
        try "content".write(to: screenshot1, atomically: true, encoding: .utf8)
        
        let screenshotDate = Date().addingTimeInterval(-100 * 86400)
        try FileManager.default.setAttributes([.creationDate: screenshotDate], ofItemAtPath: screenshot1.path)
        
        let otherFile = tempDirectory.appendingPathComponent("document.txt")
        try "content".write(to: otherFile, atomically: true, encoding: .utf8)
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .screenshotClutter,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 100,
            fileCount: 1,
            action: .groupScreenshots
        )
        
        try await healthManager.performAction(.groupScreenshots, for: opportunity)
        
        // Assert
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        let expectedFolder = tempDirectory.appendingPathComponent("Screenshots").appendingPathComponent(dateFormatter.string(from: screenshotDate))
        let expectedPath = expectedFolder.appendingPathComponent("Screen Shot 2023-01-01.png")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherFile.path))
    }
    
    @MainActor
    func testCleanInstallers() async throws {
        // Setup: Create installers
        let dmg = tempDirectory.appendingPathComponent("app.dmg")
        try "content".write(to: dmg, atomically: true, encoding: .utf8)
        
        let pkg = tempDirectory.appendingPathComponent("installer.pkg")
        try "content".write(to: pkg, atomically: true, encoding: .utf8)
        
        let txt = tempDirectory.appendingPathComponent("readme.txt")
        try "content".write(to: txt, atomically: true, encoding: .utf8)
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .largeFiles,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 100,
            fileCount: 2,
            action: .cleanInstallers
        )
        
        try await healthManager.performAction(.cleanInstallers, for: opportunity)
        
        // Assert: Installers moved to trash (verification complex due to trash), 
        // effectively we check they are GONE from source
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: dmg.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pkg.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: txt.path))
    }
    
    @MainActor
    func testPruneEmptyFolders() async throws {
        // Setup: Nested empty folders
        let empty1 = tempDirectory.appendingPathComponent("Empty1")
        let empty2 = empty1.appendingPathComponent("Empty2")
        try FileManager.default.createDirectory(at: empty2, withIntermediateDirectories: true)
        
        let notEmpty = tempDirectory.appendingPathComponent("NotEmpty")
        try FileManager.default.createDirectory(at: notEmpty, withIntermediateDirectories: true)
        let file = notEmpty.appendingPathComponent("file.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .emptyFolders,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 0,
            fileCount: 2,
            action: .pruneEmptyFolders
        )
        
        try await healthManager.performAction(.pruneEmptyFolders, for: opportunity)
        
        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notEmpty.path))
    }
}

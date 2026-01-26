
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
    
    @MainActor
    func testArchiveVeryOldFiles() async throws {
        // Setup: Create very old files and recent files
        let oldFile1 = tempDirectory.appendingPathComponent("very_old_document.txt")
        try "old content".write(to: oldFile1, atomically: true, encoding: .utf8)
        let veryOldDate = Date().addingTimeInterval(-400 * 86400) // Over 1 year old
        try FileManager.default.setAttributes([.modificationDate: veryOldDate], ofItemAtPath: oldFile1.path)
        
        let oldFile2 = tempDirectory.appendingPathComponent("ancient_file.pdf")
        try "ancient content".write(to: oldFile2, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: veryOldDate], ofItemAtPath: oldFile2.path)
        
        let recentFile = tempDirectory.appendingPathComponent("recent_file.txt")
        try "recent content".write(to: recentFile, atomically: true, encoding: .utf8)
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .veryOldFiles,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 200,
            fileCount: 2,
            action: .archiveVeryOldFiles
        )
        
        try await healthManager.performAction(.archiveVeryOldFiles, for: opportunity)
        
        // Assert: Very old files moved to ~/Documents/Archives
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let documentsFolder = homeDirectory.appendingPathComponent("Documents")
        let archiveFolder = documentsFolder.appendingPathComponent("Archives")
        
        let archivedFile1 = archiveFolder.appendingPathComponent("very_old_document.txt")
        let archivedFile2 = archiveFolder.appendingPathComponent("ancient_file.pdf")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedFile1.path), "Old file should be archived")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedFile2.path), "Old file should be archived")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile1.path), "Old file should be moved from source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile2.path), "Old file should be moved from source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path), "Recent file should remain")
        
        // Cleanup: Remove created archive files
        try? FileManager.default.removeItem(at: archivedFile1)
        try? FileManager.default.removeItem(at: archivedFile2)
    }
    
    @MainActor
    func testPruneEmptyFoldersWithDSStore() async throws {
        // Setup: Create folder with only .DS_Store
        let folderWithDSStore = tempDirectory.appendingPathComponent("FolderWithDSStore")
        try FileManager.default.createDirectory(at: folderWithDSStore, withIntermediateDirectories: true)
        
        let dsStore = folderWithDSStore.appendingPathComponent(".DS_Store")
        try "ds_store_content".write(to: dsStore, atomically: true, encoding: .utf8)
        
        let notEmptyFolder = tempDirectory.appendingPathComponent("NotEmpty")
        try FileManager.default.createDirectory(at: notEmptyFolder, withIntermediateDirectories: true)
        let realFile = notEmptyFolder.appendingPathComponent("real_file.txt")
        try "content".write(to: realFile, atomically: true, encoding: .utf8)
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .emptyFolders,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 0,
            fileCount: 1,
            action: .pruneEmptyFolders
        )
        
        try await healthManager.performAction(.pruneEmptyFolders, for: opportunity)
        
        // Assert: Folder with only .DS_Store should be removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderWithDSStore.path), "Folder with only .DS_Store should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: notEmptyFolder.path), "Folder with real files should remain")
    }
}

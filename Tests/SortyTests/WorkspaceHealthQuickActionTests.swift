import XCTest
@testable import SortyLib

class WorkspaceHealthQuickActionTests: XCTestCase {
    var healthManager: WorkspaceHealthManager!
    var tempDirectory: URL!
    
    @MainActor
    override func setUp() async throws {
        
        healthManager = WorkspaceHealthManager()
        
        // Create a temp directory for testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        self.tempDirectory = tempDir
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        
    }
    
    @MainActor
    func testArchiveOldDownloads() async throws {
        // Setup: Create old downloads
        let downloadsFolder = tempDirectory.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: downloadsFolder, withIntermediateDirectories: true)
        
        let oldFile = downloadsFolder.appendingPathComponent("old_download.dmg")
        try "content".write(to: oldFile, atomically: true, encoding: .utf8)
        
        let now = Date()
        let specificFiles = [
            CleanupOpportunity.AffectedFile(
                path: oldFile.path,
                name: "old_download.dmg",
                size: 7,
                lastAccessed: now,
                reason: "Old installer"
            )
        ]
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .downloadClutter,
            directoryPath: downloadsFolder.path,
            description: "Test",
            estimatedSavings: 100,
            fileCount: 1,
            action: .archiveOldDownloads,
            affectedFiles: specificFiles
        )
        
        try await healthManager.performAction(.archiveOldDownloads, for: opportunity, selectedFiles: specificFiles)
        
        // Assert: Moved to Archive/{year-month} folder
        let archiveFolder = downloadsFolder.appendingPathComponent("Archive")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        let dateFolder = archiveFolder.appendingPathComponent(dateFormatter.string(from: now))
        let archivedFile = dateFolder.appendingPathComponent("old_download.dmg")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
    }
    
    @MainActor
    func testGroupScreenshots() async throws {
        // Setup: Create screenshots
        let desktop = tempDirectory.appendingPathComponent("Desktop")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        
        let sc1 = desktop.appendingPathComponent("Screenshot 2023-01-01.png")
        try "content".write(to: sc1, atomically: true, encoding: .utf8)
        
        let now = Date()
        let specificFiles = [
            CleanupOpportunity.AffectedFile(
                path: sc1.path,
                name: "Screenshot 2023-01-01.png",
                size: 7,
                lastAccessed: now,
                reason: "Screenshot"
            )
        ]
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .screenshotClutter,
            directoryPath: desktop.path,
            description: "Test",
            estimatedSavings: 100,
            fileCount: 1,
            action: .groupScreenshots,
            affectedFiles: specificFiles
        )
        
        try await healthManager.performAction(.groupScreenshots, for: opportunity, selectedFiles: specificFiles)
        
        // Assert: Moved to Screenshots/{year-month} folder
        let screenshotFolder = desktop.appendingPathComponent("Screenshots")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        let dateFolder = screenshotFolder.appendingPathComponent(dateFormatter.string(from: now))
        let archivedFile = dateFolder.appendingPathComponent("Screenshot 2023-01-01.png")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedFile.path))
    }
    
    @MainActor
    func testCleanInstallers() async throws {
        // Setup: Create installers
        let installer = tempDirectory.appendingPathComponent("installer.pkg")
        try "content".write(to: installer, atomically: true, encoding: .utf8)
        
        let specificFiles = [
            CleanupOpportunity.AffectedFile(
                path: installer.path,
                name: "installer.pkg",
                size: 7,
                lastAccessed: Date(),
                reason: "Installer"
            )
        ]
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .largeFiles,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 100,
            fileCount: 1,
            action: .cleanInstallers,
            affectedFiles: specificFiles
        )
        
        try await healthManager.performAction(.cleanInstallers, for: opportunity, selectedFiles: specificFiles)
        
        // Assert: Moved to Trash
        let fileManager = FileManager.default
        let trashURL = fileManager.urls(for: .trashDirectory, in: .userDomainMask).first!
        let archivedFile = trashURL.appendingPathComponent("installer.pkg")
        
        // Note: Trash might contain a file with the same name, or system might rename it.
        // We check if it NO LONGER exists in source at least.
        XCTAssertFalse(fileManager.fileExists(atPath: installer.path))
        
        // Cleanup Trash if we found it (to avoid cluttering user trash)
        if fileManager.fileExists(atPath: archivedFile.path) {
            try? fileManager.removeItem(at: archivedFile)
        }
    }
    
    @MainActor
    func testPruneEmptyFolders() async throws {
        // Setup: Create empty folders
        let empty1 = tempDirectory.appendingPathComponent("Empty1")
        try FileManager.default.createDirectory(at: empty1, withIntermediateDirectories: true)
        
        let empty2 = tempDirectory.appendingPathComponent("Empty2")
        try FileManager.default.createDirectory(at: empty2, withIntermediateDirectories: true)
        
        let notEmpty = tempDirectory.appendingPathComponent("NotEmpty")
        try FileManager.default.createDirectory(at: notEmpty, withIntermediateDirectories: true)
        try "content".write(to: notEmpty.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        
        let specificFiles = [
            CleanupOpportunity.AffectedFile(
                path: empty1.path,
                name: "Empty1",
                size: 0,
                lastAccessed: Date(),
                reason: "Empty folder"
            ),
            CleanupOpportunity.AffectedFile(
                path: empty2.path,
                name: "Empty2",
                size: 0,
                lastAccessed: Date(),
                reason: "Empty folder"
            )
        ]
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .emptyFolders,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 0,
            fileCount: 2,
            action: .pruneEmptyFolders,
            affectedFiles: specificFiles
        )
        
        try await healthManager.performAction(.pruneEmptyFolders, for: opportunity, selectedFiles: specificFiles)
        
        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: empty2.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notEmpty.path))
    }
    
    @MainActor
    func testArchiveVeryOldFiles() async throws {
        // Setup: Create very old files using specificFiles approach (no auto-detection)
        let oldFile1 = tempDirectory.appendingPathComponent("very_old_document.txt")
        try "old content".write(to: oldFile1, atomically: true, encoding: .utf8)
        
        let oldFile2 = tempDirectory.appendingPathComponent("ancient_file.pdf")
        try "ancient content".write(to: oldFile2, atomically: true, encoding: .utf8)
        
        let recentFile = tempDirectory.appendingPathComponent("recent_file.txt")
        try "recent content".write(to: recentFile, atomically: true, encoding: .utf8)
        
        // Create the specificFiles list to archive (bypass auto-detection based on dates)
        let specificFiles = [
            CleanupOpportunity.AffectedFile(
                path: oldFile1.path, 
                name: "very_old_document.txt", 
                size: 11,
                lastAccessed: Date().addingTimeInterval(-400 * 86400),
                reason: "Over 1 year old"
            ),
            CleanupOpportunity.AffectedFile(
                path: oldFile2.path, 
                name: "ancient_file.pdf", 
                size: 15,
                lastAccessed: Date().addingTimeInterval(-400 * 86400),
                reason: "Over 1 year old"
            )
        ]
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .veryOldFiles,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 200,
            fileCount: 2,
            action: .archiveVeryOldFiles,
            affectedFiles: specificFiles
        )
        
        try await healthManager.performAction(.archiveVeryOldFiles, for: opportunity, selectedFiles: specificFiles)
        
        // Assert: Very old files moved to "Old Files Archive" within the source directory
        let archiveFolder = tempDirectory.appendingPathComponent("Old Files Archive")
        
        // Files are organized by year of modification (current year for newly created files)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy"
        let yearFolder = archiveFolder.appendingPathComponent(dateFormatter.string(from: Date()))
        
        let archivedFile1 = yearFolder.appendingPathComponent("very_old_document.txt")
        let archivedFile2 = yearFolder.appendingPathComponent("ancient_file.pdf")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedFile1.path), "Old file should be archived")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedFile2.path), "Old file should be archived")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile1.path), "Old file should be moved from source")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile2.path), "Old file should be moved from source")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recentFile.path), "Recent file should remain")
    }
    
    @MainActor
    func testPruneEmptyFoldersWithDSStore() async throws {
        // Setup: Create folder with only .DS_Store
        let folderWithDSStore = tempDirectory.appendingPathComponent("FolderWithDSStore")
        try FileManager.default.createDirectory(at: folderWithDSStore, withIntermediateDirectories: true)
        
        let dsStore = folderWithDSStore.appendingPathComponent(".DS_Store")
        try "ds_store_content".write(to: dsStore, atomically: true, encoding: .utf8)
        
        let specificFiles = [
            CleanupOpportunity.AffectedFile(
                path: folderWithDSStore.path,
                name: "FolderWithDSStore",
                size: 0,
                lastAccessed: Date(),
                reason: "Empty folder (contains only .DS_Store)"
            )
        ]
        
        // Act
        let opportunity = CleanupOpportunity(
            type: .emptyFolders,
            directoryPath: tempDirectory.path,
            description: "Test",
            estimatedSavings: 0,
            fileCount: 1,
            action: .pruneEmptyFolders,
            affectedFiles: specificFiles
        )
        
        try await healthManager.performAction(.pruneEmptyFolders, for: opportunity, selectedFiles: specificFiles)
        
        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: folderWithDSStore.path))
    }
}

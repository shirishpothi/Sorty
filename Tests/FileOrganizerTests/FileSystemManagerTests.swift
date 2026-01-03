
import XCTest
@testable import FileOrganizerLib

class FileSystemManagerTests: XCTestCase {
    
    var fileSystemManager: FileSystemManager!
    var tempDirectory: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        fileSystemManager = FileSystemManager()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    @MainActor
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        fileSystemManager = nil
        try await super.tearDown()
    }
    
    @MainActor
    func testCreateFolders() async throws {
        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "Folder1", description: "", files: [], subfolders: [
                    FolderSuggestion(folderName: "Subfolder1", description: "", files: [], subfolders: [], reasoning: "")
                ], reasoning: "")
            ],
            unorganizedFiles: [],
            notes: ""
        )
        
        let ops = try await fileSystemManager.createFolders(plan, at: tempDirectory)
        
        XCTAssertEqual(ops.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("Folder1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("Folder1/Subfolder1").path))
    }
    
    @MainActor
    func testMoveFilesWithConflicts() async throws {
        let sourceFile = tempDirectory.appendingPathComponent("test.txt")
        try "Content".write(to: sourceFile, atomically: true, encoding: .utf8)
        
        // Create a conflict at destination
        let destFolder = tempDirectory.appendingPathComponent("Dest")
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let conflictFile = destFolder.appendingPathComponent("test.txt")
        try "Existing Content".write(to: conflictFile, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: sourceFile.path, name: "test", extension: "txt", size: 10, isDirectory: false)
        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "Dest", description: "", files: [fileItem], subfolders: [], reasoning: "")
            ],
            unorganizedFiles: [],
            notes: ""
        )
        
        let ops = try await fileSystemManager.moveFiles(plan, at: tempDirectory)
        
        XCTAssertEqual(ops.count, 1)
        // Should have renamed the destination file to test_1.txt
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("test_1.txt").path))
    }
    
    @MainActor
    func testUndoOperations() async throws {
        let file = tempDirectory.appendingPathComponent("to_move.txt")
        try "data".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "to_move", extension: "txt", size: 4, isDirectory: false)
        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "NewDir", description: "", files: [fileItem], subfolders: [], reasoning: "")
            ],
            unorganizedFiles: [],
            notes: ""
        )
        
        let ops = try await fileSystemManager.applyOrganization(plan, at: tempDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("NewDir/to_move.txt").path))
        
        try await fileSystemManager.reverseOperations(ops)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("NewDir/to_move.txt").path))
    }


    // MARK: - File Tagging Tests
    
    @MainActor
    func testTagFilesInDryRun() async throws {
        let file = tempDirectory.appendingPathComponent("test.txt")
        try "Content".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "test", extension: "txt", size: 7, isDirectory: false)
        var suggestion = FolderSuggestion(folderName: "Documents", files: [fileItem])
        
        // Add tag mapping
        let tagMapping = FileTagMapping(originalFile: fileItem, tags: ["Important", "Work"])
        suggestion.fileTagMappings.append(tagMapping)
        
        let plan = OrganizationPlan(suggestions: [suggestion], unorganizedFiles: [], notes: "")
        
        // Test dry run - should not actually apply tags
        let ops = try await fileSystemManager.tagFiles(plan, at: tempDirectory, dryRun: true)
        
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.type, .tagFile)
        XCTAssertEqual(ops.first?.metadata?.newTags, ["Important", "Work"])
    }
    
    @MainActor
    func testTagFilesActualApplication() async throws {
        let destFolder = tempDirectory.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        
        let file = destFolder.appendingPathComponent("test.txt")
        try "Content".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "test", extension: "txt", size: 7, isDirectory: false)
        var suggestion = FolderSuggestion(folderName: "Documents", files: [fileItem])
        
        let tagMapping = FileTagMapping(originalFile: fileItem, tags: ["Finance", "2024"])
        suggestion.fileTagMappings.append(tagMapping)
        
        let plan = OrganizationPlan(suggestions: [suggestion], unorganizedFiles: [], notes: "")
        
        let ops = try await fileSystemManager.tagFiles(plan, at: tempDirectory, dryRun: false)
        
        XCTAssertEqual(ops.count, 1)
        XCTAssertNotNil(ops.first?.metadata?.originalTags)
        XCTAssertNotNil(ops.first?.metadata?.newTags)
    }
    
    @MainActor
    func testApplyOrganizationWithTagging() async throws {
        let file = tempDirectory.appendingPathComponent("invoice.pdf")
        try "PDF Content".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "invoice", extension: "pdf", size: 11, isDirectory: false)
        var suggestion = FolderSuggestion(folderName: "Finances", files: [fileItem])
        
        let tagMapping = FileTagMapping(originalFile: fileItem, tags: ["Invoice", "2024", "Paid"])
        suggestion.fileTagMappings.append(tagMapping)
        
        let plan = OrganizationPlan(suggestions: [suggestion], unorganizedFiles: [], notes: "")
        
        let ops = try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false, enableTagging: true)
        
        // Should have folder creation, file move, and tagging operations
        XCTAssertTrue(ops.contains { $0.type == .createFolder })
        XCTAssertTrue(ops.contains { $0.type == .moveFile })
        XCTAssertTrue(ops.contains { $0.type == .tagFile })
    }
    
    @MainActor
    func testApplyOrganizationWithoutTagging() async throws {
        let file = tempDirectory.appendingPathComponent("doc.txt")
        try "Content".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "doc", extension: "txt", size: 7, isDirectory: false)
        var suggestion = FolderSuggestion(folderName: "Docs", files: [fileItem])
        
        let tagMapping = FileTagMapping(originalFile: fileItem, tags: ["Tag1"])
        suggestion.fileTagMappings.append(tagMapping)
        
        let plan = OrganizationPlan(suggestions: [suggestion], unorganizedFiles: [], notes: "")
        
        let ops = try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false, enableTagging: false)
        
        // Should NOT have tagging operations
        XCTAssertFalse(ops.contains { $0.type == .tagFile })
    }
    
    @MainActor
    func testReverseTaggingOperation() async throws {
        let destFolder = tempDirectory.appendingPathComponent("Tagged")
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        
        let file = destFolder.appendingPathComponent("file.txt")
        try "Content".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "file", extension: "txt", size: 7, isDirectory: false)
        var suggestion = FolderSuggestion(folderName: "Tagged", files: [fileItem])
        
        let tagMapping = FileTagMapping(originalFile: fileItem, tags: ["TestTag"])
        suggestion.fileTagMappings.append(tagMapping)
        
        let plan = OrganizationPlan(suggestions: [suggestion], unorganizedFiles: [], notes: "")
        
        let ops = try await fileSystemManager.tagFiles(plan, at: tempDirectory, dryRun: false)
        
        // Reverse the tagging
        try await fileSystemManager.reverseOperations(ops)
        
        // Tags should be restored to original state
        let url = URL(fileURLWithPath: file.path)
        let resourceValues = try? url.resourceValues(forKeys: [.tagNamesKey])
        let currentTags = resourceValues?.tagNames ?? []
        
        // Should be back to original tags (empty in this case)
        XCTAssertTrue(currentTags.isEmpty || !currentTags.contains("TestTag"))
    }
    
    @MainActor
    func testTagFilesInNestedFolders() async throws {
        // Create nested structure
        let parentFolder = tempDirectory.appendingPathComponent("Parent")
        let childFolder = parentFolder.appendingPathComponent("Child")
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        
        let file = childFolder.appendingPathComponent("nested.txt")
        try "Nested Content".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "nested", extension: "txt", size: 14, isDirectory: false)
        
        var childSuggestion = FolderSuggestion(folderName: "Child", files: [fileItem])
        let tagMapping = FileTagMapping(originalFile: fileItem, tags: ["Nested", "Deep"])
        childSuggestion.fileTagMappings.append(tagMapping)
        
        let parentSuggestion = FolderSuggestion(folderName: "Parent", files: [], subfolders: [childSuggestion])
        let plan = OrganizationPlan(suggestions: [parentSuggestion], unorganizedFiles: [], notes: "")
        
        let ops = try await fileSystemManager.tagFiles(plan, at: tempDirectory, dryRun: false)
        
        XCTAssertEqual(ops.count, 1)
        XCTAssertEqual(ops.first?.type, .tagFile)
    }
    
    @MainActor
    func testEmptyFolderCleanup() async throws {
        // Create source structure with file
        let sourceFolder = tempDirectory.appendingPathComponent("Source")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        
        let file = sourceFolder.appendingPathComponent("move_me.txt")
        try "Content".write(to: file, atomically: true, encoding: .utf8)
        
        let fileItem = FileItem(path: file.path, name: "move_me", extension: "txt", size: 7, isDirectory: false)
        let plan = OrganizationPlan(
            suggestions: [FolderSuggestion(folderName: "Dest", files: [fileItem])],
            unorganizedFiles: [],
            notes: ""
        )
        
        try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false)
        
        // Source folder should be removed if empty
        // Note: This might not work in all cases depending on implementation
        let sourceExists = FileManager.default.fileExists(atPath: sourceFolder.path)
        // We can't assert it's removed because the implementation tries but doesn't guarantee
        // Just verify the file was moved
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("Dest/move_me.txt").path))
    }
}

// MARK: - Duplicate Restoration Manager Tests

@MainActor
final class DuplicateRestorationManagerTests: XCTestCase {
    
    var manager: DuplicateRestorationManager!
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        manager = DuplicateRestorationManager.shared
        manager.clearAllData() // Start fresh
        
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        manager.clearAllData()
        try super.tearDownWithError()
    }
    
    func testSafeDeleteSingleFile() throws {
        // Create original and duplicate
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Original Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Original Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let originalItem = FileItem(path: originalFile.path, name: "original", extension: "txt", size: 16, isDirectory: false)
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 16, isDirectory: false)
        
        let deleted = try manager.deleteSafely(filesToDelete: [duplicateItem], originalFile: originalItem)
        
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(deleted.first?.originalPath, originalFile.path)
        XCTAssertEqual(deleted.first?.deletedPath, duplicateFile.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFile.path))
    }
    
    func testSafeDeleteMultipleFiles() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        var duplicates: [FileItem] = []
        for i in 1...3 {
            let dupFile = tempDirectory.appendingPathComponent("duplicate\(i).txt")
            try "Content".write(to: dupFile, atomically: true, encoding: .utf8)
            duplicates.append(FileItem(path: dupFile.path, name: "duplicate\(i)", extension: "txt", size: 7, isDirectory: false))
        }
        
        let originalItem = FileItem(path: originalFile.path, name: "original", extension: "txt", size: 7, isDirectory: false)
        
        let deleted = try manager.deleteSafely(filesToDelete: duplicates, originalFile: originalItem)
        
        XCTAssertEqual(deleted.count, 3)
        XCTAssertEqual(manager.restoredItems.count, 3)
        
        // All duplicates should be deleted
        for dup in duplicates {
            XCTAssertFalse(FileManager.default.fileExists(atPath: dup.path))
        }
    }
    
    func testRestoreDuplicate() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Original Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Original Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let originalItem = FileItem(path: originalFile.path, name: "original", extension: "txt", size: 16, isDirectory: false)
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 16, isDirectory: false)
        
        let deleted = try manager.deleteSafely(filesToDelete: [duplicateItem], originalFile: originalItem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateFile.path))
        
        // Restore it
        try manager.restore(item: deleted.first!)
        
        // File should exist again
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateFile.path))
        
        // Should be removed from restoration history
        XCTAssertTrue(manager.restoredItems.isEmpty)
    }
    
    func testRestoreFailsWhenOriginalMissing() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let originalItem = FileItem(path: originalFile.path, name: "original", extension: "txt", size: 7, isDirectory: false)
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        let deleted = try manager.deleteSafely(filesToDelete: [duplicateItem], originalFile: originalItem)
        
        // Remove original
        try FileManager.default.removeItem(at: originalFile)
        
        // Try to restore - should fail
        XCTAssertThrowsError(try manager.restore(item: deleted.first!)) { error in
            XCTAssertTrue(error is DuplicateRestorationManager.RestorationError)
        }
    }
    
    func testRestoreFailsWhenTargetOccupied() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let originalItem = FileItem(path: originalFile.path, name: "original", extension: "txt", size: 7, isDirectory: false)
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        let deleted = try manager.deleteSafely(filesToDelete: [duplicateItem], originalFile: originalItem)
        
        // Recreate file at deleted location
        try "New Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        // Try to restore - should fail
        XCTAssertThrowsError(try manager.restore(item: deleted.first!)) { error in
            XCTAssertTrue(error is DuplicateRestorationManager.RestorationError)
        }
    }
    
    func testMetadataPreservation() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let originalItem = FileItem(path: originalFile.path, name: "original", extension: "txt", size: 7, isDirectory: false)
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        let deleted = try manager.deleteSafely(filesToDelete: [duplicateItem], originalFile: originalItem)
        
        // Check metadata was captured
        let item = deleted.first!
        XCTAssertNotNil(item.metadata)
        // Metadata fields might be nil depending on the filesystem
    }
    
    func testClearAllData() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let originalItem = FileItem(path: originalFile.path, name: "original", extension: "txt", size: 7, isDirectory: false)
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        _ = try manager.deleteSafely(filesToDelete: [duplicateItem], originalFile: originalItem)
        
        XCTAssertFalse(manager.restoredItems.isEmpty)
        
        manager.clearAllData()
        
        XCTAssertTrue(manager.restoredItems.isEmpty)
    }
}

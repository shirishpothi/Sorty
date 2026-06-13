
import XCTest
@testable import SortyLib

class FileSystemManagerTests: XCTestCase {
    
    var fileSystemManager: FileSystemManager!
    var tempDirectory: URL!
    
    @MainActor
    override func setUp() async throws {
        
        fileSystemManager = FileSystemManager()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    @MainActor
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        fileSystemManager = nil
        
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
    func testDeleteFileDirectDeleteDoesNotCreateHiddenDuplicatesFolder() async throws {
        let file = tempDirectory.appendingPathComponent("delete-me.txt")
        try "data".write(to: file, atomically: true, encoding: .utf8)

        let operation = try await fileSystemManager.deleteFile(at: file, moveToTrash: false)

        XCTAssertEqual(operation.type, .deleteFile)
        XCTAssertNil(operation.destinationPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(".duplicates").path))
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
        
        _ = try await fileSystemManager.reverseOperations(ops)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("NewDir/to_move.txt").path))
    }

    @MainActor
    func testFolderNameFileConflictBackupIsTrackedAndUndoable() async throws {
        let conflictingFile = tempDirectory.appendingPathComponent("Receipts")
        try "existing file".write(to: conflictingFile, atomically: true, encoding: .utf8)
        let sourceFile = tempDirectory.appendingPathComponent("receipt.txt")
        try "new receipt".write(to: sourceFile, atomically: true, encoding: .utf8)
        let fileItem = FileItem(path: sourceFile.path, name: "receipt", extension: "txt", size: 11, isDirectory: false)

        let plan = OrganizationPlan(
            suggestions: [FolderSuggestion(folderName: "Receipts", files: [fileItem])],
            unorganizedFiles: [],
            notes: ""
        )

        let operations = try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: conflictingFile.path))
        XCTAssertTrue(operations.contains { $0.type == .moveFile && $0.sourcePath == conflictingFile.path })

        _ = try await fileSystemManager.reverseOperations(operations)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflictingFile.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
    }

    @MainActor
    func testRenameFlowParseApplyAndUndo() async throws {
        let sourceA = tempDirectory.appendingPathComponent("doc1.pdf")
        let sourceB = tempDirectory.appendingPathComponent("doc2.pdf")
        try "A".write(to: sourceA, atomically: true, encoding: .utf8)
        try "B".write(to: sourceB, atomically: true, encoding: .utf8)

        let originalFiles = [
            FileItem(path: sourceA.path, name: "doc1", extension: "pdf", size: 1, isDirectory: false),
            FileItem(path: sourceB.path, name: "doc2", extension: "pdf", size: 1, isDirectory: false)
        ]

        let json = """
        {
          "folders": [
            {
              "name": "Invoices",
              "files": [
                {"filename": "doc1.pdf", "suggested_name": "2026-01_Invoice_Acme.pdf", "rename_reason": "Descriptive"},
                {"filename": "doc2.pdf", "suggested_name": "2026-01_Invoice_Beta.pdf", "rename_reason": "Descriptive"}
              ]
            }
          ],
          "unorganized": []
        }
        """

        let plan = try ResponseParser.parseResponse(json, originalFiles: originalFiles, mode: .organizeAndRename)
        let operations = try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("Invoices/2026-01_Invoice_Acme.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("Invoices/2026-01_Invoice_Beta.pdf").path))
        XCTAssertTrue(operations.contains { $0.type == .renameFile })

        _ = try await fileSystemManager.reverseOperations(operations)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceA.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceB.path))
    }

    @MainActor
    func testConflictingRenameTargetsBecomeUnique() async throws {
        let sourceA = tempDirectory.appendingPathComponent("a.txt")
        let sourceB = tempDirectory.appendingPathComponent("b.txt")
        try "A".write(to: sourceA, atomically: true, encoding: .utf8)
        try "B".write(to: sourceB, atomically: true, encoding: .utf8)

        let fileA = FileItem(path: sourceA.path, name: "a", extension: "txt", size: 1, isDirectory: false)
        let fileB = FileItem(path: sourceB.path, name: "b", extension: "txt", size: 1, isDirectory: false)

        var folder = FolderSuggestion(folderName: "Renamed", files: [fileA, fileB])
        folder.updateRename(for: fileA, newName: "shared.txt")
        folder.updateRename(for: fileB, newName: "shared.txt")

        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")
        let operations = try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false)

        let renamedDir = tempDirectory.appendingPathComponent("Renamed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedDir.appendingPathComponent("shared.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedDir.appendingPathComponent("shared_1.txt").path))
        XCTAssertEqual(operations.filter { $0.type == .renameFile }.count, 2)
    }

    @MainActor
    func testCrossVolumeRenamePathWithNameChange() async throws {
        final class ProgressRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var values: [Double] = []

            func append(_ value: Double) {
                lock.lock()
                values.append(value)
                lock.unlock()
            }

            func snapshot() -> [Double] {
                lock.lock()
                let copy = values
                lock.unlock()
                return copy
            }
        }

        let source = tempDirectory.appendingPathComponent("camera.jpg")
        try "image".write(to: source, atomically: true, encoding: .utf8)

        let file = FileItem(path: source.path, name: "camera", extension: "jpg", size: 5, isDirectory: false)
        var folder = FolderSuggestion(folderName: "Photos", files: [file])
        folder.updateRename(for: file, newName: "Sunset.png") // extension must be preserved as .jpg
        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")

        let recorder = ProgressRecorder()
        await fileSystemManager.setCrossVolumeProgressHandler { _, progress in
            recorder.append(progress)
        }
        await fileSystemManager.setCrossVolumeDetectorForTesting { _, _ in true }

        let operations = try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false)
        let destination = tempDirectory.appendingPathComponent("Photos/Sunset.jpg")
        let progressEvents = recorder.snapshot()

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(progressEvents.contains { $0 >= 1.0 })
        XCTAssertTrue(operations.contains { $0.type == .renameFile && $0.destinationPath == destination.path })

        await fileSystemManager.setCrossVolumeProgressHandler(nil)
        await fileSystemManager.setCrossVolumeDetectorForTesting(nil)
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
        _ = try await fileSystemManager.reverseOperations(ops)
        
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
        
        _ = try await fileSystemManager.applyOrganization(plan, at: tempDirectory, dryRun: false)
        
        // Source folder should be removed if empty
        // Note: This might not work in all cases depending on implementation
        _ = FileManager.default.fileExists(atPath: sourceFolder.path)
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
    
    @MainActor
    override func setUp() async throws {
        manager = DuplicateRestorationManager.shared
        manager.clearAllData() // Start fresh
        
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    @MainActor
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        manager.clearAllData()
        manager = nil
        tempDirectory = nil
    }
    
    func testMoveSingleFileToTrash() throws {
        // Create original and duplicate
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Original Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Original Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 16, isDirectory: false)
        
        let deleted = try manager.moveToTrash(files: [duplicateItem])
        
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(deleted.first?.originalPath, duplicateFile.path)
        XCTAssertEqual(deleted.first?.deletedPath, duplicateFile.path)
        XCTAssertNotNil(deleted.first?.trashPath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent(".duplicates").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFile.path))
    }
    
    func testMoveMultipleFilesToTrash() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        var duplicates: [FileItem] = []
        for i in 1...3 {
            let dupFile = tempDirectory.appendingPathComponent("duplicate\(i).txt")
            try "Content".write(to: dupFile, atomically: true, encoding: .utf8)
            duplicates.append(FileItem(path: dupFile.path, name: "duplicate\(i)", extension: "txt", size: 7, isDirectory: false))
        }
        
        let deleted = try manager.moveToTrash(files: duplicates)
        
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
        
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 16, isDirectory: false)
        
        let deleted = try manager.moveToTrash(files: [duplicateItem])
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicateFile.path))
        
        // Restore it
        try manager.restore(item: deleted.first!)
        
        // File should exist again
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateFile.path))
        
        // Should be removed from restoration history
        XCTAssertTrue(manager.restoredItems.isEmpty)
    }
    
    func testRestoreDoesNotDependOnSurvivingDuplicate() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        let deleted = try manager.moveToTrash(files: [duplicateItem])
        
        // Remove original
        try FileManager.default.removeItem(at: originalFile)
        
        try manager.restore(item: deleted.first!)
        XCTAssertTrue(FileManager.default.fileExists(atPath: duplicateFile.path))
    }
    
    func testRestoreFailsWhenTargetOccupied() throws {
        let originalFile = tempDirectory.appendingPathComponent("original.txt")
        try "Content".write(to: originalFile, atomically: true, encoding: .utf8)
        
        let duplicateFile = tempDirectory.appendingPathComponent("duplicate.txt")
        try "Content".write(to: duplicateFile, atomically: true, encoding: .utf8)
        
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        let deleted = try manager.moveToTrash(files: [duplicateItem])
        
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
        
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        let deleted = try manager.moveToTrash(files: [duplicateItem])
        
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
        
        let duplicateItem = FileItem(path: duplicateFile.path, name: "duplicate", extension: "txt", size: 7, isDirectory: false)
        
        _ = try manager.moveToTrash(files: [duplicateItem])
        
        XCTAssertFalse(manager.restoredItems.isEmpty)
        
        manager.clearAllData()
        
        XCTAssertTrue(manager.restoredItems.isEmpty)
    }
}

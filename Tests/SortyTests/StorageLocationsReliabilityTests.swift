import XCTest
@testable import SortyLib

final class StorageLocationsReliabilityTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    func testValidatorAcceptsTrailingSlashForAllowedStoragePath() throws {
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        let fileURL = sourceDir.appendingPathComponent("notes.txt")
        let contents = "hello".data(using: .utf8)!
        try contents.write(to: fileURL)

        let file = FileItem(
            path: fileURL.path,
            name: "notes",
            extension: "txt",
            size: Int64(contents.count),
            isDirectory: false
        )

        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: storageDir.path + "/", files: [file])
            ],
            unorganizedFiles: [],
            notes: "test"
        )

        XCTAssertNoThrow(
            try FileOrganizationValidator.validate(
                plan,
                at: sourceDir,
                allowedStorageLocations: [StorageLocation(path: storageDir.path)],
                maxTopLevelFolders: 10
            )
        )
    }

    func testValidatorAllowsStorageSubfolderWhenSourceAlreadyInStorage() throws {
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        let storageSubfolder = storageDir.appendingPathComponent("2025", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storageSubfolder, withIntermediateDirectories: true)

        let fileURL = storageDir.appendingPathComponent("receipt.pdf")
        let contents = "data".data(using: .utf8)!
        try contents.write(to: fileURL)

        let file = FileItem(
            path: fileURL.path,
            name: "receipt",
            extension: "pdf",
            size: Int64(contents.count),
            isDirectory: false
        )

        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(
                    folderName: storageDir.path,
                    files: [],
                    subfolders: [
                        FolderSuggestion(folderName: "2025", files: [file])
                    ]
                )
            ],
            unorganizedFiles: [],
            notes: "test"
        )

        XCTAssertNoThrow(
            try FileOrganizationValidator.validate(
                plan,
                at: sourceDir,
                allowedStorageLocations: [StorageLocation(path: storageDir.path)],
                maxTopLevelFolders: 10
            )
        )
    }

    func testValidatorAcceptsAbsoluteStorageSubfolderDestination() throws {
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        let excelSubfolder = storageDir.appendingPathComponent("Excel Sheets", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: excelSubfolder, withIntermediateDirectories: true)

        let fileURL = sourceDir.appendingPathComponent("budget.xlsx")
        let contents = "sheet".data(using: .utf8)!
        try contents.write(to: fileURL)

        let file = FileItem(
            path: fileURL.path,
            name: "budget",
            extension: "xlsx",
            size: Int64(contents.count),
            isDirectory: false
        )

        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: excelSubfolder.path, files: [file])
            ],
            unorganizedFiles: [],
            notes: "test"
        )

        XCTAssertNoThrow(
            try FileOrganizationValidator.validate(
                plan,
                at: sourceDir,
                allowedStorageLocations: [StorageLocation(path: storageDir.path)],
                maxTopLevelFolders: 10
            )
        )
    }

    func testValidatorRejectsMovingDirectoryItemToStorage() throws {
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        let projectDir = sourceDir.appendingPathComponent("Project Alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        let directoryItem = FileItem(
            path: projectDir.path,
            name: "Project Alpha",
            extension: "",
            size: 0,
            isDirectory: true
        )

        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: storageDir.path, files: [directoryItem])
            ],
            unorganizedFiles: [],
            notes: "directory to storage"
        )

        XCTAssertThrowsError(
            try FileOrganizationValidator.validate(
                plan,
                at: sourceDir,
                allowedStorageLocations: [StorageLocation(path: storageDir.path)],
                maxTopLevelFolders: 10
            )
        ) { error in
            guard case ValidationError.directoryMovedToStorage("Project Alpha") = error else {
                XCTFail("Expected directoryMovedToStorage error, got: \(error)")
                return
            }
        }
    }

    func testValidatorRejectsBulkFolderMigrationToStorage() throws {
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        let invoicesDir = sourceDir.appendingPathComponent("Invoices", isDirectory: true)
        try FileManager.default.createDirectory(at: invoicesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        let fileURLs = (1...3).map { index in
            invoicesDir.appendingPathComponent("invoice-\(index).pdf")
        }
        for (index, url) in fileURLs.enumerated() {
            try "invoice-\(index + 1)".write(to: url, atomically: true, encoding: .utf8)
        }

        let files = fileURLs.map { url in
            FileItem(
                path: url.path,
                name: url.deletingPathExtension().lastPathComponent,
                extension: url.pathExtension,
                size: 1,
                isDirectory: false
            )
        }

        let plan = OrganizationPlan(
            suggestions: [FolderSuggestion(folderName: storageDir.path, files: files)],
            unorganizedFiles: [],
            notes: "bulk storage migration"
        )

        XCTAssertThrowsError(
            try FileOrganizationValidator.validate(
                plan,
                at: sourceDir,
                allowedStorageLocations: [StorageLocation(path: storageDir.path)],
                maxTopLevelFolders: 10
            )
        ) { error in
            guard case ValidationError.folderBulkMovedToStorage("Invoices", 3) = error else {
                XCTFail("Expected folderBulkMovedToStorage error, got: \(error)")
                return
            }
        }
    }

    func testValidatorAllowsSelectiveStorageMoveFromSubfolder() throws {
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        let storageDir = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        let receiptsDir = sourceDir.appendingPathComponent("Receipts", isDirectory: true)
        try FileManager.default.createDirectory(at: receiptsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)

        let moveURL = receiptsDir.appendingPathComponent("receipt-jan.pdf")
        let stayURL = receiptsDir.appendingPathComponent("draft-notes.txt")
        try "receipt".write(to: moveURL, atomically: true, encoding: .utf8)
        try "notes".write(to: stayURL, atomically: true, encoding: .utf8)

        let moveFile = FileItem(
            path: moveURL.path,
            name: "receipt-jan",
            extension: "pdf",
            size: 10,
            isDirectory: false
        )
        let stayFile = FileItem(
            path: stayURL.path,
            name: "draft-notes",
            extension: "txt",
            size: 5,
            isDirectory: false
        )

        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: storageDir.path, files: [moveFile]),
                FolderSuggestion(folderName: "LocalNotes", files: [stayFile])
            ],
            unorganizedFiles: [],
            notes: "selective storage"
        )

        XCTAssertNoThrow(
            try FileOrganizationValidator.validate(
                plan,
                at: sourceDir,
                allowedStorageLocations: [StorageLocation(path: storageDir.path)],
                maxTopLevelFolders: 10
            )
        )
    }

    @MainActor
    func testApplyRevalidatesAndRejectsUnapprovedStoragePath() async throws {
        let sourceDir = tempRoot.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let fileURL = sourceDir.appendingPathComponent("todo.txt")
        let contents = "todo".data(using: .utf8)!
        try contents.write(to: fileURL)

        let file = FileItem(
            path: fileURL.path,
            name: "todo",
            extension: "txt",
            size: Int64(contents.count),
            isDirectory: false
        )

        let organizer = FolderOrganizer()
        organizer.currentPlan = OrganizationPlan(
            suggestions: [FolderSuggestion(folderName: "/tmp/not-approved", files: [file])],
            unorganizedFiles: [],
            notes: "invalid storage destination"
        )

        do {
            try await organizer.apply(at: sourceDir, dryRun: true)
            XCTFail("Expected validation failure for unapproved absolute destination")
        } catch let error as ValidationError {
            guard case .invalidStorageLocation = error else {
                XCTFail("Expected invalidStorageLocation error, got: \(error)")
                return
            }
        }
    }

    @MainActor
    func testStoragePromptContextIncludesValidPathList() {
        let manager = StorageLocationsManager()
        manager.clearAll()
        defer { manager.clearAll() }

        let archive = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        let projects = tempRoot.appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)

        manager.addLocation(StorageLocation(path: archive.path, name: "Archive"))
        manager.addLocation(StorageLocation(path: projects.path, name: "Projects"))

        let context = manager.generatePromptContext()
        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("VALID_STORAGE_PATHS") == true)
        XCTAssertTrue(context?.contains(archive.path) == true)
        XCTAssertTrue(context?.contains(projects.path) == true)
    }

    @MainActor
    func testAddLocationFromURLCreatesEntry() throws {
        let manager = StorageLocationsManager()
        manager.clearAll()
        defer { manager.clearAll() }

        let archive = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        XCTAssertNoThrow(try manager.addLocation(url: archive, customName: "Archive"))
        XCTAssertEqual(manager.locations.count, 1)
        XCTAssertEqual(manager.locations.first?.name, "Archive")
        XCTAssertEqual(
            manager.locations.first?.path,
            StorageLocationPathResolver.canonicalPath(archive.path)
        )
        XCTAssertNotNil(manager.locations.first?.bookmarkData)
        XCTAssertEqual(manager.locations.first?.accessStatus, .valid)
    }

    @MainActor
    func testAddingDuplicateLocationThrowsClearError() throws {
        let manager = StorageLocationsManager()
        manager.clearAll()
        defer { manager.clearAll() }

        let archive = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try manager.addLocation(url: archive)

        XCTAssertThrowsError(try manager.addLocation(url: archive)) { error in
            XCTAssertEqual(error as? StorageLocationError, .duplicateLocation)
        }
        XCTAssertEqual(manager.locations.count, 1)
    }

    @MainActor
    func testRepeatedAccessRefreshKeepsLocationValid() throws {
        let manager = StorageLocationsManager()
        manager.clearAll()
        defer { manager.clearAll() }

        let archive = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try manager.addLocation(url: archive)

        manager.refreshAccessStatus()
        manager.refreshAccessStatus()

        XCTAssertEqual(manager.locations.first?.accessStatus, .valid)
        XCTAssertEqual(manager.enabledLocations.count, 1)
    }

    @MainActor
    func testDiscoverAllSubfoldersIncludesMoreThanPromptLimitedSet() throws {
        let manager = StorageLocationsManager()
        manager.clearAll()
        defer { manager.clearAll() }

        let archive = tempRoot.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        for index in 1...20 {
            let folder = archive.appendingPathComponent(String(format: "Folder%02d", index), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        manager.addLocation(StorageLocation(path: archive.path, name: "Archive"))

        let discovered = manager.discoverAllSubfolders()
        let paths = discovered[StorageLocationPathResolver.canonicalPath(archive.path)] ?? []

        XCTAssertTrue(paths.contains(archive.appendingPathComponent("Folder20", isDirectory: true).path))
        XCTAssertGreaterThanOrEqual(paths.count, 20)
    }
}

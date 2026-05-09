
import XCTest
@testable import SortyLib

class HistoryTests: XCTestCase {
    
    var history: OrganizationHistory!
    private var testSuiteName: String!
    private var testDefaults: UserDefaults!
    private var storageDirectory: URL!
    
    @MainActor
    override func setUp() async throws {
        
        testSuiteName = "com.sorty.tests.history.\(name)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        testDefaults.removePersistentDomain(forName: testSuiteName)
        storageDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        history = OrganizationHistory(userDefaults: testDefaults, storageDirectory: storageDirectory)
        history.clearHistory() // Start with clean slate
    }
    
    @MainActor
    override func tearDown() async throws {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        if let storageDirectory {
            try? FileManager.default.removeItem(at: storageDirectory)
        }
        testDefaults = nil
        storageDirectory = nil
        history = nil
        
    }
    
    @MainActor
    func testAddEntry() {
        let entry = OrganizationHistoryEntry(
            directoryPath: "/test/path",
            filesOrganized: 5,
            foldersCreated: 2,
            status: .completed
        )
        
        history.addEntry(entry)
        
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.totalFilesOrganized, 5)
        XCTAssertEqual(history.totalFoldersCreated, 2)
    }
    
    @MainActor
    func testStatsCalculation() {
        let entry1 = OrganizationHistoryEntry(directoryPath: "/p1", filesOrganized: 10, foldersCreated: 3, status: .completed)
        let entry2 = OrganizationHistoryEntry(directoryPath: "/p2", filesOrganized: 5, foldersCreated: 1, status: .completed)
        let entry3 = OrganizationHistoryEntry(directoryPath: "/p3", filesOrganized: 0, foldersCreated: 0, status: .failed)
        
        history.addEntry(entry1)
        history.addEntry(entry2)
        history.addEntry(entry3)
        
        XCTAssertEqual(history.totalFilesOrganized, 15)
        XCTAssertEqual(history.totalFoldersCreated, 4)
        XCTAssertEqual(history.totalSessions, 3)
        XCTAssertEqual(history.failedCount, 1)
        XCTAssertEqual(history.successRate, 2.0/3.0, accuracy: 0.01)
    }
    
    @MainActor
    func testPersistence() async {
        let entry = OrganizationHistoryEntry(directoryPath: "/persist", filesOrganized: 1, foldersCreated: 1)
        history.addEntry(entry)

        let newHistory = OrganizationHistory(userDefaults: testDefaults, storageDirectory: storageDirectory)

        XCTAssertTrue(newHistory.entries.contains(where: { $0.directoryPath == "/persist" }))
    }

    @MainActor
    func testMigratesLegacyUserDefaultsIntoFileStore() throws {
        let legacyEntry = OrganizationHistoryEntry(
            directoryPath: "/legacy",
            filesOrganized: 3,
            foldersCreated: 1,
            status: .completed
        )
        let encoded = try JSONEncoder().encode([legacyEntry])
        testDefaults.set(encoded, forKey: "organizationHistory")

        let migratedHistory = OrganizationHistory(userDefaults: testDefaults, storageDirectory: storageDirectory)

        XCTAssertEqual(migratedHistory.entries.count, 1)
        XCTAssertEqual(migratedHistory.entries.first?.directoryPath, "/legacy")
        XCTAssertNil(testDefaults.data(forKey: "organizationHistory"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(migratedHistory.storageFileURL).path))
    }

    @MainActor
    func testCorruptedPrimaryRecoversLatestSnapshotFromBackup() throws {
        let first = OrganizationHistoryEntry(directoryPath: "/one", filesOrganized: 1, foldersCreated: 1, status: .completed)
        let second = OrganizationHistoryEntry(directoryPath: "/two", filesOrganized: 2, foldersCreated: 1, status: .completed)

        history.addEntry(first)
        history.addEntry(second)

        let primaryURL = try XCTUnwrap(history.storageFileURL)
        let backupURL = try XCTUnwrap(history.backupStorageFileURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        let corruptData = Data("{\"entries\": [".utf8)
        try corruptData.write(to: primaryURL)

        let recoveredHistory = OrganizationHistory(userDefaults: testDefaults, storageDirectory: storageDirectory)

        XCTAssertEqual(recoveredHistory.entries.count, 2)
        XCTAssertEqual(Set(recoveredHistory.entries.map(\.directoryPath)), Set(["/one", "/two"]))

        let recoveredEntries = OrganizationHistory.loadPersistedEntries(
            userDefaults: testDefaults,
            storageDirectory: storageDirectory
        )
        XCTAssertEqual(recoveredEntries.count, 2)
    }

    @MainActor
    func testCancelledEntryWithStoredPlanCanBeAppliedLater() {
        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "Invoices", files: [])
            ]
        )
        let entry = OrganizationHistoryEntry(
            directoryPath: "/planned",
            filesOrganized: 0,
            foldersCreated: 0,
            plan: plan,
            success: false,
            status: .cancelled
        )

        XCTAssertTrue(entry.hasApplicablePlan)
    }

    @MainActor
    func testCompletedEntryWithOperationsIsNotTreatedAsUnappliedPlan() {
        let operation = FileSystemManager.FileOperation(
            type: .createFolder,
            sourcePath: "/planned",
            destinationPath: "/planned/Invoices"
        )
        let entry = OrganizationHistoryEntry(
            directoryPath: "/planned",
            filesOrganized: 1,
            foldersCreated: 1,
            plan: OrganizationPlan(),
            status: .completed,
            operations: [operation]
        )

        XCTAssertFalse(entry.hasApplicablePlan)
    }
}

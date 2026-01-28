
import XCTest
@testable import SortyLib

class HistoryTests: XCTestCase {
    
    var history: OrganizationHistory!
    private var testSuiteName: String!
    private var testDefaults: UserDefaults!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        testSuiteName = "com.sorty.tests.history.\(name)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!
        testDefaults.removePersistentDomain(forName: testSuiteName)
        history = OrganizationHistory(userDefaults: testDefaults)
        history.clearHistory() // Start with clean slate
    }
    
    @MainActor
    override func tearDown() async throws {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        history = nil
        try await super.tearDown()
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

        // Create a new instance using the same isolated UserDefaults suite
        // This is deterministic and doesn't rely on flaky synchronize() calls
        let newHistory = OrganizationHistory(userDefaults: testDefaults)

        XCTAssertTrue(newHistory.entries.contains(where: { $0.directoryPath == "/persist" }))
    }
}

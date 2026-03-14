import XCTest
@testable import SortyLib

final class UserStatsSnapshotTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "com.sorty.tests.user-stats-snapshot"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testLoadReturnsZerosWhenNoHistoryExists() {
        let stats = UserStatsSnapshot.load(userDefaults: defaults)

        XCTAssertEqual(stats.sessions, 0)
        XCTAssertEqual(stats.filesOrganized, 0)
        XCTAssertEqual(stats.successRate, 0)
        XCTAssertEqual(stats.activeDays, 0)
        XCTAssertEqual(stats.successRatePercent, 0)
    }

    func testLoadAggregatesCompletedEntriesAndActiveDays() throws {
        let calendar = Calendar.current
        let dayOne = calendar.startOfDay(for: Date())
        let dayTwo = calendar.date(byAdding: .day, value: -1, to: dayOne)!

        let entries = [
            makeEntry(timestamp: dayOne.addingTimeInterval(60), status: .completed, filesOrganized: 12),
            makeEntry(timestamp: dayOne.addingTimeInterval(3600), status: .failed, filesOrganized: 99),
            makeEntry(timestamp: dayTwo.addingTimeInterval(120), status: .completed, filesOrganized: 8)
        ]

        defaults.set(try JSONEncoder().encode(entries), forKey: "organizationHistory")

        let stats = UserStatsSnapshot.load(userDefaults: defaults)

        XCTAssertEqual(stats.sessions, 3)
        XCTAssertEqual(stats.filesOrganized, 20)
        XCTAssertEqual(stats.successRatePercent, 67)
        XCTAssertEqual(stats.activeDays, 2)
    }

    private func makeEntry(timestamp: Date, status: OrganizationStatus, filesOrganized: Int) -> OrganizationHistoryEntry {
        OrganizationHistoryEntry(
            id: UUID(),
            timestamp: timestamp,
            directoryPath: "/tmp/Test Folder",
            filesOrganized: filesOrganized,
            foldersCreated: 2,
            plan: nil,
            success: status == .completed,
            status: status,
            errorMessage: status == .failed ? "Network error" : nil,
            rawAIResponse: nil,
            operations: nil,
            isUndone: false,
            source: .manual,
            undoRestoredCount: nil,
            undoFailedFiles: nil,
            duplicatesDeleted: nil,
            recoveredSpace: nil,
            restorableItems: nil,
            duplicateCleanupMode: nil
        )
    }
}

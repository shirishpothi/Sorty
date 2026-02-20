import XCTest
@testable import SortyLib

final class FinderIntegrationStatusTests: XCTestCase {
    func testIntegrationCountUsesActiveIntegrationsOnly() {
        let status = ExtensionCommunication.FinderIntegrationStatus(
            quickActionInstalled: true,
            quickWatchActionInstalled: true,
            toolbarAppInstalled: false,
            finderSyncEnabled: true,
            menuBarEnabled: false
        )

        XCTAssertEqual(status.integrationCount, 2)
        XCTAssertEqual(ExtensionCommunication.FinderIntegrationStatus.totalIntegrations, 4)
        XCTAssertEqual(status.overallStatus, "Active")
    }

    func testAsyncIntegrationStatusReturnsWithoutThrowing() async {
        let status = await ExtensionCommunication.getIntegrationStatusAsync()
        XCTAssertGreaterThanOrEqual(status.integrationCount, 0)
        XCTAssertLessThanOrEqual(status.integrationCount, ExtensionCommunication.FinderIntegrationStatus.totalIntegrations)
    }
}

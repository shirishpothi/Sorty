import XCTest
@testable import SortyLib

final class WorkspaceHealthBandTests: XCTestCase {
    @MainActor
    func testHealthScoreBandThresholdsUseTrafficLightMapping() {
        let manager = WorkspaceHealthManager()

        XCTAssertEqual(manager.healthScoreBand(for: 100), .healthy)
        XCTAssertEqual(manager.healthScoreBand(for: 80), .healthy)
        XCTAssertEqual(manager.healthScoreBand(for: 79), .caution)
        XCTAssertEqual(manager.healthScoreBand(for: 60), .caution)
        XCTAssertEqual(manager.healthScoreBand(for: 59), .critical)
        XCTAssertEqual(manager.healthScoreBand(for: 0), .critical)
    }
}

import XCTest
@testable import SortyLib

final class PreviewPlanSelectionTests: XCTestCase {
    @MainActor
    func testHistoricalVersionIsThePlanSelectedForApply() {
        let current = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "current")
        let historical = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "historical")

        let selected = PreviewView.planForApply(
            editablePlan: current,
            history: [historical],
            viewingHistoryIndex: 0
        )

        XCTAssertEqual(selected.notes, "historical")
    }

    @MainActor
    func testCurrentEditableVersionIsSelectedWhenHistoryIsNotVisible() {
        let current = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "current")
        let historical = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "historical")

        let selected = PreviewView.planForApply(
            editablePlan: current,
            history: [historical],
            viewingHistoryIndex: nil
        )

        XCTAssertEqual(selected.notes, "current")
    }
}

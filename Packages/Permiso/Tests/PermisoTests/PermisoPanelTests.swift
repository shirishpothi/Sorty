import XCTest

@testable import Permiso

final class PermisoPanelTests: XCTestCase {
    func testOnlyFlatTCCListsSupportAppDrop() {
        XCTAssertTrue(PermisoPanel.fullDiskAccess.supportsAppDrop)
        XCTAssertFalse(PermisoPanel.automation.supportsAppDrop)
        XCTAssertFalse(PermisoPanel.notifications.supportsAppDrop)
    }

    func testSettingsURLsTargetMatchingPanes() {
        XCTAssertTrue(PermisoPanel.fullDiskAccess.settingsURL.absoluteString.contains("Privacy_AllFiles"))
        XCTAssertTrue(PermisoPanel.automation.settingsURL.absoluteString.contains("Privacy_Automation"))
        XCTAssertTrue(PermisoPanel.notifications.settingsURL.absoluteString.contains("Notifications-Settings"))
    }

    func testGuidanceMatchesSystemInteraction() {
        XCTAssertEqual(
            PermisoPanel.fullDiskAccess.guideInstruction(appName: "Sorty"),
            "Drag Sorty to the list above"
        )
        XCTAssertEqual(
            PermisoPanel.automation.guideInstruction(appName: "Sorty"),
            "Find Sorty, then turn on Finder"
        )
        XCTAssertEqual(
            PermisoPanel.notifications.guideInstruction(appName: "Sorty"),
            "Turn on Allow notifications for Sorty"
        )
    }
}

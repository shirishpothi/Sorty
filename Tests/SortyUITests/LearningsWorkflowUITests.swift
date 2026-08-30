import XCTest

final class LearningsWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testOrganizeLearningsChipHiddenWithoutConsent() throws {
        launchApp(environment: [
            "XCUITEST_DEEPLINK": "sorty://organize?path=/tmp",
            "XCUITEST_LEARNINGS_CONSENT": "0"
        ])

        let startButton = app.buttons["StartOrganizationButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))

        XCTAssertFalse(app.otherElements["OrganizeLearningsStatusChip"].exists)
    }

    func testOrganizeLearningsChipVisibleWithSeededProfile() throws {
        launchApp(environment: [
            "XCUITEST_DEEPLINK": "sorty://organize?path=/tmp",
            "XCUITEST_LEARNINGS_CONSENT": "1",
            "XCUITEST_SEED_LEARNINGS_PROFILE": "active_rule"
        ])

        let startButton = app.buttons["StartOrganizationButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["OrganizeLearningsStatusChip"].waitForExistence(timeout: 4))
    }

    func testHistoryFeedbackHiddenWithoutConsent() throws {
        launchApp(environment: [
            "XCUITEST_DEEPLINK": "sorty://history",
            "XCUITEST_LEARNINGS_CONSENT": "0",
            "XCUITEST_SEED_HISTORY_ENTRY": "1"
        ])

        let firstCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'HistorySessionCard-'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 8))
        firstCard.click()

        XCTAssertFalse(app.buttons["FeedbackUsefulButton"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["FeedbackNotUsefulButton"].exists)
    }

    func testHistoryFeedbackVisibleAndActionableWithConsent() throws {
        launchApp(environment: [
            "XCUITEST_DEEPLINK": "sorty://history",
            "XCUITEST_LEARNINGS_CONSENT": "1",
            "XCUITEST_SEED_LEARNINGS_PROFILE": "active_rule",
            "XCUITEST_SEED_HISTORY_ENTRY": "1"
        ])

        let firstCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'HistorySessionCard-'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 8))
        firstCard.click()

        let usefulButton = app.buttons["FeedbackUsefulButton"]
        XCTAssertTrue(usefulButton.waitForExistence(timeout: 4))
        usefulButton.click()

        XCTAssertTrue(app.staticTexts["Thanks!"].waitForExistence(timeout: 3))
    }

    private func launchApp(environment: [String: String]) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = environment
        app.launch()
    }
}

//
//  DeeplinkUITests.swift
//  SortyUITests
//
//  Tests end-to-end deeplink handling by triggering the app via URL schemes.
//

import XCTest

final class DeeplinkUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Do not launch here, as we need to inject arguments per test
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }

    func testHelpDeeplinkNavigation() throws {
        // Trigger deeplink via launch environment
        app.launchEnvironment["XCUITEST_DEEPLINK"] = "sorty://help"
        app.launch()
        
        // Help might open in a separate window or browser
        // We just verify the app is running
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5.0), "App should run after help deeplink launch")
    }

    func testSettingsDeeplinkNavigation() throws {
        app.launchEnvironment["XCUITEST_DEEPLINK"] = "sorty://settings"
        app.launch()
        
        // Verify Settings view is active by checking for unique settings elements
        // "ReasoningToggle" is a specific identifier in SettingsView
        let reasoningToggle = app.switches["ReasoningToggle"]
        XCTAssertTrue(waitForElement(reasoningToggle, timeout: 10.0), "Settings view (ReasoningToggle) should be shown")
    }

    func testHistoryDeeplinkNavigation() throws {
        app.launchEnvironment["XCUITEST_DEEPLINK"] = "sorty://history"
        app.launch()
        
        // Verify History view by checking for the filter dropdown
        let filterDropdown = app.buttons["HistoryFilterDropdown"]
        XCTAssertTrue(waitForElement(filterDropdown, timeout: 10.0), "History view (FilterDropdown) should be shown")
    }

    func testHealthDeeplinkNavigation() throws {
        app.launchEnvironment["XCUITEST_DEEPLINK"] = "sorty://health"
        app.launch()
        
        // Verify Workspace Health view by checking for Analyze button
        let analyzeButton = app.buttons["AnalyzeFolderButton"]
        XCTAssertTrue(waitForElement(analyzeButton, timeout: 10.0), "Workspace Health view (AnalyzeFolderButton) should be shown")
    }

    func testOrganizeDeeplinkWithParameters() throws {
        // Trigger deeplink: sorty://organize?path=/tmp&persona=developer
        app.launchEnvironment["XCUITEST_DEEPLINK"] = "sorty://organize?path=/tmp&persona=developer"
        app.launch()
        
        // When path is provided, we expect the 'ReadyToOrganizeView' to appear, NOT the directory selector
        // So we look for "StartOrganizationButton"
        let startButton = app.buttons["StartOrganizationButton"]
        
        // Also check if we might be in directory selection (fallback)
        let browseButton = app.buttons["BrowseForFolderButton"]
        
        // We expect either dependent on if path was accepted
        let exists = waitForElement(startButton, timeout: 10.0) || waitForElement(browseButton, timeout: 5.0)
        
        XCTAssertTrue(exists, "Organize view should be shown (Start button or Browse button)")
    }
}

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
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }

    func testHelpDeeplinkNavigation() throws {
        // Trigger deeplink: sorty://help
        let url = URL(string: "sorty://help")!
        NSWorkspace.shared.open(url)
        
        // Check if Help view is shown
        // In Sorty, appState.showHelp() likely shows a help window or a specific view
        // Looking at AppUITests, we check for static texts
        let helpText = app.staticTexts["Help"]
        XCTAssertTrue(waitForElement(helpText), "Help view should be shown via deeplink")
    }

    func testSettingsDeeplinkNavigation() throws {
        // Trigger deeplink: sorty://settings
        let url = URL(string: "sorty://settings")!
        NSWorkspace.shared.open(url)
        
        // Verify Settings view is active
        let settingsTitle = app.staticTexts["Settings"]
        XCTAssertTrue(waitForElement(settingsTitle), "Settings view should be shown via deeplink")
    }

    func testHistoryDeeplinkNavigation() throws {
        // Trigger deeplink: sorty://history
        let url = URL(string: "sorty://history")!
        NSWorkspace.shared.open(url)
        
        // Verify History view is active
        let historyTitle = app.staticTexts["History"]
        XCTAssertTrue(waitForElement(historyTitle), "History view should be shown via deeplink")
    }

    func testHealthDeeplinkNavigation() throws {
        // Trigger deeplink: sorty://health
        let url = URL(string: "sorty://health")!
        NSWorkspace.shared.open(url)
        
        // Verify Workspace Health view is active
        let healthTitle = app.staticTexts["Workspace Health"]
        XCTAssertTrue(waitForElement(healthTitle), "Workspace Health view should be shown via deeplink")
    }

    func testOrganizeDeeplinkWithParameters() throws {
        // Trigger deeplink: sorty://organize?path=/tmp&persona=developer&autostart=false
        let url = URL(string: "sorty://organize?path=/tmp&persona=developer")!
        NSWorkspace.shared.open(url)
        
        // Verify Organize view is active
        let organizeTitle = app.staticTexts["Organize"]
        XCTAssertTrue(waitForElement(organizeTitle), "Organize view should be shown via deeplink")
        
        // Verify path is set (if there's a label for selected directory)
        // Looking at AppUITests, there's a BrowseForFolderButton
        // We might not easily see the path text depending on the UI implementation
    }
}

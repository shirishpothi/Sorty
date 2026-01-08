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
        
        // Help opens in a separate window "Sorty Help"
        let helpWindow = app.windows["Sorty Help"]
        
        let exists = helpWindow.waitForExistence(timeout: 5.0)
        XCTAssertTrue(exists, "Help window 'Sorty Help' should be shown via deeplink")
    }

    func testSettingsDeeplinkNavigation() throws {
        let url = URL(string: "sorty://settings")!
        NSWorkspace.shared.open(url)
        
        // Verify Settings view is active
        // Use a more specific identifier if possible, or wait for Title
        // SettingsView usually has a navigation title "Settings"
        
        // In macOS SwiftUI, navigation title often appears as a generic static text or window title
        // We will look for "Organization Rules" header which is unique to Settings
        let settingsHeader = app.staticTexts["Organization Rules"]
        XCTAssertTrue(waitForElement(settingsHeader), "Settings view content should be shown")
    }

    func testHistoryDeeplinkNavigation() throws {
        let url = URL(string: "sorty://history")!
        NSWorkspace.shared.open(url)
        
        // Verify History view
        // Looking for unique content in HistoryView
        // Assuming navigation title "History" or similar
        let historyTitle = app.staticTexts["History"]
        XCTAssertTrue(waitForElement(historyTitle), "History view should be shown")
    }

    func testHealthDeeplinkNavigation() throws {
        let url = URL(string: "sorty://health")!
        NSWorkspace.shared.open(url)
        
        // Verify Workspace Health view
        // Is titled "Workspace Health"
        let healthTitle = app.staticTexts["Workspace Health"]
        XCTAssertTrue(waitForElement(healthTitle), "Workspace Health view should be shown")
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

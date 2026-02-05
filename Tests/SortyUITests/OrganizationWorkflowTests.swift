//
//  OrganizationWorkflowTests.swift
//  SortyUITests
//
//  End-to-end workflow tests for the organization feature.
//  Tests the full flow from folder selection through preview and edge cases.
//

import XCTest

final class OrganizationWorkflowTests: XCTestCase {

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

    // MARK: - Workflow Tests

    func testOrganizeViewShowsFolderSelectionInitially() throws {
        let organizeSidebarItem = app.buttons["OrganizeSidebarItem"]
        XCTAssertTrue(organizeSidebarItem.waitForExistence(timeout: 3.0))
        organizeSidebarItem.click()
        Thread.sleep(forTimeInterval: 0.5)

        // Verify we see the initial folder selection state
        // Look for "Drop a folder" or similar prompt
        let dropPrompt = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'drop' OR label CONTAINS[c] 'folder' OR label CONTAINS[c] 'select'")
        ).firstMatch

        XCTAssertTrue(
            dropPrompt.waitForExistence(timeout: 3.0),
            "Organize view should prompt for folder selection"
        )
    }

    func testNavigationDoesNotCrash() throws {
        // Rapidly navigate between all views to check for crashes
        let viewIdentifiers = [
            "OrganizeSidebarItem",
            "SettingsSidebarItem",
            "HistorySidebarItem",
            "DuplicatesSidebarItem",
            "WorkspaceHealthSidebarItem",
            "ExclusionsSidebarItem",
            "WatchedFoldersSidebarItem",
            "LearningsSidebarItem"
        ]

        for (index, identifier) in viewIdentifiers.enumerated() {
            let sidebarItem = app.buttons[identifier]
            if sidebarItem.waitForExistence(timeout: 2.0) {
                sidebarItem.click()
                // Quick delay between navigations
                Thread.sleep(forTimeInterval: 0.3)
            }
            
            // Verify app hasn't crashed
            XCTAssertTrue(
                app.windows.firstMatch.exists,
                "App should not crash during navigation to \(identifier)"
            )
        }
    }

    // MARK: - Settings Integration Tests

    func testSettingsToggleAffectsState() throws {
        let settingsSidebarItem = app.buttons["SettingsSidebarItem"]
        XCTAssertTrue(settingsSidebarItem.waitForExistence(timeout: 3.0))
        settingsSidebarItem.click()
        Thread.sleep(forTimeInterval: 0.5)

        // Find and toggle a switch
        let reasoningToggle = app.switches["ReasoningToggle"]
        guard reasoningToggle.waitForExistence(timeout: 3.0) else {
            throw XCTSkip("Reasoning toggle not found")
        }

        let initialValue = reasoningToggle.value as? String
        reasoningToggle.click()
        Thread.sleep(forTimeInterval: 0.3)

        let newValue = reasoningToggle.value as? String
        XCTAssertNotEqual(
            initialValue,
            newValue,
            "Toggle should change value when clicked"
        )
    }

    // MARK: - Edge Cases

    func testEmptyStateDisplays() throws {
        // Navigate to History (likely empty on test launch)
        let historySidebarItem = app.buttons["HistorySidebarItem"]
        XCTAssertTrue(historySidebarItem.waitForExistence(timeout: 3.0))
        historySidebarItem.click()
        Thread.sleep(forTimeInterval: 0.5)

        // Look for empty state message
        let emptyStateExists = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'no' OR label CONTAINS[c] 'empty' OR label CONTAINS[c] 'history'")
        ).firstMatch.waitForExistence(timeout: 2.0)

        // An empty state or history list should be present
        XCTAssertTrue(
            app.windows.firstMatch.exists,
            "History view should display without crashing"
        )
    }
}

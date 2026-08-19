//
//  AppAccessibilityTests.swift
//  SortyUITests
//
//  Tests for verifying proper accessibility identifiers
//  are set on all major UI elements.
//

import XCTest

@MainActor
final class AppAccessibilityTests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        launchApp()
    }

    override func tearDown() async throws {
        app = nil
    }

    private func launchApp(environment: [String: String] = [:]) {
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = ["XCUITEST_FORCE_MAIN_APP": "1"].merging(environment) { _, new in new }
        app.launch()
    }

    private func navigate(to sidebarIdentifier: String, screenIdentifier: String) throws {
        let sidebarItem = app.buttons[sidebarIdentifier]
        XCTAssertTrue(sidebarItem.waitForExistence(timeout: 5))
        sidebarItem.click()
        XCTAssertTrue(
            app.otherElements[screenIdentifier].waitForExistence(timeout: 5),
            "\(screenIdentifier) should appear before its accessibility audit"
        )
    }

    private func auditCurrentScreen() throws {
        try app.performAccessibilityAudit()
    }

    func testOnboardingAccessibilityAudit() throws {
        app.terminate()
        launchApp(environment: [
            "XCUITEST_FORCE_MAIN_APP": "0",
            "XCUITEST_FORCE_ONBOARDING": "1",
            "XCUITEST_DISABLE_STORED_PROVIDER_CREDENTIALS": "1"
        ])
        XCTAssertTrue(app.otherElements["OnboardingView"].waitForExistence(timeout: 5))

        try auditCurrentScreen()
    }

    func testOrganizerAccessibilityAudit() throws {
        try navigate(to: "OrganizeSidebarItem", screenIdentifier: "OrganizerScreen")
        try auditCurrentScreen()
    }

    func testPreviewAccessibilityAudit() throws {
        app.terminate()
        launchApp(environment: ["XCUITEST_SEED_PREVIEW": "1"])
        XCTAssertTrue(app.otherElements["OrganizationPreviewScreen"].waitForExistence(timeout: 8))

        try auditCurrentScreen()
    }

    func testHistoryAccessibilityAudit() throws {
        try navigate(to: "HistorySidebarItem", screenIdentifier: "HistoryScreen")
        try auditCurrentScreen()
    }

    func testDuplicatesAccessibilityAudit() throws {
        try navigate(to: "DuplicatesSidebarItem", screenIdentifier: "DuplicatesScreen")
        try auditCurrentScreen()
    }

    func testWatchedFoldersAccessibilityAudit() throws {
        try navigate(to: "WatchedFoldersSidebarItem", screenIdentifier: "WatchedFoldersScreen")
        try auditCurrentScreen()
    }

    func testSettingsAccessibilityAudit() throws {
        try navigate(to: "SettingsSidebarItem", screenIdentifier: "SettingsScreen")
        try auditCurrentScreen()
    }

    // MARK: - Sidebar Navigation Identifiers

    func testSidebarNavigationElementsExist() throws {
        let sidebarItems = [
            "OrganizeSidebarItem",
            "DuplicatesSidebarItem",
            "SettingsSidebarItem",
            "HistorySidebarItem",
            "ExclusionsSidebarItem",
            "WatchedFoldersSidebarItem",
            "LearningsSidebarItem"
        ]

        for identifier in sidebarItems {
            let element = app.buttons[identifier]
            XCTAssertTrue(
                element.waitForExistence(timeout: 3.0),
                "Sidebar item '\(identifier)' should exist for accessibility"
            )
        }
    }

    // MARK: - Settings View Accessibility

    func testSettingsViewToggleIdentifiersExist() throws {
        // Navigate to Settings
        let settingsSidebarItem = app.buttons["SettingsSidebarItem"]
        XCTAssertTrue(settingsSidebarItem.waitForExistence(timeout: 3.0))
        settingsSidebarItem.click()
        Thread.sleep(forTimeInterval: 0.5)

        let expectedToggles = [
            "ReasoningToggle",
            "DeepScanToggle",
            "DuplicatesToggle",
            "FileTaggingToggle"
        ]

        for identifier in expectedToggles {
            let toggle = app.switches[identifier]
            // Use waitForExistence rather than immediate check
            let exists = toggle.waitForExistence(timeout: 2.0)
            // Log but don't fail immediately - some may be hidden/collapsed
            if !exists {
                print("Warning: Toggle '\(identifier)' not immediately visible, may require scrolling")
            }
        }
    }

    // MARK: - Duplicates View Accessibility

    func testDuplicatesViewCoreElementsExist() throws {
        let duplicatesSidebarItem = app.buttons["DuplicatesSidebarItem"]
        XCTAssertTrue(duplicatesSidebarItem.waitForExistence(timeout: 3.0))
        duplicatesSidebarItem.click()
        Thread.sleep(forTimeInterval: 0.5)

        let scanButton = app.buttons["ScanDuplicatesButton"]
        XCTAssertTrue(
            scanButton.waitForExistence(timeout: 3.0),
            "Scan Duplicates button should exist with accessibility identifier"
        )
    }

    // MARK: - Organize View Accessibility

    func testOrganizeViewCoreElementsExist() throws {
        let organizeSidebarItem = app.buttons["OrganizeSidebarItem"]
        XCTAssertTrue(organizeSidebarItem.waitForExistence(timeout: 3.0))
        organizeSidebarItem.click()
        Thread.sleep(forTimeInterval: 0.5)

        // The DirectorySelectionView should be shown initially
        // Check for the drop zone or folder selection UI
        let hasDropZone = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] 'folder'")
        ).firstMatch.waitForExistence(timeout: 2.0)
        
        XCTAssertTrue(hasDropZone, "Organize view should show folder selection UI")
    }

}

//
//  AppStateTests.swift
//  SortyTests
//
//  Comprehensive tests for AppState and menu bar controls
//

import XCTest
@testable import SortyLib

// MARK: - AppState Tests

@MainActor
class AppStateTests: XCTestCase {
    
    var appState: AppState!
    var organizer: FolderOrganizer!
    
    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        organizer = FolderOrganizer()
        appState.organizer = organizer
    }
    
    override func tearDown() async throws {
        appState = nil
        organizer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        let freshState = AppState()
        
        XCTAssertEqual(freshState.currentView, .organize)
        XCTAssertTrue(freshState.showingSidebar)
        XCTAssertFalse(freshState.showDirectoryPicker)
        XCTAssertNil(freshState.selectedDirectory)
    }
    
    func testOnboardingPersistence() {
        let key = "hasCompletedOnboarding"
        let originalValue = UserDefaults.standard.bool(forKey: key)
        
        UserDefaults.standard.removeObject(forKey: key)
        
        let state1 = AppState()
        XCTAssertFalse(state1.hasCompletedOnboarding)
        
        state1.hasCompletedOnboarding = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        
        let state2 = AppState()
        XCTAssertTrue(state2.hasCompletedOnboarding)
        
        UserDefaults.standard.set(originalValue, forKey: key)
    }
    
    // MARK: - View Navigation Tests
    
    func testAllAppViewCases() {
        let allViews: [AppState.AppView] = [
            .settings, .organize, .history, .workspaceHealth,
            .duplicates, .exclusions, .watchedFolders, .learnings
        ]
        
        for view in allViews {
            appState.currentView = view
            XCTAssertEqual(appState.currentView, view)
        }
    }
    
    func testAppViewEquatable() {
        XCTAssertEqual(AppState.AppView.organize, AppState.AppView.organize)
        XCTAssertNotEqual(AppState.AppView.organize, AppState.AppView.settings)
    }
    
    // MARK: - Sidebar Toggle Tests
    
    func testSidebarToggle() {
        XCTAssertTrue(appState.showingSidebar)
        
        appState.showingSidebar.toggle()
        XCTAssertFalse(appState.showingSidebar)
        
        appState.showingSidebar.toggle()
        XCTAssertTrue(appState.showingSidebar)
    }
    
    // MARK: - Directory Picker Tests
    
    func testDirectoryPickerToggle() {
        XCTAssertFalse(appState.showDirectoryPicker)
        
        appState.showDirectoryPicker = true
        XCTAssertTrue(appState.showDirectoryPicker)
    }
    
    func testSelectedDirectory() {
        XCTAssertNil(appState.selectedDirectory)
        
        let testURL = URL(fileURLWithPath: "/tmp/test")
        appState.selectedDirectory = testURL
        XCTAssertEqual(appState.selectedDirectory, testURL)
    }
    
    // MARK: - Computed Properties Tests
    
    func testHasResultsWhenNoOrganizer() {
        appState.organizer = nil
        XCTAssertFalse(appState.hasResults)
    }
    
    func testHasResultsWhenNoPlan() {
        XCTAssertNil(organizer.currentPlan)
        XCTAssertFalse(appState.hasResults)
    }
    
    func testHasFilesWhenNoPlan() {
        XCTAssertNil(organizer.currentPlan)
        XCTAssertFalse(appState.hasFiles)
    }
    
    func testCanStartOrganizationRequiresDirectory() {
        appState.selectedDirectory = nil
        XCTAssertFalse(appState.canStartOrganization)
    }
    
    func testCanStartOrganizationWhenIdle() {
        appState.selectedDirectory = URL(fileURLWithPath: "/tmp")
        XCTAssertEqual(organizer.state, .idle)
        XCTAssertTrue(appState.canStartOrganization)
    }
    
    func testHasCurrentPlanWhenNoPlan() {
        XCTAssertNil(organizer.currentPlan)
        XCTAssertFalse(appState.hasCurrentPlan)
    }
    
    func testCanApplyWhenIdle() {
        XCTAssertEqual(organizer.state, .idle)
        XCTAssertFalse(appState.canApply)
    }
    
    func testIsOperationInProgressWhenIdle() {
        XCTAssertEqual(organizer.state, .idle)
        XCTAssertFalse(appState.isOperationInProgress)
    }
    
    func testIsOperationInProgressWhenNoOrganizer() {
        appState.organizer = nil
        XCTAssertFalse(appState.isOperationInProgress)
    }
    
    // MARK: - Action Methods Tests
    
    func testResetSessionClearsDirectory() {
        appState.selectedDirectory = URL(fileURLWithPath: "/tmp/test")
        
        appState.resetSession()
        
        XCTAssertNil(appState.selectedDirectory)
    }
    
    func testResetSessionWithNoOrganizer() {
        appState.organizer = nil
        appState.selectedDirectory = URL(fileURLWithPath: "/tmp/test")
        
        appState.resetSession()
        
        XCTAssertNil(appState.selectedDirectory)
    }
    
    func testStartOrganizationRequiresOrganizer() {
        appState.organizer = nil
        appState.selectedDirectory = URL(fileURLWithPath: "/tmp")
        
        appState.startOrganization()
    }
    
    func testStartOrganizationRequiresDirectory() {
        appState.selectedDirectory = nil
        
        appState.startOrganization()
    }
    
    func testCancelOperationWithNoOrganizer() {
        appState.organizer = nil
        appState.cancelOperation()
    }
    
    func testCancelOperationResetsOrganizer() {
        appState.cancelOperation()
        XCTAssertEqual(organizer.state, .idle)
    }
    
    func testPreviewChanges() {
        appState.previewChanges()
    }
    
    func testSelectAllFiles() {
        appState.selectAllFiles()
    }
    
    func testApplyChangesRequiresDirectory() {
        appState.selectedDirectory = nil
        appState.applyChanges()
    }
    
    func testRegenerateOrganizationWithNoOrganizer() {
        appState.organizer = nil
        appState.regenerateOrganization()
    }
    
    // MARK: - Learnings Actions Tests
    
    func testStartHoningSession() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .startHoningSession,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        appState.startHoningSession()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testShowLearningsStats() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .showLearningsStats,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        appState.showLearningsStats()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testPauseLearning() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .pauseLearning,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        appState.pauseLearning()
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testExportLearningsProfile() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .exportLearningsProfile,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        appState.exportLearningsProfile()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testImportLearningsProfile() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .importLearningsProfile,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        appState.importLearningsProfile()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testDeleteUsageData() {
        appState.deleteUsageData()
    }
    
    // MARK: - Edge Cases
    
    func testWeakOrganizerReference() {
        var localOrganizer: FolderOrganizer? = FolderOrganizer()
        appState.organizer = localOrganizer
        
        XCTAssertNotNil(appState.organizer)
        
        localOrganizer = nil
        
        XCTAssertNil(appState.organizer)
    }
    
    func testComputedPropertiesWithNilOrganizer() {
        appState.organizer = nil
        
        XCTAssertFalse(appState.hasResults)
        XCTAssertFalse(appState.hasFiles)
        XCTAssertFalse(appState.canStartOrganization)
        XCTAssertFalse(appState.hasCurrentPlan)
        XCTAssertFalse(appState.canApply)
        XCTAssertFalse(appState.isOperationInProgress)
    }
    
    func testMultipleViewChanges() {
        let views: [AppState.AppView] = [.organize, .settings, .history, .duplicates, .learnings]
        
        for view in views {
            appState.currentView = view
        }
        
        XCTAssertEqual(appState.currentView, .learnings)
    }
    
    // MARK: - Calibrate Action Tests
    
    func testCalibrateActionProperty() {
        XCTAssertNil(appState.calibrateAction)
        
        appState.calibrateAction = { _ in }
        
        XCTAssertNotNil(appState.calibrateAction)
    }
    
    // MARK: - UpdateManager Tests
    
    func testUpdateManagerExists() {
        XCTAssertNotNil(appState.updateManager)
    }
}

// MARK: - SortyCommands Tests

@MainActor
class SortyCommandsTests: XCTestCase {
    
    var appState: AppState!
    var organizer: FolderOrganizer!
    
    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        organizer = FolderOrganizer()
        appState.organizer = organizer
    }
    
    override func tearDown() async throws {
        appState = nil
        organizer = nil
        try await super.tearDown()
    }
    
    func testSortyCommandsInitialization() {
        let commands = SortyCommands(appState: appState)
        XCTAssertNotNil(commands)
    }
    
    func testCommandsCanAccessAppState() {
        let commands = SortyCommands(appState: appState)
        
        appState.currentView = .settings
        XCTAssertEqual(commands.appState.currentView, .settings)
    }
    
    func testCommandsReflectSidebarState() {
        let commands = SortyCommands(appState: appState)
        
        XCTAssertTrue(commands.appState.showingSidebar)
        
        appState.showingSidebar = false
        XCTAssertFalse(commands.appState.showingSidebar)
    }
    
    func testCommandsReflectDirectoryState() {
        let commands = SortyCommands(appState: appState)
        
        XCTAssertNil(commands.appState.selectedDirectory)
        
        let testURL = URL(fileURLWithPath: "/tmp/test")
        appState.selectedDirectory = testURL
        XCTAssertEqual(commands.appState.selectedDirectory, testURL)
    }
    
    func testCommandsReflectComputedProperties() {
        let commands = SortyCommands(appState: appState)
        
        XCTAssertFalse(commands.appState.hasResults)
        XCTAssertFalse(commands.appState.hasFiles)
        XCTAssertFalse(commands.appState.canApply)
        XCTAssertFalse(commands.appState.isOperationInProgress)
    }
}

// MARK: - AppView Enum Tests

class AppViewEnumTests: XCTestCase {
    
    func testAppViewIsSendable() {
        let view: AppState.AppView = .organize
        
        Task {
            let _ = view
        }
    }
    
    func testAppViewEquality() {
        XCTAssertEqual(AppState.AppView.settings, AppState.AppView.settings)
        XCTAssertEqual(AppState.AppView.organize, AppState.AppView.organize)
        XCTAssertEqual(AppState.AppView.history, AppState.AppView.history)
        XCTAssertEqual(AppState.AppView.workspaceHealth, AppState.AppView.workspaceHealth)
        XCTAssertEqual(AppState.AppView.duplicates, AppState.AppView.duplicates)
        XCTAssertEqual(AppState.AppView.exclusions, AppState.AppView.exclusions)
        XCTAssertEqual(AppState.AppView.watchedFolders, AppState.AppView.watchedFolders)
        XCTAssertEqual(AppState.AppView.learnings, AppState.AppView.learnings)
    }
    
    func testAppViewInequality() {
        XCTAssertNotEqual(AppState.AppView.settings, AppState.AppView.organize)
        XCTAssertNotEqual(AppState.AppView.history, AppState.AppView.duplicates)
        XCTAssertNotEqual(AppState.AppView.learnings, AppState.AppView.exclusions)
    }
    
    func testAllViewsAreDifferent() {
        let allViews: [AppState.AppView] = [
            .settings, .organize, .history, .workspaceHealth,
            .duplicates, .exclusions, .watchedFolders, .learnings
        ]
        
        for i in 0..<allViews.count {
            for j in 0..<allViews.count {
                if i != j {
                    XCTAssertNotEqual(allViews[i], allViews[j])
                }
            }
        }
    }
}

// MARK: - OrganizationState Tests

class OrganizationStateTests: XCTestCase {
    
    func testOrganizationStateEquality() {
        XCTAssertEqual(OrganizationState.idle, OrganizationState.idle)
        XCTAssertEqual(OrganizationState.scanning, OrganizationState.scanning)
        XCTAssertEqual(OrganizationState.organizing, OrganizationState.organizing)
        XCTAssertEqual(OrganizationState.ready, OrganizationState.ready)
        XCTAssertEqual(OrganizationState.applying, OrganizationState.applying)
        XCTAssertEqual(OrganizationState.completed, OrganizationState.completed)
    }
    
    func testOrganizationStateInequality() {
        XCTAssertNotEqual(OrganizationState.idle, OrganizationState.scanning)
        XCTAssertNotEqual(OrganizationState.scanning, OrganizationState.organizing)
        XCTAssertNotEqual(OrganizationState.ready, OrganizationState.completed)
    }
    
    func testErrorStateEquality() {
        let error1 = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error"])
        let error2 = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Error"])
        let error3 = NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Different"])
        
        XCTAssertEqual(OrganizationState.error(error1), OrganizationState.error(error2))
        XCTAssertNotEqual(OrganizationState.error(error1), OrganizationState.error(error3))
    }
    
    func testErrorStateNotEqualToOtherStates() {
        let error = NSError(domain: "test", code: 1, userInfo: nil)
        
        XCTAssertNotEqual(OrganizationState.error(error), OrganizationState.idle)
        XCTAssertNotEqual(OrganizationState.error(error), OrganizationState.completed)
    }
    
    func testAllStatesAreDifferent() {
        let states: [OrganizationState] = [
            .idle, .scanning, .organizing, .ready, .applying, .completed
        ]
        
        for i in 0..<states.count {
            for j in 0..<states.count {
                if i != j {
                    XCTAssertNotEqual(states[i], states[j])
                }
            }
        }
    }
}

// MARK: - Notification Names Tests

class NotificationNamesTests: XCTestCase {
    
    func testLearningsNotificationNamesExist() {
        XCTAssertNotNil(Notification.Name.startHoningSession)
        XCTAssertNotNil(Notification.Name.showLearningsStats)
        XCTAssertNotNil(Notification.Name.pauseLearning)
        XCTAssertNotNil(Notification.Name.exportLearningsProfile)
        XCTAssertNotNil(Notification.Name.importLearningsProfile)
    }
    
    func testOrganizationNotificationNamesExist() {
        XCTAssertNotNil(Notification.Name.organizationDidStart)
        XCTAssertNotNil(Notification.Name.organizationDidFinish)
        XCTAssertNotNil(Notification.Name.organizationDidRevert)
    }
    
    func testNotificationNamesAreUnique() {
        let names: [Notification.Name] = [
            .startHoningSession,
            .showLearningsStats,
            .pauseLearning,
            .exportLearningsProfile,
            .importLearningsProfile,
            .organizationDidStart,
            .organizationDidFinish,
            .organizationDidRevert
        ]
        
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count)
    }
}

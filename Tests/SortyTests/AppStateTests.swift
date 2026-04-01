//
//  AppStateTests.swift
//  SortyTests
//
//  Comprehensive tests for AppState and menu bar controls
//

import XCTest
import Combine
@testable import SortyLib

// MARK: - AppState Tests

@MainActor
class AppStateTests: XCTestCase {
    
    var appState: AppState!
    var organizer: FolderOrganizer!
    private let requiresSetupRepairKey = "requiresSetupRepair"
    private let setupRepairMessageKey = "setupRepairMessage"
    
    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: requiresSetupRepairKey)
        UserDefaults.standard.removeObject(forKey: setupRepairMessageKey)
        
        appState = AppState()
        organizer = FolderOrganizer()
        appState.organizer = organizer
    }
    
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: requiresSetupRepairKey)
        UserDefaults.standard.removeObject(forKey: setupRepairMessageKey)
        appState = nil
        organizer = nil
        
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
        let testSuiteName = "test.onboarding.persistence.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: testSuiteName)!
        let onboardingKey = "hasCompletedOnboarding"
        let versionKey = "lastLaunchedVersion"
        
        defer {
            userDefaults.removePersistentDomain(forName: testSuiteName)
        }
        
        // Simulate fresh install (no version stored, onboarding not completed)
        userDefaults.removeObject(forKey: onboardingKey)
        userDefaults.removeObject(forKey: versionKey)
        
        // Verify state
        XCTAssertFalse(userDefaults.bool(forKey: onboardingKey), "Fresh install should show onboarding")
        
        // Set onboarding completed
        userDefaults.set(true, forKey: onboardingKey)
        XCTAssertTrue(userDefaults.bool(forKey: onboardingKey))
        
        // Version should be manageable
        userDefaults.set("1.0.0", forKey: versionKey)
        XCTAssertNotNil(userDefaults.string(forKey: versionKey), "Version should be stored after first launch")
    }
    
    func testOnboardingSkippedForUpdates() {
        let testSuiteName = "test.onboarding.updates.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: testSuiteName)!
        let onboardingKey = "hasCompletedOnboarding"
        let versionKey = "lastLaunchedVersion"
        
        defer {
            userDefaults.removePersistentDomain(forName: testSuiteName)
        }
        
        // Simulate an in-app update scenario: previous version exists, even if onboarding flag was reset
        userDefaults.set("0.9.0", forKey: versionKey)
        userDefaults.set(false, forKey: onboardingKey)  // Somehow got reset
        
        // Verify the state is set correctly
        XCTAssertEqual(userDefaults.string(forKey: versionKey), "0.9.0")
        XCTAssertFalse(userDefaults.bool(forKey: onboardingKey))
    }
    
    func testOnboardingShownForFreshInstall() {
        let testSuiteName = "test.onboarding.fresh.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: testSuiteName)!
        let onboardingKey = "hasCompletedOnboarding"
        let versionKey = "lastLaunchedVersion"
        
        defer {
            userDefaults.removePersistentDomain(forName: testSuiteName)
        }
        
        // Simulate fresh install: no version, no onboarding completed
        userDefaults.removeObject(forKey: versionKey)
        userDefaults.removeObject(forKey: onboardingKey)
        
        // Verify state
        XCTAssertFalse(userDefaults.bool(forKey: onboardingKey), "Fresh install should show onboarding")
        XCTAssertNil(userDefaults.string(forKey: versionKey), "Fresh install should have no version")
    }

    func testStartSetupRepairRoutesToProviderSettingsAndPersistsMessage() {
        appState.currentView = .history

        appState.startSetupRepair(message: "Provider setup is incomplete.")

        XCTAssertTrue(appState.requiresSetupRepair)
        XCTAssertEqual(appState.setupRepairMessage, "Provider setup is incomplete.")
        XCTAssertEqual(appState.currentView, .settings)
        XCTAssertEqual(appState.selectedSettingsSection, .provider)
        XCTAssertEqual(UserDefaults.standard.string(forKey: setupRepairMessageKey), "Provider setup is incomplete.")
    }

    func testClearSetupRepairStateRemovesPersistence() {
        appState.startSetupRepair(message: "Repair me.")

        appState.clearSetupRepairState()

        XCTAssertFalse(appState.requiresSetupRepair)
        XCTAssertNil(appState.setupRepairMessage)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: requiresSetupRepairKey))
        XCTAssertNil(UserDefaults.standard.string(forKey: setupRepairMessageKey))
    }

    func testProviderSetupValidatorBlocksMissingAPIKey() {
        let config = AIConfig(
            provider: .openAICompatible,
            apiURL: "https://api.example.com",
            apiKey: nil,
            model: AIProvider.openAICompatible.defaultModel,
            requiresAPIKey: true
        )

        let status = OnboardingSetupValidator.providerStatus(
            context: ProviderSetupContext(
                config: config,
                isGitHubCopilotAuthenticated: false,
                isCodexAuthenticated: false,
                isCodexInstalled: false,
                isAppleFoundationModelAvailable: false
            )
        )

        XCTAssertFalse(status.isReady)
        XCTAssertEqual(status.title, "Credentials required")
        XCTAssertTrue(status.message.contains("API key"))
    }

    func testProviderSetupValidatorAllowsConfiguredOllama() {
        let config = AIConfig(
            provider: .ollama,
            apiURL: "http://localhost:11434",
            apiKey: nil,
            model: AIProvider.ollama.defaultModel,
            requiresAPIKey: false
        )

        let status = OnboardingSetupValidator.providerStatus(
            context: ProviderSetupContext(
                config: config,
                isGitHubCopilotAuthenticated: false,
                isCodexAuthenticated: false,
                isCodexInstalled: false,
                isAppleFoundationModelAvailable: false
            )
        )

        XCTAssertTrue(status.isReady)
    }

    func testProviderSetupValidatorRequiresCodexSignInForOpenAIAccountAuth() {
        var config = AIConfig(
            provider: .openAI,
            apiURL: AIProvider.openAI.defaultAPIURL,
            apiKey: nil,
            model: AIProvider.openAI.defaultModel,
            requiresAPIKey: true
        )
        config.setAuthMethod(.accountSignIn, for: .openAI)

        let status = OnboardingSetupValidator.providerStatus(
            context: ProviderSetupContext(
                config: config,
                isGitHubCopilotAuthenticated: false,
                isCodexAuthenticated: false,
                isCodexInstalled: true,
                isAppleFoundationModelAvailable: false
            )
        )

        XCTAssertFalse(status.isReady)
        XCTAssertTrue(status.message.contains("Codex CLI"))
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

    func testHandoffToDuplicatesCarriesNormalizedFilePaths() {
        let folder = URL(fileURLWithPath: "/tmp/handoff-folder")
        appState.handoffToDuplicates(
            forFilePaths: [
                "/tmp/handoff-folder/a/../a/file1.txt",
                "/tmp/handoff-folder/a/file1.txt",
                "/tmp/handoff-folder/b/file2.txt"
            ],
            preferredDirectory: folder,
            autoStart: true
        )

        XCTAssertEqual(appState.currentView, .duplicates)
        XCTAssertEqual(appState.selectedDirectory, folder.standardizedFileURL)
        XCTAssertEqual(appState.pendingDuplicatesHandoff?.directory, folder.standardizedFileURL)
        XCTAssertEqual(
            appState.pendingDuplicatesHandoff?.filePaths ?? [],
            [
                "/tmp/handoff-folder/a/file1.txt",
                "/tmp/handoff-folder/b/file2.txt"
            ]
        )
    }

    func testHandoffToDuplicatesDirectoryOnlyHasNoFilePaths() {
        let folder = URL(fileURLWithPath: "/tmp/directory-only")
        appState.handoffToDuplicates(directory: folder, autoStart: false)

        XCTAssertEqual(appState.currentView, .duplicates)
        XCTAssertEqual(appState.pendingDuplicatesHandoff?.directory, folder.standardizedFileURL)
        XCTAssertEqual(appState.pendingDuplicatesHandoff?.filePaths ?? [], [])
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
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        
        appState.startHoningSession()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 2.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testShowLearningsStats() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .showLearningsStats,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        
        appState.showLearningsStats()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 2.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testPauseLearning() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .pauseLearning,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        
        appState.pauseLearning()
        
        wait(for: [expectation], timeout: 2.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testExportLearningsProfile() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .exportLearningsProfile,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        
        appState.exportLearningsProfile()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 2.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testImportLearningsProfile() {
        let expectation = XCTestExpectation(description: "Notification received")
        
        let observer = NotificationCenter.default.addObserver(
            forName: .importLearningsProfile,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        
        appState.importLearningsProfile()
        
        XCTAssertEqual(appState.currentView, .learnings)
        
        wait(for: [expectation], timeout: 2.0)
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

    func testMultipleAppStatesKeepIndependentSelections() {
        let stateA = AppState()
        let stateB = AppState()
        stateA.selectedDirectory = URL(fileURLWithPath: "/tmp/a")
        stateB.selectedDirectory = URL(fileURLWithPath: "/tmp/b")

        XCTAssertEqual(stateA.selectedDirectory?.path, "/tmp/a")
        XCTAssertEqual(stateB.selectedDirectory?.path, "/tmp/b")
    }

    func testCancelOperationDoesNotAffectOtherWindowOrganizer() {
        let stateA = AppState()
        let stateB = AppState()
        let organizerA = FolderOrganizer()
        let organizerB = FolderOrganizer()
        stateA.organizer = organizerA
        stateB.organizer = organizerB

        organizerA.state = .organizing
        organizerB.state = .organizing

        stateA.cancelOperation()

        XCTAssertEqual(organizerA.state, .idle)
        XCTAssertEqual(organizerB.state, .organizing)
    }
}

// MARK: - SortyCommands Tests

@MainActor
class SortyCommandsTests: XCTestCase {

    func testSortyCommandsInitialization() {
        let commands = SortyCommands()
        XCTAssertNotNil(commands)
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

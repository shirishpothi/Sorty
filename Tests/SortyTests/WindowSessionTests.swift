import XCTest
@testable import SortyLib

@MainActor
final class WindowSessionTests: XCTestCase {
    private var session: WindowSession!
    private var settingsViewModel: SettingsViewModel!
    private var personaManager: PersonaManager!
    private var customPersonaStore: CustomPersonaStore!
    private var watchedFoldersManager: WatchedFoldersManager!
    private var exclusionRules: ExclusionRulesManager!
    private var storageLocationsManager: StorageLocationsManager!
    private var learningsManager: LearningsManager!

    override func setUp() async throws {
        session = WindowSession()
        settingsViewModel = SettingsViewModel()
        personaManager = PersonaManager()
        customPersonaStore = CustomPersonaStore()
        watchedFoldersManager = WatchedFoldersManager()
        watchedFoldersManager.clearAll()
        exclusionRules = ExclusionRulesManager()
        storageLocationsManager = StorageLocationsManager()
        learningsManager = LearningsManager()
    }

    override func tearDown() async throws {
        watchedFoldersManager.clearAll()
        session = nil
        settingsViewModel = nil
        personaManager = nil
        customPersonaStore = nil
        watchedFoldersManager = nil
        exclusionRules = nil
        storageLocationsManager = nil
        learningsManager = nil
    }

    func testWindowLaunchRequestRoundTripsURL() {
        let url = URL(string: "sorty://settings?section=provider")!
        let request = WindowLaunchRequest(url: url)

        XCTAssertEqual(request.deeplinkURLString, url.absoluteString)
        XCTAssertEqual(request.deeplinkURL, url)
    }

    func testExternalDeeplinkDeduplicatesRapidCalls() {
        let url = URL(string: "sorty://watched?action=add&path=/tmp/test")!
        XCTAssertTrue(ExternalDeeplinkDeduper.shouldHandle(url))
        XCTAssertFalse(ExternalDeeplinkDeduper.shouldHandle(url))
    }

    func testWindowSessionUsesInjectedSharedUpdateManager() {
        let updateManager = SparkleUpdateManager()
        let session = WindowSession(updateManager: updateManager)

        XCTAssertTrue(session.appState.updateManager === updateManager)
        XCTAssertEqual(session.appState.windowSessionID, session.id)
    }

    func testWindowScopedNotificationMatchesOnlyTargetWindowSession() {
        let targetSessionID = UUID()
        let otherSessionID = UUID()
        let notification = Notification(
            name: .importLearningsProfile,
            object: nil,
            userInfo: MainWindowRouter.scopedUserInfo(targetSessionID: targetSessionID)
        )

        XCTAssertTrue(notification.targetsWindowSession(targetSessionID))
        XCTAssertFalse(notification.targetsWindowSession(otherSessionID))
    }

    func testImportLearningsProfilePostsTargetedNotification() {
        final class TargetCapture: @unchecked Sendable {
            var value: String?
        }

        let targetSessionID = UUID()
        let defaultsSuiteName = "WindowSessionTests-\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: defaultsSuiteName)!
        defer {
            userDefaults.removePersistentDomain(forName: defaultsSuiteName)
        }

        let appState = AppState(
            windowSessionID: targetSessionID,
            updateManager: SparkleUpdateManager(),
            userDefaults: userDefaults
        )

        let expectation = expectation(description: "import notification posted")
        let capture = TargetCapture()
        let observer = NotificationCenter.default.addObserver(
            forName: .importLearningsProfile,
            object: nil,
            queue: .main
        ) { notification in
            capture.value = notification.userInfo?[WindowRoutingUserInfoKey.targetSessionID] as? String
            expectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
        }

        appState.importLearningsProfile()

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(capture.value, targetSessionID.uuidString)
    }

    func testWatchedAddMarksFolderAsLostWhenBookmarkMissing() {
        let missingPath = "/tmp/sorty-missing-\(UUID().uuidString)"

        handle(.watched(action: "add", path: missingPath))

        XCTAssertEqual(session.appState.currentView, .watchedFolders)
        XCTAssertEqual(watchedFoldersManager.folders.count, 1)
        let addedFolder = watchedFoldersManager.folders[0]
        XCTAssertEqual(addedFolder.path, URL(fileURLWithPath: missingPath).standardizedFileURL.path)
        XCTAssertEqual(addedFolder.accessStatus, .lost)
        XCTAssertNil(addedFolder.bookmarkData)
    }

    func testSettingsSectionSelectionIsAppliedAfterYield() async {
        handle(.settings(section: "provider"))

        XCTAssertEqual(session.appState.currentView, .organize)
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .provider)
        XCTAssertNil(session.appState.settingsFocusTarget)
    }

    func testWatchedSettingsSectionMapsToRulesFocusTarget() async {
        handle(.settings(section: "watched"))

        XCTAssertEqual(session.appState.currentView, .organize)
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .rules)
        XCTAssertNil(session.appState.settingsFocusTarget)
    }

    func testWatchedFoldersAliasMapsToRulesSection() async {
        handle(.settings(section: "watched-folders"))

        XCTAssertEqual(session.appState.currentView, .organize)
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .rules)
        XCTAssertNil(session.appState.settingsFocusTarget)
    }

    func testStorageSettingsSectionMapsToStorageFocusTarget() async {
        handle(.settings(section: "storage"))

        XCTAssertEqual(session.appState.currentView, .organize)
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .rules)
        XCTAssertEqual(session.appState.settingsFocusTarget, .rulesStorageLocations)
    }

    func testUnknownSettingsSectionClearsSelectionAndFocusTarget() async {
        handle(.settings(section: "storage-locations"))
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .rules)
        XCTAssertEqual(session.appState.settingsFocusTarget, .rulesStorageLocations)

        handle(.settings(section: "totally-unknown-section"))
        await spinMainActor()
        XCTAssertNil(session.appState.selectedSettingsSection)
        XCTAssertNil(session.appState.settingsFocusTarget)
    }

    func testNilSettingsSectionClearsSelectionAndFocusTarget() async {
        handle(.settings(section: "provider"))
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .provider)

        handle(.settings(section: nil))
        await spinMainActor()
        XCTAssertNil(session.appState.selectedSettingsSection)
        XCTAssertNil(session.appState.settingsFocusTarget)
    }

    private func handle(_ destination: DeeplinkDestination) {
        session.handle(
            destination: destination,
            settingsViewModel: settingsViewModel,
            personaManager: personaManager,
            customPersonaStore: customPersonaStore,
            watchedFoldersManager: watchedFoldersManager,
            exclusionRules: exclusionRules,
            storageLocationsManager: storageLocationsManager,
            learningsManager: learningsManager
        )
    }

    private func spinMainActor(iterations: Int = 6) async {
        for _ in 0..<iterations {
            await Task.yield()
        }
    }
}

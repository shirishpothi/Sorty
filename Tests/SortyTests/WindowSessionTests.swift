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

        XCTAssertEqual(session.appState.currentView, .settings)
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .provider)
        XCTAssertNil(session.appState.settingsFocusTarget)
    }

    func testWatchedSettingsSectionMapsToRulesFocusTarget() async {
        handle(.settings(section: "watched"))

        XCTAssertEqual(session.appState.currentView, .settings)
        await spinMainActor()
        XCTAssertEqual(session.appState.selectedSettingsSection, .rules)
        XCTAssertEqual(session.appState.settingsFocusTarget, .rulesWatchedFolders)
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

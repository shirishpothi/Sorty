import XCTest
@testable import SortyLib

final class ApplePrivateCloudComputeClientTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ApplePrivateCloudComputeClientTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testResolveShortcutPrefersConfiguredCustomShortcut() {
        defaults.set("My Cloud Shortcut", forKey: "applePCCShortcutName")

        let resolved = ApplePrivateCloudComputeClient.resolveShortcutName(
            installedShortcutNames: ["Use Model", "My Cloud Shortcut"],
            defaults: defaults
        )

        XCTAssertEqual(resolved, "My Cloud Shortcut")
    }

    func testResolveShortcutFallsBackToBuiltinThenLegacy() {
        let resolvedBuiltinPreferred = ApplePrivateCloudComputeClient.resolveShortcutName(
            installedShortcutNames: ["Sorty-PCC", "Use Model"],
            defaults: defaults
        )
        XCTAssertEqual(resolvedBuiltinPreferred, "Use Model")

        defaults.removeObject(forKey: "applePCCResolvedShortcutName")

        let resolvedBuiltin = ApplePrivateCloudComputeClient.resolveShortcutName(
            installedShortcutNames: ["Use Model"],
            defaults: defaults
        )
        XCTAssertEqual(resolvedBuiltin, "Use Model")
    }

    func testResolveShortcutUsesCachedShortcutIfStillInstalled() {
        defaults.set("Sorty-PCC", forKey: "applePCCResolvedShortcutName")

        let resolved = ApplePrivateCloudComputeClient.resolveShortcutName(
            installedShortcutNames: ["Sorty-PCC", "Use Model"],
            defaults: defaults
        )

        XCTAssertEqual(resolved, "Sorty-PCC")
    }

    func testResolveShortcutClearsMissingCache() {
        defaults.set("Missing Shortcut", forKey: "applePCCResolvedShortcutName")

        let resolved = ApplePrivateCloudComputeClient.resolveShortcutName(
            installedShortcutNames: [],
            defaults: defaults
        )

        XCTAssertNil(resolved)
        XCTAssertNil(defaults.string(forKey: "applePCCResolvedShortcutName"))
    }
}

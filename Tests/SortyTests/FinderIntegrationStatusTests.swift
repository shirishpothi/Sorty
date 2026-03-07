import XCTest
@testable import SortyLib

final class FinderIntegrationStatusTests: XCTestCase {
    private let preferredExtensionPath = "/Users/test/Applications/Sorty.app/Contents/PlugIns/SortyFinderSync.appex"
    private let staleExtensionPath = "/Applications/Sorty.app/Contents/PlugIns/SortyFinderSync.appex"

    func testIntegrationCountUsesActiveIntegrationsOnly() {
        let status = ExtensionCommunication.FinderIntegrationStatus(
            quickActionInstalled: true,
            quickWatchActionInstalled: true,
            toolbarAppInstalled: false,
            finderSyncEnabled: true,
            menuBarEnabled: false
        )

        XCTAssertEqual(status.integrationCount, 2)
        XCTAssertEqual(ExtensionCommunication.FinderIntegrationStatus.totalIntegrations, 4)
        XCTAssertEqual(status.overallStatus, "Active")
    }

    func testAsyncIntegrationStatusReturnsWithoutThrowing() async {
        let status = await ExtensionCommunication.getIntegrationStatusAsync()
        XCTAssertGreaterThanOrEqual(status.integrationCount, 0)
        XCTAssertLessThanOrEqual(status.integrationCount, ExtensionCommunication.FinderIntegrationStatus.totalIntegrations)
    }

    func testParseFinderSyncRegistrationEntriesTracksEnabledStates() {
        let output = """
        +    com.sorty.app.SortyFinderSync(1.1.2)\tUUID-1\t2026-03-07 02:42:55 +0000\t\(preferredExtensionPath)
        -    com.sorty.app.SortyFinderSync(1.1.2)\tUUID-2\t2026-03-07 02:42:55 +0000\t\(staleExtensionPath)
             com.sorty.app.SortyFinderSync(1.1.2)\tUUID-3\t2026-03-07 02:42:55 +0000\t/private/tmp/Sorty.app/Contents/PlugIns/SortyFinderSync.appex
        """

        let entries = ExtensionCommunication.parseFinderSyncRegistrationEntries(from: output)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.first(where: { $0.path == preferredExtensionPath })?.isEnabled, true)
        XCTAssertEqual(entries.first(where: { $0.path == staleExtensionPath })?.isEnabled, false)
        XCTAssertNil(entries.first(where: { $0.path.contains("/private/tmp/") })?.isEnabled)
    }

    func testFinderSyncDiagnosticsFlagsAnotherActiveAppCopy() {
        let diagnostics = ExtensionCommunication.finderSyncDiagnostics(
            entries: [.init(path: staleExtensionPath, isEnabled: true)],
            preferredPath: preferredExtensionPath,
            heartbeat: nil
        )

        XCTAssertEqual(diagnostics.kind, .activeElsewhere)
        XCTAssertEqual(diagnostics.activePath, staleExtensionPath)
        XCTAssertTrue(diagnostics.needsRepair)
    }

    func testFinderSyncDiagnosticsDoesNotClaimWorkingWithoutFinderHeartbeat() {
        let diagnostics = ExtensionCommunication.finderSyncDiagnostics(
            entries: [.init(path: preferredExtensionPath, isEnabled: true)],
            preferredPath: preferredExtensionPath,
            heartbeat: nil
        )

        XCTAssertEqual(diagnostics.kind, .registered)
        XCTAssertTrue(diagnostics.isOperational)
        XCTAssertFalse(diagnostics.isVerifiedWorking)
    }

    func testFinderSyncDiagnosticsVerifiesCurrentBuildWithHeartbeat() {
        let diagnostics = ExtensionCommunication.finderSyncDiagnostics(
            entries: [.init(path: preferredExtensionPath, isEnabled: true)],
            preferredPath: preferredExtensionPath,
            heartbeat: .init(
                event: "launch",
                bundleIdentifier: "com.sorty.app.SortyFinderSync",
                path: preferredExtensionPath,
                reportedAt: Date()
            )
        )

        XCTAssertEqual(diagnostics.kind, .verified)
        XCTAssertTrue(diagnostics.isOperational)
        XCTAssertTrue(diagnostics.isVerifiedWorking)
    }

    func testFinderSyncDiagnosticsFlagsStaleDuplicateRegistrations() {
        let diagnostics = ExtensionCommunication.finderSyncDiagnostics(
            entries: [
                .init(path: preferredExtensionPath, isEnabled: true),
                .init(path: staleExtensionPath, isEnabled: true)
            ],
            preferredPath: preferredExtensionPath,
            heartbeat: nil
        )

        XCTAssertEqual(diagnostics.kind, .needsCleanup)
        XCTAssertEqual(diagnostics.problemPaths, [staleExtensionPath])
        XCTAssertTrue(diagnostics.needsRepair)
    }
}

import Foundation
import XCTest
@testable import SortyLib

@MainActor
final class SettingsViewModelStartupTests: XCTestCase {
    func testInitializationDoesNotWaitForCredentialLookup() throws {
        let suiteName = "SettingsViewModelStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var storedConfig = AIConfig.default
        storedConfig.model = "startup-test-model"
        defaults.set(try JSONEncoder().encode(storedConfig), forKey: "aiConfig")

        let slowCredentialStore = SettingsCredentialStore(
            load: { _ in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return nil
            },
            save: { _, _ in true },
            delete: { _ in true }
        )

        let startedAt = CFAbsoluteTimeGetCurrent()
        let viewModel = SettingsViewModel(
            userDefaults: defaults,
            credentialStore: slowCredentialStore,
            observesNotifications: false
        )
        let initializationDuration = CFAbsoluteTimeGetCurrent() - startedAt

        XCTAssertEqual(viewModel.config.model, "startup-test-model")
        XCTAssertLessThan(
            initializationDuration,
            0.5,
            "Settings construction must not wait for Security.framework or a locked keychain."
        )
    }

    func testSwitchingToProviderWithoutAPIKeyDoesNotHydrateStoredCredential() async throws {
        let suiteName = "SettingsViewModelStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storedConfig = AIConfig(
            provider: .openRouter,
            model: AIProvider.openRouter.defaultModel
        )
        defaults.set(try JSONEncoder().encode(storedConfig), forKey: "aiConfig")

        let credentialStore = SettingsCredentialStore(
            load: { _ in "stale-credential" },
            save: { _, _ in true },
            delete: { _ in true }
        )
        let viewModel = SettingsViewModel(
            userDefaults: defaults,
            credentialStore: credentialStore,
            observesNotifications: false
        )

        viewModel.config.apiKey = "openrouter-secret"
        viewModel.config.provider = .ollama
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.config.provider, .ollama)
        XCTAssertNil(viewModel.config.apiKey)
    }
}

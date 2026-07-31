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

    func testStartupSaveDoesNotDeleteCredentialBeforeHydrationCompletes() async throws {
        let suiteName = "SettingsViewModelStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var storedConfig = AIConfig.default
        storedConfig.provider = .openRouter
        storedConfig.model = AIProvider.openRouter.defaultModel
        defaults.set(try JSONEncoder().encode(storedConfig), forKey: "aiConfig")

        let recorder = StartupCredentialStoreRecorder()
        let credentialStore = SettingsCredentialStore(
            load: { key in
                if key == "apiKey" {
                    return nil
                }
                try? await Task.sleep(for: .milliseconds(800))
                return "persisted-openrouter-key"
            },
            save: { key, value in
                await recorder.recordSave(key: key, value: value)
                return true
            },
            delete: { key in
                await recorder.recordDelete(key: key)
                return true
            }
        )
        let viewModel = SettingsViewModel(
            userDefaults: defaults,
            credentialStore: credentialStore,
            observesNotifications: false
        )

        viewModel.config.temperature = 0.2
        try await Task.sleep(for: .milliseconds(600))

        let deletedBeforeHydration = await recorder.deletedKeys()
        XCTAssertEqual(deletedBeforeHydration, [])

        try await Task.sleep(for: .milliseconds(300))
        let deletedAfterHydration = await recorder.deletedKeys()
        XCTAssertEqual(viewModel.config.apiKey, "persisted-openrouter-key")
        XCTAssertEqual(deletedAfterHydration, [])
    }
}

private actor StartupCredentialStoreRecorder {
    private var saves: [(key: String, value: String)] = []
    private var deletes: [String] = []

    func recordSave(key: String, value: String) {
        saves.append((key, value))
    }

    func recordDelete(key: String) {
        deletes.append(key)
    }

    func deletedKeys() -> [String] {
        deletes
    }
}

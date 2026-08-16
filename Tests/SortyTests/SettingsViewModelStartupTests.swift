import Combine
import Foundation
import XCTest
@testable import SortyLib

@MainActor
final class SettingsViewModelStartupTests: XCTestCase {
    func testProviderSwitchPublishesOneNormalizedConfigUpdate() throws {
        let suiteName = "SettingsViewModelStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var storedConfig = AIConfig.default
        storedConfig.provider = .openRouter
        defaults.set(try JSONEncoder().encode(storedConfig), forKey: "aiConfig")

        let credentialStore = SettingsCredentialStore(
            load: { _ in nil },
            save: { _, _ in true },
            saveImmediately: { _, _ in true },
            delete: { _ in true }
        )
        let viewModel = SettingsViewModel(
            userDefaults: defaults,
            credentialStore: credentialStore,
            observesNotifications: false
        )
        var configPublicationCount = 0
        let cancellable = viewModel.$config.dropFirst().sink { _ in
            configPublicationCount += 1
        }

        viewModel.config.provider = .ollama

        XCTAssertEqual(configPublicationCount, 2)
        XCTAssertEqual(viewModel.config.provider, .ollama)
        XCTAssertEqual(viewModel.config.apiURL, AIProvider.ollama.defaultAPIURL)
        XCTAssertEqual(viewModel.config.model, AIProvider.ollama.defaultModel)
        withExtendedLifetime(cancellable) {}
    }

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
            saveImmediately: { _, _ in true },
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
            saveImmediately: { _, _ in true },
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

    func testUpdatingAPIKeyPersistsBeforeReturning() throws {
        let suiteName = "SettingsViewModelStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var storedConfig = AIConfig.default
        storedConfig.provider = .openRouter
        defaults.set(try JSONEncoder().encode(storedConfig), forKey: "aiConfig")

        let recorder = ImmediateCredentialSaveRecorder()
        let credentialStore = SettingsCredentialStore(
            load: { _ in nil },
            save: { _, _ in true },
            saveImmediately: { key, value in
                recorder.record(key: key, value: value)
                return true
            },
            delete: { _ in true }
        )
        let viewModel = SettingsViewModel(
            userDefaults: defaults,
            credentialStore: credentialStore,
            observesNotifications: false
        )

        viewModel.updateAPIKey("openrouter-secret")

        XCTAssertEqual(recorder.savedKey, AIProvider.openRouter.keychainKey)
        XCTAssertEqual(recorder.savedValue, "openrouter-secret")
    }

    func testForceSavePersistsCredentialBeforeReturning() throws {
        let suiteName = "SettingsViewModelStartupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var storedConfig = AIConfig.default
        storedConfig.provider = .openRouter
        defaults.set(try JSONEncoder().encode(storedConfig), forKey: "aiConfig")

        let recorder = ImmediateCredentialSaveRecorder()
        let credentialStore = SettingsCredentialStore(
            load: { _ in nil },
            save: { _, _ in true },
            saveImmediately: { key, value in
                recorder.record(key: key, value: value)
                return true
            },
            delete: { _ in true }
        )
        let viewModel = SettingsViewModel(
            userDefaults: defaults,
            credentialStore: credentialStore,
            observesNotifications: false
        )
        viewModel.config.apiKey = "openrouter-secret"

        viewModel.forceSave()

        XCTAssertEqual(recorder.savedKey, AIProvider.openRouter.keychainKey)
        XCTAssertEqual(recorder.savedValue, "openrouter-secret")
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
            saveImmediately: { _, _ in true },
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

@MainActor
private final class ImmediateCredentialSaveRecorder {
    private(set) var savedKey: String?
    private(set) var savedValue: String?

    func record(key: String, value: String) {
        savedKey = key
        savedValue = value
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

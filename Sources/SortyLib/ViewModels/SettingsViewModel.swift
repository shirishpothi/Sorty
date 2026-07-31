//
//  SettingsViewModel.swift
//  Sorty
//
//  Manages API configuration and settings
//

import Foundation
import Combine

struct SettingsCredentialStore: Sendable {
    let load: @Sendable (String) async -> String?
    let save: @Sendable (String, String) async -> Bool
    let delete: @Sendable (String) async -> Bool

    static let keychain = SettingsCredentialStore(
        load: { await KeychainManager.getAsync(key: $0) },
        save: { await KeychainManager.saveAsync(key: $0, value: $1) },
        delete: { await KeychainManager.deleteAsync(key: $0) }
    )
}

@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var config: AIConfig = .default {
        didSet {
            guard !isApplyingConfigMutation else { return }

            let oldKey = oldValue.apiKey
            let newKey = config.apiKey
            let oldProvider = oldValue.provider
            let newProvider = config.provider
            let oldAuthMethod = oldValue.authMethod(for: oldProvider)
            let newAuthMethod = config.authMethod(for: newProvider)

            // Persist model changes immediately for the active provider.
            if oldProvider == newProvider, oldValue.model != config.model {
                userDefaults.set(config.model, forKey: modelSelectionKey(for: newProvider))
            }

            // Same provider, auth method switched — preserve API key and hydrate/clear in-memory field.
            if oldProvider == newProvider, oldAuthMethod != newAuthMethod {
                cancelCredentialHydration()

                if oldAuthMethod == .apiKey,
                   let oldKey = oldValue.apiKey,
                   !oldKey.isEmpty {
                    persistCredential(oldKey, for: newProvider)
                }

                if newAuthMethod == .apiKey {
                    hydrateStoredCredential(for: newProvider, authMethod: newAuthMethod)
                } else {
                    setInMemoryAPIKey(nil)
                }
            }

            // Debounce the save operation
            debouncedSave()

            // Invalidate cached URL sessions when timeout or API URL settings change
            // so the next request creates a fresh session with updated values
            if oldValue.requestTimeout != config.requestTimeout ||
               oldValue.resourceTimeout != config.resourceTimeout ||
               oldValue.apiURL != config.apiURL {
                AISessionManager.shared.invalidateAll()
            }

            // If smart rename is disabled, ensure mode is set to .organize
            if !config.enableSmartRename && config.mode != .organize {
                config.mode = .organize
            }

            // Provider switched — swap API keys via Keychain
            if oldProvider != newProvider {
                cancelCredentialHydration()

                // Save the old provider's selected model so it can be restored later
                userDefaults.set(oldValue.model, forKey: modelSelectionKey(for: oldProvider))

                // Save the old provider's API key to its keychain slot
                // Skip for GitHub Copilot — its token is managed by GitHubCopilotAuthManager
                if oldProvider != .githubCopilot,
                   oldAuthMethod == .apiKey,
                   let oldKey = oldValue.apiKey,
                   !oldKey.isEmpty {
                    persistCredential(oldKey, for: oldProvider)
                }

                // Load the new provider's API key from its keychain slot
                // Skip for GitHub Copilot — auth is handled by GitHubCopilotAuthManager, not apiKey
                isApplyingConfigMutation = true
                config.apiKey = nil
                config.apiURL = newProvider.defaultAPIURL
                config.requiresAPIKey = newProvider.typicallyRequiresAPIKey
                config.visionDetailLevel = VisionDetailLevel.defaultFor(provider: newProvider)
                config.model = userDefaults.string(forKey: modelSelectionKey(for: newProvider)) ?? newProvider.defaultModel
                isApplyingConfigMutation = false
                userDefaults.set(config.model, forKey: modelSelectionKey(for: newProvider))

                if newProvider != .githubCopilot,
                   newProvider.typicallyRequiresAPIKey,
                   newAuthMethod == .apiKey {
                    hydrateStoredCredential(for: newProvider, authMethod: newAuthMethod)
                }

                // Invalidate sessions for new provider URL
                AISessionManager.shared.invalidateAll()

                // Refresh model list for the new provider
                updateAvailableModels(force: true)

                // Auto-check connection after a short delay
                // For GitHub Copilot, skip apiKey check since auth is token-based
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if newProvider == .githubCopilot || newProvider == .appleFoundationModel || config.apiKey != nil {
                        try? await testConnection()
                    }
                    await AISessionManager.shared.prewarm(provider: newProvider, config: config)
                }
            } else if oldKey != newKey,
                      newProvider.typicallyRequiresAPIKey,
                      newAuthMethod == .apiKey,
                      let newKey = newKey,
                      !newKey.isEmpty {
                cancelCredentialHydration()

                // Same provider, API key changed — save immediately to Keychain
                // so ModelCatalog reads the fresh key (fixes Gemini model list race)
                Task { [weak self, credentialStore] in
                    _ = await credentialStore.save(newProvider.keychainKey, newKey)
                    guard let self, self.config.provider == newProvider else { return }
                    self.updateAvailableModels(force: true)
                    await AISessionManager.shared.prewarm(provider: newProvider, config: self.config)
                }
            }
        }
    }
    
    @Published public var isAppleModelAvailable: Bool = false
    @Published public var appleModelStatus: String = ""
    @Published public var availableModels: [String] = []
    @Published public var isLoadingModels: Bool = false
    
    private let userDefaults: UserDefaults
    private let credentialStore: SettingsCredentialStore
    private let configKey = "aiConfig"
    private let disableStoredCredentialsForUITestsKey = "uitestDisableStoredProviderCredentials"
    private let providerHealthCheckModeForUITestsKey = "uitestProviderHealthCheckMode"
    private let providerHealthCheckFailedOnceForUITestsKey = "uitestProviderHealthCheckFailedOnce"
    private var saveTask: Task<Void, Never>?
    private var credentialTask: Task<Void, Never>?
    private var credentialHydrationID: UUID?
    private var credentialHydrationProvider: AIProvider?
    private var isApplyingConfigMutation = false

    private func modelSelectionKey(for provider: AIProvider) -> String {
        "lastSelectedModel_\(provider.rawValue)"
    }
    
    public init() {
        userDefaults = .standard
        credentialStore = .keychain
        loadConfig()
        checkAppleModelAvailability()
        setupNotificationObservers()
    }

    init(
        userDefaults: UserDefaults,
        credentialStore: SettingsCredentialStore,
        observesNotifications: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.credentialStore = credentialStore
        loadConfig()
        checkAppleModelAvailability()
        if observesNotifications {
            setupNotificationObservers()
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.reset()
        }
    }
    
    private func loadConfig() {
        if let data = userDefaults.data(forKey: configKey),
           var decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            decoded.apiKey = nil

            decoded.enableSmartRename = true
            isApplyingConfigMutation = true
            config = decoded
            isApplyingConfigMutation = false
        }

        let provider = config.provider
        let authMethod = config.authMethod(for: provider)
        guard !userDefaults.bool(forKey: disableStoredCredentialsForUITestsKey),
              provider != .githubCopilot,
              provider.typicallyRequiresAPIKey,
              authMethod == .apiKey else { return }
        hydrateStoredCredential(for: provider, authMethod: authMethod, migratesLegacyKey: true)
    }

    private func setInMemoryAPIKey(_ apiKey: String?) {
        isApplyingConfigMutation = true
        config.apiKey = apiKey
        isApplyingConfigMutation = false
    }

    private func persistCredential(_ apiKey: String, for provider: AIProvider) {
        Task { [credentialStore] in
            _ = await credentialStore.save(provider.keychainKey, apiKey)
        }
    }

    private func hydrateStoredCredential(
        for provider: AIProvider,
        authMethod: ProviderAuthMethod,
        migratesLegacyKey: Bool = false
    ) {
        cancelCredentialHydration()
        let hydrationID = UUID()
        credentialHydrationID = hydrationID
        credentialHydrationProvider = provider
        credentialTask = Task { [weak self, credentialStore] in
            if migratesLegacyKey,
               let oldAPIKey = await credentialStore.load("apiKey"),
               await credentialStore.load(provider.keychainKey) == nil {
                _ = await credentialStore.save(provider.keychainKey, oldAPIKey)
            }

            guard !Task.isCancelled else { return }
            let apiKey = await credentialStore.load(provider.keychainKey)
            guard !Task.isCancelled,
                  let self,
                  self.credentialHydrationID == hydrationID else { return }
            self.credentialTask = nil
            self.credentialHydrationID = nil
            self.credentialHydrationProvider = nil
            guard
                  self.config.provider == provider,
                  self.config.authMethod(for: provider) == authMethod else { return }
            self.setInMemoryAPIKey(apiKey)
        }
    }

    private func cancelCredentialHydration() {
        credentialTask?.cancel()
        credentialTask = nil
        credentialHydrationID = nil
        credentialHydrationProvider = nil
    }
    
    /// Debounced save that batches rapid changes
    private func debouncedSave() {
        // Cancel any existing save task
        saveTask?.cancel()
        
        // Create new delayed save task
        saveTask = Task { @MainActor in
            // Wait 0.5 seconds before saving
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Only save if task wasn't cancelled
            guard !Task.isCancelled else { return }
            
            await performSave()
        }
    }
    
    /// Immediate save for when app terminates or explicit save is needed
    public func forceSave() {
        saveTask?.cancel()
        Task { @MainActor in
            await performSave()
        }
    }
    
    private func performSave() async {
        // Capture values for thread-safe access
        let apiKey = config.apiKey
        let provider = config.provider
        var configToSave = config
        configToSave.apiKey = nil // Don't store in UserDefaults
        let configData = try? JSONEncoder().encode(configToSave)
        
        DebugLogger.log(hypothesisId: "B", location: "SettingsViewModel", message: "Saving config (debounced)", data: [
            "hasAPIKey": apiKey != nil,
            "provider": provider.rawValue
        ])
        
        // Save API key to provider-specific Keychain key
        if provider != .githubCopilot,
           provider.typicallyRequiresAPIKey,
           config.authMethod(for: provider) == .apiKey {
            let providerKey = provider.keychainKey
            if let apiKey = apiKey {
                _ = await credentialStore.save(providerKey, apiKey)
            } else if credentialHydrationProvider != provider {
                _ = await credentialStore.delete(providerKey)
            }
        }
        
        // Save config to UserDefaults
        if let encoded = configData {
            userDefaults.set(encoded, forKey: configKey)
        }
    }
    
    private func checkAppleModelAvailability() {
        #if canImport(FoundationModels) && os(macOS)
        if #available(macOS 26.0, *) {
            isAppleModelAvailable = AppleFoundationModelClient.isAvailable()
            appleModelStatus = AppleFoundationModelClient.unavailabilityReason
        } else {
            isAppleModelAvailable = false
            appleModelStatus = "Apple Intelligence requires macOS 26.0 or later."
        }
        #else
        isAppleModelAvailable = false
        appleModelStatus = "Apple Intelligence is not supported on this version of macOS."
        #endif
    }

    public func refreshAppleModelStatus() {
        checkAppleModelAvailability()
    }
    
    public func testConnection() async throws {
        if let uiTestOverride = userDefaults.string(forKey: providerHealthCheckModeForUITestsKey) {
            switch uiTestOverride {
            case "always_succeed":
                return
            case "always_fail":
                throw AIClientError.apiError(statusCode: 503, message: "UI test forced provider health-check failure.")
            case "fail_once_then_succeed":
                if !userDefaults.bool(forKey: providerHealthCheckFailedOnceForUITestsKey) {
                    userDefaults.set(true, forKey: providerHealthCheckFailedOnceForUITestsKey)
                    throw AIClientError.apiError(statusCode: 503, message: "UI test forced provider health-check failure.")
                }
                return
            default:
                break
            }
        }

        let clientConfig = config
        let client = try AIClientFactory.createClient(config: clientConfig)
        try await client.checkHealth()
    }
    
    public func updateAvailableModels(force: Bool = false) {
        Task {
            let loadStartedAt = Date()
            await MainActor.run {
                self.isLoadingModels = true
            }
            
            await ModelCatalog.shared.refresh(provider: config.provider, force: force)
            let catalogModels = ModelCatalog.shared.cachedModels(for: config.provider)
            
            await MainActor.run {
                if !catalogModels.isEmpty {
                    self.availableModels = catalogModels.map { $0.id }
                } else {
                    self.availableModels = config.provider.recommendedModels
                }
                
                if !self.availableModels.isEmpty && !self.availableModels.contains(self.config.model) {
                    self.config.model = self.availableModels.first ?? config.provider.defaultModel
                }
                self.isLoadingModels = false
                AnalyticsManager.shared.captureWorkflow(
                    workflow: "model_catalog",
                    stage: "loaded",
                    outcome: catalogModels.isEmpty ? "fallback" : "success",
                    properties: AnalyticsManager.durationProperties(
                        Date().timeIntervalSince(loadStartedAt)
                    ).merging(["source": "settings"]) { current, _ in current }
                )
            }
        }
    }

    public func reset() {
        // Clear per-provider saved model selections
        for provider in AIProvider.allCases {
            userDefaults.removeObject(forKey: modelSelectionKey(for: provider))
        }
        config = .default
        availableModels = config.provider.recommendedModels
        // No need to save manually here as config.didSet will trigger debouncedSave,
        // but since we want to clear from UserDefaults, we already handled it in AppState.
    }
}

//
//  SettingsViewModel.swift
//  Sorty
//
//  Manages API configuration and settings
//

import Foundation
import Combine

@MainActor
public class SettingsViewModel: ObservableObject {
    @Published public var config: AIConfig = .default {
        didSet {
            let oldKey = oldValue.apiKey
            let newKey = config.apiKey
            let oldProvider = oldValue.provider
            let newProvider = config.provider

            // Persist model changes immediately for the active provider.
            if oldProvider == newProvider, oldValue.model != config.model {
                userDefaults.set(config.model, forKey: modelSelectionKey(for: newProvider))
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
                // Save the old provider's selected model so it can be restored later
                userDefaults.set(oldValue.model, forKey: modelSelectionKey(for: oldProvider))

                // Save the old provider's API key to its keychain slot
                // Skip for GitHub Copilot — its token is managed by GitHubCopilotAuthManager
                if oldProvider != .githubCopilot, let oldKey = oldValue.apiKey, !oldKey.isEmpty {
                    _ = KeychainManager.save(key: oldProvider.keychainKey, value: oldKey)
                }

                // Load the new provider's API key from its keychain slot
                // Skip for GitHub Copilot — auth is handled by GitHubCopilotAuthManager, not apiKey
                if newProvider == .githubCopilot {
                    config.apiKey = nil
                } else {
                    config.apiKey = KeychainManager.get(key: newProvider.keychainKey)
                }

                // Update API URL and requiresAPIKey for the new provider
                config.apiURL = newProvider.defaultAPIURL
                config.requiresAPIKey = newProvider.typicallyRequiresAPIKey

                // Restore previously selected model for this provider, or fall back to default
                config.model = userDefaults.string(forKey: modelSelectionKey(for: newProvider)) ?? newProvider.defaultModel
                userDefaults.set(config.model, forKey: modelSelectionKey(for: newProvider))

                // Invalidate sessions for new provider URL
                AISessionManager.shared.invalidateAll()

                // Refresh model list for the new provider
                updateAvailableModels(force: true)

                // Auto-check connection after a short delay
                // For GitHub Copilot, skip apiKey check since auth is token-based
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if newProvider == .githubCopilot || config.apiKey != nil {
                        try? await testConnection()
                    }
                    await AISessionManager.shared.prewarm(provider: newProvider, config: config)
                }
            } else if oldKey != newKey, let newKey = newKey, !newKey.isEmpty {
                // Same provider, API key changed — save immediately to Keychain
                // so ModelCatalog reads the fresh key (fixes Gemini model list race)
                _ = KeychainManager.save(key: newProvider.keychainKey, value: newKey)

                // Now refresh models (key is already in Keychain)
                updateAvailableModels(force: true)

                // Prewarm connection
                Task {
                    await AISessionManager.shared.prewarm(provider: newProvider, config: config)
                }
            }
        }
    }
    
    @Published public var isAppleModelAvailable: Bool = false
    @Published public var appleModelStatus: String = ""
    @Published public var availableModels: [String] = []
    @Published public var isLoadingModels: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "aiConfig"
    private var saveTask: Task<Void, Never>?

    private func modelSelectionKey(for provider: AIProvider) -> String {
        "lastSelectedModel_\(provider.rawValue)"
    }
    
    public init() {
        loadConfig()
        checkAppleModelAvailability()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.reset()
        }
    }
    
    private func loadConfig() {
        if let data = userDefaults.data(forKey: configKey),
           var decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            
            // 1. Check for legacy generic key
            if let oldApiKey = KeychainManager.get(key: "apiKey") {
                // Migrate to provider-specific key if it doesn't exist yet
                let providerKey = decoded.provider.keychainKey
                if KeychainManager.get(key: providerKey) == nil {
                    _ = KeychainManager.save(key: providerKey, value: oldApiKey)
                }
                // Optional: Cleanup old key after transition period
            }
            
            // 2. Load API key from provider-specific Keychain key
            if let apiKey = KeychainManager.get(key: decoded.provider.keychainKey) {
                decoded.apiKey = apiKey
            }
            
            config = decoded
        }
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
        if provider != .githubCopilot {
            let providerKey = provider.keychainKey
            if let apiKey = apiKey {
                _ = KeychainManager.save(key: providerKey, value: apiKey)
            } else {
                _ = KeychainManager.delete(key: providerKey)
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
        let clientConfig = config
        let client = try AIClientFactory.createClient(config: clientConfig)
        // Use lightweight health check endpoint (e.g., /models) instead of inference
        // This avoids unnecessary token usage and is faster
        try await client.checkHealth()
    }
    
    public func updateAvailableModels(force: Bool = false) {
        Task {
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

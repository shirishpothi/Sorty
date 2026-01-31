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
            
            saveConfig()
            
            // If smart rename is disabled, ensure mode is set to .organize
            if !config.enableSmartRename && config.mode != .organize {
                config.mode = .organize
            }
            
            // Force refresh models if provider changed or API key was updated
            if oldProvider != newProvider || (oldKey != newKey && newKey != nil) {
                updateAvailableModels(force: true)
                
                // Prewarm connection when API key is configured
                if newKey != nil {
                    Task {
                        await AISessionManager.shared.prewarm(provider: newProvider, config: config)
                    }
                }
            }
        }
    }
    
    @Published public var isAppleIntelligenceAvailable: Bool = false
    @Published public var appleIntelligenceStatus: String = ""
    @Published public var availableModels: [String] = []
    @Published public var isLoadingModels: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "aiConfig"
    
    public init() {
        loadConfig()
        checkAppleIntelligenceAvailability()
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
    
    private func saveConfig() {
        // Capture values for thread-safe access
        let apiKey = config.apiKey
        let provider = config.provider
        var configToSave = config
        configToSave.apiKey = nil // Don't store in UserDefaults
        let configData = try? JSONEncoder().encode(configToSave)
        
        DebugLogger.log(hypothesisId: "B", location: "SettingsViewModel", message: "Saving config", data: [
            "hasAPIKey": apiKey != nil,
            "provider": provider.rawValue
        ])
        
        // Save API key to provider-specific Keychain key
        if provider != .githubCopilot {
            let providerKey = provider.keychainKey
            if let apiKey = apiKey {
                _ = KeychainManager.save(key: providerKey, value: apiKey)
                // Also update the generic "apiKey" for components that still rely on it
                _ = KeychainManager.save(key: "apiKey", value: apiKey)
            } else {
                _ = KeychainManager.delete(key: providerKey)
            }
        }
        
        // Save config to UserDefaults
        if let encoded = configData {
            userDefaults.set(encoded, forKey: configKey)
        }
    }
    
    private func checkAppleIntelligenceAvailability() {
        #if canImport(FoundationModels) && os(macOS)
        if #available(macOS 26.0, *) {
            isAppleIntelligenceAvailable = AppleFoundationModelClient.isAvailable()
            appleIntelligenceStatus = AppleFoundationModelClient.unavailabilityReason
        } else {
            isAppleIntelligenceAvailable = false
            appleIntelligenceStatus = "Apple Intelligence requires macOS 26.0 or later."
        }
        #else
        isAppleIntelligenceAvailable = false
        appleIntelligenceStatus = "Apple Intelligence is not supported on this version of macOS."
        #endif
    }
    
    public func refreshAppleIntelligenceStatus() {
        checkAppleIntelligenceAvailability()
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
}


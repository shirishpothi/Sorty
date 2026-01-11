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
            saveConfig()
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
            // Migrate API key from UserDefaults to Keychain if it exists in UserDefaults
            if let oldApiKey = decoded.apiKey, !oldApiKey.isEmpty {
                // Check if already in Keychain
                if KeychainManager.get(key: "apiKey") == nil {
                    // Migrate to Keychain
                    _ = KeychainManager.save(key: "apiKey", value: oldApiKey)
                }
            }
            
            // Load API key from Keychain (preferred source)
            if let apiKey = KeychainManager.get(key: "apiKey") {
                decoded.apiKey = apiKey
            }
            config = decoded
        }
    }
    
    private func saveConfig() {
        // Capture values for thread-safe access
        let apiKey = config.apiKey
        let provider = config.provider.rawValue
        var configToSave = config
        configToSave.apiKey = nil // Don't store in UserDefaults
        let configData = try? JSONEncoder().encode(configToSave)
        
        DebugLogger.log(hypothesisId: "B", location: "SettingsViewModel", message: "Saving config", data: [
            "hasAPIKey": apiKey != nil,
            "provider": provider
        ])
        
        // Save API key to Keychain securely
        if let apiKey = apiKey {
            _ = KeychainManager.save(key: "apiKey", value: apiKey)
        } else {
            _ = KeychainManager.delete(key: "apiKey")
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
        // Test with a minimal file list
        let testFiles = [
            FileItem(path: "/test/file1.txt", name: "file1", extension: "txt"),
            FileItem(path: "/test/file2.pdf", name: "file2", extension: "pdf")
        ]
        _ = try await client.analyze(files: testFiles, customInstructions: nil, personaPrompt: nil, temperature: clientConfig.temperature)
    }
    
    public func updateAvailableModels() {
        guard config.provider == .githubCopilot else {
            // For other providers, we don't dynamically fetch models yet
            return
        }
        
        Task {
            await MainActor.run {
                self.isLoadingModels = true
            }
            
            do {
                // Create a temporary client just for fetching models, using current config
                if let client = try AIClientFactory.createClient(config: config) as? GitHubCopilotClient {
                    let models = try await client.fetchAvailableModels()
                    await MainActor.run {
                        self.availableModels = models
                        // Ensure current model is valid
                        if !models.contains(self.config.model) {
                            self.config.model = models.first ?? "gpt-4"
                        }
                        self.isLoadingModels = false
                    }
                }
            } catch let fetchError {
                DebugLogger.log("Error fetching models: \(fetchError)")
                await MainActor.run {
                    self.isLoadingModels = false
                }
            }
        }
    }
}


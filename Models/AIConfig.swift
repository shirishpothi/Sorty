//
//  AIConfig.swift
//  FileOrganizer
//
//  AI Configuration Model
//

import Foundation

public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case openAICompatible = "openai_compatible"
    case appleFoundationModel = "apple_foundation_model"
    
    public var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI-Compatible API"
        case .appleFoundationModel:
            return "Apple Foundation Model"
        }
    }
    
    public var isAvailable: Bool {
        switch self {
        case .openAICompatible:
            return true
        case .appleFoundationModel:
            #if canImport(FoundationModels) && os(macOS)
            if #available(macOS 26.0, *) {
                return AppleFoundationModelClient.isAvailable()
            }
            #endif
            return false
        }
    }
    
    public var unavailabilityReason: String? {
        switch self {
        case .openAICompatible:
            return nil
        case .appleFoundationModel:
            #if canImport(FoundationModels) && os(macOS)
            if #available(macOS 26.0, *) {
                return AppleFoundationModelClient.unavailabilityReason
            }
            #endif
            return "Apple Intelligence is not supported on this version of macOS."
        }
    }
}

public struct AIConfig: Codable, Sendable {
    public var provider: AIProvider
    public var apiURL: String?
    public var apiKey: String?
    public var model: String
    public var temperature: Double
    
    // Advanced Settings
    public var requestTimeout: TimeInterval
    public var resourceTimeout: TimeInterval
    public var systemPromptOverride: String?
    public var maxTokens: Int?
    public var enableStreaming: Bool
    public var requiresAPIKey: Bool
    public var enableReasoning: Bool  // Ask AI to explain organization decisions
    
    // Deep Scanning & Duplicate Detection
    public var enableDeepScan: Bool   // Analyze file content (PDF text, EXIF, etc.)
    public var detectDuplicates: Bool // Find duplicate files by hash
    
    public init(
        provider: AIProvider = .openAICompatible,
        apiURL: String? = nil,
        apiKey: String? = nil,
        model: String = "gpt-4",
        temperature: Double = 0.7,
        requestTimeout: TimeInterval = 120,
        resourceTimeout: TimeInterval = 600,
        systemPromptOverride: String? = nil,
        maxTokens: Int? = nil,
        enableStreaming: Bool = true,
        requiresAPIKey: Bool = true,
        enableReasoning: Bool = false,
        enableDeepScan: Bool = false,
        detectDuplicates: Bool = false
    ) {
        self.provider = provider
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.systemPromptOverride = systemPromptOverride
        self.maxTokens = maxTokens
        self.enableStreaming = enableStreaming
        self.requiresAPIKey = requiresAPIKey
        self.enableReasoning = enableReasoning
        self.enableDeepScan = enableDeepScan
        self.detectDuplicates = detectDuplicates
    }
    
    public static let `default` = AIConfig(
        provider: .openAICompatible,
        apiURL: "https://api.openai.com",
        model: "gpt-4",
        temperature: 0.7,
        requestTimeout: 120,
        resourceTimeout: 600,
        systemPromptOverride: nil,
        maxTokens: nil,
        enableStreaming: true,
        requiresAPIKey: true,
        enableReasoning: false,
        enableDeepScan: false,
        detectDuplicates: false
    )
}


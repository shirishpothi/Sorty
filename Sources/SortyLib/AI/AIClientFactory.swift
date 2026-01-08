//
//  AIClientFactory.swift
//  Sorty
//
//  Factory for creating appropriate AI client
//

import Foundation

struct AIClientFactory {
    static func createClient(config: AIConfig) throws -> AIClientProtocol {
        switch config.provider {
        case .openAI, .groq, .openAICompatible, .openRouter, .ollama:
            return OpenAIClient(config: config)
            
        case .githubCopilot:
            return GitHubCopilotClient(config: config)
            
        case .anthropic:
            return AnthropicClient(config: config)
            
        case .appleFoundationModel:
            #if canImport(FoundationModels) && os(macOS)
            if #available(macOS 26.0, *) {
                if AppleFoundationModelClient.isAvailable() {
                    return AppleFoundationModelClient(config: config)
                }
            }
            #endif
            throw AIClientError.apiError(statusCode: 501, message: "Apple Intelligence is not supported on this version of macOS.")
        }
    }
}




//
//  AIClientFactory.swift
//  Sorty
//
//  Factory for creating appropriate AI client
//

import Foundation

public struct AIClientFactory {
    public static func createClient(config: AIConfig) throws -> AIClientProtocol {
        if config.usesApplePrivateCloudCompute {
            #if canImport(FoundationModels) && os(macOS)
            if #available(macOS 26.0, *),
               !ApplePrivateCloudComputeClient.isShortcutInstalled(),
               AppleFoundationModelClient.isAvailable() {
                return AppleFoundationModelClient(config: config)
            }
            #endif
            return ApplePrivateCloudComputeClient(config: config)
        }

        switch config.provider {
        case .openAI, .groq, .openAICompatible, .openRouter, .ollama, .gemini:
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
            
        case .applePrivateCloudCompute:
            guard FeatureFlags.applePrivateCloudComputeModelEnabled else {
                throw AIClientError.apiError(
                    statusCode: 403,
                    message: "Apple Private Cloud Compute is disabled by feature flag."
                )
            }
            return ApplePrivateCloudComputeClient(config: config)
        }
    }
}


//
//  AIClientFactory.swift
//  Sorty
//
//  Factory for creating appropriate AI client
//

import Foundation

public struct AIClientFactory {
    public static func createClient(
        config: AIConfig,
        entitlements: EntitlementSnapshot = EntitlementRuntime.currentSnapshot
    ) throws -> AIClientProtocol {
        let provider = config.provider
        let authMethod = config.authMethod(for: provider)

        guard entitlements.isProviderSelectable(provider),
              entitlements.isProviderAllowed(provider, authMethod: authMethod) else {
            throw AIClientError.apiError(
                statusCode: 403,
                message: entitlements.providerRestrictionMessage(for: provider, authMethod: authMethod)
            )
        }

        let gatedConfig = entitlements.sanitized(config)

        switch gatedConfig.provider {
        case .openAI:
            if ProviderAuthResolver.effectiveAuthMethod(for: .openAI, config: gatedConfig) == .accountSignIn {
                return CodexSubscriptionClient(config: gatedConfig)
            }
            return OpenAIClient(config: gatedConfig)

        case .groq, .openAICompatible, .openRouter, .ollama, .gemini:
            return OpenAIClient(config: gatedConfig)
            
        case .githubCopilot:
            return GitHubCopilotClient(config: gatedConfig)
            
        case .anthropic:
            return AnthropicClient(config: gatedConfig)
            
        case .appleFoundationModel:
            #if canImport(FoundationModels) && os(macOS)
            if #available(macOS 26.0, *) {
                if AppleFoundationModelClient.isAvailable() {
                    return AppleFoundationModelClient(config: gatedConfig)
                }
            }
            #endif
            throw AIClientError.apiError(statusCode: 501, message: "Apple Intelligence is not supported on this version of macOS.")
        }
    }
}

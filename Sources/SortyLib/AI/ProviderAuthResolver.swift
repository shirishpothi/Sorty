import Foundation

enum ProviderAuthResolver {
    typealias Header = (field: String, value: String)
    private static let subscriptionAuthFlagKey = "subscriptionAuthEnabled"

    static func authHeaders(for provider: AIProvider, config: AIConfig) -> [String: String] {
        guard let header = authHeader(for: provider, config: config) else {
            return [:]
        }
        return [header.field: header.value]
    }

    static func authHeader(for provider: AIProvider, config: AIConfig) -> Header? {
        let method = effectiveAuthMethod(for: provider, config: config)

        guard let credential = credential(for: provider, method: method, config: config), !credential.isEmpty else {
            return nil
        }

        switch provider {
        case .openAI, .groq, .openRouter, .openAICompatible:
            return ("Authorization", "Bearer \(credential)")
        case .anthropic:
            if method == .apiKey {
                return ("x-api-key", credential)
            }
            return ("Authorization", "Bearer \(credential)")
        case .gemini:
            return ("x-goog-api-key", credential)
        case .githubCopilot, .ollama, .appleFoundationModel:
            return nil
        }
    }

    static func hasRequiredCredential(for provider: AIProvider, config: AIConfig) -> Bool {
        guard config.requiresAPIKey else {
            return true
        }

        switch provider {
        case .githubCopilot, .ollama, .appleFoundationModel:
            return true
        default:
            return authHeader(for: provider, config: config) != nil
        }
    }

    static func effectiveAuthMethod(for provider: AIProvider, config: AIConfig) -> ProviderAuthMethod {
        guard isSubscriptionAuthEnabled, provider.supportsSubscriptionAuth else {
            return .apiKey
        }
        return config.authMethod(for: provider)
    }

    private static var isSubscriptionAuthEnabled: Bool {
        if UserDefaults.standard.object(forKey: subscriptionAuthFlagKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: subscriptionAuthFlagKey)
    }

    private static func credential(for provider: AIProvider, method: ProviderAuthMethod, config: AIConfig) -> String? {
        switch method {
        case .apiKey:
            return configuredOrStoredAPIKey(for: provider, config: config)
        case .accountSignIn:
            if provider == .openAI {
                return CodexCLIAuthManager.readAccessToken()
            }
            return configuredOrStoredAPIKey(for: provider, config: config)
        case .manualSessionToken:
            return configuredOrStoredAPIKey(for: provider, config: config)
        }
    }

    private static func configuredOrStoredAPIKey(for provider: AIProvider, config: AIConfig) -> String? {
        if let key = config.apiKey, !key.isEmpty {
            return key
        }
        return KeychainManager.get(key: provider.keychainKey)
    }
}

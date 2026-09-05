import Foundation

public enum ProviderAuthResolver {
    typealias Header = (field: String, value: String)
    private static let subscriptionAuthFlagKey = "subscriptionAuthEnabled"
    private static let disableStoredCredentialsForUITestsKey = "uitestDisableStoredProviderCredentials"

    static func authHeaders(for provider: AIProvider, config: AIConfig) -> [String: String] {
        guard let header = authHeader(for: provider, config: config) else {
            return [:]
        }
        return [header.field: header.value]
    }

    static func authHeader(for provider: AIProvider, config: AIConfig) -> Header? {
        let method = effectiveAuthMethod(for: provider, config: config)

        guard let rawCredential = credential(for: provider, method: method, config: config) else {
            return nil
        }

        let credential = rawCredential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !credential.isEmpty else {
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
        switch provider {
        case .githubCopilot:
            return KeychainManager.get(key: provider.keychainKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
        case .ollama, .appleFoundationModel:
            return true
        default:
            let method = effectiveAuthMethod(for: provider, config: config)
            switch method {
            case .accountSignIn:
                if provider == .openAI {
                    return CodexCLIAuthManager.hasUsableSubscriptionLogin()
                }
                return authHeader(for: provider, config: config) != nil
            case .manualSessionToken:
                return authHeader(for: provider, config: config) != nil
            case .apiKey:
                guard config.requiresAPIKey else {
                    return true
                }
                return authHeader(for: provider, config: config) != nil
            }
        }
    }

    public static func effectiveAuthMethod(for provider: AIProvider, config: AIConfig) -> ProviderAuthMethod {
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
            // Codex ChatGPT/account credentials are consumed by `codex exec`, not
            // by Sorty's direct OpenAI API client.
            if provider == .openAI {
                return nil
            }
            return configuredOrStoredAPIKey(for: provider, config: config)
        case .manualSessionToken:
            return configuredOrStoredAPIKey(for: provider, config: config)
        }
    }

    private static func configuredOrStoredAPIKey(for provider: AIProvider, config: AIConfig) -> String? {
        if let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        if UserDefaults.standard.bool(forKey: disableStoredCredentialsForUITestsKey) {
            return nil
        }
        return KeychainManager.get(key: provider.keychainKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
//  AISessionManager.swift
//  Sorty
//
//  Manages URLSession pooling and connection prewarming for AI clients.
//  Reduces latency by reusing connections and prewarming before organization.
//

import Foundation
import Combine

/// Manages shared URLSession instances for AI providers
@MainActor
public class AISessionManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = AISessionManager()
    
    // MARK: - Properties
    
    /// Cached sessions per provider
    private var sessions: [AIProvider: URLSession] = [:]
    
    /// Last usage time for cleanup
    private var lastUsed: [AIProvider: Date] = [:]
    
    /// Prewarming status
    @Published public private(set) var prewarmingProvider: AIProvider?
    @Published public private(set) var isPrewarmed: Bool = false
    @Published public private(set) var prewarmError: String?
    
    /// Session timeout for cleanup (10 minutes of inactivity)
    private let sessionTimeout: TimeInterval = 10 * 60
    
    /// Cleanup task
    private var cleanupTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    private init() {
        scheduleCleanup()
    }
    
    // MARK: - Session Management
    
    /// Get or create a URLSession for a provider
    public func session(for provider: AIProvider, config: AIConfig) -> URLSession {
        // Update last used time
        lastUsed[provider] = Date()
        
        // Return existing session if available
        if let existing = sessions[provider] {
            return existing
        }
        
        // Create new session with optimized configuration
        let sessionConfig = createSessionConfiguration(for: provider, aiConfig: config)
        let session = URLSession(configuration: sessionConfig)
        sessions[provider] = session
        
        LogManager.shared.log("Created new session for \(provider.displayName)", category: "AISessionManager")
        
        return session
    }
    
    /// Check if a provider has a valid API key configured
    private func hasValidAPIKey(for provider: AIProvider) -> Bool {
        switch provider {
        case .openAI, .anthropic, .gemini, .groq, .openRouter, .openAICompatible:
            guard let key = KeychainManager.get(key: provider.keychainKey), !key.isEmpty else {
                return false
            }
            return true
        case .githubCopilot:
            // GitHub Copilot uses a different auth mechanism
            return true
        case .ollama:
            // Local provider - always available if reachable
            return true
        case .appleFoundationModel:
            // On-device model - always available
            return true
        }
    }
    
    /// Prewarm connection for a provider (call when user selects folder)
    public func prewarm(provider: AIProvider, config: AIConfig) async {
        guard prewarmingProvider == nil else { return }

        prewarmingProvider = provider
        prewarmError = nil
        isPrewarmed = false

        defer {
            prewarmingProvider = nil
        }

        // Skip prewarming for local/on-device providers
        switch provider {
        case .ollama, .appleFoundationModel:
            isPrewarmed = true
            return
        default:
            break
        }

        do {
            let session = session(for: provider, config: config)

            // Try the models endpoint first, then fallback to base URL if it fails
            // This handles custom setups (Azure, proxies, enterprise gateways) where
            // the standard /v1/models path may not exist
            let prewarmURLs = getPrewarmURLs(for: provider, config: config)

            guard !prewarmURLs.isEmpty else {
                prewarmError = "Invalid API URL"
                return
            }

            // Try each URL in order (specific endpoint first, then root)
            for (index, url) in prewarmURLs.enumerated() {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 5

                addAuthHeaders(to: &request, provider: provider, config: config)

                do {
                    let (_, response) = try await session.data(for: request)

                    if let httpResponse = response as? HTTPURLResponse {
                        // Any response (including 404) means connection is established
                        // 404 on models endpoint is OK for custom/proxy setups
                        let isSuccess = (200...299).contains(httpResponse.statusCode) || httpResponse.statusCode == 404

                        if isSuccess {
                            LogManager.shared.log("Prewarmed \(provider.displayName): HTTP \(httpResponse.statusCode) at \(url.absoluteString)", category: "AISessionManager")
                            isPrewarmed = true
                            prewarmError = nil
                            return
                        } else {
                            // Non-success status, try next URL
                            LogManager.shared.log("Prewarm attempt \(index + 1) for \(provider.displayName): HTTP \(httpResponse.statusCode) at \(url.absoluteString)", category: "AISessionManager")
                        }
                    }
                } catch {
                    // This URL failed, try the next one
                    LogManager.shared.log("Prewarm attempt \(index + 1) failed for \(provider.displayName): \(error.localizedDescription)", category: "AISessionManager")
                    continue
                }
            }

            // All URLs failed
            prewarmError = "Could not establish connection to \(provider.displayName)"
            isPrewarmed = false

        } catch {
            // Connection failed, but that's okay - we tried
            LogManager.shared.log("Prewarm failed for \(provider.displayName): \(error.localizedDescription)", category: "AISessionManager")
            prewarmError = error.localizedDescription
            // Session is still created and may work when the actual request is made
            isPrewarmed = false
        }
    }
    
    /// Prewarm all configured providers in parallel
    public func prewarmAllConfigured() async {
        let configuredProviders = AIProvider.allCases.filter { hasValidAPIKey(for: $0) }
        
        guard !configuredProviders.isEmpty else {
            LogManager.shared.log("No configured providers to prewarm", category: "AISessionManager")
            return
        }
        
        LogManager.shared.log("Prewarming \(configuredProviders.count) configured providers in parallel...", category: "AISessionManager")
        
        await withTaskGroup(of: Void.self) { group in
            for provider in configuredProviders {
                group.addTask {
                    let config = AIConfig(
                        provider: provider,
                        apiKey: nil, // Will be fetched from Keychain by clients
                        model: "default"
                    )
                    await self.prewarm(provider: provider, config: config)
                }
            }
        }
        
        LogManager.shared.log("Parallel prewarm complete for all configured providers", category: "AISessionManager")
    }
    
    /// Get the appropriate URLs for prewarming (models endpoint and fallback to base URL)
    /// Returns array of URLs to try in order - specific endpoint first, then root URL
    private func getPrewarmURLs(for provider: AIProvider, config: AIConfig) -> [URL] {
        let baseURLString = (config.apiURL?.isEmpty ?? true) ? provider.defaultAPIURL : config.apiURL

        guard var urlString = baseURLString else { return [] }

        var urls: [URL] = []

        // First try the specific models endpoint
        var modelsURLString = urlString
        switch provider {
        case .openAI, .groq:
            modelsURLString = urlString.hasSuffix("/") ? urlString + "v1/models" : urlString + "/v1/models"
        case .anthropic:
            modelsURLString = urlString.hasSuffix("/") ? urlString + "v1/models" : urlString + "/v1/models"
        case .gemini:
            modelsURLString = urlString.hasSuffix("/") ? urlString + "v1/models" : urlString + "/v1/models"
        case .openRouter:
            modelsURLString = urlString.hasSuffix("/") ? urlString + "api/v1/models" : urlString + "/api/v1/models"
        case .githubCopilot:
            modelsURLString = urlString.hasSuffix("/") ? urlString + "models" : urlString + "/models"
        case .ollama:
            modelsURLString = urlString.hasSuffix("/") ? urlString + "api/tags" : urlString + "/api/tags"
        case .openAICompatible:
            modelsURLString = urlString.hasSuffix("/") ? urlString + "v1/models" : urlString + "/v1/models"
        case .appleFoundationModel:
            return [] // No prewarming needed for on-device
        }

        if let modelsURL = URL(string: modelsURLString) {
            urls.append(modelsURL)
        }

        // Add base URL as fallback for custom setups (Azure, proxies, enterprise gateways)
        // where the models endpoint might not exist but the base connection works
        if let baseURL = URL(string: urlString) {
            // Only add if different from models URL
            if urls.isEmpty || baseURL.absoluteString != modelsURLString {
                urls.append(baseURL)
            }
        }

        return urls
    }
    
    /// Invalidate session for a provider (e.g., after auth failure)
    public func invalidate(provider: AIProvider) {
        if let session = sessions[provider] {
            session.invalidateAndCancel()
            sessions.removeValue(forKey: provider)
            lastUsed.removeValue(forKey: provider)
            LogManager.shared.log("Invalidated session for \(provider.displayName)", category: "AISessionManager")
        }
        
        if prewarmingProvider == provider {
            isPrewarmed = false
        }
    }
    
    /// Invalidate all sessions
    public func invalidateAll() {
        for (provider, session) in sessions {
            session.invalidateAndCancel()
            LogManager.shared.log("Invalidated session for \(provider.displayName)", category: "AISessionManager")
        }
        sessions.removeAll()
        lastUsed.removeAll()
        isPrewarmed = false
    }
    
    // MARK: - Configuration
    
    private func createSessionConfiguration(for provider: AIProvider, aiConfig: AIConfig) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        
        // Enable HTTP/2 for better performance
        config.httpAdditionalHeaders = [
            "Accept-Encoding": "gzip, deflate",
            "Connection": "keep-alive"
        ]
        
        // Connection establishment timeout (fast for initial connection)
        config.timeoutIntervalForRequest = 10  // 10 seconds for connection establishment
        config.timeoutIntervalForResource = 180  // 3 minutes for streaming responses
        
        // Enable connection reuse - critical for performance
        config.httpMaximumConnectionsPerHost = 6
        config.urlCache = nil  // No caching for AI requests
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        // Enable TLS 1.3 where available for faster handshakes
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        
        // TCP connection optimization
        config.shouldUseExtendedBackgroundIdleMode = true
        config.sessionSendsLaunchEvents = false
        
        return config
    }
    
    /// Update session timeout for streaming operations
    public func configureForStreaming(for provider: AIProvider) {
        // Sessions are already configured with appropriate timeouts
        // This method exists for future streaming-specific optimizations
        LogManager.shared.log("Session configured for streaming: \(provider.displayName)", category: "AISessionManager")
    }
    
    private func getBaseURL(for provider: AIProvider, config: AIConfig) -> URL? {
        let urlString = (config.apiURL?.isEmpty ?? true) ? provider.defaultAPIURL : config.apiURL
        guard let urlString = urlString else { return nil }
        return URL(string: urlString)
    }
    
    private func addAuthHeaders(to request: inout URLRequest, provider: AIProvider, config: AIConfig) {
        // Add appropriate auth headers based on provider
        // For prewarming, fetch from Keychain if config doesn't have the key
        let apiKey = (config.apiKey?.isEmpty ?? true) ? KeychainManager.get(key: provider.keychainKey) : config.apiKey
        
        switch provider {
        case .openAI, .groq, .openRouter, .openAICompatible:
            if let key = apiKey, !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            if let key = apiKey, !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
            }
        case .gemini:
            if let key = apiKey, !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            }
        case .githubCopilot:
            // GitHub Copilot uses dynamic tokens, skip for prewarm
            break
        case .ollama:
            // Local providers typically don't need auth
            break
        case .appleFoundationModel:
            // Apple's on-device model doesn't need auth
            break
        }
    }
    
    // MARK: - Cleanup
    
    private func scheduleCleanup() {
        cleanupTask?.cancel()
        cleanupTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // Check every minute
                guard !Task.isCancelled else { break }
                
                cleanupStaleSessions()
            }
        }
    }
    
    private func cleanupStaleSessions() {
        let now = Date()
        
        for (provider, lastAccess) in lastUsed {
            if now.timeIntervalSince(lastAccess) > sessionTimeout {
                LogManager.shared.log("Cleaning up stale session for \(provider.displayName)", category: "AISessionManager")
                invalidate(provider: provider)
            }
        }
    }
}

// MARK: - AIProvider Extension
// defaultAPIURL is already defined in AIConfig.swift

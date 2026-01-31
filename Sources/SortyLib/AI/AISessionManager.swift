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
    
    /// Prewarm connection for a provider (call when user selects folder)
    public func prewarm(provider: AIProvider, config: AIConfig) async {
        guard prewarmingProvider == nil else { return }
        
        prewarmingProvider = provider
        prewarmError = nil
        isPrewarmed = false
        
        defer {
            prewarmingProvider = nil
        }
        
        do {
            let session = session(for: provider, config: config)
            
            // Get the base URL for the provider
            guard let baseURL = getBaseURL(for: provider, config: config) else {
                prewarmError = "Invalid API URL"
                return
            }
            
            // Perform a lightweight request to establish connection
            // Most providers support a simple OPTIONS or HEAD request
            var request = URLRequest(url: baseURL)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 10
            
            // Add auth headers if needed
            addAuthHeaders(to: &request, provider: provider, config: config)
            
            let (_, response) = try await session.data(for: request)
            
            // Any response (even 4xx) means connection is established
            if let httpResponse = response as? HTTPURLResponse {
                LogManager.shared.log("Prewarmed \(provider.displayName): HTTP \(httpResponse.statusCode)", category: "AISessionManager")
                isPrewarmed = true
            }
            
        } catch {
            // Connection failed, but that's okay - we tried
            LogManager.shared.log("Prewarm failed for \(provider.displayName): \(error.localizedDescription)", category: "AISessionManager")
            prewarmError = error.localizedDescription
            // Don't set isPrewarmed = false here, as the session is still created
            // and may work when the actual request is made
            isPrewarmed = false
        }
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
        
        // Optimize timeouts
        config.timeoutIntervalForRequest = 120  // 2 minutes for streaming
        config.timeoutIntervalForResource = 300  // 5 minutes total
        
        // Enable connection reuse
        config.httpMaximumConnectionsPerHost = 4
        config.urlCache = nil  // No caching for AI requests
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        // Enable TLS 1.3 where available
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        
        return config
    }
    
    private func getBaseURL(for provider: AIProvider, config: AIConfig) -> URL? {
        let urlString = (config.apiURL?.isEmpty ?? true) ? provider.defaultAPIURL : config.apiURL
        guard let urlString = urlString else { return nil }
        return URL(string: urlString)
    }
    
    private func addAuthHeaders(to request: inout URLRequest, provider: AIProvider, config: AIConfig) {
        // Add appropriate auth headers based on provider
        switch provider {
        case .openAI, .openRouter:
            if let key = config.apiKey, !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        case .anthropic:
            if let key = config.apiKey, !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
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
        default:
             // Handle other cases like .groq, .gemini, .openAICompatible if needed, or do nothing
             if let key = config.apiKey, !key.isEmpty {
                 request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
             }
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

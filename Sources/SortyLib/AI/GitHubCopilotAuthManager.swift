//
//  GitHubCopilotAuthManager.swift
//  Sorty
//
//  Handles GitHub Device Flow Authentication
//

import Foundation

enum GitHubAuthError: Error {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
    case authorizationPending
    case slowDown
    case expiredToken
    case accessDenied
    case unknown(String)
}

struct DeviceCodeResponse: Codable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int
    
    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct AccessTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

struct CopilotTokenResponse: Codable {
    let token: String
    let expiresAt: Int
    
    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
    }
}

@MainActor
class GitHubCopilotAuthManager: ObservableObject {
    static let shared = GitHubCopilotAuthManager()
    
    // Client ID for VS Code's Copilot integration
    private let clientID = "Iv1.b507a08c87ecfe98"
    
    @Published var deviceCodeResponse: DeviceCodeResponse?
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var isPolling = false
    @Published var authError: String?
    
    private let session = URLSession.shared
    private var pollTask: Task<Void, Never>?
    
    init() {
        checkAuthenticationStatus()
    }
    
    func checkAuthenticationStatus() {
        if let _ = KeychainManager.get(key: "github_access_token") {
            self.isAuthenticated = true
            // Optionally fetch user profile to confirm validity and get username
            Task {
                await fetchUserProfile()
            }
        } else {
            self.isAuthenticated = false
        }
    }
    
    func startDeviceFlow() async throws {
        self.authError = nil
        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": clientID,
            "scope": "read:user" // Basic scope, Copilot specifics are handled by the token later
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GitHubAuthError.invalidResponse
        }
        
        let codeResponse = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        self.deviceCodeResponse = codeResponse
        LogManager.shared.log("Starting polling for access token", category: "AuthManager")
        // Start polling
        startPolling(interval: Double(codeResponse.interval), deviceCode: codeResponse.deviceCode)
    }
    
    private func startPolling(interval: Double, deviceCode: String) {
        pollTask?.cancel()
        isPolling = true
        
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                do {
                    let token = try await requestAccessToken(deviceCode: deviceCode)
                    // Success!
                    _ = KeychainManager.save(key: "github_access_token", value: token)
                    self.isAuthenticated = true
                    self.isPolling = false
                    self.deviceCodeResponse = nil
                    await fetchUserProfile()
                    return
                } catch GitHubAuthError.authorizationPending {
                    // Continue polling
                    continue
                } catch GitHubAuthError.slowDown {
                    // Wait longer (add 5 seconds)
                    try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                    continue
                } catch {
                    LogManager.shared.log("Error polling for token: \(error)", level: .error, category: "AuthManager")
                    await MainActor.run {
                        self.authError = "Authentication failed: \(error.localizedDescription)"
                        self.isPolling = false
                        return
                    }
                }
            }
        }
    }
    
    private func requestAccessToken(deviceCode: String) async throws -> String {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GitHubAuthError.invalidResponse
        }
        
        // Check for specific error fields in JSON even if 200 OK
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String {
            switch error {
            case "authorization_pending": throw GitHubAuthError.authorizationPending
            case "slow_down": throw GitHubAuthError.slowDown
            case "expired_token": throw GitHubAuthError.expiredToken
            case "access_denied": throw GitHubAuthError.accessDenied
            default: throw GitHubAuthError.unknown(error)
            }
        }
        
        let tokenResponse = try JSONDecoder().decode(AccessTokenResponse.self, from: data)
        return tokenResponse.accessToken
    }
    
    func fetchUserProfile() async {
        guard let token = KeychainManager.get(key: "github_access_token") else { return }
        
        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Sorty/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await session.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let login = json["login"] as? String {
                self.username = login
            }
        } catch {
            LogManager.shared.log("Error fetching user profile: \(error)", level: .error, category: "AuthManager")
        }
    }
    
    func signOut() {
        _ = KeychainManager.delete(key: "github_access_token")
        _ = KeychainManager.delete(key: "github_copilot_token") // Also clear the cached copilot token
        self.isAuthenticated = false
        self.username = nil
        self.pollTask?.cancel()
        self.isPolling = false
        self.deviceCodeResponse = nil
    }
    
    // Retrieve Copilot-specific token using the auth token
    func getCopilotToken() async throws -> String {
        // Return cached token if valid
        if let cached = KeychainManager.get(key: "github_copilot_token"),
           let expiry = UserDefaults.standard.object(forKey: "github_copilot_token_expiry") as? Date,
           expiry > Date().addingTimeInterval(300) { // Buffer of 5 mins
            return cached
        }
        
        guard let accessToken = KeychainManager.get(key: "github_access_token") else {
            throw GitHubAuthError.accessDenied
        }
        
        let url = URL(string: "https://api.github.com/copilot_internal/v2/token")!
        var request = URLRequest(url: url)
        request.setValue("token \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Sorty/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // If 401/403, might need to re-auth
            if let httpResponse = response as? HTTPURLResponse, (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) {
                 // Trigger re-auth flow or notifications if needed
                 throw GitHubAuthError.accessDenied
            }
            throw GitHubAuthError.invalidResponse
        }
        
        let tokenResponse = try JSONDecoder().decode(CopilotTokenResponse.self, from: data)
        
        // Cache it
        _ = KeychainManager.save(key: "github_copilot_token", value: tokenResponse.token)
        let expiryDate = Date(timeIntervalSince1970: TimeInterval(tokenResponse.expiresAt))
        UserDefaults.standard.set(expiryDate, forKey: "github_copilot_token_expiry")
        
        return tokenResponse.token
    }
}

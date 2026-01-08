//
//  UpdateManager.swift
//  Sorty
//
//  Utility for checking updates via GitHub Releases API
//

import Foundation

@MainActor
public class UpdateManager: ObservableObject {
    public enum UpdateState: Equatable {
        case idle
        case checking
        case available(version: String, url: URL, notes: String?)
        case upToDate
        case error(String)
    }
    
    @Published public var state: UpdateState = .idle
    @Published public var lastCheckDate: Date?
    
    // Repository details
    private let repoOwner: String
    private let repoName: String
    
    public init(repoOwner: String = "shirishpothi", repoName: String = "Sorty") {
        self.repoOwner = repoOwner
        self.repoName = repoName
    }
    
    /// Checks for updates from GitHub Releases
    public func checkForUpdates() async {
        state = .checking
        lastCheckDate = Date()
        
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            state = .error("Invalid update URL")
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("Sorty/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                state = .error("Invalid server response")
                return
            }
            
            if httpResponse.statusCode == 200 {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                print("[UpdateManager] Found latest release: \(release.tagName)")
                
                // Robust normalization: strip leading 'v' if present
                let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                
                print("[UpdateManager] Comparing latest \(latestVersion) with current \(BuildInfo.version)")
                if isVersionNewer(latest: latestVersion, current: BuildInfo.version) {
                    if let htmlUrl = URL(string: release.htmlUrl) {
                        state = .available(version: latestVersion, url: htmlUrl, notes: release.body)
                    } else {
                        state = .error("Invalid release URL")
                    }
                } else {
                    state = .upToDate
                }
            } else {
                let statusCode = httpResponse.statusCode
                print("[UpdateManager] Error response: \(statusCode)")
                
                let message: String
                switch statusCode {
                case 401:
                    message = "Authentication required to access releases."
                case 403:
                    message = "GitHub API rate limit exceeded. Please try again later."
                case 404:
                    // Treat 404 as no releases exist, which means we are technically "up to date"
                    print("[UpdateManager] No releases found for this repository (404)")
                    state = .upToDate
                    return
                default:
                    message = "Failed to connect to GitHub (Status: \(statusCode))"
                }
                state = .error(message)
            }
        } catch {
            state = .error("Update check failed: \(error.localizedDescription)")
        }
    }
    
    /// Resets the state to idle
    public func resetState() {
        state = .idle
    }
    
    // MARK: - Helper Logic
    
    /// Compares version strings (e.g., "1.0.0" vs "1.1.0")
    private func isVersionNewer(latest: String, current: String) -> Bool {
        // Strip any pre-release identifiers for basic comparison
        let latestNumeric = latest.components(separatedBy: "-").first ?? latest
        let currentNumeric = current.components(separatedBy: "-").first ?? current
        
        let latestComponents = latestNumeric.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentNumeric.split(separator: ".").compactMap { Int($0) }
        
        let count = max(latestComponents.count, currentComponents.count)
        
        for i in 0..<count {
            let l = i < latestComponents.count ? latestComponents[i] : 0
            let c = i < currentComponents.count ? currentComponents[i] : 0
            
            if l > c { return true }
            if l < c { return false }
        }
        
        // Handle pre-release awareness: if numeric parts are equal, check if one is a pre-release
        // A full release "1.0.0" is newer than "1.0.0-beta"
        if latestNumeric == currentNumeric {
            let latestHasPreRelease = latest.contains("-")
            let currentHasPreRelease = current.contains("-")
            
            if currentHasPreRelease && !latestHasPreRelease {
                return true // Current is beta, latest is full release -> update available
            }
        }
        
        return false
    }
    
    // MARK: - GitHub API Model
    
    private struct GitHubRelease: Codable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
        }
    }
}

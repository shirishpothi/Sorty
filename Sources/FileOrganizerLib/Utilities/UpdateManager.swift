//
//  UpdateManager.swift
//  FileOrganizer
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
    
    // Repository details - adjust if necessary
    private let repoOwner = "shirishpothi"
    private let repoName = "FileOrganizer"
    
    public init() {}
    
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
            request.setValue("FileOrganizer/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                state = .error("Invalid server response")
                return
            }
            
            if httpResponse.statusCode == 404 {
                print("[UpdateManager] No releases found for this repository (404)")
                state = .upToDate // Treat no releases as "up to date" for now
                return
            }
            
            guard httpResponse.statusCode == 200 else {
                print("[UpdateManager] Error response: \(httpResponse.statusCode)")
                state = .error("Failed to connect to GitHub (Status: \(httpResponse.statusCode))")
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            print("[UpdateManager] Found latest release: \(release.tagName)")
            let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
            
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
        } catch {
            state = .error("Update check failed: \(error.localizedDescription)")
        }
    }
    
    /// Resets the state to idle
    public func resetState() {
        state = .idle
    }
    
    // MARK: - Helper Logic
    
    private func isVersionNewer(latest: String, current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }
        
        let count = max(latestComponents.count, currentComponents.count)
        
        for i in 0..<count {
            let l = i < latestComponents.count ? latestComponents[i] : 0
            let c = i < currentComponents.count ? currentComponents[i] : 0
            
            if l > c { return true }
            if l < c { return false }
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

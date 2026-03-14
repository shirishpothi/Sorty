//
//  NetworkPrivacyPolicy.swift
//  Sorty
//
//  Centralized network privacy policy enforcement.
//

import Foundation

public enum NetworkPrivacyPolicy {
    public static let internetPrivacyModeKey = "internetPrivacyModeEnabled"

    /// Dedicated privacy mode for network traffic.
    /// When enabled, only loopback hosts are allowed.
    public static var isInternetPrivacyModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: internetPrivacyModeKey)
    }

    public static var blockedMessage: String {
        "Privacy Mode is enabled. Internet connections are blocked. Only localhost loopback requests are allowed."
    }

    public static func isRequestAllowed(url: URL) -> Bool {
        guard isInternetPrivacyModeEnabled else { return true }
        return isLoopbackURL(url)
    }

    public static func isLoopbackURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }

        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
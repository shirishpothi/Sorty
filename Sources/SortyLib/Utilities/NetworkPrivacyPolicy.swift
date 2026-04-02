//
//  NetworkPrivacyPolicy.swift
//  Sorty
//
//  Centralized network privacy policy enforcement.
//

import Foundation
import Darwin

public enum NetworkPrivacyPolicy {
    public static let internetPrivacyModeKey = "internetPrivacyModeEnabled"
    private static let testDefaultsSuiteLock = NSLock()
    private nonisolated(unsafe) static var testDefaultsSuiteName: String?

    /// Dedicated privacy mode for network traffic.
    /// When enabled, only loopback hosts are allowed.
    public static var isInternetPrivacyModeEnabled: Bool {
        activeDefaults().bool(forKey: internetPrivacyModeKey)
    }

    // Allows tests to isolate privacy mode state from process-shared UserDefaults.standard.
    static func setTestDefaultsSuiteName(_ suiteName: String?) {
        testDefaultsSuiteLock.lock()
        testDefaultsSuiteName = suiteName
        testDefaultsSuiteLock.unlock()
    }

    public static var blockedMessage: String {
        "Privacy Mode is enabled. Internet connections are blocked. Only localhost loopback requests are allowed."
    }

    public static func isRequestAllowed(url: URL) -> Bool {
        guard isInternetPrivacyModeEnabled else { return true }
        return isLoopbackURL(url)
    }

    private static func activeDefaults() -> UserDefaults {
        testDefaultsSuiteLock.lock()
        let suiteName = testDefaultsSuiteName
        testDefaultsSuiteLock.unlock()

        guard let suiteName else { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    public static func isLoopbackURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }

        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" { return true }
        if isIPv4LoopbackHost(host) { return true }
        if isIPv6LoopbackHost(host) { return true }
        return false
    }

    private static func isIPv4LoopbackHost(_ host: String) -> Bool {
        var address = in_addr()
        let parseResult = host.withCString { inet_pton(AF_INET, $0, &address) }
        guard parseResult == 1 else { return false }

        let value = UInt32(bigEndian: address.s_addr)
        return (value & 0xFF00_0000) == 0x7F00_0000
    }

    private static func isIPv6LoopbackHost(_ host: String) -> Bool {
        var address = in6_addr()
        let parseResult = host.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parseResult == 1 else { return false }

        let bytes = withUnsafeBytes(of: address) { Array($0) }
        guard bytes.count == 16 else { return false }

        let isIPv6Loopback = bytes[0..<15].allSatisfy { $0 == 0 } && bytes[15] == 1
        if isIPv6Loopback { return true }

        let isIPv4Mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
        if isIPv4Mapped {
            return bytes[12] == 127
        }

        return false
    }
}
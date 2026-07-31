//
//  KeychainManager.swift
//  Sorty
//
//  Secure storage for API keys using Keychain
//

import Foundation
import Security

struct KeychainManager {
    // Use a fixed service name so credentials persist across app rebuilds
    // and bundle ID changes during development
    private static let primaryService = "com.sorty.app.credentials"

    private static var fallbackServices: [String] {
        var services: [String] = []

        if let bundleID = Bundle.main.bundleIdentifier,
           !bundleID.isEmpty,
           bundleID != primaryService {
            services.append(bundleID)
        }

        services.append(contentsOf: [
            "com.sorty.app",
            "com.sorty.Sorty",
            "com.sorty.SortyApp",
            "shirishpothi.Sorty"
        ])

        var seen = Set<String>()
        return services.filter { seen.insert($0).inserted }
    }

    private static var allServices: [String] {
        [primaryService] + fallbackServices
    }
    
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: primaryService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            cleanupFallbackServices(for: key)
            return true
        }

        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: primaryService,
                kSecAttrAccount as String: key
            ]
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus == errSecSuccess {
                cleanupFallbackServices(for: key)
                return true
            }
            logFailure(operation: "update", status: updateStatus)
            return false
        }

        logFailure(operation: "save", status: status)
        return false
    }

    /// Security.framework can block while macOS unlocks or searches a keychain.
    /// Keep those calls away from the main actor so app and settings construction
    /// can never stall the first window.
    static func saveAsync(key: String, value: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            save(key: key, value: value)
        }.value
    }
    
    static func get(key: String) -> String? {
        if let value = readValue(key: key, service: primaryService) {
            return value
        }

        for service in fallbackServices {
            guard let value = readValue(key: key, service: service) else { continue }
            _ = save(key: key, value: value)
            return value
        }

        return nil
    }

    static func getAsync(key: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            get(key: key)
        }.value
    }

    static func delete(key: String) -> Bool {
        var success = true

        for service in allServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]

            let status = SecItemDelete(query as CFDictionary)
            let isDeleted = status == errSecSuccess || status == errSecItemNotFound
            success = success && isDeleted
        }

        return success
    }

    static func deleteAsync(key: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            delete(key: key)
        }.value
    }

    static func deleteAll() -> Bool {
        var success = true

        for service in allServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service
            ]

            let status = SecItemDelete(query as CFDictionary)
            let isDeleted = status == errSecSuccess || status == errSecItemNotFound
            success = success && isDeleted
        }

        return success
    }

    static func deleteAllAsync() async -> Bool {
        await Task.detached(priority: .userInitiated) {
            deleteAll()
        }.value
    }

    private static func readValue(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private static func cleanupFallbackServices(for key: String) {
        for service in fallbackServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            _ = SecItemDelete(query as CFDictionary)
        }
    }

    private static func logFailure(operation: String, status: OSStatus) {
        let message = SecCopyErrorMessageString(status, nil).map { $0 as String } ?? "Unknown Keychain error"
        NSLog("Sorty Keychain %@ failed (OSStatus %d): %@", operation, status, message)
    }
}

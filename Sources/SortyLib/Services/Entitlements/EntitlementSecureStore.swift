import Foundation
import CryptoKit

#if canImport(AppKit)
import AppKit
#endif

public protocol EntitlementSecretStore: Sendable {
    func save(value: String, for key: String) -> Bool
    func loadValue(for key: String) -> String?
    func deleteValue(for key: String) -> Bool
}

public struct SystemEntitlementSecretStore: EntitlementSecretStore {
    public init() {}

    public func save(value: String, for key: String) -> Bool {
        KeychainManager.save(key: key, value: value)
    }

    public func loadValue(for key: String) -> String? {
        KeychainManager.get(key: key)
    }

    public func deleteValue(for key: String) -> Bool {
        KeychainManager.delete(key: key)
    }
}

public struct EntitlementCacheRecord: Codable, Equatable, Sendable {
    public let envelope: SignedEntitlementEnvelope
    public let cachedAt: Date

    public init(envelope: SignedEntitlementEnvelope, cachedAt: Date) {
        self.envelope = envelope
        self.cachedAt = cachedAt
    }
}

public enum EntitlementSecureStoreError: LocalizedError {
    case keychainSaveFailed
    case invalidCacheData

    public var errorDescription: String? {
        switch self {
        case .keychainSaveFailed:
            return "Sorty couldn't update the secure local license store."
        case .invalidCacheData:
            return "Sorty's local entitlement cache is unreadable or has been tampered with."
        }
    }
}

public final class EntitlementSecureStore: @unchecked Sendable {
    private enum StorageKey {
        static let deviceID = "sorty_license_device_id"
        static let cacheKey = "sorty_license_cache_key"
        static let activeLicenseKeys = "sorty_active_license_keys"
    }

    private let rootDirectory: URL
    private let secretStore: any EntitlementSecretStore
    private let fileManager: FileManager

    public init(
        rootDirectory: URL? = nil,
        secretStore: any EntitlementSecretStore = SystemEntitlementSecretStore(),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.secretStore = secretStore
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
    }

    public func currentDeviceIdentity() -> LicenseDeviceIdentity {
        LicenseDeviceIdentity(
            deviceID: loadOrCreateDeviceID(),
            deviceName: currentDeviceName(),
            appVersion: BuildInfo.version
        )
    }

    public func storedLicenseKeys() -> [String] {
        guard let raw = secretStore.loadValue(for: StorageKey.activeLicenseKeys),
              let data = raw.data(using: .utf8),
              let keys = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return normalize(keys: keys)
    }

    @discardableResult
    public func saveLicenseKeys(_ keys: [String]) -> Bool {
        let normalized = normalize(keys: keys)
        guard let data = try? JSONEncoder().encode(normalized),
              let json = String(data: data, encoding: .utf8) else {
            return false
        }
        return secretStore.save(value: json, for: StorageKey.activeLicenseKeys)
    }

    @discardableResult
    public func clearLicenseKeys() -> Bool {
        secretStore.deleteValue(for: StorageKey.activeLicenseKeys)
    }

    public func loadCachedEnvelope() throws -> SignedEntitlementEnvelope? {
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        let encryptedData = try Data(contentsOf: cacheURL)
        let decrypted = try decrypt(data: encryptedData)
        let record = try JSONDecoder.licensePayloadDecoder.decode(EntitlementCacheRecord.self, from: decrypted)
        return record.envelope
    }

    public func saveCachedEnvelope(_ envelope: SignedEntitlementEnvelope) throws {
        try ensureDirectoryExists()
        let record = EntitlementCacheRecord(envelope: envelope, cachedAt: Date())
        let data = try JSONEncoder.licensePayloadEncoder.encode(record)
        let encrypted = try encrypt(data: data)
        try encrypted.write(to: cacheURL, options: .atomic)
    }

    public func clearCachedEnvelope() throws {
        if fileManager.fileExists(atPath: cacheURL.path) {
            try fileManager.removeItem(at: cacheURL)
        }
    }

    public func clearAll() throws {
        _ = clearLicenseKeys()
        _ = secretStore.deleteValue(for: StorageKey.cacheKey)
        try clearCachedEnvelope()
    }

    private func encrypt(data: Data) throws -> Data {
        let key = try loadOrCreateEncryptionKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw EntitlementSecureStoreError.invalidCacheData
        }
        return combined
    }

    private func decrypt(data: Data) throws -> Data {
        let key = try loadOrCreateEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func loadOrCreateEncryptionKey() throws -> SymmetricKey {
        if let base64Key = secretStore.loadValue(for: StorageKey.cacheKey),
           let keyData = Data(base64Encoded: base64Key) {
            return SymmetricKey(data: keyData)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        guard secretStore.save(value: keyData.base64EncodedString(), for: StorageKey.cacheKey) else {
            throw EntitlementSecureStoreError.keychainSaveFailed
        }
        return key
    }

    private func loadOrCreateDeviceID() -> String {
        if let existing = secretStore.loadValue(for: StorageKey.deviceID),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }

        let deviceID = UUID().uuidString.lowercased()
        _ = secretStore.save(value: deviceID, for: StorageKey.deviceID)
        return deviceID
    }

    private func currentDeviceName() -> String {
        #if canImport(AppKit)
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
    }

    private func normalize(keys: [String]) -> [String] {
        var seen: Set<String> = []
        var normalized: [String] = []

        for key in keys {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                normalized.append(trimmed)
            }
        }

        return normalized.sorted()
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return baseURL.appendingPathComponent("Sorty/Entitlements", isDirectory: true)
    }

    private var cacheURL: URL {
        rootDirectory.appendingPathComponent("license-cache.enc")
    }
}

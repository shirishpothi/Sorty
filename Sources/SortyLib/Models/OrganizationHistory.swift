//
//  OrganizationHistory.swift
//  Sorty
//
//  Organization history and analytics with undo support
//

import Foundation
import Combine

public enum OrganizationStatus: String, Codable, Sendable {
    case completed
    case failed
    case cancelled
    case skipped // Superseded by "Try Another"
    case undo // Reverted
    case partiallyUndone // Partially reverted (some files could not be restored)
    case duplicatesCleanup // New: Duplicate removal session

    public var displayName: String {
        switch self {
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .skipped: "Skipped"
        case .undo: "Undo"
        case .partiallyUndone: "Partially Undone"
        case .duplicatesCleanup: "Duplicates Cleanup"
        }
    }
}

public enum OrganizationEntrySource: String, Codable, Sendable {
    case manual
    case watchedFolder
}

public enum DuplicateCleanupMode: String, Codable, Sendable {
    case safeDeletion
    case directDelete
    case trash
}

public struct OrganizationHistoryEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let directoryPath: String
    public let filesOrganized: Int
    public let foldersCreated: Int
    public let plan: OrganizationPlan?
    public let success: Bool // Legacy format, kept for decoding old entries
    public var status: OrganizationStatus // New detailed status
    public let errorMessage: String?
    public let rawAIResponse: String?
    public var operations: [FileSystemManager.FileOperation]?
    public var isUndone: Bool
    public var source: OrganizationEntrySource
    
    // Undo result tracking
    public var undoRestoredCount: Int?
    public var undoFailedFiles: [String]?
    
    // Duplicate Specific Fields
    public var duplicatesDeleted: Int?
    public var recoveredSpace: Int64?
    public var restorableItems: [RestorableDuplicate]?
    public var duplicateCleanupMode: DuplicateCleanupMode?

    public var hasApplicablePlan: Bool {
        guard !success, plan != nil, status != .duplicatesCleanup else {
            return false
        }

        return operations?.isEmpty ?? true
    }
    
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        directoryPath: String,
        filesOrganized: Int,
        foldersCreated: Int,
        plan: OrganizationPlan? = nil,
        success: Bool = true,
        status: OrganizationStatus? = nil,
        errorMessage: String? = nil,
        rawAIResponse: String? = nil,
        operations: [FileSystemManager.FileOperation]? = nil,
        isUndone: Bool = false,
        source: OrganizationEntrySource = .manual,
        undoRestoredCount: Int? = nil,
        undoFailedFiles: [String]? = nil,
        duplicatesDeleted: Int? = nil,
        recoveredSpace: Int64? = nil,
        restorableItems: [RestorableDuplicate]? = nil,
        duplicateCleanupMode: DuplicateCleanupMode? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.directoryPath = directoryPath
        self.filesOrganized = filesOrganized
        self.foldersCreated = foldersCreated
        self.plan = plan
        self.success = success
        
        // Migrate legacy success boolean to status if status not provided
        if let providedStatus = status {
            self.status = providedStatus
        } else {
            if isUndone {
                 self.status = .undo
            } else if success {
                self.status = .completed
            } else {
                self.status = .failed
            }
        }
        
        self.errorMessage = errorMessage
        self.rawAIResponse = rawAIResponse
        self.operations = operations
        self.isUndone = isUndone
        self.source = source
        self.undoRestoredCount = undoRestoredCount
        self.undoFailedFiles = undoFailedFiles
        self.duplicatesDeleted = duplicatesDeleted
        self.recoveredSpace = recoveredSpace
        self.restorableItems = restorableItems
        self.duplicateCleanupMode = duplicateCleanupMode
    }
    
    // Custom decoding to handle migration from old format
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        directoryPath = try container.decode(String.self, forKey: .directoryPath)
        filesOrganized = try container.decode(Int.self, forKey: .filesOrganized)
        foldersCreated = try container.decode(Int.self, forKey: .foldersCreated)
        plan = try container.decodeIfPresent(OrganizationPlan.self, forKey: .plan)
        
        // Handle legacy 'success'
        let successVal = try container.decodeIfPresent(Bool.self, forKey: .success) ?? true
        success = successVal
        
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        rawAIResponse = try container.decodeIfPresent(String.self, forKey: .rawAIResponse)
        operations = try container.decodeIfPresent([FileSystemManager.FileOperation].self, forKey: .operations)
        isUndone = try container.decodeIfPresent(Bool.self, forKey: .isUndone) ?? false
        source = try container.decodeIfPresent(OrganizationEntrySource.self, forKey: .source) ?? .manual
        undoRestoredCount = try container.decodeIfPresent(Int.self, forKey: .undoRestoredCount)
        undoFailedFiles = try container.decodeIfPresent([String].self, forKey: .undoFailedFiles)
        
        // Decode status if present, otherwise infer
        if let decodedStatus = try container.decodeIfPresent(OrganizationStatus.self, forKey: .status) {
            status = decodedStatus
        } else {
            // Infer
            if isUndone {
                status = .undo
            } else if successVal {
                status = .completed
            } else {
                status = .failed
            }
        }

        duplicatesDeleted = try container.decodeIfPresent(Int.self, forKey: .duplicatesDeleted)
        recoveredSpace = try container.decodeIfPresent(Int64.self, forKey: .recoveredSpace)
        restorableItems = try container.decodeIfPresent([RestorableDuplicate].self, forKey: .restorableItems)
        duplicateCleanupMode = try container.decodeIfPresent(DuplicateCleanupMode.self, forKey: .duplicateCleanupMode)
    }
}

private struct OrganizationHistorySnapshot: Codable {
    let schemaVersion: Int
    let entries: [OrganizationHistoryEntry]
}

private final class OrganizationHistoryRepository {
    static let legacyHistoryKey = "organizationHistory"
    static let fileName = "organization-history.json"
    static let backupFileName = "organization-history.json.bak"
    private static let schemaVersion = 1

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let storageDirectory: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        storageDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.storageDirectory = storageDirectory ?? Self.defaultStorageDirectory(fileManager: fileManager)
    }

    var primaryFileURL: URL? {
        storageDirectory?.appendingPathComponent(Self.fileName)
    }

    var backupFileURL: URL? {
        storageDirectory?.appendingPathComponent(Self.backupFileName)
    }

    func loadEntries() -> [OrganizationHistoryEntry] {
        guard let primaryFileURL else {
            LogManager.shared.log(
                "History file store unavailable; using legacy UserDefaults fallback",
                level: .warning,
                category: "OrganizationHistory"
            )
            return loadLegacyEntries()
        }

        if fileManager.fileExists(atPath: primaryFileURL.path) {
            do {
                return try readEntries(from: primaryFileURL)
            } catch {
                LogManager.shared.log(
                    "Primary history store unreadable at \(primaryFileURL.path): \(error.localizedDescription)",
                    level: .warning,
                    category: "OrganizationHistory"
                )

                if let recoveredEntries = recoverFromBackup() {
                    return recoveredEntries
                }

                return []
            }
        }

        if let recoveredEntries = recoverFromBackup() {
            return recoveredEntries
        }

        let legacyEntries = loadLegacyEntries()
        guard !legacyEntries.isEmpty else {
            return []
        }

        if saveEntries(legacyEntries) {
            userDefaults.removeObject(forKey: Self.legacyHistoryKey)
            LogManager.shared.log(
                "Migrated \(legacyEntries.count) history entr\(legacyEntries.count == 1 ? "y" : "ies") from UserDefaults to file store",
                category: "OrganizationHistory"
            )
        } else {
            LogManager.shared.log(
                "History migration fell back to UserDefaults because file storage could not be written",
                level: .warning,
                category: "OrganizationHistory"
            )
        }

        return legacyEntries
    }

    @discardableResult
    func saveEntries(_ entries: [OrganizationHistoryEntry]) -> Bool {
        guard let primaryFileURL, let backupFileURL else {
            persistLegacyFallback(entries)
            return false
        }

        do {
            try ensureStorageDirectoryExists()

            let snapshot = OrganizationHistorySnapshot(
                schemaVersion: Self.schemaVersion,
                entries: entries
            )
            let data = try encoder.encode(snapshot)
            let tempURL = primaryFileURL.deletingLastPathComponent()
                .appendingPathComponent(".\(Self.fileName).\(UUID().uuidString).tmp")

            do {
                try writeVerifiedTemp(data, to: tempURL)
                try replacePrimary(with: tempURL, at: primaryFileURL)
                try verifyFileSize(at: primaryFileURL, expectedByteCount: data.count)
                try mirrorBackup(from: primaryFileURL, to: backupFileURL)
                userDefaults.removeObject(forKey: Self.legacyHistoryKey)
                return true
            } catch {
                try? cleanupFileIfPresent(at: tempURL)
                if let recoveredEntries = recoverFromBackup() {
                    LogManager.shared.log(
                        "Recovered history store from backup after failed write; preserved \(recoveredEntries.count) entries",
                        level: .warning,
                        category: "OrganizationHistory"
                    )
                }
                throw error
            }
        } catch {
            LogManager.shared.log(
                "Failed to persist history file store, using UserDefaults fallback: \(error.localizedDescription)",
                level: .warning,
                category: "OrganizationHistory"
            )
            persistLegacyFallback(entries)
            return false
        }
    }

    func clear() {
        if let primaryFileURL {
            try? cleanupFileIfPresent(at: primaryFileURL)
        }
        if let backupFileURL {
            try? cleanupFileIfPresent(at: backupFileURL)
        }
        userDefaults.removeObject(forKey: Self.legacyHistoryKey)
    }

    private func loadLegacyEntries() -> [OrganizationHistoryEntry] {
        guard
            let data = userDefaults.data(forKey: Self.legacyHistoryKey),
            let decoded = try? decoder.decode([OrganizationHistoryEntry].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func persistLegacyFallback(_ entries: [OrganizationHistoryEntry]) {
        guard let encoded = try? encoder.encode(entries) else {
            return
        }
        userDefaults.set(encoded, forKey: Self.legacyHistoryKey)
    }

    private func ensureStorageDirectoryExists() throws {
        guard let storageDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }

        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
    }

    private func writeVerifiedTemp(_ data: Data, to tempURL: URL) throws {
        try cleanupFileIfPresent(at: tempURL)

        guard fileManager.createFile(atPath: tempURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let handle = try FileHandle(forWritingTo: tempURL)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        try verifyFileSize(at: tempURL, expectedByteCount: data.count)
    }

    private func verifyFileSize(at url: URL, expectedByteCount: Int) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.intValue == expectedByteCount else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func replacePrimary(with tempURL: URL, at primaryFileURL: URL) throws {
        if fileManager.fileExists(atPath: primaryFileURL.path) {
            _ = try fileManager.replaceItemAt(
                primaryFileURL,
                withItemAt: tempURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fileManager.moveItem(at: tempURL, to: primaryFileURL)
        }
    }

    private func mirrorBackup(from primaryFileURL: URL, to backupFileURL: URL) throws {
        let stagingURL = backupFileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(Self.backupFileName).\(UUID().uuidString).tmp")

        try cleanupFileIfPresent(at: stagingURL)
        try fileManager.copyItem(at: primaryFileURL, to: stagingURL)

        do {
            if fileManager.fileExists(atPath: backupFileURL.path) {
                _ = try fileManager.replaceItemAt(
                    backupFileURL,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: stagingURL, to: backupFileURL)
            }
        } catch {
            try? cleanupFileIfPresent(at: stagingURL)
            throw error
        }
    }

    private func recoverFromBackup() -> [OrganizationHistoryEntry]? {
        guard let primaryFileURL, let backupFileURL,
              fileManager.fileExists(atPath: backupFileURL.path) else {
            return nil
        }

        do {
            let entries = try readEntries(from: backupFileURL)
            try ensureStorageDirectoryExists()

            let recoveryTempURL = primaryFileURL.deletingLastPathComponent()
                .appendingPathComponent(".\(Self.fileName).recovery.\(UUID().uuidString).tmp")
            try cleanupFileIfPresent(at: recoveryTempURL)
            try fileManager.copyItem(at: backupFileURL, to: recoveryTempURL)
            try replacePrimary(with: recoveryTempURL, at: primaryFileURL)

            LogManager.shared.log(
                "Recovered history store from backup at \(backupFileURL.path)",
                level: .warning,
                category: "OrganizationHistory"
            )
            return entries
        } catch {
            LogManager.shared.log(
                "Failed to recover history store from backup: \(error.localizedDescription)",
                level: .error,
                category: "OrganizationHistory"
            )
            return nil
        }
    }

    private func readEntries(from fileURL: URL) throws -> [OrganizationHistoryEntry] {
        let data = try Data(contentsOf: fileURL)

        if let snapshot = try? decoder.decode(OrganizationHistorySnapshot.self, from: data) {
            return snapshot.entries
        }

        return try decoder.decode([OrganizationHistoryEntry].self, from: data)
    }

    private func cleanupFileIfPresent(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private static func defaultStorageDirectory(fileManager: FileManager) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Sorty/History", isDirectory: true)
    }
}

@MainActor
public class OrganizationHistory: ObservableObject {
    public struct ImportResult: Equatable, Sendable {
        public let added: Int
        public let updated: Int
        public let unchanged: Int
        public let omittedByRetentionLimit: Int

        public var changed: Int { added + updated }
    }

    @Published public private(set) var entries: [OrganizationHistoryEntry] = []
    private let repository: OrganizationHistoryRepository
    private let maxEntries = 100
    
    public init(userDefaults: UserDefaults = .standard, storageDirectory: URL? = nil) {
        self.repository = OrganizationHistoryRepository(
            userDefaults: userDefaults,
            storageDirectory: storageDirectory
        )
        loadHistory()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.clearHistory()
        }
    }
    
    public func addEntry(_ entry: OrganizationHistoryEntry) {
        var cleanEntry = entry
        cleanEntry.isUndone = false // Enforce clean state for new entries
        entries.insert(cleanEntry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast()
        }
        saveHistory()
    }
    
    public func updateEntry(_ entry: OrganizationHistoryEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            saveHistory()
        }
    }
    
    public func clearHistory() {
        entries.removeAll()
        repository.clear()
    }

    @discardableResult
    public func importEntries(_ importedEntries: [OrganizationHistoryEntry]) -> ImportResult {
        guard !importedEntries.isEmpty else {
            return ImportResult(added: 0, updated: 0, unchanged: 0, omittedByRetentionLimit: 0)
        }

        var mergedByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var added = 0
        var updated = 0
        var unchanged = 0

        for entry in importedEntries {
            if let existing = mergedByID[entry.id] {
                if existing == entry {
                    unchanged += 1
                    continue
                }
                updated += 1
            } else {
                added += 1
            }
            mergedByID[entry.id] = entry
        }

        let sorted = mergedByID.values.sorted { $0.timestamp > $1.timestamp }
        entries = Array(sorted.prefix(maxEntries))
        saveHistory()
        return ImportResult(
            added: added,
            updated: updated,
            unchanged: unchanged,
            omittedByRetentionLimit: max(0, sorted.count - maxEntries)
        )
    }
    
    public var totalFilesOrganized: Int {
        entries.filter { $0.status == .completed }.reduce(0) { $0 + $1.filesOrganized }
    }
    
    public var totalFoldersCreated: Int {
        entries.filter { $0.status == .completed }.reduce(0) { $0 + $1.foldersCreated }
    }

    public var totalSessions: Int {
        entries.count
    }

    public var revertedCount: Int {
        entries.filter { $0.status == .undo || $0.status == .partiallyUndone || $0.isUndone }.count
    }
    
    public var successRate: Double {
        let completed = entries.filter { $0.status == .completed }.count
        let total = entries.count
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
    
    public var failedCount: Int {
        entries.filter { $0.status == .failed }.count
    }
    
    public var successCount: Int {
        entries.filter { $0.status == .completed }.count
    }

    public var totalRecoveredSpace: Int64 {
        entries.compactMap { $0.recoveredSpace }.reduce(0, +)
    }

    public var totalTimeSaved: TimeInterval {
        entries.filter { $0.status == .completed }
            .compactMap { $0.plan?.generationStats?.estimatedTimeSaved }
            .reduce(0, +)
    }

    public var totalEstimatedCost: Decimal {
        entries.compactMap { $0.plan?.generationStats?.computedCost }
            .reduce(0, +)
    }

    private func loadHistory() {
        entries = repository.loadEntries()
    }
    
    private func saveHistory() {
        _ = repository.saveEntries(entries)
    }

    public nonisolated static func loadPersistedEntries(
        userDefaults: UserDefaults = .standard,
        storageDirectory: URL? = nil
    ) -> [OrganizationHistoryEntry] {
        OrganizationHistoryRepository(
            userDefaults: userDefaults,
            storageDirectory: storageDirectory
        ).loadEntries()
    }

    var storageFileURL: URL? {
        repository.primaryFileURL
    }

    var backupStorageFileURL: URL? {
        repository.backupFileURL
    }
}



/// Represents a duplicate file that has been safely deleted and can be restored
public struct RestorableDuplicate: Codable, Identifiable, Sendable, Hashable, Equatable {
    public let id: UUID
    public let originalPath: String
    public let deletedPath: String
    public let trashPath: String?
    public let deletedDate: Date
    public let metadata: FileMetadata
    
    public struct FileMetadata: Codable, Sendable, Hashable, Equatable {
        public let creationDate: Date?
        public let modificationDate: Date?
        public let permissions: Int?
        public let ownerAccountID: Int?
        public let groupOwnerAccountID: Int?
    }
    
    public init(
        id: UUID = UUID(),
        originalPath: String,
        deletedPath: String,
        trashPath: String? = nil,
        deletedDate: Date = Date(),
        metadata: FileMetadata
    ) {
        self.id = id
        self.originalPath = originalPath
        self.deletedPath = deletedPath
        self.trashPath = trashPath
        self.deletedDate = deletedDate
        self.metadata = metadata
    }
}

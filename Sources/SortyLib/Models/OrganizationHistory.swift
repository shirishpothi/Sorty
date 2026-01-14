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
    case duplicatesCleanup // New: Duplicate removal session
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
    
    // Duplicate Specific Fields
    public var duplicatesDeleted: Int?
    public var recoveredSpace: Int64?
    public var restorableItems: [RestorableDuplicate]?
    
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
        duplicatesDeleted: Int? = nil,
        recoveredSpace: Int64? = nil,
        restorableItems: [RestorableDuplicate]? = nil
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
        self.duplicatesDeleted = duplicatesDeleted
        self.recoveredSpace = recoveredSpace
        self.restorableItems = restorableItems
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
    }
}

@MainActor
public class OrganizationHistory: ObservableObject {
    @Published public private(set) var entries: [OrganizationHistoryEntry] = []
    private let userDefaults = UserDefaults.standard
    private let historyKey = "organizationHistory"
    private let maxEntries = 100
    
    public init() {
        loadHistory()
    }
    
    public func addEntry(_ entry: OrganizationHistoryEntry) {
        entries.insert(entry, at: 0)
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
        saveHistory()
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
        entries.filter { $0.status == .undo || $0.isUndone }.count
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
    
    private func loadHistory() {
        if let data = userDefaults.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([OrganizationHistoryEntry].self, from: data) {
            entries = decoded
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(entries) {
            userDefaults.set(encoded, forKey: historyKey)
        }
    }
}



/// Represents a duplicate file that has been safely deleted and can be restored
public struct RestorableDuplicate: Codable, Identifiable, Sendable, Hashable, Equatable {
    public let id: UUID
    public let originalPath: String
    public let deletedPath: String
    public let deletedDate: Date
    public let metadata: FileMetadata
    
    public struct FileMetadata: Codable, Sendable, Hashable, Equatable {
        public let creationDate: Date?
        public let modificationDate: Date?
        public let permissions: Int?
        public let ownerAccountID: Int?
        public let groupOwnerAccountID: Int?
    }
    
    public init(id: UUID = UUID(), originalPath: String, deletedPath: String, deletedDate: Date = Date(), metadata: FileMetadata) {
        self.id = id
        self.originalPath = originalPath
        self.deletedPath = deletedPath
        self.deletedDate = deletedDate
        self.metadata = metadata
    }
}


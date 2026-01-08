//
//  OrganizationPlan.swift
//  Sorty
//
//  Complete Organization Proposal
//

import Foundation

public struct UnorganizedFile: Codable, Hashable, Sendable, Identifiable {
    public var id: String { filename }
    public let filename: String
    public let reason: String
}

public struct OrganizationPlan: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var suggestions: [FolderSuggestion]
    public var unorganizedFiles: [FileItem] // Keep for backward compatibility/UI logic
    public var unorganizedDetails: [UnorganizedFile]
    public var notes: String
    public var timestamp: Date
    public var version: Int
    public var generationStats: GenerationStats?
    
    public init(
        id: UUID = UUID(),
        suggestions: [FolderSuggestion] = [],
        unorganizedFiles: [FileItem] = [],
        unorganizedDetails: [UnorganizedFile] = [],
        notes: String = "",
        timestamp: Date = Date(),
        version: Int = 1,
        generationStats: GenerationStats? = nil
    ) {
        self.id = id
        self.suggestions = suggestions
        self.unorganizedFiles = unorganizedFiles
        self.unorganizedDetails = unorganizedDetails
        self.notes = notes
        self.timestamp = timestamp
        self.version = version
        self.generationStats = generationStats
    }
    
    public var totalFiles: Int {
        suggestions.reduce(0) { $0 + $1.totalFileCount } + unorganizedFiles.count
    }
    
    public var totalFolders: Int {
        func countFolders(_ folders: [FolderSuggestion]) -> Int {
            folders.count + folders.reduce(0) { $0 + countFolders($1.subfolders) }
        }
        return countFolders(suggestions)
    }
}


public struct GenerationStats: Codable, Sendable, Hashable {
    public let duration: TimeInterval
    public let tps: Double
    public let ttft: TimeInterval
    public let totalTokens: Int
    public let model: String
    
    public init(duration: TimeInterval, tps: Double, ttft: TimeInterval, totalTokens: Int, model: String) {
        self.duration = duration
        self.tps = tps
        self.ttft = ttft
        self.totalTokens = totalTokens
        self.model = model
    }
}


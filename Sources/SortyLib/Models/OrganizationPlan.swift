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
    
    // Additional metrics
    public var filesScanned: Int?
    public var totalFileSize: Int64?
    public var duplicatesFound: Int?
    public var promptTokens: Int?
    public var retryCount: Int?
    public var provider: String?
    public var scanDuration: TimeInterval?
    public var estimatedCost: Decimal?
    
    /// User productivity metrics
    public var estimatedTimeSaved: TimeInterval {
        // Assume 4 seconds saved per file organized (browsing, clicking, dragging, verifying)
        // This is a conservative estimate for manual organization effort.
        Double(filesScanned ?? 0) * 4.0
    }
    
    /// Automatically calculated cost based on model and tokens if estimatedCost is nil
    public var computedCost: Decimal {
        if let cost = estimatedCost { return cost }
        return CostCalculator.calculate(
            model: model,
            inputTokens: promptTokens ?? 0,
            outputTokens: totalTokens
        )
    }

    public var responseTokens: Int {
        totalTokens
    }

    public var totalContextTokens: Int? {
        guard let promptTokens else { return nil }
        return promptTokens + totalTokens
    }

    public var hasBillableCost: Bool {
        computedCost > 0
    }

    public var formattedTotalFileSize: String? {
        guard let totalFileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }

    public var compactModelName: String {
        model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ".")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? model
    }

    public static func formatDuration(_ interval: TimeInterval) -> String {
        let normalizedInterval = max(interval, 0)
        if normalizedInterval < 10 {
            return String(format: "%.1fs", normalizedInterval)
        }
        if normalizedInterval < 60 {
            return String(format: "%.0fs", normalizedInterval)
        }
        if normalizedInterval < 3600 {
            let minutes = Int(normalizedInterval / 60)
            let seconds = Int(normalizedInterval.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }

        let hours = Int(normalizedInterval / 3600)
        let minutes = Int((normalizedInterval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "\(hours)h \(minutes)m"
    }

    public static func formatCount(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    public static func formatCost(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let number = NSDecimalNumber(decimal: value)
        let usesExtendedPrecision = number.doubleValue < 0.01
        formatter.minimumFractionDigits = usesExtendedPrecision ? 4 : 2
        formatter.maximumFractionDigits = usesExtendedPrecision ? 4 : 2
        return formatter.string(from: number) ?? "$0.00"
    }
    
    public init(
        duration: TimeInterval, 
        tps: Double, 
        ttft: TimeInterval, 
        totalTokens: Int, 
        model: String,
        filesScanned: Int? = nil,
        totalFileSize: Int64? = nil,
        duplicatesFound: Int? = nil,
        promptTokens: Int? = nil,
        retryCount: Int? = nil,
        provider: String? = nil,
        scanDuration: TimeInterval? = nil,
        estimatedCost: Decimal? = nil
    ) {
        self.duration = duration
        self.tps = tps
        self.ttft = ttft
        self.totalTokens = totalTokens
        self.model = model
        self.filesScanned = filesScanned
        self.totalFileSize = totalFileSize
        self.duplicatesFound = duplicatesFound
        self.promptTokens = promptTokens
        self.retryCount = retryCount
        self.provider = provider
        self.scanDuration = scanDuration
        self.estimatedCost = estimatedCost
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

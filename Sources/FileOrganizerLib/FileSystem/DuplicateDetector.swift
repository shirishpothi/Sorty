//
//  DuplicateDetector.swift
//  FileOrganizer
//
//  Detects duplicate files using SHA-256 hashing
//

import Foundation
import CryptoKit
import Combine

/// Group of files with identical content
public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let hash: String
    public let files: [FileItem]
    public let totalSize: Int64
    public let potentialSavings: Int64 // Size that could be recovered by deleting duplicates
    
    public init(hash: String, files: [FileItem]) {
        self.id = UUID()
        self.hash = hash
        self.files = files
        self.totalSize = files.reduce(0) { $0 + $1.size }
        // Savings = total - one copy
        self.potentialSavings = files.dropFirst().reduce(0) { $0 + $1.size }
    }
    
    public var duplicateCount: Int {
        max(0, files.count - 1)
    }
}

/// Actor for detecting duplicate files based on content hash
public actor DuplicateDetector {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Find all duplicate files in a list of file items
    /// Files must have sha256Hash already computed
    public func findDuplicates(in files: [FileItem]) -> [DuplicateGroup] {
        // Group by hash
        var hashGroups: [String: [FileItem]] = [:]
        
        for file in files {
            guard let hash = file.sha256Hash else { continue }
            if hashGroups[hash] != nil {
                hashGroups[hash]?.append(file)
            } else {
                hashGroups[hash] = [file]
            }
        }
        
        // Filter to only groups with more than one file
        let duplicates = hashGroups
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(hash: $0.key, files: $0.value) }
            .sorted { $0.potentialSavings > $1.potentialSavings }
        
        return duplicates
    }
    
    /// Compute hashes for files that don't have them
    public func computeHashes(for files: inout [FileItem], progressHandler: ((Int, Int) -> Void)? = nil) async {
        for i in 0..<files.count {
            if files[i].sha256Hash == nil {
                files[i].sha256Hash = computeSHA256(for: URL(fileURLWithPath: files[i].path))
            }
            progressHandler?(i + 1, files.count)
            
            // Yield periodically for UI updates
            if i % 10 == 0 {
                await Task.yield()
            }
        }
    }
    
    /// Compute SHA-256 hash for a file
    private func computeSHA256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Get total potential savings from all duplicate groups
    public func totalPotentialSavings(in groups: [DuplicateGroup]) -> Int64 {
        groups.reduce(0) { $0 + $1.potentialSavings }
    }
    
    /// Get formatted savings string
    public func formattedSavings(in groups: [DuplicateGroup]) -> String {
        let savings = totalPotentialSavings(in: groups)
        return ByteCountFormatter.string(fromByteCount: savings, countStyle: .file)
    }
}

/// Manager for duplicate detection settings and results
@MainActor
public class DuplicateDetectionManager: ObservableObject {
    @Published public var duplicateGroups: [DuplicateGroup] = []
    @Published public var isScanning = false
    @Published public var scanProgress: Double = 0
    @Published public var lastScanDate: Date?
    
    private let detector = DuplicateDetector()
    
    public init() {}
    
    public var totalDuplicates: Int {
        duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
    }
    
    public var potentialSavings: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.potentialSavings }
    }
    
    public var formattedSavings: String {
        ByteCountFormatter.string(fromByteCount: potentialSavings, countStyle: .file)
    }
    
    public func scanForDuplicates(files: [FileItem]) async {
        isScanning = true
        scanProgress = 0
        
        var mutableFiles = files
        let total = files.count
        
        // Compute hashes inline to avoid Sendable closure issues
        for i in 0..<mutableFiles.count {
            if mutableFiles[i].sha256Hash == nil {
                mutableFiles[i].sha256Hash = Self.computeSHA256(for: URL(fileURLWithPath: mutableFiles[i].path))
            }
            scanProgress = Double(i + 1) / Double(total)
            
            // Yield periodically for UI updates
            if i % 10 == 0 {
                await Task.yield()
            }
        }
        
        // Find duplicates
        let groups = await detector.findDuplicates(in: mutableFiles)
        
        duplicateGroups = groups
        lastScanDate = Date()
        isScanning = false
        scanProgress = 1.0
    }
    
    /// Compute SHA-256 hash for a file (static to avoid actor issues)
    private static func computeSHA256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    public func clearResults() {
        duplicateGroups = []
        lastScanDate = nil
    }
}

//
//  FolderSuggestion.swift
//  FileOrganizer
//
//  AI-Generated Folder Organization Suggestion with Smart Renaming Support
//

import Foundation

/// Represents a file with its suggested rename
public struct FileRenameMapping: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var originalFile: FileItem
    public var suggestedName: String?
    public var renameReason: String?

    public init(
        id: UUID = UUID(),
        originalFile: FileItem,
        suggestedName: String? = nil,
        renameReason: String? = nil
    ) {
        self.id = id
        self.originalFile = originalFile
        self.suggestedName = suggestedName
        self.renameReason = renameReason
    }

    /// Returns the final filename (suggested or original)
    public var finalFilename: String {
        if let suggested = suggestedName, !suggested.isEmpty {
            return suggested
        }
        return originalFile.displayName
    }

    /// Check if this file has a rename suggestion
    public var hasRename: Bool {
        suggestedName != nil && suggestedName != originalFile.displayName
    }
}

public struct FolderSuggestion: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var folderName: String
    public var description: String
    public var files: [FileItem]
    public var subfolders: [FolderSuggestion]
    public var reasoning: String

    // Smart renaming support
    public var fileRenameMappings: [FileRenameMapping]
    
    // Tagging support
    public var fileTagMappings: [FileTagMapping]

    // Semantic analysis metadata
    public var semanticTags: [String]
    public var confidenceScore: Double?

    public init(
        id: UUID = UUID(),
        folderName: String,
        description: String = "",
        files: [FileItem] = [],
        subfolders: [FolderSuggestion] = [],
        reasoning: String = "",
        fileRenameMappings: [FileRenameMapping] = [],
        fileTagMappings: [FileTagMapping] = [],
        semanticTags: [String] = [],
        confidenceScore: Double? = nil
    ) {
        self.id = id
        self.folderName = folderName
        self.description = description
        self.files = files
        self.subfolders = subfolders
        self.reasoning = reasoning
        self.fileRenameMappings = fileRenameMappings
        self.fileTagMappings = fileTagMappings
        self.semanticTags = semanticTags
        self.confidenceScore = confidenceScore
    }

    public var totalFileCount: Int {
        files.count + subfolders.reduce(0) { $0 + $1.totalFileCount }
    }

    /// Number of files with rename suggestions in this folder
    public var renameCount: Int {
        let directRenames = fileRenameMappings.filter { $0.hasRename }.count
        let subfolderRenames = subfolders.reduce(0) { $0 + $1.renameCount }
        return directRenames + subfolderRenames
    }

    /// Get all file rename mappings including from subfolders
    public var allFileRenameMappings: [FileRenameMapping] {
        var mappings = fileRenameMappings
        for subfolder in subfolders {
            mappings.append(contentsOf: subfolder.allFileRenameMappings)
        }
        return mappings
    }

    /// Get rename mapping for a specific file
    public func renameMapping(for file: FileItem) -> FileRenameMapping? {
        if let mapping = fileRenameMappings.first(where: { $0.originalFile.id == file.id }) {
            return mapping
        }
        for subfolder in subfolders {
            if let mapping = subfolder.renameMapping(for: file) {
                return mapping
            }
        }
        return nil
    }

    /// Get tags for a specific file
    public func tags(for file: FileItem) -> [String] {
        if let mapping = fileTagMappings.first(where: { $0.originalFile.id == file.id }) {
            return mapping.tags
        }
        for subfolder in subfolders {
            let tags = subfolder.tags(for: file)
            if !tags.isEmpty { return tags }
        }
        return []
    }

    /// Returns files with their final names (renamed or original)
    public var filesWithFinalNames: [(file: FileItem, finalName: String)] {
        files.map { file in
            let mapping = fileRenameMappings.first { $0.originalFile.id == file.id }
            let finalName = mapping?.finalFilename ?? file.displayName
            return (file, finalName)
        }
    }

    // MARK: - Mutating Helpers

    /// Add a file to this folder
    public mutating func addFile(_ file: FileItem, suggestedName: String? = nil, renameReason: String? = nil) {
        files.append(file)
        if suggestedName != nil {
            let mapping = FileRenameMapping(
                originalFile: file,
                suggestedName: suggestedName,
                renameReason: renameReason
            )
            fileRenameMappings.append(mapping)
        }
    }

    /// Remove a file from this folder
    public mutating func removeFile(_ file: FileItem) {
        files.removeAll { $0.id == file.id }
        fileRenameMappings.removeAll { $0.originalFile.id == file.id }
    }

    /// Update rename suggestion for a file
    public mutating func updateRename(for file: FileItem, newName: String?, reason: String? = nil) {
        if let index = fileRenameMappings.firstIndex(where: { $0.originalFile.id == file.id }) {
            fileRenameMappings[index].suggestedName = newName
            fileRenameMappings[index].renameReason = reason
        } else if newName != nil {
            let mapping = FileRenameMapping(
                originalFile: file,
                suggestedName: newName,
                renameReason: reason
            )
            fileRenameMappings.append(mapping)
        }
    }
}

/// Represents a file with its suggested tags
public struct FileTagMapping: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var originalFile: FileItem
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        originalFile: FileItem,
        tags: [String] = []
    ) {
        self.id = id
        self.originalFile = originalFile
        self.tags = tags
    }
}

public extension FolderSuggestion {
    mutating func addTag(_ tag: String, for file: FileItem) {
        if let index = fileTagMappings.firstIndex(where: { $0.originalFile.id == file.id }) {
            if !fileTagMappings[index].tags.contains(tag) {
                fileTagMappings[index].tags.append(tag)
            }
        } else {
            let mapping = FileTagMapping(
                originalFile: file,
                tags: [tag]
            )
            fileTagMappings.append(mapping)
        }
    }
}


//
//  DirectoryScanner.swift
//  FileOrganizer
//
//  Recursively scans directories and builds file tree
//

import Foundation
import CryptoKit

actor DirectoryScanner {
    private var isScanning = false
    private var scannedCount = 0
    private let contentAnalyzer = ContentAnalyzer()
    
    /// Scan directory with optional deep content analysis and hash computation
    func scanDirectory(
        at url: URL,
        includeHidden: Bool = false,
        deepScan: Bool = false,
        computeHashes: Bool = false
    ) async throws -> [FileItem] {
        guard !isScanning else {
            throw ScannerError.alreadyScanning
        }
        
        isScanning = true
        scannedCount = 0
        defer { isScanning = false }
        
        var files: [FileItem] = []
        let fileManager = FileManager.default
        
        guard url.isFileURL else {
            throw ScannerError.invalidURL
        }
        
        guard fileManager.fileExists(atPath: url.path) else {
            throw ScannerError.pathNotFound
        }
        
        try await scanDirectoryRecursive(
            at: url,
            fileManager: fileManager,
            includeHidden: includeHidden,
            deepScan: deepScan,
            computeHashes: computeHashes,
            files: &files
        )
        
        return files
    }

    /// Scan a single file and return a FileItem
    func scanFile(
        at url: URL,
        deepScan: Bool = false,
        computeHashes: Bool = false
    ) async throws -> FileItem {
        let fileManager = FileManager.default
        
        guard url.isFileURL else {
            throw ScannerError.invalidURL
        }
        
        guard fileManager.fileExists(atPath: url.path) else {
            throw ScannerError.pathNotFound
        }
        
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .creationDateKey, .isHiddenKey]
        let resourceValues = try? url.resourceValues(forKeys: Set(resourceKeys))
        
        let isDirectory = resourceValues?.isDirectory ?? false
        let size = resourceValues?.fileSize ?? 0
        let creationDate = resourceValues?.creationDate
        
        let pathExtension = url.pathExtension
        let fileName = url.deletingPathExtension().lastPathComponent
        
        // Deep scan: extract content metadata
        var contentMetadata: ContentMetadata?
        if deepScan {
            contentMetadata = await contentAnalyzer.analyze(fileURL: url)
        }
        
        // Hash computation for duplicate detection
        var sha256Hash: String?
        if computeHashes {
            sha256Hash = computeSHA256(for: url)
        }
        
        return FileItem(
            path: url.path,
            name: fileName,
            extension: pathExtension,
            size: Int64(size),
            isDirectory: isDirectory,
            creationDate: creationDate,
            contentMetadata: contentMetadata,
            sha256Hash: sha256Hash
        )
    }
    
    private func scanDirectoryRecursive(
        at url: URL,
        fileManager: FileManager,
        includeHidden: Bool,
        deepScan: Bool,
        computeHashes: Bool,
        files: inout [FileItem]
    ) async throws {
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .creationDateKey, .isHiddenKey]
        
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            throw ScannerError.enumerationFailed
        }
        
        while let fileURL = enumerator.nextObject() as? URL {
            // Skip hidden files if not including them
            if !includeHidden {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isHiddenKey])
                if resourceValues?.isHidden == true {
                    continue
                }
            }
            
            // Get file attributes
            let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            let isDirectory = resourceValues?.isDirectory ?? false
            let size = resourceValues?.fileSize ?? 0
            let creationDate = resourceValues?.creationDate
            
            // Skip if it's a directory (we only want files)
            if isDirectory {
                continue
            }
            
            let pathExtension = fileURL.pathExtension
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            
            // Deep scan: extract content metadata
            var contentMetadata: ContentMetadata?
            if deepScan {
                contentMetadata = await contentAnalyzer.analyze(fileURL: fileURL)
            }
            
            // Hash computation for duplicate detection
            var sha256Hash: String?
            if computeHashes {
                sha256Hash = computeSHA256(for: fileURL)
            }
            
            let fileItem = FileItem(
                path: fileURL.path,
                name: fileName,
                extension: pathExtension,
                size: Int64(size),
                isDirectory: false,
                creationDate: creationDate,
                contentMetadata: contentMetadata,
                sha256Hash: sha256Hash
            )
            
            files.append(fileItem)
            scannedCount += 1
            
            // Yield to allow UI updates
            if scannedCount % 50 == 0 {
                await Task.yield()
            }
        }
    }
    
    /// Compute SHA-256 hash for duplicate detection
    private func computeSHA256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    func getProgress() -> Int {
        scannedCount
    }
}

enum ScannerError: LocalizedError {
    case alreadyScanning
    case invalidURL
    case pathNotFound
    case enumerationFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyScanning:
            return "A scan is already in progress"
        case .invalidURL:
            return "Invalid URL provided"
        case .pathNotFound:
            return "The specified path does not exist"
        case .enumerationFailed:
            return "Failed to enumerate directory contents"
        }
    }
}




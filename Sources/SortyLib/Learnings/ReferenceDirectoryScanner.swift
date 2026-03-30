//
//  ReferenceDirectoryScanner.swift
//  Sorty
//
//  Scans a reference model directory off the main actor, capturing folder hierarchy,
//  file-type distribution, and naming conventions for prompt injection.
//

import Foundation

public struct ReferenceDirectoryScanner: Sendable {
    
    private static let maxDepth = 3
    private static let maxFolders = 50
    private static let maxFilesPerFolder = 20
    private static let maxSampleFileNames = 5
    
    /// Scan a directory and return a snapshot. Safe to call off the main actor.
    public static func scan(url: URL) async -> ReferenceDirectorySnapshot {
        await Task.detached {
            performScan(url: url)
        }.value
    }
    
    private static func performScan(url: URL) -> ReferenceDirectorySnapshot {
        let fm = FileManager.default
        var folders: [ReferenceFolder] = []
        var totalFileCount = 0
        var allFolderNames: [String] = []
        
        func scanDirectory(_ scanURL: URL, depth: Int, prefix: String) {
            guard depth <= maxDepth, folders.count < maxFolders else { return }
            
            guard let contents = try? fm.contentsOfDirectory(
                at: scanURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            
            let subdirs = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
            
            let files = contents.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            }
            
            let sampledFiles = files.prefix(maxFilesPerFolder)
            var typeDistribution: [String: Int] = [:]
            var sampleNames: [String] = []
            
            for file in sampledFiles {
                let ext = file.pathExtension.lowercased()
                let key = ext.isEmpty ? "(none)" : ext
                typeDistribution[key, default: 0] += 1
                if sampleNames.count < maxSampleFileNames {
                    sampleNames.append(file.lastPathComponent)
                }
            }
            
            let fileCount = files.count
            totalFileCount += fileCount
            
            if !prefix.isEmpty {
                let folderName = scanURL.lastPathComponent
                allFolderNames.append(folderName)
                folders.append(ReferenceFolder(
                    relativePath: prefix,
                    name: folderName,
                    depth: depth,
                    fileCount: fileCount,
                    fileTypeDistribution: typeDistribution,
                    sampleFileNames: sampleNames
                ))
            }
            
            for subdir in subdirs {
                guard folders.count < maxFolders else { return }
                let name = prefix.isEmpty ? subdir.lastPathComponent : "\(prefix)/\(subdir.lastPathComponent)"
                scanDirectory(subdir, depth: depth + 1, prefix: name)
            }
        }
        
        scanDirectory(url, depth: 0, prefix: "")
        
        let conventions = detectNamingConventions(folderNames: allFolderNames)
        
        return ReferenceDirectorySnapshot(
            scannedAt: Date(),
            folderHierarchy: folders,
            namingConventions: conventions,
            totalFolderCount: folders.count,
            totalFileCount: totalFileCount
        )
    }
    
    // MARK: - Naming Convention Detection
    
    private static func detectNamingConventions(folderNames: [String]) -> [String] {
        guard !folderNames.isEmpty else { return [] }
        
        var conventions: [String] = []
        var kebabCount = 0
        var snakeCount = 0
        var titleCaseCount = 0
        var camelCaseCount = 0
        var datePatternCount = 0
        var uppercaseCount = 0
        
        let dateRegex = try? NSRegularExpression(pattern: #"\d{4}[-_]\d{2}[-_]\d{2}"#)
        let kebabRegex = try? NSRegularExpression(pattern: #"^[a-z0-9]+(-[a-z0-9]+)+$"#)
        let snakeRegex = try? NSRegularExpression(pattern: #"^[a-z0-9]+(_[a-z0-9]+)+$"#)
        
        for name in folderNames {
            let range = NSRange(name.startIndex..., in: name)
            
            if let dateRegex, dateRegex.firstMatch(in: name, range: range) != nil {
                datePatternCount += 1
            }
            if let kebabRegex, kebabRegex.firstMatch(in: name, range: range) != nil {
                kebabCount += 1
            }
            if let snakeRegex, snakeRegex.firstMatch(in: name, range: range) != nil {
                snakeCount += 1
            }
            if name == name.uppercased() && name.count > 1 && name.contains(where: { $0.isLetter }) {
                uppercaseCount += 1
            }
            if isTitleCase(name) {
                titleCaseCount += 1
            }
            if isCamelCase(name) {
                camelCaseCount += 1
            }
        }
        
        let threshold = max(1, folderNames.count / 5)
        
        if datePatternCount >= threshold { conventions.append("YYYY-MM-DD date prefixes") }
        if kebabCount >= threshold { conventions.append("kebab-case") }
        if snakeCount >= threshold { conventions.append("snake_case") }
        if titleCaseCount >= threshold { conventions.append("Title Case") }
        if camelCaseCount >= threshold { conventions.append("camelCase") }
        if uppercaseCount >= threshold { conventions.append("UPPERCASE") }
        
        if conventions.isEmpty {
            conventions.append("mixed naming")
        }
        
        return conventions
    }
    
    private static func isTitleCase(_ name: String) -> Bool {
        let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard words.count >= 2 else { return false }
        return words.allSatisfy { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }
    }
    
    private static func isCamelCase(_ name: String) -> Bool {
        guard name.count > 2,
              let first = name.first, first.isLowercase,
              !name.contains(" "), !name.contains("-"), !name.contains("_")
        else { return false }
        return name.contains(where: { $0.isUppercase })
    }
}

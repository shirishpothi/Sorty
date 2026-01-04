//
//  PatternMatcher.swift
//  FileOrganizer
//
//  Utilities for pattern detection and regex/template matching
//

import Foundation

/// Utilities for extracting patterns from filenames and paths
public struct PatternMatcher {
    
    // MARK: - Common Patterns
    
    /// Known filename patterns for various file types
    public enum KnownPattern: String, CaseIterable {
        // Photo patterns
        case imgDate = "IMG_YYYYMMDD_HHMMSS"    // IMG_20240101_123456.jpg
        case dscSeq = "DSC_NNNN"                 // DSC_1234.jpg
        case photoDate = "PHOTO_YYYY-MM-DD"      // PHOTO_2024-01-01.jpg
        
        // Video patterns
        case vidDate = "VID_YYYYMMDD_HHMMSS"    // VID_20240101_123456.mp4
        case movieRelease = "Title.Year.Quality" // Movie.2010.1080p.BluRay.mkv
        
        // Music patterns
        case artistTitle = "Artist - Title"      // Artist Name - Song Title.mp3
        case trackNumber = "NN - Title"          // 01 - Song Title.mp3
        
        // Document patterns
        case datePrefix = "YYYY-MM-DD - Name"    // 2024-01-01 - Document.pdf
        case dateInName = "Name YYYY-MM-DD"      // Report 2024-01-01.pdf
        
        public var regex: String {
            switch self {
            case .imgDate:
                return "^IMG_(\\d{4})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})(\\d{2})"
            case .dscSeq:
                return "^DSC[_-]?(\\d{4,5})"
            case .photoDate:
                return "^PHOTO[_-]?(\\d{4})-(\\d{2})-(\\d{2})"
            case .vidDate:
                return "^VID_(\\d{4})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})(\\d{2})"
            case .movieRelease:
                return "^(.+?)\\.(19|20\\d{2})\\.(\\d{3,4}p)"
            case .artistTitle:
                return "^(.+?) - (.+)$"
            case .trackNumber:
                return "^(\\d{1,2}) - (.+)$"
            case .datePrefix:
                return "^(\\d{4})-(\\d{2})-(\\d{2}) - (.+)$"
            case .dateInName:
                return "^(.+?) (\\d{4})-(\\d{2})-(\\d{2})$"
            }
        }
    }
    
    // MARK: - Date Extraction
    
    /// Extract date from filename using known patterns
    public static func extractDate(from filename: String) -> Date? {
        let name = (filename as NSString).deletingPathExtension
        
        // Try IMG/VID pattern: YYYYMMDD_HHMMSS
        if let match = name.range(of: "(\\d{4})(\\d{2})(\\d{2})_(\\d{2})(\\d{2})(\\d{2})", options: .regularExpression) {
            let dateStr = String(name[match])
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            return formatter.date(from: dateStr)
        }
        
        // Try YYYY-MM-DD pattern
        if let match = name.range(of: "(\\d{4})-(\\d{2})-(\\d{2})", options: .regularExpression) {
            let dateStr = String(name[match])
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateStr)
        }
        
        // Try YYYY.MM.DD pattern
        if let match = name.range(of: "(\\d{4})\\.(\\d{2})\\.(\\d{2})", options: .regularExpression) {
            let dateStr = String(name[match]).replacingOccurrences(of: ".", with: "-")
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: dateStr)
        }
        
        return nil
    }
    
    /// Extract year from filename
    public static func extractYear(from filename: String) -> Int? {
        let name = (filename as NSString).deletingPathExtension
        
        // Look for 4-digit year (19xx or 20xx)
        if let match = name.range(of: "(19|20)\\d{2}", options: .regularExpression) {
            return Int(name[match])
        }
        return nil
    }
    
    // MARK: - Name Components
    
    /// Tokenize filename into components
    public static func tokenize(_ filename: String) -> [String] {
        let name = (filename as NSString).deletingPathExtension
        
        // Split on common delimiters
        let components = name.components(separatedBy: CharacterSet(charactersIn: "_ -.,"))
            .filter { !$0.isEmpty }
        
        return components
    }
    
    /// Check if filename matches a known pattern
    public static func matchesPattern(_ filename: String, pattern: KnownPattern) -> Bool {
        let name = (filename as NSString).deletingPathExtension
        return name.range(of: pattern.regex, options: .regularExpression) != nil
    }
    
    /// Detect which known patterns a filename matches
    public static func detectPatterns(in filename: String) -> [KnownPattern] {
        KnownPattern.allCases.filter { matchesPattern(filename, pattern: $0) }
    }
    
    // MARK: - Folder Structure Analysis
    
    /// Analyze folder structure from example paths
    public static func analyzeFolderStructure(from paths: [String]) -> FolderStructureAnalysis {
        var result = FolderStructureAnalysis()
        
        for path in paths {
            let components = URL(fileURLWithPath: path).pathComponents
            
            // Check for date-based folders
            for component in components {
                // Year folder (e.g., "2024")
                if let year = Int(component), year >= 1990 && year <= 2100 {
                    result.usesYearFolders = true
                }
                
                // Month folder (e.g., "01" or "January")
                if component.range(of: "^(0[1-9]|1[0-2])$", options: .regularExpression) != nil {
                    result.usesMonthFolders = true
                }
                
                // Date folder (e.g., "2024-01-01")
                if component.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil {
                    result.usesDateFolders = true
                }
            }
            
            // Check for extension-based organization
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            let category = FileCategory.from(extension: ext)
            if components.contains(where: { $0.lowercased() == category.rawValue + "s" || $0.lowercased() == category.rawValue }) {
                result.usesCategoryFolders = true
            }
        }
        
        // Determine primary grouping key
        if result.usesDateFolders {
            result.primaryGroupingKey = "date"
        } else if result.usesYearFolders && result.usesMonthFolders {
            result.primaryGroupingKey = "year/month"
        } else if result.usesYearFolders {
            result.primaryGroupingKey = "year"
        } else if result.usesCategoryFolders {
            result.primaryGroupingKey = "category"
        }
        
        return result
    }
    
    // MARK: - Template Building
    
    /// Build a template string from example mappings
    public static func buildTemplate(from examples: [(src: String, dst: String)]) -> String? {
        guard !examples.isEmpty else { return nil }
        
        // Analyze destination paths
        let dstPaths = examples.map { $0.dst }
        let structure = analyzeFolderStructure(from: dstPaths)
        
        var templateParts: [String] = []
        
        // Build folder template
        if structure.usesDateFolders {
            templateParts.append("{year}/{date}")
        } else if structure.usesYearFolders && structure.usesMonthFolders {
            templateParts.append("{year}/{month}")
        } else if structure.usesYearFolders {
            templateParts.append("{year}")
        } else if structure.usesCategoryFolders {
            templateParts.append("{category}")
        }
        
        // Add filename template
        templateParts.append("{filename}")
        
        return templateParts.joined(separator: "/")
    }
    
    /// Build a regex pattern from example filenames
    public static func buildPattern(from filenames: [String]) -> String? {
        guard !filenames.isEmpty else { return nil }
        
        // Find common patterns among filenames
        let detectedPatterns = filenames.flatMap { detectPatterns(in: $0) }
        let patternCounts = Dictionary(grouping: detectedPatterns, by: { $0 }).mapValues { $0.count }
        
        // Use the most common pattern
        if let mostCommon = patternCounts.max(by: { $0.value < $1.value })?.key {
            return mostCommon.regex
        }
        
        // Fallback: try to build a simple pattern
        let _ = filenames.flatMap { tokenize($0) }
        
        // If filenames share a common prefix, use it
        if let prefix = findCommonPrefix(filenames) {
            return "^\(NSRegularExpression.escapedPattern(for: prefix)).*"
        }
        
        return nil
    }
    
    /// Find common prefix among strings
    private static func findCommonPrefix(_ strings: [String]) -> String? {
        guard let first = strings.first else { return nil }
        
        var prefix = ""
        for (index, _) in first.enumerated() {
            let prefixCandidate = String(first.prefix(index + 1))
            if strings.allSatisfy({ $0.hasPrefix(prefixCandidate) }) {
                prefix = prefixCandidate
            } else {
                break
            }
        }
        
        return prefix.isEmpty ? nil : prefix
    }
}

// MARK: - Supporting Types

public struct FolderStructureAnalysis: Sendable {
    public var usesYearFolders: Bool = false
    public var usesMonthFolders: Bool = false
    public var usesDateFolders: Bool = false
    public var usesCategoryFolders: Bool = false
    public var primaryGroupingKey: String?
}

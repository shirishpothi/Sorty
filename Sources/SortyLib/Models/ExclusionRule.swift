//
//  ExclusionRule.swift
//  Sorty
//
//  Comprehensive exclusion rules for file organization
//  Supports multiple rule types, presets, and advanced matching
//

import Foundation
import SwiftUI
import Combine

// MARK: - Rule Types

public enum ExclusionRuleType: String, Codable, CaseIterable, Identifiable {
    case fileExtension = "File Extension"
    case fileName = "File Name"
    case folderName = "Folder Name"
    case pathContains = "Path Contains"
    case regex = "Regular Expression"
    case fileSize = "File Size"
    case creationDate = "Creation Date"
    case modificationDate = "Modification Date"
    case hiddenFiles = "Hidden Files"
    case systemFiles = "System Files"
    case fileType = "File Type Category"
    case customScript = "Custom Script"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .fileExtension: return "doc.badge.ellipsis"
        case .fileName: return "textformat"
        case .folderName: return "folder"
        case .pathContains: return "folder.badge.questionmark"
        case .regex: return "chevron.left.forwardslash.chevron.right"
        case .fileSize: return "externaldrive"
        case .creationDate: return "calendar.badge.plus"
        case .modificationDate: return "calendar.badge.clock"
        case .hiddenFiles: return "eye.slash"
        case .systemFiles: return "gearshape.2"
        case .fileType: return "doc.on.doc"
        case .customScript: return "applescript"
        }
    }

    public var description: String {
        switch self {
        case .fileExtension: return "Match files by extension (e.g., 'pdf', 'jpg')"
        case .fileName: return "Match files containing text in their name"
        case .folderName: return "Exclude entire folders by name"
        case .pathContains: return "Match files whose path contains text"
        case .regex: return "Advanced pattern matching with regular expressions"
        case .fileSize: return "Exclude files based on size (MB)"
        case .creationDate: return "Exclude files by creation date"
        case .modificationDate: return "Exclude files by modification date"
        case .hiddenFiles: return "Match hidden files (starting with '.')"
        case .systemFiles: return "Match macOS system files"
        case .fileType: return "Match by file type category"
        case .customScript: return "Run custom AppleScript for matching"
        }
    }

    public var requiresPattern: Bool {
        switch self {
        case .hiddenFiles, .systemFiles:
            return false
        default:
            return true
        }
    }
}

// MARK: - File Type Categories

public enum FileTypeCategory: String, Codable, CaseIterable, Identifiable {
    case images = "Images"
    case videos = "Videos"
    case audio = "Audio"
    case documents = "Documents"
    case archives = "Archives"
    case code = "Code"
    case applications = "Applications"
    case fonts = "Fonts"
    case databases = "Databases"
    case other = "Other"

    public var id: String { rawValue }

    public var extensions: [String] {
        switch self {
        case .images:
            return ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg", "raw", "cr2", "nef", "arw", "dng", "ico", "psd", "ai"]
        case .videos:
            return ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpeg", "mpg", "3gp", "mts", "m2ts", "vob"]
        case .audio:
            return ["mp3", "wav", "aac", "flac", "ogg", "wma", "m4a", "aiff", "alac", "midi", "mid"]
        case .documents:
            return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "odt", "ods", "odp", "pages", "numbers", "keynote", "md", "markdown", "epub", "mobi"]
        case .archives:
            return ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso", "pkg", "deb", "rpm"]
        case .code:
            return ["swift", "py", "js", "ts", "html", "css", "java", "c", "cpp", "h", "hpp", "m", "mm", "rb", "php", "go", "rs", "kt", "scala", "sh", "bash", "zsh", "json", "xml", "yaml", "yml", "toml", "sql"]
        case .applications:
            return ["app", "exe", "msi", "apk", "ipa"]
        case .fonts:
            return ["ttf", "otf", "woff", "woff2", "eot", "fon"]
        case .databases:
            return ["db", "sqlite", "sqlite3", "mdb", "accdb", "realm"]
        case .other:
            return []
        }
    }

    public var icon: String {
        switch self {
        case .images: return "photo"
        case .videos: return "film"
        case .audio: return "music.note"
        case .documents: return "doc.text"
        case .archives: return "archivebox"
        case .code: return "curlybraces"
        case .applications: return "app.badge"
        case .fonts: return "textformat.abc"
        case .databases: return "cylinder"
        case .other: return "questionmark.folder"
        }
    }
}

// MARK: - Exclusion Rule Model

public struct ExclusionRule: Codable, Identifiable, Hashable {
    public let id: UUID
    public var type: ExclusionRuleType
    public var pattern: String
    public var isEnabled: Bool
    public var description: String?
    public var isBuiltIn: Bool

    // For size comparison (in MB)
    public var numericValue: Double?
    // For date comparison direction (true = older than, false = newer than)
    // For size (true = larger than, false = smaller than)
    public var comparisonGreater: Bool?

    // For file type category matching
    public var fileTypeCategory: FileTypeCategory?

    // Case sensitivity for text matching
    public var caseSensitive: Bool

    // Negate the rule (exclude files that DON'T match)
    public var negated: Bool

    public init(
        id: UUID = UUID(),
        type: ExclusionRuleType,
        pattern: String = "",
        isEnabled: Bool = true,
        description: String? = nil,
        isBuiltIn: Bool = false,
        numericValue: Double? = nil,
        comparisonGreater: Bool? = nil,
        fileTypeCategory: FileTypeCategory? = nil,
        caseSensitive: Bool = false,
        negated: Bool = false
    ) {
        self.id = id
        self.type = type
        self.pattern = pattern
        self.isEnabled = isEnabled
        self.description = description
        self.isBuiltIn = isBuiltIn
        self.numericValue = numericValue
        self.comparisonGreater = comparisonGreater
        self.fileTypeCategory = fileTypeCategory
        self.caseSensitive = caseSensitive
        self.negated = negated
    }

    /// Check if a file matches this rule
    public func matches(_ file: FileItem) -> Bool {
        guard isEnabled else { return false }

        let result: Bool
        switch type {
        case .fileExtension:
            if caseSensitive {
                result = file.extension == pattern
            } else {
                result = file.extension.lowercased() == pattern.lowercased()
            }

        case .fileName:
            if caseSensitive {
                result = file.name.contains(pattern)
            } else {
                result = file.name.localizedCaseInsensitiveContains(pattern)
            }

        case .folderName:
            let pathComponents = file.path.components(separatedBy: "/")
            if caseSensitive {
                result = pathComponents.contains { $0.contains(pattern) }
            } else {
                result = pathComponents.contains { $0.localizedCaseInsensitiveContains(pattern) }
            }

        case .pathContains:
            if caseSensitive {
                result = file.path.contains(pattern)
            } else {
                result = file.path.localizedCaseInsensitiveContains(pattern)
            }

        case .regex:
            let options: NSRegularExpression.Options = caseSensitive ? [] : .caseInsensitive
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                return false
            }
            let range = NSRange(location: 0, length: file.name.utf16.count)
            result = regex.firstMatch(in: file.name, options: [], range: range) != nil

        case .fileSize:
            guard let limitMB = numericValue, let greater = comparisonGreater else { return false }
            let sizeMB = Double(file.size) / (1024 * 1024)
            result = greater ? (sizeMB > limitMB) : (sizeMB < limitMB)

        case .creationDate:
            guard let days = numericValue, let older = comparisonGreater else { return false }
            let date = file.creationDate ?? Date()
            let limitDate = Calendar.current.date(byAdding: .day, value: -Int(days), to: Date()) ?? Date()
            result = older ? (date < limitDate) : (date > limitDate)

        case .modificationDate:
            guard let days = numericValue, let older = comparisonGreater else { return false }
            // Use creation date as fallback since FileItem doesn't track modification date
            let date = file.creationDate ?? Date()
            let limitDate = Calendar.current.date(byAdding: .day, value: -Int(days), to: Date()) ?? Date()
            result = older ? (date < limitDate) : (date > limitDate)

        case .hiddenFiles:
            result = file.name.hasPrefix(".") || file.path.contains("/.")

        case .systemFiles:
            let systemPatterns = [".DS_Store", "Thumbs.db", "desktop.ini", ".Spotlight-V100", ".Trashes", ".fseventsd", ".TemporaryItems"]
            result = systemPatterns.contains { file.name == $0 || file.path.contains($0) }

        case .fileType:
            guard let category = fileTypeCategory else { return false }
            result = category.extensions.contains(file.extension.lowercased())

        case .customScript:
            // Custom scripts not implemented in basic matching
            result = false
        }

        return negated ? !result : result
    }

    /// Human-readable description of the rule
    public var displayDescription: String {
        if let desc = description, !desc.isEmpty {
            return desc
        }

        switch type {
        case .fileExtension:
            return ".\(pattern) files"
        case .fileName:
            return "Files containing '\(pattern)'"
        case .folderName:
            return "Folders named '\(pattern)'"
        case .pathContains:
            return "Paths containing '\(pattern)'"
        case .regex:
            return "Pattern: \(pattern)"
        case .fileSize:
            let direction = (comparisonGreater ?? true) ? "larger" : "smaller"
            return "Files \(direction) than \(Int(numericValue ?? 0)) MB"
        case .creationDate, .modificationDate:
            let direction = (comparisonGreater ?? true) ? "older" : "newer"
            return "Files \(direction) than \(Int(numericValue ?? 0)) days"
        case .hiddenFiles:
            return "Hidden files"
        case .systemFiles:
            return "System files"
        case .fileType:
            return "\(fileTypeCategory?.rawValue ?? "Unknown") files"
        case .customScript:
            return "Custom script"
        }
    }
}

// MARK: - Rule Presets

public struct ExclusionRulePreset: Identifiable {
    public let id: UUID
    public let name: String
    public let description: String
    public let icon: String
    public let rules: [ExclusionRule]

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String,
        rules: [ExclusionRule]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.rules = rules
    }

    public static let presets: [ExclusionRulePreset] = [
        // Development Preset
        ExclusionRulePreset(
            name: "Developer",
            description: "Exclude common development folders and files",
            icon: "hammer",
            rules: [
                ExclusionRule(type: .folderName, pattern: "node_modules", description: "Node.js modules", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".git", description: "Git repositories", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".svn", description: "SVN repositories", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".hg", description: "Mercurial repositories", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "build", description: "Build folders", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "dist", description: "Distribution folders", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "DerivedData", description: "Xcode derived data", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "__pycache__", description: "Python cache", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".venv", description: "Python virtual environments", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "Pods", description: "CocoaPods", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "Carthage", description: "Carthage dependencies", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "o", description: "Object files", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "pyc", description: "Python bytecode", isBuiltIn: true),
            ]
        ),

        // System Files Preset
        ExclusionRulePreset(
            name: "System Files",
            description: "Exclude macOS system and hidden files",
            icon: "gearshape.2",
            rules: [
                ExclusionRule(type: .hiddenFiles, pattern: "", description: "All hidden files", isBuiltIn: true),
                ExclusionRule(type: .systemFiles, pattern: "", description: "System metadata files", isBuiltIn: true),
                ExclusionRule(type: .fileName, pattern: ".DS_Store", description: "Finder metadata", isBuiltIn: true),
                ExclusionRule(type: .fileName, pattern: ".localized", description: "Localization files", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".Spotlight-V100", description: "Spotlight index", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".Trashes", description: "Trash folder", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".fseventsd", description: "File system events", isBuiltIn: true),
            ]
        ),

        // Large Files Preset
        ExclusionRulePreset(
            name: "Large Files",
            description: "Exclude files larger than 100MB",
            icon: "externaldrive",
            rules: [
                ExclusionRule(type: .fileSize, pattern: "", description: "Files > 100MB", isBuiltIn: true, numericValue: 100, comparisonGreater: true),
            ]
        ),

        // Old Files Preset
        ExclusionRulePreset(
            name: "Old Files",
            description: "Exclude files older than 1 year",
            icon: "clock.arrow.circlepath",
            rules: [
                ExclusionRule(type: .creationDate, pattern: "", description: "Files > 365 days old", isBuiltIn: true, numericValue: 365, comparisonGreater: true),
            ]
        ),

        // Applications Preset
        ExclusionRulePreset(
            name: "Applications",
            description: "Exclude application bundles and installers",
            icon: "app.badge",
            rules: [
                ExclusionRule(type: .fileExtension, pattern: "app", description: "Application bundles", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "dmg", description: "Disk images", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "pkg", description: "Installer packages", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "exe", description: "Windows executables", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "msi", description: "Windows installers", isBuiltIn: true),
            ]
        ),

        // Media Preset
        ExclusionRulePreset(
            name: "Media Files",
            description: "Exclude large media files",
            icon: "play.rectangle",
            rules: [
                ExclusionRule(type: .fileType, pattern: "", description: "Video files", isBuiltIn: true, fileTypeCategory: .videos),
                ExclusionRule(type: .fileType, pattern: "", description: "Audio files", isBuiltIn: true, fileTypeCategory: .audio),
            ]
        ),

        // Temporary Files Preset
        ExclusionRulePreset(
            name: "Temporary Files",
            description: "Exclude temporary and cache files",
            icon: "trash",
            rules: [
                ExclusionRule(type: .fileExtension, pattern: "tmp", description: "Temporary files", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "temp", description: "Temp files", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "cache", description: "Cache files", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "log", description: "Log files", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "bak", description: "Backup files", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "swp", description: "Vim swap files", isBuiltIn: true),
                ExclusionRule(type: .regex, pattern: "~$.*", description: "Office temp files", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "Caches", description: "Cache folders", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "tmp", description: "Temp folders", isBuiltIn: true),
            ]
        ),

        // Minimal Preset
        ExclusionRulePreset(
            name: "Minimal",
            description: "Basic exclusions only",
            icon: "minus.circle",
            rules: [
                ExclusionRule(type: .folderName, pattern: ".git", description: "Git repositories", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "app", description: "Application bundles", isBuiltIn: true),
            ]
        ),
    ]
}

// MARK: - Exclusion Rules Manager

@MainActor
public class ExclusionRulesManager: ObservableObject {
    @Published public private(set) var rules: [ExclusionRule] = []
    @Published public var activePresetName: String?

    private let userDefaults = UserDefaults.standard
    private let rulesKey = "exclusionRules"
    private let presetKey = "activeExclusionPreset"

    public init() {
        loadRules()
        if rules.isEmpty {
            setupDefaultRules()
        }
    }

    // MARK: - Rule Management

    public func addRule(_ rule: ExclusionRule) {
        rules.append(rule)
        saveRules()
    }

    public func removeRule(_ rule: ExclusionRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }

    public func updateRule(_ rule: ExclusionRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            saveRules()
        }
    }

    public func toggleRule(_ rule: ExclusionRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].isEnabled.toggle()
            saveRules()
        }
    }

    public func moveRule(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        saveRules()
    }

    // MARK: - Preset Management

    public func applyPreset(_ preset: ExclusionRulePreset) {
        // Remove existing non-custom rules
        rules.removeAll { $0.isBuiltIn }

        // Add preset rules
        rules.append(contentsOf: preset.rules)
        activePresetName = preset.name
        saveRules()
    }

    public func clearAllRules() {
        rules.removeAll()
        activePresetName = nil
        saveRules()
    }

    public func resetToDefaults() {
        rules.removeAll()
        setupDefaultRules()
    }

    // MARK: - Matching

    public func shouldExclude(_ file: FileItem) -> Bool {
        rules.contains { $0.matches(file) }
    }

    public func filterFiles(_ files: [FileItem]) -> [FileItem] {
        files.filter { !shouldExclude($0) }
    }

    /// Returns which rules matched a file (for debugging)
    public func matchingRules(for file: FileItem) -> [ExclusionRule] {
        rules.filter { $0.matches(file) }
    }

    // MARK: - Statistics

    public var enabledRulesCount: Int {
        rules.filter { $0.isEnabled }.count
    }

    public var rulesByType: [ExclusionRuleType: [ExclusionRule]] {
        Dictionary(grouping: rules) { $0.type }
    }

    // MARK: - Persistence

    private func setupDefaultRules() {
        // Start with Developer preset for sensible defaults
        if let devPreset = ExclusionRulePreset.presets.first(where: { $0.name == "Developer" }) {
            rules = devPreset.rules
            activePresetName = devPreset.name
        } else {
            // Fallback basic rules
            rules = [
                ExclusionRule(type: .folderName, pattern: ".git", description: "Git repositories", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: ".svn", description: "SVN repositories", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "node_modules", description: "Node modules", isBuiltIn: true),
                ExclusionRule(type: .fileExtension, pattern: "app", description: "Application bundles", isBuiltIn: true),
                ExclusionRule(type: .hiddenFiles, pattern: "", description: "Hidden files", isBuiltIn: true),
            ]
        }
        saveRules()
    }

    private func loadRules() {
        if let data = userDefaults.data(forKey: rulesKey),
           let decoded = try? JSONDecoder().decode([ExclusionRule].self, from: data) {
            rules = decoded
        }
        activePresetName = userDefaults.string(forKey: presetKey)
    }

    private func saveRules() {
        if let encoded = try? JSONEncoder().encode(rules) {
            userDefaults.set(encoded, forKey: rulesKey)
        }
        userDefaults.set(activePresetName, forKey: presetKey)
    }
}


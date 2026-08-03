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

public enum ExclusionRuleType: String, Codable, CaseIterable, Identifiable, Sendable {
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

    public var friendlyName: String {
        switch self {
        case .fileExtension: return "Files with an extension"
        case .fileName: return "Files with a name"
        case .folderName: return "Folders with a name"
        case .pathContains: return "Folder"
        case .regex: return "Advanced name pattern"
        case .fileSize: return "Files by size"
        case .creationDate: return "Files by creation date"
        case .modificationDate: return "Files by modification date"
        case .hiddenFiles: return "Hidden files"
        case .systemFiles: return "macOS system files"
        case .fileType: return "A kind of file"
        case .customScript: return "Custom script"
        }
    }

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

public enum FileTypeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
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

public struct ExclusionRule: Codable, Identifiable, Hashable, Sendable {
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
        ExclusionMatcher(rules: [self]).shouldExclude(file)
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

private extension String {
    func trimmingLeadingDots() -> String {
        var value = self
        while value.hasPrefix(".") {
            value.removeFirst()
        }
        return value
    }
}

// MARK: - Compiled Matching

/// An immutable, concurrency-safe snapshot of exclusion rules.
///
/// Rules are normalized and regular expressions are compiled once when the
/// snapshot is created. The snapshot can then be shared by manual organization,
/// watched-folder work, and background scanners without main-actor contention.
public struct ExclusionMatcher: Sendable {
    public static let empty = ExclusionMatcher(rules: [])

    private static let systemPatterns = [
        ".DS_Store",
        "Thumbs.db",
        "desktop.ini",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
    ]

    private let rules: [CompiledExclusionRule]
    private let pathOnlyRules: [CompiledExclusionRule]
    private let metadataRules: [CompiledExclusionRule]
    private let directoryPruningRules: [CompiledExclusionRule]
    private let sourceRules: [ExclusionRule]
    private let referenceDate: Date
    private let hasRelativeDateRules: Bool

    public init(rules: [ExclusionRule], referenceDate: Date = Date()) {
        let compiled = rules.compactMap {
            CompiledExclusionRule(rule: $0, referenceDate: referenceDate)
        }
        self.rules = compiled
        self.pathOnlyRules = compiled
            .filter(\.isPathOnly)
            .sorted { $0.evaluationCost < $1.evaluationCost }
        self.metadataRules = compiled
            .filter { !$0.isPathOnly }
            .sorted { $0.evaluationCost < $1.evaluationCost }
        self.directoryPruningRules = compiled.filter(\.canPruneDirectory)
        self.sourceRules = rules
        self.referenceDate = referenceDate
        self.hasRelativeDateRules = rules.contains {
            $0.isEnabled && ($0.type == .creationDate || $0.type == .modificationDate)
        }
    }

    public var isEmpty: Bool {
        rules.isEmpty
    }

    public func needsRefresh(
        at date: Date = Date(),
        maximumAge: TimeInterval = 60
    ) -> Bool {
        hasRelativeDateRules
            && date.timeIntervalSince(referenceDate) >= max(0, maximumAge)
    }

    public func refreshed(at date: Date = Date()) -> ExclusionMatcher {
        guard hasRelativeDateRules else { return self }
        return ExclusionMatcher(rules: sourceRules, referenceDate: date)
    }

    public func shouldExclude(_ file: FileItem) -> Bool {
        var cache = ExclusionMatchCache(
            path: file.path,
            name: file.name,
            pathExtension: file.extension,
            size: file.size,
            creationDate: file.creationDate,
            modificationDate: file.modificationDate
        )
        return matchesAnyRule(cache: &cache)
    }

    /// Fast path for scanners to reject name/path based exclusions before any
    /// resource values, extended attributes, OCR, hashes, or image work.
    public func shouldExcludeUsingPathOnly(at url: URL) -> Bool {
        guard !pathOnlyRules.isEmpty else { return false }
        var cache = ExclusionMatchCache(url: url)
        return pathOnlyRules.contains { $0.matches(cache: &cache) }
    }

    /// Completes matching once inexpensive filesystem metadata is available.
    public func shouldExcludeFile(
        at url: URL,
        size: Int64,
        creationDate: Date?,
        modificationDate: Date?
    ) -> Bool {
        var cache = ExclusionMatchCache(
            url: url,
            size: size,
            creationDate: creationDate,
            modificationDate: modificationDate
        )
        if pathOnlyRules.contains(where: { $0.matches(cache: &cache) }) {
            return true
        }
        return metadataRules.contains { $0.matches(cache: &cache) }
    }

    /// Returns true only when every descendant must match a positive rule.
    /// Negated and file-metadata rules cannot safely prune an entire subtree.
    public func shouldPruneDirectory(at url: URL) -> Bool {
        guard !directoryPruningRules.isEmpty else { return false }
        var cache = ExclusionMatchCache(url: url)
        return directoryPruningRules.contains {
            $0.matchesDirectoryForPruning(cache: &cache)
        }
    }

    /// The enabled rule that excludes an entire directory tree, if one applies.
    public func firstBlockingDirectoryRuleID(at url: URL) -> UUID? {
        guard !directoryPruningRules.isEmpty else { return nil }
        var cache = ExclusionMatchCache(url: url)
        return directoryPruningRules.first {
            $0.matchesDirectoryForPruning(cache: &cache)
        }?.id
    }

    public func filterFiles(_ files: [FileItem]) -> [FileItem] {
        guard !rules.isEmpty else { return files }

        var included: [FileItem] = []
        included.reserveCapacity(min(files.count, 4_096))
        for file in files where !shouldExclude(file) {
            included.append(file)
        }
        return included
    }

    func shouldExclude(
        path: String,
        name: String,
        pathExtension: String,
        size: Int64 = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) -> Bool {
        var cache = ExclusionMatchCache(
            path: path,
            name: name,
            pathExtension: pathExtension,
            size: size,
            creationDate: creationDate,
            modificationDate: modificationDate
        )
        return matchesAnyRule(cache: &cache)
    }

    func firstMatchingRuleID(for file: FileItem) -> UUID? {
        var cache = ExclusionMatchCache(
            path: file.path,
            name: file.name,
            pathExtension: file.extension,
            size: file.size,
            creationDate: file.creationDate,
            modificationDate: file.modificationDate
        )
        return rules.first { $0.matches(cache: &cache) }?.id
    }

    func matchingRuleIDs(for file: FileItem) -> [UUID] {
        var cache = ExclusionMatchCache(
            path: file.path,
            name: file.name,
            pathExtension: file.extension,
            size: file.size,
            creationDate: file.creationDate,
            modificationDate: file.modificationDate
        )
        var matches: [UUID] = []
        for rule in rules where rule.matches(cache: &cache) {
            matches.append(rule.id)
        }
        return matches
    }

    private func matchesAnyRule(cache: inout ExclusionMatchCache) -> Bool {
        if pathOnlyRules.contains(where: { $0.matches(cache: &cache) }) {
            return true
        }
        return metadataRules.contains { $0.matches(cache: &cache) }
    }

    fileprivate static func isSystemItem(name: String, path: String) -> Bool {
        systemPatterns.contains { name == $0 || path.contains($0) }
    }
}

private struct ExclusionMatchCache {
    let path: String
    let name: String
    let pathExtension: String
    let size: Int64
    let creationDate: Date?
    let modificationDate: Date?

    private var lowercasedPathStorage: String?
    private var lowercasedNameStorage: String?
    private var normalizedExtensionStorage: String?
    private var pathComponentsStorage: [Substring]?
    private var lowercasedPathComponentsStorage: [Substring]?

    init(
        path: String,
        name: String,
        pathExtension: String,
        size: Int64,
        creationDate: Date?,
        modificationDate: Date?
    ) {
        self.path = path
        self.name = name
        self.pathExtension = pathExtension
        self.size = size
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    init(
        url: URL,
        size: Int64 = 0,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.init(
            path: url.path,
            name: url.deletingPathExtension().lastPathComponent,
            pathExtension: url.pathExtension,
            size: size,
            creationDate: creationDate,
            modificationDate: modificationDate
        )
    }

    mutating func lowercasedPath() -> String {
        if let lowercasedPathStorage {
            return lowercasedPathStorage
        }
        let value = path.lowercased()
        lowercasedPathStorage = value
        return value
    }

    mutating func lowercasedName() -> String {
        if let lowercasedNameStorage {
            return lowercasedNameStorage
        }
        let value = name.lowercased()
        lowercasedNameStorage = value
        return value
    }

    mutating func normalizedExtension() -> String {
        if let normalizedExtensionStorage {
            return normalizedExtensionStorage
        }
        let value = pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        normalizedExtensionStorage = value
        return value
    }

    mutating func pathComponents() -> [Substring] {
        if let pathComponentsStorage {
            return pathComponentsStorage
        }
        let value = path.split(separator: "/", omittingEmptySubsequences: false)
        pathComponentsStorage = value
        return value
    }

    mutating func lowercasedPathComponents() -> [Substring] {
        if let lowercasedPathComponentsStorage {
            return lowercasedPathComponentsStorage
        }
        let value = lowercasedPath().split(separator: "/", omittingEmptySubsequences: false)
        lowercasedPathComponentsStorage = value
        return value
    }
}

private struct CompiledExclusionRule: Sendable {
    let id: UUID
    let predicate: CompiledExclusionPredicate
    let negated: Bool

    init?(rule: ExclusionRule, referenceDate: Date) {
        guard rule.isEnabled else { return nil }

        let trimmedPattern = rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let predicate: CompiledExclusionPredicate

        switch rule.type {
        case .fileExtension:
            let pattern = trimmedPattern.trimmingLeadingDots()
            guard !pattern.isEmpty else { return nil }
            predicate = .fileExtension(
                rule.caseSensitive ? pattern : pattern.lowercased(),
                caseSensitive: rule.caseSensitive
            )

        case .fileName:
            guard !trimmedPattern.isEmpty else { return nil }
            predicate = .fileNameContains(
                rule.caseSensitive ? trimmedPattern : trimmedPattern.lowercased(),
                caseSensitive: rule.caseSensitive
            )

        case .folderName:
            guard !trimmedPattern.isEmpty else { return nil }
            predicate = .folderNameContains(
                rule.caseSensitive ? trimmedPattern : trimmedPattern.lowercased(),
                caseSensitive: rule.caseSensitive
            )

        case .pathContains:
            guard !trimmedPattern.isEmpty else { return nil }
            if trimmedPattern.hasPrefix("/") {
                let normalizedPath = URL(fileURLWithPath: trimmedPattern).standardizedFileURL.path
                predicate = .folderTree(
                    rule.caseSensitive ? normalizedPath : normalizedPath.lowercased(),
                    caseSensitive: rule.caseSensitive
                )
            } else {
                predicate = .pathContains(
                    rule.caseSensitive ? trimmedPattern : trimmedPattern.lowercased(),
                    caseSensitive: rule.caseSensitive
                )
            }

        case .regex:
            guard !trimmedPattern.isEmpty else { return nil }
            let options: NSRegularExpression.Options = rule.caseSensitive ? [] : .caseInsensitive
            guard let regex = try? NSRegularExpression(pattern: trimmedPattern, options: options) else {
                return nil
            }
            predicate = .regex(CompiledExclusionRegex(regex))

        case .fileSize:
            guard let limitMB = rule.numericValue,
                  let greater = rule.comparisonGreater else {
                return nil
            }
            predicate = .fileSize(limitMB: limitMB, greater: greater)

        case .creationDate, .modificationDate:
            guard let days = rule.numericValue,
                  days.isFinite,
                  days >= Double(Int.min),
                  days <= Double(Int.max),
                  let older = rule.comparisonGreater else {
                return nil
            }
            let threshold = Calendar.current.date(
                byAdding: .day,
                value: -Int(days),
                to: referenceDate
            ) ?? referenceDate
            predicate = .date(
                type: rule.type,
                threshold: threshold,
                fallbackDate: referenceDate,
                older: older
            )

        case .hiddenFiles:
            predicate = .hiddenFiles

        case .systemFiles:
            predicate = .systemFiles

        case .fileType:
            guard let category = rule.fileTypeCategory else { return nil }
            predicate = .fileType(Set(category.extensions.map { $0.lowercased() }))

        case .customScript:
            predicate = .constant(false)
        }

        self.id = rule.id
        self.predicate = predicate
        self.negated = rule.negated
    }

    var isPathOnly: Bool {
        predicate.isPathOnly
    }

    var canPruneDirectory: Bool {
        !negated && predicate.canPruneDirectory
    }

    var evaluationCost: Int {
        predicate.evaluationCost
    }

    func matches(cache: inout ExclusionMatchCache) -> Bool {
        let result = predicate.matches(cache: &cache)
        return negated ? !result : result
    }

    func matchesDirectoryForPruning(cache: inout ExclusionMatchCache) -> Bool {
        guard canPruneDirectory else { return false }
        return predicate.matches(cache: &cache)
    }
}

private enum CompiledExclusionPredicate: Sendable {
    case fileExtension(String, caseSensitive: Bool)
    case fileNameContains(String, caseSensitive: Bool)
    case folderNameContains(String, caseSensitive: Bool)
    case pathContains(String, caseSensitive: Bool)
    case folderTree(String, caseSensitive: Bool)
    case regex(CompiledExclusionRegex)
    case fileSize(limitMB: Double, greater: Bool)
    case date(
        type: ExclusionRuleType,
        threshold: Date,
        fallbackDate: Date,
        older: Bool
    )
    case hiddenFiles
    case systemFiles
    case fileType(Set<String>)
    case constant(Bool)

    var isPathOnly: Bool {
        switch self {
        case .fileSize, .date:
            return false
        default:
            return true
        }
    }

    var canPruneDirectory: Bool {
        switch self {
        case .folderNameContains, .pathContains, .folderTree, .hiddenFiles, .systemFiles:
            return true
        default:
            return false
        }
    }

    var evaluationCost: Int {
        switch self {
        case .fileExtension, .fileType, .constant:
            return 0
        case .fileSize, .date, .hiddenFiles:
            return 1
        case .fileNameContains:
            return 2
        case .systemFiles:
            return 3
        case .pathContains, .folderTree:
            return 4
        case .folderNameContains:
            return 5
        case .regex:
            return 6
        }
    }

    func matches(cache: inout ExclusionMatchCache) -> Bool {
        switch self {
        case .fileExtension(let pattern, let caseSensitive):
            if caseSensitive {
                return cache.pathExtension
                    .trimmingCharacters(in: .whitespacesAndNewlines) == pattern
            }
            return cache.normalizedExtension() == pattern

        case .fileNameContains(let pattern, let caseSensitive):
            return caseSensitive
                ? cache.name.contains(pattern)
                : cache.lowercasedName().contains(pattern)

        case .folderNameContains(let pattern, let caseSensitive):
            let components = caseSensitive
                ? cache.pathComponents()
                : cache.lowercasedPathComponents()
            return components.contains { $0.range(of: pattern) != nil }

        case .pathContains(let pattern, let caseSensitive):
            return caseSensitive
                ? cache.path.contains(pattern)
                : cache.lowercasedPath().contains(pattern)

        case .folderTree(let folderPath, let caseSensitive):
            let path = caseSensitive ? cache.path : cache.lowercasedPath()
            return path == folderPath || path.hasPrefix(folderPath + "/")

        case .regex(let regex):
            return regex.matches(cache.name)

        case .fileSize(let limitMB, let greater):
            let sizeMB = Double(cache.size) / (1_024 * 1_024)
            return greater ? sizeMB > limitMB : sizeMB < limitMB

        case .date(let type, let threshold, let fallbackDate, let older):
            let date: Date
            if type == .modificationDate {
                date = cache.modificationDate ?? cache.creationDate ?? fallbackDate
            } else {
                date = cache.creationDate ?? fallbackDate
            }
            return older ? date < threshold : date > threshold

        case .hiddenFiles:
            return cache.name.hasPrefix(".") || cache.path.contains("/.")

        case .systemFiles:
            return ExclusionMatcher.isSystemItem(name: cache.name, path: cache.path)

        case .fileType(let extensions):
            return extensions.contains(cache.normalizedExtension())

        case .constant(let value):
            return value
        }
    }
}

private final class CompiledExclusionRegex: @unchecked Sendable {
    private let expression: NSRegularExpression

    init(_ expression: NSRegularExpression) {
        self.expression = expression
    }

    func matches(_ value: String) -> Bool {
        let range = NSRange(location: 0, length: value.utf16.count)
        return expression.firstMatch(in: value, options: [], range: range) != nil
    }
}

// MARK: - Rule Presets

public struct ExclusionRulePreset: Identifiable, Sendable {
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

    @MainActor
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

public struct NaturalLanguageException: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), text: String, isEnabled: Bool = true) {
        self.id = id
        self.text = text
        self.isEnabled = isEnabled
    }

    public var referencedPaths: [String] {
        let pattern = #"(?:\"((?:~/|/)[^\"]+)\"|'((?:~/|/)[^']+)'|((?:~/|/)[^\s,;]+))"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        var paths: [String] = []
        for match in expression.matches(in: text, range: range) {
            for captureIndex in 1..<match.numberOfRanges {
                let captureRange = match.range(at: captureIndex)
                guard captureRange.location != NSNotFound,
                      let range = Range(captureRange, in: text)
                else { continue }

                let path = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".!?:)"))
                if !path.isEmpty, !paths.contains(path) {
                    paths.append(path)
                }
                break
            }
        }
        return paths
    }
}

@MainActor
public class ExclusionRulesManager: ObservableObject {
    public static let legacyLearningsLinkedDescription = "Added from Learnings exclusion"

    @Published public private(set) var rules: [ExclusionRule] = []
    @Published public var activePresetName: String?
    @Published public private(set) var naturalLanguageExceptions: [NaturalLanguageException] = []
    @Published public private(set) var compiledMatcher = ExclusionMatcher.empty

    private let userDefaults: UserDefaults
    private let rulesKey = "exclusionRules"
    private let presetKey = "activeExclusionPreset"
    private let nlExceptionsKey = "naturalLanguageExceptions"

    public convenience init() {
        self.init(userDefaults: .standard)
    }

    init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
        loadRules()
        removeLegacyLearningsLinkedRules()
        loadNaturalLanguageExceptions()
        if rules.isEmpty {
            setupDefaultRules()
        }
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.clearEverything()
        }
    }

    // MARK: - Rule Management

    public func addRule(_ rule: ExclusionRule) {
        rules.append(rule)
        saveRules()
    }

    public func clearEverything() {
        rules.removeAll()
        activePresetName = nil
        naturalLanguageExceptions.removeAll()
        userDefaults.removeObject(forKey: rulesKey)
        userDefaults.removeObject(forKey: presetKey)
        userDefaults.removeObject(forKey: nlExceptionsKey)
        setupDefaultRules()
    }

    public func removeRule(_ rule: ExclusionRule) {
        rules.removeAll { $0.id == rule.id }
        saveRules()
    }

    public func removeLegacyLearningsLinkedRules() {
        removeRules { isLegacyLearningsLinkedRule($0) }
    }

    public func removeLegacyLearningsLinkedRules(matchingLearningPattern pattern: String) {
        let normalizedPattern = normalizedLearningsLinkedPattern(pattern)
        removeRules { rule in
            isLegacyLearningsLinkedRule(rule) &&
            normalizedLearningsLinkedPattern(rule.pattern) == normalizedPattern
        }
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
        matcherSnapshot().shouldExclude(file)
    }

    public func filterFiles(_ files: [FileItem]) -> [FileItem] {
        matcherSnapshot().filterFiles(files)
    }

    /// Returns which rules matched a file (for debugging)
    public func matchingRules(for file: FileItem) -> [ExclusionRule] {
        let matchingIDs = Set(matcherSnapshot().matchingRuleIDs(for: file))
        return rules.filter { matchingIDs.contains($0.id) }
    }

    public func firstMatchingRule(for file: FileItem) -> ExclusionRule? {
        guard let matchingID = matcherSnapshot().firstMatchingRuleID(for: file) else {
            return nil
        }
        return rules.first { $0.id == matchingID }
    }

    public func matcherSnapshot() -> ExclusionMatcher {
        if compiledMatcher.needsRefresh() {
            compiledMatcher = compiledMatcher.refreshed()
        }
        return compiledMatcher
    }

    /// Returns the exact enabled rule that prevents Sorty from entering this folder.
    public func blockingRule(forDirectoryAt url: URL) -> ExclusionRule? {
        guard let ruleID = matcherSnapshot().firstBlockingDirectoryRuleID(at: url) else {
            return nil
        }
        return rules.first { $0.id == ruleID }
    }

    // MARK: - Statistics

    public var enabledRulesCount: Int {
        rules.filter { $0.isEnabled }.count
    }

    public var rulesByType: [ExclusionRuleType: [ExclusionRule]] {
        Dictionary(grouping: rules) { $0.type }
    }

    // MARK: - Natural Language Exceptions

    public func addNaturalLanguageException(_ text: String) {
        let sanitized = sanitizeException(text)
        guard !sanitized.isEmpty else { return }
        naturalLanguageExceptions.append(NaturalLanguageException(text: sanitized))
        saveNaturalLanguageExceptions()
    }

    public func updateNaturalLanguageException(_ exception: NaturalLanguageException) {
        guard let index = naturalLanguageExceptions.firstIndex(where: { $0.id == exception.id }) else {
            return
        }
        naturalLanguageExceptions[index] = exception
        saveNaturalLanguageExceptions()
    }

    public func removeNaturalLanguageException(id: UUID) {
        naturalLanguageExceptions.removeAll { $0.id == id }
        saveNaturalLanguageExceptions()
    }

    /// Returns sanitized exceptions formatted for injection into AI prompts
    public var sanitizedExceptionsForPrompt: [String] {
        naturalLanguageExceptions
            .filter(\.isEnabled)
            .map { sanitizeException($0.text) }
            .filter { !$0.isEmpty }
    }

    /// Sanitizes user input to prevent prompt injection
    private func sanitizeException(_ text: String) -> String {
        var sanitized = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Truncate to reasonable length
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }

        // Remove patterns that could be prompt injection
        let injectionPatterns = [
            "ignore previous", "ignore above", "disregard", "forget",
            "system:", "assistant:", "user:", "```",
            "override", "new instructions", "instead of"
        ]
        let lowered = sanitized.lowercased()
        for pattern in injectionPatterns {
            if lowered.contains(pattern) {
                sanitized = sanitized.replacingOccurrences(
                    of: pattern,
                    with: "",
                    options: .caseInsensitive
                )
            }
        }

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadNaturalLanguageExceptions() {
        if let data = userDefaults.data(forKey: nlExceptionsKey),
           let saved = try? JSONDecoder().decode([NaturalLanguageException].self, from: data) {
            naturalLanguageExceptions = saved
            return
        }

        if let legacyExceptions = userDefaults.stringArray(forKey: nlExceptionsKey) {
            naturalLanguageExceptions = legacyExceptions.compactMap {
                let text = sanitizeException($0)
                return text.isEmpty ? nil : NaturalLanguageException(text: text)
            }
            saveNaturalLanguageExceptions()
        }
    }

    private func saveNaturalLanguageExceptions() {
        guard let data = try? JSONEncoder().encode(naturalLanguageExceptions) else { return }
        userDefaults.set(data, forKey: nlExceptionsKey)
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
                ExclusionRule(type: .folderName, pattern: "node_modules", description: "Node modules", isBuiltIn: true),
                ExclusionRule(type: .folderName, pattern: "Library", description: "macOS Library folder", isBuiltIn: true),
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
        rebuildMatcher()
    }

    private func removeRules(where shouldRemove: (ExclusionRule) -> Bool) {
        let originalCount = rules.count
        rules.removeAll(where: shouldRemove)
        if rules.count != originalCount {
            saveRules()
        }
    }

    private func isLegacyLearningsLinkedRule(_ rule: ExclusionRule) -> Bool {
        rule.type == .folderName &&
        rule.description == Self.legacyLearningsLinkedDescription
    }

    private func normalizedLearningsLinkedPattern(_ pattern: String) -> String {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed).lastPathComponent.lowercased()
    }

    private func saveRules() {
        rebuildMatcher()
        if let encoded = try? JSONEncoder().encode(rules) {
            userDefaults.set(encoded, forKey: rulesKey)
        }
        userDefaults.set(activePresetName, forKey: presetKey)
    }

    private func rebuildMatcher() {
        compiledMatcher = ExclusionMatcher(rules: rules)
    }
}

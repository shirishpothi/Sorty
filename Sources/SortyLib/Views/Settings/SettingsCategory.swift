//
//  SettingsCategory.swift
//  Sorty
//
//  Shared settings category enum and utilities
//

import SwiftUI

public struct SettingsFeatureSnippet: Identifiable, Hashable {
    public let title: String
    public let summary: String
    public let keywords: [String]

    public var id: String { "\(title)|\(summary)" }

    public init(title: String, summary: String, keywords: [String] = []) {
        self.title = title
        self.summary = summary
        self.keywords = keywords
    }
}

public struct SettingsFeatureMatch: Identifiable, Hashable {
    public let category: SettingsCategory
    public let snippet: SettingsFeatureSnippet
    public let score: Int

    public var id: String { "\(category.rawValue)|\(snippet.id)" }
}

public enum SettingsFocusTarget: String, Sendable {
    case rulesStorageLocations = "settings.rules.storage-locations"
    case rulesOrganizationLimits = "settings.rules.organization-limits"
    case rulesContentRules = "settings.rules.content-rules"
    case rulesSteeringPrompts = "settings.rules.steering-prompts"
    case rulesOrganizationStyle = "settings.rules.organization-style"
}

public enum SettingsCategoryGroup: String, CaseIterable {
    case aiAndOrganization = "AI & Organization"
    case features = "Features"
    case system = "System"
}

public enum SettingsCategory: String, CaseIterable, Identifiable {
    case provider = "AI Provider"
    case strategy = "Organization Strategy"
    case rules = "Organization Rules"
    case tuning = "Parameter Tuning"
    case automation = "Automation"
    case finder = "Finder Integration"
    case notifications = "Notifications"
    case advanced = "Advanced"
    case troubleshooting = "Troubleshooting"
    case help = "Help & Support"
    case experimental = "Experimental"
    
    public var id: String { rawValue }
    
    public var group: SettingsCategoryGroup {
        switch self {
        case .provider, .strategy, .rules, .tuning:
            return .aiAndOrganization
        case .automation, .finder, .notifications:
            return .features
        case .advanced, .troubleshooting, .help, .experimental:
            return .system
        }
    }
    
    public static func categories(for group: SettingsCategoryGroup) -> [SettingsCategory] {
        allCases.filter { $0.group == group }
    }
    
    public var icon: String {
        switch self {
        case .rules: return "folder.badge.gearshape"
        case .provider: return "cpu"
        case .strategy: return "wand.and.stars"
        case .tuning: return "slider.horizontal.3"
        case .automation: return "bolt.circle"
        case .finder: return "folder.badge.plus"
        case .notifications: return "bell"
        case .advanced: return "gearshape.2"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .help: return "questionmark.circle"
        case .experimental: return "flask"
        }
    }
    
    public var color: Color {
        switch self {
        case .rules: return .blue
        case .provider: return .purple
        case .strategy: return .orange
        case .tuning: return .green
        case .automation: return .green
        case .finder: return .cyan
        case .notifications: return .pink
        case .advanced: return .gray
        case .troubleshooting: return .red
        case .help: return .teal
        case .experimental: return .indigo
        }
    }

    public var searchKeywords: [String] {
        switch self {
        case .provider:
            return ["api key", "provider", "model", "endpoint", "token", "connection", "copilot", "ollama", "openrouter", "anthropic", "gemini"]
        case .strategy:
            return ["strategy", "deep scanning", "smart renaming", "vision", "naming style", "folder structure", "organization style"]
        case .rules:
            return ["rules", "instructions", "steering prompt", "default prompt", "storage locations", "destinations", "tagging", "pattern"]
        case .tuning:
            return ["temperature", "creativity", "strictness", "parameters", "timeouts", "token limits", "quality"]
        case .automation:
            return ["automation", "watched folders", "auto organize", "background", "scheduler", "spring cleaning", "folder trigger"]
        case .finder:
            return ["finder", "quick action", "toolbar", "extension", "service", "keyboard shortcut", "url scheme"]
        case .notifications:
            return ["notification", "alerts", "sound", "banner", "notificli", "completion", "foreground", "permissions"]
        case .advanced:
            return ["advanced", "menu bar", "streaming", "performance", "developer", "diagnostics", "debug", "cache", "privacy", "blur", "username"]
        case .troubleshooting:
            return ["troubleshoot", "errors", "reset", "logs", "repair", "recovery", "diagnose"]
        case .help:
            return ["help", "support", "documentation", "faq", "guide", "tips", "contact"]
        case .experimental:
            return ["experimental", "labs", "beta", "feature flags", "defaults", "finder integration", "batch organization"]
        }
    }

    public var featureSnippets: [SettingsFeatureSnippet] {
        switch self {
        case .provider:
            return [
                SettingsFeatureSnippet(title: "Select Provider", summary: "Choose OpenAI, Anthropic, Gemini, Copilot, Ollama, or OpenAI-compatible APIs."),
                SettingsFeatureSnippet(title: "API Configuration", summary: "Set endpoint URL and API key/token details for your selected provider.", keywords: ["api key", "endpoint", "token"]),
                SettingsFeatureSnippet(title: "Model Catalog", summary: "Search and pick models available for each provider."),
                SettingsFeatureSnippet(title: "Connection Testing", summary: "Validate credentials and endpoint connectivity before organizing files.", keywords: ["test connection"]),
                SettingsFeatureSnippet(title: "GitHub Copilot", summary: "Configure Copilot integration and model options.", keywords: ["copilot"])
            ]
        case .strategy:
            return [
                SettingsFeatureSnippet(title: "Deep Scanning", summary: "Analyze file content including PDF text and metadata for better categorization."),
                SettingsFeatureSnippet(title: "Smart Renaming", summary: "Generate cleaner, consistent filenames while organizing."),
                SettingsFeatureSnippet(title: "AI Vision for Images", summary: "Use image understanding to classify screenshots and photos.", keywords: ["vision"]),
                SettingsFeatureSnippet(title: "Naming Preset", summary: "Choose naming conventions for organized files."),
                SettingsFeatureSnippet(title: "Custom Naming Instructions", summary: "Define your own naming rules and generate instructions.")
            ]
        case .rules:
            return [
                SettingsFeatureSnippet(title: "Storage Locations", summary: "Route files into preferred external destinations."),
                SettingsFeatureSnippet(title: "Organization Limits", summary: "Set max top-level folders to control output structure."),
                SettingsFeatureSnippet(title: "Duplicate Handling", summary: "Use the duplicate detection dropdown in preview to control how duplicates are scanned.", keywords: ["duplicates", "duplicate detection"]),
                SettingsFeatureSnippet(title: "Enable File Tagging", summary: "Allow AI to suggest and apply Finder tags to files.", keywords: ["tagging", "finder tags", "smart tags"]),
                SettingsFeatureSnippet(title: "Steering Prompts", summary: "Save default or reusable instructions that steer organization behavior."),
                SettingsFeatureSnippet(title: "Organization Style", summary: "Pick personas and style preferences for folder structures.")
            ]
        case .tuning:
            return [
                SettingsFeatureSnippet(title: "AI Temperature", summary: "Adjust creativity vs determinism in generation output."),
                SettingsFeatureSnippet(title: "Token Limits", summary: "Control request and response token budgets."),
                SettingsFeatureSnippet(title: "Timeout Behavior", summary: "Tune request timeout settings for slower providers."),
                SettingsFeatureSnippet(title: "Response Quality", summary: "Balance speed, quality, and strictness.")
            ]
        case .automation:
            return [
                SettingsFeatureSnippet(title: "Global Automation Model", summary: "Use a dedicated model for background and watched-folder tasks."),
                SettingsFeatureSnippet(title: "Watched Folders Summary", summary: "See total, active, and auto-organizing folder counts."),
                SettingsFeatureSnippet(title: "Manage Watched Folders", summary: "Jump to watched-folder configuration."),
                SettingsFeatureSnippet(title: "Background Behavior", summary: "Configure launch at login, keep in background, and Dock visibility."),
                SettingsFeatureSnippet(title: "Automation Notifications", summary: "Control notifications for auto-organized files.")
            ]
        case .finder:
            return [
                SettingsFeatureSnippet(title: "Quick Action", summary: "Run Sorty directly from Finder context menus."),
                SettingsFeatureSnippet(title: "URL Scheme", summary: "Use sorty:// deep links for Finder and scripts."),
                SettingsFeatureSnippet(title: "Finder Sync Extension", summary: "Enable extension status and integration checks."),
                SettingsFeatureSnippet(title: "Advanced Controls", summary: "Access permission and troubleshooting controls for Finder integration.")
            ]
        case .notifications:
            return [
                SettingsFeatureSnippet(title: "System Notification Permission", summary: "Check macOS notification authorization status."),
                SettingsFeatureSnippet(title: "Delivery Method", summary: "Choose In-App HUD and system notification delivery."),
                SettingsFeatureSnippet(title: "NotifiCLI Settings", summary: "Configure backend, action buttons, persistent notifications, and sounds."),
                SettingsFeatureSnippet(title: "Notification Types", summary: "Control which events trigger notifications."),
                SettingsFeatureSnippet(title: "Show Preview Ready in foreground", summary: "Show preview-ready system alerts even while app is active."),
                SettingsFeatureSnippet(title: "Sounds", summary: "Configure completion and notification sounds."),
                SettingsFeatureSnippet(title: "Test Notifications", summary: "Send test alerts to validate current notification setup.")
            ]
        case .advanced:
            return [
                SettingsFeatureSnippet(title: "Privacy", summary: "Blur usernames in file paths for privacy.", keywords: ["privacy", "blur", "username", "path"]),
                SettingsFeatureSnippet(title: "Menu Bar", summary: "Configure menu bar UI behavior."),
                SettingsFeatureSnippet(title: "Streaming", summary: "Toggle streaming responses in AI flows."),
                SettingsFeatureSnippet(title: "Timeouts", summary: "Tune max request durations and retries."),
                SettingsFeatureSnippet(title: "Token Limits", summary: "Set global token constraints for requests."),
                SettingsFeatureSnippet(title: "Developer Tools", summary: "Enable diagnostics and debugging controls.")
            ]
        case .troubleshooting:
            return [
                SettingsFeatureSnippet(title: "Cache", summary: "Clear cached data and recover from stale state."),
                SettingsFeatureSnippet(title: "Learnings Data", summary: "Inspect or reset learning signals and history."),
                SettingsFeatureSnippet(title: "Reset Sorty", summary: "Perform a full reset of app configuration."),
                SettingsFeatureSnippet(title: "Common Issues", summary: "Reference known fixes and quick repair actions.")
            ]
        case .help:
            return [
                SettingsFeatureSnippet(title: "The Basics", summary: "Walk through the core organize-preview-apply workflow."),
                SettingsFeatureSnippet(title: "Privacy and Support", summary: "Open docs, changelog, and issue reporting links.")
            ]
        case .experimental:
            return [
                SettingsFeatureSnippet(title: "Finder Integration Flag", summary: "Enable Finder quick actions, toolbar support, and extension wiring."),
                SettingsFeatureSnippet(title: "Batch Organization Flag", summary: "Enable multi-folder organization workflows."),
                SettingsFeatureSnippet(title: "GitHub Update Checker Flag", summary: "Enable in-app release checks via GitHub."),
                SettingsFeatureSnippet(title: "Advanced Notification Controls Flag", summary: "Expose technical notification backend controls.")
            ]
        }
    }

    public var searchableFeatureText: [String] {
        featureSnippets.flatMap { [$0.title, $0.summary] + $0.keywords }
    }

    public func featureMatches(query: String) -> [SettingsFeatureMatch] {
        let normalizedQuery = query.normalizedSearchText
        guard !normalizedQuery.isEmpty else { return [] }

        return featureSnippets
            .compactMap { snippet in
                let score = snippet.searchScore(matching: normalizedQuery)
                guard score > 0 else { return nil }
                return SettingsFeatureMatch(category: self, snippet: snippet, score: score)
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.snippet.title < $1.snippet.title
            }
    }

    public func matchesSearch(query: String) -> Bool {
        let normalizedQuery = query.normalizedSearchText
        guard !normalizedQuery.isEmpty else { return true }

        let haystack = ([rawValue] + searchKeywords + searchableFeatureText)
            .map(\.normalizedSearchText)
            .joined(separator: " ")

        if haystack.contains(normalizedQuery) {
            return true
        }

        let terms = normalizedQuery.searchTerms
        return !terms.isEmpty && terms.allSatisfy { haystack.contains($0) }
    }

    public func focusTarget(for snippet: SettingsFeatureSnippet) -> SettingsFocusTarget? {
        guard self == .rules else { return nil }

        switch snippet.title {
        case "Storage Locations":
            return .rulesStorageLocations
        case "Organization Limits":
            return .rulesOrganizationLimits
        case "Duplicate Handling", "Enable File Tagging":
            return .rulesContentRules
        case "Steering Prompts":
            return .rulesSteeringPrompts
        case "Organization Style":
            return .rulesOrganizationStyle
        default:
            return nil
        }
    }
}

private extension SettingsFeatureSnippet {
    func searchScore(matching normalizedQuery: String) -> Int {
        let normalizedTitle = title.normalizedSearchText
        let normalizedSummary = summary.normalizedSearchText
        let normalizedKeywords = keywords.map(\.normalizedSearchText)
        let queryTerms = normalizedQuery.searchTerms

        let searchableText = ([normalizedTitle, normalizedSummary] + normalizedKeywords)
            .joined(separator: " ")

        guard !searchableText.isEmpty else { return 0 }

        var score = 0

        if normalizedTitle.contains(normalizedQuery) {
            score += 24
        }
        if normalizedSummary.contains(normalizedQuery) {
            score += 14
        }
        if normalizedKeywords.contains(where: { $0.contains(normalizedQuery) }) {
            score += 10
        }

        var matchedTermCount = 0
        for term in queryTerms where !term.isEmpty {
            if normalizedTitle.contains(term) {
                score += 6
                matchedTermCount += 1
            } else if normalizedSummary.contains(term) {
                score += 4
                matchedTermCount += 1
            } else if normalizedKeywords.contains(where: { $0.contains(term) }) {
                score += 3
                matchedTermCount += 1
            }
        }

        if queryTerms.count > 1 && matchedTermCount == queryTerms.count {
            score += 8
        }

        return score
    }
}

private extension String {
    var normalizedSearchText: String {
        self.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var searchTerms: [String] {
        normalizedSearchText
            .split(separator: " ")
            .map(String.init)
    }
}

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
    case strategyFastMode = "settings.strategy.fast-mode"
    case strategyVision = "settings.strategy.vision"
    case strategyRenaming = "settings.strategy.renaming"
    case rulesOrganizationLimits = "settings.rules.organization-limits"
    case rulesContentRules = "settings.rules.content-rules"
    case rulesOrganizationStyle = "settings.rules.organization-style"
    case automationGlobalModel = "settings.automation.global-model"
    case automationLaunchAtLogin = "settings.automation.launch-at-login"
    case automationKeepInBackground = "settings.automation.keep-in-background"
    case automationHideDockIcon = "settings.automation.hide-dock-icon"
    case notificationsPermission = "settings.notifications.permission"
    case notificationsInAppHUD = "settings.notifications.in-app-hud"
    case notificationsSystem = "settings.notifications.system"
    case notificationsTypes = "settings.notifications.types"
    case notificationsCompletionSound = "settings.notifications.completion-sound"
    case advancedMenuBar = "settings.advanced.menu-bar"
    case advancedFinderWorkflow = "settings.advanced.finder-workflow"
    case advancedPrivacyMode = "settings.advanced.privacy-mode"
    case advancedInternetPrivacy = "settings.advanced.internet-privacy"
    case advancedTimeouts = "settings.advanced.timeouts"
    case advancedDeveloper = "settings.advanced.developer"
}

public enum SettingsCategoryGroup: String, CaseIterable {
    case aiAndOrganization = "AI & Organization"
    case features = "Features"
    case system = "System"
}

public enum SettingsCategory: String, CaseIterable, Identifiable {
    case provider = "AI Provider"
    case strategy = "Analysis & Naming"
    case rules = "Organize Rules"
    case tuning = "Parameter Tuning"
    case automation = "Automation"
    case deeplinks = "Deeplinks"
    case finder = "Finder Integration"
    case notifications = "Notifications"
    case advanced = "Advanced"
    case troubleshooting = "Troubleshooting"
    case licensing = "Licensing & Access"
    case help = "Help & Support"
    case experimental = "Experimental"
    
    public var id: String { rawValue }
    
    public var group: SettingsCategoryGroup {
        switch self {
        case .provider, .strategy, .rules, .tuning:
            return .aiAndOrganization
        case .automation, .deeplinks, .finder, .notifications:
            return .features
        case .advanced, .troubleshooting, .licensing, .help, .experimental:
            return .system
        }
    }
    
    public static func categories(for group: SettingsCategoryGroup) -> [SettingsCategory] {
        allCases.filter { $0.group == group && $0 != .tuning }
    }
    
    public var icon: String {
        switch self {
        case .rules: return "folder.badge.gearshape"
        case .provider: return "cpu"
        case .strategy: return "wand.and.stars"
        case .tuning: return "slider.horizontal.3"
        case .automation: return "bolt.circle"
        case .deeplinks: return "link.badge.plus"
        case .finder: return "folder.badge.plus"
        case .notifications: return "bell"
        case .advanced: return "gearshape.2"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .licensing: return "checkmark.seal"
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
        case .deeplinks: return .cyan
        case .finder: return .cyan
        case .notifications: return .pink
        case .advanced: return .gray
        case .troubleshooting: return .red
        case .licensing: return .mint
        case .help: return .teal
        case .experimental: return .indigo
        }
    }

    public var searchKeywords: [String] {
        switch self {
        case .provider:
            return ["api key", "provider", "model", "endpoint", "token", "connection", "copilot", "ollama", "openrouter", "anthropic", "gemini"]
        case .strategy:
            return ["strategy", "analysis", "fast mode", "deep scan", "deep scanning", "content analysis", "vision", "image analysis", "naming style", "rename", "renaming", "folder structure", "organization style"]
        case .rules:
            return ["rules", "controls", "organization controls", "instructions", "tagging", "pattern", "temperature", "creativity", "strictness"]
        case .tuning:
            return ["temperature", "creativity", "strictness", "parameters", "timeouts", "quality"]
        case .automation:
            return ["automation", "watched folders", "auto organize", "background", "scheduler", "spring cleaning", "folder trigger", "custom model", "global model", "launch at login", "login item", "dock icon", "menu bar app"]
        case .deeplinks:
            return ["deeplink", "deeplinks", "deep link", "url scheme", "sorty://", "shortcuts", "raycast", "automation links", "scripts", "downloads", "desktop", "documents", "open url"]
        case .finder:
            return ["finder", "quick action", "organize action", "watch action", "exclude action", "extension", "service", "automation permission", "repair"]
        case .notifications:
            return ["notification", "notifications", "alerts", "sound", "banner", "hud", "in app hud", "notificli", "completion", "foreground", "permissions", "notification center"]
        case .advanced:
            return ["advanced", "menu bar", "streaming", "performance", "developer", "diagnostics", "debug", "logs", "error logs", "red logs"]
        case .troubleshooting:
            return ["troubleshoot", "errors", "reset", "logs", "repair", "recovery", "diagnose"]
        case .licensing:
            return ["license", "licensing", "upgrade", "restore", "activation", "access", "gumroad", "pro"]
        case .help:
            return ["help", "support", "documentation", "faq", "guide", "tips", "contact", "issue details", "bug report", "diagnostics"]
        case .experimental:
            return ["experimental", "labs", "beta", "feature flags", "defaults", "nightly updates", "crash risk"]
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
                SettingsFeatureSnippet(title: "Fast Mode", summary: "Skip content analysis for faster organization when filenames and folder context are enough.", keywords: ["deep scanning"]),
                SettingsFeatureSnippet(title: "AI Vision for Images", summary: "Use image understanding to classify screenshots and photos.", keywords: ["vision"]),
                SettingsFeatureSnippet(title: "Renaming", summary: "Choose naming templates, separators, case, date policy, output language, max length, and custom presets.", keywords: ["naming preset", "template", "separator", "language", "max length", "custom naming instructions"])
            ]
        case .rules:
            return [
                SettingsFeatureSnippet(title: "Organization Limits", summary: "Set max top-level folders to control output structure."),
                SettingsFeatureSnippet(title: "Duplicate Handling", summary: "Use the duplicate detection dropdown in preview to control how duplicates are scanned.", keywords: ["duplicates", "duplicate detection"]),
                SettingsFeatureSnippet(title: "Enable File Tagging", summary: "Allow AI to suggest and apply Finder tags to files.", keywords: ["tagging", "finder tags", "smart tags"]),
                SettingsFeatureSnippet(title: "AI Temperature", summary: "Adjust creativity vs determinism in generation output."),
                SettingsFeatureSnippet(title: "Organization Style", summary: "Pick personas and style preferences for folder structures.")
            ]
        case .tuning:
            return [
                SettingsFeatureSnippet(title: "AI Temperature", summary: "Adjust creativity vs determinism in generation output."),
                SettingsFeatureSnippet(title: "Timeout Behavior", summary: "Tune request timeout settings for slower providers."),
                SettingsFeatureSnippet(title: "Response Quality", summary: "Balance speed, quality, and strictness.")
            ]
        case .automation:
            return [
                SettingsFeatureSnippet(title: "Global Automation Model", summary: "Use one dedicated model for watched-folder automation, overriding folder-specific model picks while enabled.", keywords: ["custom model", "watched folder model override"]),
                SettingsFeatureSnippet(title: "Launch at Login", summary: "Automatically start Sorty when you log in to macOS.", keywords: ["launch-at-login", "login item", "start on login"]),
                SettingsFeatureSnippet(title: "Keep in Background", summary: "Continue monitoring folders even when all windows are closed.", keywords: ["background activity", "background app", "folder watching"]),
                SettingsFeatureSnippet(title: "Hide Dock Icon", summary: "Run Sorty as a menu bar app without showing in the Dock.", keywords: ["dock visibility", "menu bar app"])
            ]
        case .deeplinks:
            return [
                SettingsFeatureSnippet(title: "Core Deeplinks", summary: "Copy sorty:// links for opening Sorty, Settings, Help, and History.", keywords: ["sorty://open", "sorty://settings", "sorty://help"]),
                SettingsFeatureSnippet(title: "Organization Deeplinks", summary: "Copy links for organize, duplicates, scan, storage, and workspace-health workflows.", keywords: ["organize", "duplicates", "scan", "storage", "sorty://organize?path=/Users/me/Downloads", "sorty:///Users/me/Downloads", "downloads", "desktop", "documents"]),
                SettingsFeatureSnippet(title: "Automation Deeplinks", summary: "Copy links for watched folders, rules, exclusions, personas, and learning flows.", keywords: ["watched", "rules", "exclusions", "persona", "learnings", "sorty://watched?action=add&path=/Users/me/Downloads", "downloads"]),
                SettingsFeatureSnippet(title: "Legacy Path Deeplink", summary: "Open older path-only links such as sorty:///Users/me/Downloads.", keywords: ["legacy path", "sorty:///Users/me/Downloads", "downloads"])
            ]
        case .finder:
            return [
                SettingsFeatureSnippet(title: "Organize with Sorty", summary: "Run Sorty directly from Finder context menus.", keywords: ["quick action", "service"]),
                SettingsFeatureSnippet(title: "Watch with Sorty", summary: "Add watched folders directly from Finder context menus.", keywords: ["quick action", "service", "watched folders"]),
                SettingsFeatureSnippet(title: "Exclude with Sorty", summary: "Add files and folders to exclusions directly from Finder context menus.", keywords: ["quick action", "service", "exclude path", "exclusion rules"]),
                SettingsFeatureSnippet(title: "Finder Extension", summary: "Activate or repair the Finder Sync extension and jump to macOS Extensions settings."),
                SettingsFeatureSnippet(title: "Automation Permission", summary: "Grant and recover Finder automation permission required for workflow controls.")
            ]
        case .notifications:
            return [
                SettingsFeatureSnippet(title: "Notification Permission", summary: "Check macOS notification authorization status.", keywords: ["system notification permission", "settings gear"]),
                SettingsFeatureSnippet(title: "In-App HUD", summary: "Show notifications as subtle bottom-left overlays.", keywords: ["delivery method", "hud", "overlay"]),
                SettingsFeatureSnippet(title: "System Notifications", summary: "Show notifications in macOS Notification Center.", keywords: ["delivery method", "notification center", "system notification"]),
                SettingsFeatureSnippet(title: "Notification Types", summary: "Control processing complete, preview ready, and processing error notifications."),
                SettingsFeatureSnippet(title: "Completion Sound", summary: "Play a sound when organization finishes.", keywords: ["sounds"])
            ]
        case .advanced:
            return [
                SettingsFeatureSnippet(title: "Show Menu Bar Icon", summary: "Display the Sorty icon in the menu bar for quick access.", keywords: ["menu bar", "menubar"]),
                SettingsFeatureSnippet(title: "Finder Workflow", summary: "Open Finder and highlight newly organized folders after each completed run.", keywords: ["automatically reveal organized folders", "view in finder", "auto reveal"]),
                SettingsFeatureSnippet(title: "Privacy Mode", summary: "Mask sensitive paths, usernames, API keys, and raw AI details.", keywords: ["privacy", "redact", "mask", "hide"]),
                SettingsFeatureSnippet(title: "Block Internet Connections", summary: "Allow only localhost requests for local models and offline workflows.", keywords: ["internet privacy", "network privacy", "offline", "localhost"]),
                SettingsFeatureSnippet(title: "Timeouts", summary: "Tune request timeout and maximum total request duration."),
                SettingsFeatureSnippet(title: "Stats for Nerds", summary: "Show detailed generation metrics.", keywords: ["developer", "metrics"]),
                SettingsFeatureSnippet(title: "Show Error Logs", summary: "Export and reveal diagnostic logs for debugging.", keywords: ["developer tools", "red logs", "error logs", "logs"])
            ]
        case .troubleshooting:
            return [
                SettingsFeatureSnippet(title: "Cache", summary: "Clear cached data and recover from stale state."),
                SettingsFeatureSnippet(title: "Learnings Data", summary: "Inspect or reset learning signals and history."),
                SettingsFeatureSnippet(title: "Reset Sorty", summary: "Perform a full reset of app configuration.")
            ]
        case .licensing:
            return [
                SettingsFeatureSnippet(title: "Activate License", summary: "Activate a purchase key on this Mac.", keywords: ["gumroad", "license key"]),
                SettingsFeatureSnippet(title: "Restore Access", summary: "Refresh signed access or restore purchases already stored in Keychain."),
                SettingsFeatureSnippet(title: "Remove License", summary: "Remove the stored license key and return this Mac to the free tier.", keywords: ["deactivate", "keychain"])
            ]
        case .help:
            return [
                SettingsFeatureSnippet(title: "Support Links", summary: "Open docs, changelog, and issue reporting links."),
                SettingsFeatureSnippet(title: "Copy Issue Details", summary: "Copy app, build, macOS, and device details for GitHub issue reports.", keywords: ["support data", "diagnostics", "bug report"])
            ]
        case .experimental:
            return [
                SettingsFeatureSnippet(title: "Nightly Updates", summary: "Try fresh builds from the nightly feed with higher crash risk.", keywords: ["experimental", "beta", "defaults"])
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
        switch (self, snippet.title) {
        case (.strategy, "Fast Mode"):
            return .strategyFastMode
        case (.strategy, "AI Vision for Images"):
            return .strategyVision
        case (.strategy, "Renaming"):
            return .strategyRenaming
        case (.rules, "Organization Limits"):
            return .rulesOrganizationLimits
        case (.rules, "Duplicate Handling"), (.rules, "Enable File Tagging"):
            return .rulesContentRules
        case (.rules, "Organization Style"):
            return .rulesOrganizationStyle
        case (.automation, "Global Automation Model"):
            return .automationGlobalModel
        case (.automation, "Launch at Login"):
            return .automationLaunchAtLogin
        case (.automation, "Keep in Background"):
            return .automationKeepInBackground
        case (.automation, "Hide Dock Icon"):
            return .automationHideDockIcon
        case (.notifications, "Notification Permission"):
            return .notificationsPermission
        case (.notifications, "In-App HUD"):
            return .notificationsInAppHUD
        case (.notifications, "System Notifications"):
            return .notificationsSystem
        case (.notifications, "Notification Types"):
            return .notificationsTypes
        case (.notifications, "Completion Sound"):
            return .notificationsCompletionSound
        case (.advanced, "Show Menu Bar Icon"):
            return .advancedMenuBar
        case (.advanced, "Finder Workflow"):
            return .advancedFinderWorkflow
        case (.advanced, "Privacy Mode"):
            return .advancedPrivacyMode
        case (.advanced, "Block Internet Connections"):
            return .advancedInternetPrivacy
        case (.advanced, "Timeouts"):
            return .advancedTimeouts
        case (.advanced, "Stats for Nerds"), (.advanced, "Show Error Logs"):
            return .advancedDeveloper
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

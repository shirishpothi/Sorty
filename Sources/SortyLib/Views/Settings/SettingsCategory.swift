//
//  SettingsCategory.swift
//  Sorty
//
//  Shared settings category enum and utilities
//

import SwiftUI

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
    
    public var id: String { rawValue }
    
    public var group: SettingsCategoryGroup {
        switch self {
        case .provider, .strategy, .rules, .tuning:
            return .aiAndOrganization
        case .automation, .finder, .notifications:
            return .features
        case .advanced, .troubleshooting, .help:
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
        }
    }
}

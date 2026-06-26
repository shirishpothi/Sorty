//
//  SidebarNavigationItem.swift
//  Sorty
//

import Foundation

struct SidebarNavigationItem: Identifiable, Hashable {
    let view: AppState.AppView
    let title: String
    let systemImage: String
    let iconAssetName: String
    let selectedIconAssetName: String
    let accessibilityIdentifier: String
    let accessibilityHint: String
    let helpText: String

    var id: AppState.AppView { view }

    func iconAssetName(isSelected: Bool) -> String {
        isSelected ? selectedIconAssetName : iconAssetName
    }

    @MainActor
    static var mainItems: [SidebarNavigationItem] {
        var items: [SidebarNavigationItem] = [
            SidebarNavigationItem(
                view: .organize,
                title: "Organize",
                systemImage: "folder.badge.gearshape",
                iconAssetName: "SidebarOrganizeIcon",
                selectedIconAssetName: "SidebarOrganizeSelectedIcon",
                accessibilityIdentifier: "OrganizeSidebarItem",
                accessibilityHint: "Open the main organization workflow",
                helpText: "Organize files with Sorty suggestions"
            )
        ]

        items.append(contentsOf: [
            SidebarNavigationItem(
                view: .watchedFolders,
                title: "Watched Folders",
                systemImage: "eye",
                iconAssetName: "SidebarWatchedFoldersIcon",
                selectedIconAssetName: "SidebarWatchedFoldersSelectedIcon",
                accessibilityIdentifier: "WatchedFoldersSidebarItem",
                accessibilityHint: "Configure folders monitored for automation",
                helpText: "Manage watched folders and triggers"
            ),
            SidebarNavigationItem(
                view: .duplicates,
                title: "Duplicates",
                systemImage: "doc.on.doc",
                iconAssetName: "SidebarDuplicatesIcon",
                selectedIconAssetName: "SidebarDuplicatesSelectedIcon",
                accessibilityIdentifier: "DuplicatesSidebarItem",
                accessibilityHint: "Find and review duplicate files",
                helpText: "Detect and manage duplicate files"
            ),
            SidebarNavigationItem(
                view: .history,
                title: "History",
                systemImage: "clock",
                iconAssetName: "SidebarHistoryIcon",
                selectedIconAssetName: "SidebarHistorySelectedIcon",
                accessibilityIdentifier: "HistorySidebarItem",
                accessibilityHint: "Review past organization sessions",
                helpText: "View organization history and outcomes"
            ),
            SidebarNavigationItem(
                view: .learnings,
                title: "Learnings",
                systemImage: "brain",
                iconAssetName: "SidebarLearningsIcon",
                selectedIconAssetName: "SidebarLearningsSelectedIcon",
                accessibilityIdentifier: "LearningsSidebarItem",
                accessibilityHint: "Review and manage learned preferences",
                helpText: "See what Sorty has learned from your edits"
            ),
            SidebarNavigationItem(
                view: .exclusions,
                title: "Exclusions",
                systemImage: "eye.slash",
                iconAssetName: "SidebarExclusionsIcon",
                selectedIconAssetName: "SidebarExclusionsSelectedIcon",
                accessibilityIdentifier: "ExclusionsSidebarItem",
                accessibilityHint: "Define files and folders Sorty should skip",
                helpText: "Manage exclusion rules"
            ),
            SidebarNavigationItem(
                view: .settings,
                title: "Settings",
                systemImage: "gear",
                iconAssetName: "SidebarSettingsIcon",
                selectedIconAssetName: "SidebarSettingsSelectedIcon",
                accessibilityIdentifier: "SettingsSidebarItem",
                accessibilityHint: "Configure Sorty behavior and AI providers",
                helpText: "Adjust provider, strategy, automation, and system settings"
            )
        ])

        if FeatureFlags.workspaceHealthEnabled {
            items.insert(
                SidebarNavigationItem(
                    view: .workspaceHealth,
                    title: "Workspace Health",
                    systemImage: "heart.text.square",
                    iconAssetName: "SidebarWorkspaceHealthIcon",
                    selectedIconAssetName: "SidebarWorkspaceHealthSelectedIcon",
                    accessibilityIdentifier: "WorkspaceHealthSidebarItem",
                    accessibilityHint: "Inspect workspace quality and cleanup opportunities",
                    helpText: "Check workspace health insights"
                ),
                at: 3
            )
        }

        return items
    }
}

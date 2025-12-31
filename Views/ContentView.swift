//
//  ContentView.swift
//  FileOrganizer
//
//  Main container view with full-width layout
//  Updated to include Workspace Health and Duplicates navigation
//  Enhanced with micro-animations and haptic feedback
//

import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var exclusionRules: ExclusionRulesManager
    @EnvironmentObject var extensionListener: ExtensionListener

    @State private var previousView: AppState.AppView?
    @State private var navigationDirection: NavigationDirection = .forward

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: Binding(
            get: { appState.showingSidebar ? .all : .detailOnly },
            set: { appState.showingSidebar = $0 != .detailOnly }
        )) {
            // Sidebar
            List(selection: Binding(
                get: { appState.currentView },
                set: { newValue in
                    if let newValue = newValue {
                        // Determine navigation direction for animation
                        navigationDirection = determineDirection(from: appState.currentView, to: newValue)
                        previousView = appState.currentView

                        // Haptic feedback on navigation
                        HapticFeedbackManager.shared.selection()

                        withAnimation(.pageTransition) {
                            appState.currentView = newValue
                        }
                    }
                }
            )) {
                Section("Main") {
                    NavigationLink(value: AppState.AppView.organize) {
                        Label("Organize", systemImage: "folder.badge.gearshape")
                    }
                    .accessibilityIdentifier("OrganizeSidebarItem")
                    .bounceTap(scale: 0.97)

                    NavigationLink(value: AppState.AppView.workspaceHealth) {
                        Label("Workspace Health", systemImage: "heart.text.square")
                    }
                    .accessibilityIdentifier("WorkspaceHealthSidebarItem")
                    .bounceTap(scale: 0.97)

                    NavigationLink(value: AppState.AppView.duplicates) {
                        Label("Duplicates", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("DuplicatesSidebarItem")
                    .bounceTap(scale: 0.97)
                }

                Section("Options") {
                    NavigationLink(value: AppState.AppView.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("SettingsSidebarItem")
                    .bounceTap(scale: 0.97)

                    NavigationLink(value: AppState.AppView.history) {
                        Label("History", systemImage: "clock")
                    }
                    .accessibilityIdentifier("HistorySidebarItem")
                    .bounceTap(scale: 0.97)

                    NavigationLink(value: AppState.AppView.exclusions) {
                        Label("Exclusions", systemImage: "eye.slash")
                    }
                    .accessibilityIdentifier("ExclusionsSidebarItem")
                    .bounceTap(scale: 0.97)

                    NavigationLink(value: AppState.AppView.watchedFolders) {
                        Label("Watched Folders", systemImage: "eye")
                    }
                    .accessibilityIdentifier("WatchedFoldersSidebarItem")
                    .bounceTap(scale: 0.97)
                }
            }
            .navigationTitle("FileOrganizer")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            // Main content area - uses full width with page transitions
            ZStack {
                contentView(for: appState.currentView)
                    .id(appState.currentView)
                    .transition(transitionForDirection(navigationDirection))
            }
            .animation(.pageTransition, value: appState.currentView)
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main Navigation")
        .frame(minWidth: 1000, minHeight: 700)
        .onChange(of: appState.showDirectoryPicker) { oldValue, showPicker in
            if showPicker {
                openDirectoryPicker()
            }
        }
        .onReceive(extensionListener.$incomingURL) { url in
            if let url = url {
                appState.selectedDirectory = url
                withAnimation(.pageTransition) {
                    appState.currentView = .organize
                }
                extensionListener.incomingURL = nil
            }
        }
    }

    @ViewBuilder
    private func contentView(for view: AppState.AppView) -> some View {
        switch view {
        case .organize:
            OrganizeView()
                .animatedAppearance(delay: 0.05)
        case .settings:
            SettingsView()
                .animatedAppearance(delay: 0.05)
        case .history:
            HistoryView()
                .animatedAppearance(delay: 0.05)
        case .workspaceHealth:
            WorkspaceHealthView()
                .animatedAppearance(delay: 0.05)
        case .duplicates:
            DuplicatesView()
                .animatedAppearance(delay: 0.05)
        case .exclusions:
            ExclusionRulesView()
                .animatedAppearance(delay: 0.05)
        case .watchedFolders:
            WatchedFoldersView()
                .animatedAppearance(delay: 0.05)
        }
    }

    private func transitionForDirection(_ direction: NavigationDirection) -> AnyTransition {
        switch direction {
        case .forward:
            return TransitionStyles.slideFromRight
        case .backward:
            return TransitionStyles.slideFromLeft
        }
    }

    private func determineDirection(from oldView: AppState.AppView, to newView: AppState.AppView) -> NavigationDirection {
        let viewOrder: [AppState.AppView] = [
            .organize, .workspaceHealth, .duplicates, .settings, .history, .exclusions, .watchedFolders
        ]

        guard let oldIndex = viewOrder.firstIndex(of: oldView),
              let newIndex = viewOrder.firstIndex(of: newView) else {
            return .forward
        }

        return newIndex > oldIndex ? .forward : .backward
    }

    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to organize"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            appState.selectedDirectory = url
            HapticFeedbackManager.shared.success()
        }

        appState.showDirectoryPicker = false
    }
}

// MARK: - Navigation Direction

enum NavigationDirection {
    case forward
    case backward
}

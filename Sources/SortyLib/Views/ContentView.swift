//
//  ContentView.swift
//  Sorty
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
        if !appState.hasCompletedOnboarding {
            OnboardingView(hasCompletedOnboarding: $appState.hasCompletedOnboarding)
                .transition(TransitionStyles.scaleAndFade)
        } else {
            mainContent
        }
    }
    
    private var mainContent: some View {
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

                    NavigationLink(value: AppState.AppView.workspaceHealth) {
                        Label("Workspace Health", systemImage: "heart.text.square")
                    }
                    .accessibilityIdentifier("WorkspaceHealthSidebarItem")

                    NavigationLink(value: AppState.AppView.duplicates) {
                        Label("Duplicates", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("DuplicatesSidebarItem")
                }

                Section("Options") {
                    NavigationLink(value: AppState.AppView.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("SettingsSidebarItem")

                    NavigationLink(value: AppState.AppView.history) {
                        Label("History", systemImage: "clock")
                    }
                    .accessibilityIdentifier("HistorySidebarItem")

                    NavigationLink(value: AppState.AppView.exclusions) {
                        Label("Exclusions", systemImage: "eye.slash")
                    }
                    .accessibilityIdentifier("ExclusionsSidebarItem")

                    NavigationLink(value: AppState.AppView.watchedFolders) {
                        Label("Watched Folders", systemImage: "eye")
                    }
                    .accessibilityIdentifier("WatchedFoldersSidebarItem")
                    
                    NavigationLink(value: AppState.AppView.learnings) {
                        Label("The Learnings", systemImage: "brain")
                    }
                    .accessibilityIdentifier("LearningsSidebarItem")
                }
            }
            .navigationTitle("Sorty")
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
        case .settings:
            SettingsView()
        case .history:
            HistoryView()
        case .workspaceHealth:
            WorkspaceHealthView()
        case .duplicates:
            DuplicatesView()
        case .exclusions:
            ExclusionRulesView()
        case .watchedFolders:
            WatchedFoldersView()
        case .learnings:
            LearningsView()
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
            .organize, .workspaceHealth, .duplicates, .settings, .history, .exclusions, .watchedFolders, .learnings
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

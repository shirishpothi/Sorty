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
    @State private var isCoreExpanded = true
    @State private var isProductivityExpanded = true
    @State private var isAdvancedExpanded = false

    public init() {}

    public var body: some View {
        if !appState.hasCompletedOnboarding {
            OnboardingView(hasCompletedOnboarding: $appState.hasCompletedOnboarding)
                .transition(TransitionStyles.scaleAndFade)
        } else {
            ZStack {
                mainContent
                
                // HUD notification overlay (bottom-left)
                HUDNotificationOverlay()
            }
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
                        
                        // Clear navigatedFromSettings when using sidebar
                        appState.navigatedFromSettings = false

                        withAnimation(.pageTransition) {
                            appState.currentView = newValue
                        }
                    }
                }
            )) {
                DisclosureGroup(isExpanded: $isCoreExpanded) {
                    NavigationLink(value: AppState.AppView.organize) {
                        Label("Organize", systemImage: "folder.badge.gearshape")
                    }
                    .accessibilityIdentifier("OrganizeSidebarItem")
                    .accessibilityHint("Open the main organization workflow")
                    .help("Organize files with AI suggestions")

                    NavigationLink(value: AppState.AppView.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                    .accessibilityIdentifier("SettingsSidebarItem")
                    .accessibilityHint("Configure Sorty behavior and AI providers")
                    .help("Adjust provider, strategy, and system settings")
                } label: {
                    sidebarDisclosureLabel(title: "Core", isExpanded: isCoreExpanded) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            isCoreExpanded.toggle()
                        }
                    }
                }

                DisclosureGroup(isExpanded: $isProductivityExpanded) {
                    NavigationLink(value: AppState.AppView.workspaceHealth) {
                        Label("Workspace Health", systemImage: "heart.text.square")
                    }
                    .accessibilityIdentifier("WorkspaceHealthSidebarItem")
                    .accessibilityHint("Inspect workspace quality and cleanup opportunities")
                    .help("Check workspace health insights")

                    NavigationLink(value: AppState.AppView.duplicates) {
                        Label("Duplicates", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("DuplicatesSidebarItem")
                    .accessibilityHint("Find and review duplicate files")
                    .help("Detect and manage duplicate files")

                    NavigationLink(value: AppState.AppView.history) {
                        Label("History", systemImage: "clock")
                    }
                    .accessibilityIdentifier("HistorySidebarItem")
                    .accessibilityHint("Review past organization sessions")
                    .help("View organization history and outcomes")
                } label: {
                    sidebarDisclosureLabel(title: "Productivity", isExpanded: isProductivityExpanded) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            isProductivityExpanded.toggle()
                        }
                    }
                }

                DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                    if FeatureFlags.batchOrganizationEnabled {
                        NavigationLink(value: AppState.AppView.batchOrganization) {
                            Label("Batch Organize", systemImage: "square.stack.3d.up.fill")
                        }
                        .accessibilityIdentifier("BatchOrganizeSidebarItem")
                        .accessibilityHint("Organize multiple folders in one run")
                        .help("Run organization for multiple folders")
                    }

                    NavigationLink(value: AppState.AppView.exclusions) {
                        Label("Exclusions", systemImage: "eye.slash")
                    }
                    .accessibilityIdentifier("ExclusionsSidebarItem")
                    .accessibilityHint("Define files and folders Sorty should skip")
                    .help("Manage exclusion rules")

                    NavigationLink(value: AppState.AppView.watchedFolders) {
                        Label("Watched Folders", systemImage: "eye")
                    }
                    .accessibilityIdentifier("WatchedFoldersSidebarItem")
                    .accessibilityHint("Configure folders monitored for automation")
                    .help("Manage watched folders and triggers")
                    
                    NavigationLink(value: AppState.AppView.learnings) {
                        Label("The Learnings", systemImage: "brain")
                    }
                    .accessibilityIdentifier("LearningsSidebarItem")
                    .accessibilityHint("Review and manage learned preferences")
                    .help("See what Sorty has learned from your edits")
                } label: {
                    sidebarDisclosureLabel(title: "Advanced", isExpanded: isAdvancedExpanded) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                            isAdvancedExpanded.toggle()
                        }
                    }
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
            .toolbar {
                if appState.navigatedFromSettings, let prev = previousView, prev != appState.currentView {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            appState.navigatedFromSettings = false
                            withAnimation(.pageTransition) {
                                appState.currentView = prev
                            }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .accessibilityIdentifier("SettingsReturnButton")
                        .accessibilityLabel("Return to previous view")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main Navigation")
        .frame(minWidth: 1000, minHeight: 700)
        .onChange(of: appState.currentView) { oldValue, newValue in
            if oldValue != newValue {
                previousView = oldValue
            }
        }
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
        .sheet(isPresented: $appState.showUpdateSheet) {
            UpdateDialogView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.isFeatureTourPresented) {
            FeatureTourView()
                .environmentObject(appState)
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
        case .storageLocations:
            StorageLocationsView()
        case .batchOrganization:
            BatchOrganizationView()
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
            .organize, .batchOrganization, .workspaceHealth, .duplicates, .settings, .history, .exclusions, .watchedFolders, .storageLocations, .learnings
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

    @ViewBuilder
    private func sidebarDisclosureLabel(title: String, isExpanded: Bool, onToggle: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isExpanded ? "Collapse section" : "Expand section")
    }
}

// MARK: - Navigation Direction

enum NavigationDirection {
    case forward
    case backward
}

// MARK: - Preview

#Preview("Content View - Main") {
    ContentView()
        .environmentObject(PreviewObjects.mainAppState)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(FolderOrganizer.preview)
        .environmentObject(ExclusionRulesManager.preview)
        .environmentObject(ExtensionListener.preview)
        .frame(width: 1200, height: 800)
}

#Preview("Content View - Onboarding") {
    ContentView()
        .environmentObject(PreviewObjects.onboardingAppState)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(FolderOrganizer.preview)
        .environmentObject(ExclusionRulesManager.preview)
        .environmentObject(ExtensionListener.preview)
        .frame(width: 1000, height: 720)
}

// MARK: - Preview Helpers

@MainActor
enum PreviewObjects {
    static var mainAppState: AppState {
        let state = AppState()
        state.hasCompletedOnboarding = true
        return state
    }
    
    static var onboardingAppState: AppState {
        let state = AppState()
        state.hasCompletedOnboarding = false
        return state
    }
}

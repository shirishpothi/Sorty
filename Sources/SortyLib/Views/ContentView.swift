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
    @State private var displayedView: AppState.AppView = .organize
    @State private var showCommandNumbers = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var commandFlagsMonitor: Any?
    @StateObject private var windowLinkHoverState = WindowLinkHoverState()

    public init() {}

    public var body: some View {
        ZStack {
            if !appState.hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $appState.hasCompletedOnboarding)
                    .transition(TransitionStyles.scaleAndFade)
            } else {
                ZStack {
                    mainContent

                    // HUD notification overlay (bottom-left)
                    HUDNotificationOverlay()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.01)))
            }

            WindowLinkHoverPillOverlay(hoverState: windowLinkHoverState)
        }
        .environment(\.windowLinkHoverUpdate) { hovering, url, sourceID in
            windowLinkHoverState.setHovering(hovering, url: url, sourceID: sourceID)
        }
        .onDisappear {
            windowLinkHoverState.clearAllHover()
        }
        .animation(.easeInOut(duration: 0.36), value: appState.hasCompletedOnboarding)
    }

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sorty")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.top, 16)

                VStack(spacing: 4) {
                    ForEach(Array(sidebarItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            navigateToSidebarItem(item)
                        } label: {
                            sidebarRow(item: item, commandNumber: index + 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(item.accessibilityIdentifier)
                        .accessibilityHint(item.accessibilityHint)
                        .help(item.helpText)
                    }
                }
                .padding(.horizontal, 8)

                Spacer()
            }
            .padding(.top, 44)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(NSColor.controlBackgroundColor))
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            ZStack {
                // Keep the detail view lightweight during navigation: only render the active page.
                contentView(for: displayedView)
                    .id(displayedView)
                    .transition(.identity)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Color.clear
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }

                if appState.navigatedFromSettings, let prev = previousView, prev != appState.currentView {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            appState.navigatedFromSettings = false
                            appState.currentView = prev
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
        .onAppear {
            displayedView = appState.currentView
            columnVisibility = appState.showingSidebar ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, newValue in
            let isShowingSidebar = newValue != .detailOnly
            guard appState.showingSidebar != isShowingSidebar else { return }
            appState.showingSidebar = isShowingSidebar
        }
        .onChange(of: appState.showingSidebar) { _, isShowingSidebar in
            let nextVisibility: NavigationSplitViewVisibility = isShowingSidebar ? .all : .detailOnly
            guard columnVisibility != nextVisibility else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                columnVisibility = nextVisibility
            }
        }
        .onChange(of: appState.currentView) { oldValue, newValue in
            if oldValue != newValue {
                previousView = oldValue
                displayedView = newValue
            }
        }
        .onChange(of: appState.showDirectoryPicker) { _, showPicker in
            if showPicker {
                openDirectoryPicker()
            }
        }
        .onAppear {
            installCommandKeyMonitorIfNeeded()
        }
        .onDisappear {
            removeCommandKeyMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            withAnimation(.easeOut(duration: 0.12)) {
                showCommandNumbers = false
            }
        }
        .onReceive(extensionListener.$incomingURL) { url in
            if let url = url {
                appState.selectedDirectory = url
                appState.currentView = .organize
                extensionListener.incomingURL = nil
            }
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
        }
    }

    private var sidebarItems: [SidebarNavigationItem] {
        SidebarNavigationItem.mainItems
    }

    @ViewBuilder
    private func sidebarRow(item: SidebarNavigationItem, commandNumber: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20)
                .foregroundStyle(appState.currentView == item.view ? Color.accentColor : .secondary)

            Text(item.title)
                .font(.system(size: 13, weight: appState.currentView == item.view ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Text("\(commandNumber)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(minWidth: 18)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.quaternary)
                }
                .opacity(showCommandNumbers ? 1 : 0)
                .offset(x: showCommandNumbers ? 0 : 14)
                .scaleEffect(showCommandNumbers ? 1 : 0.96)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if appState.currentView == item.view {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.16))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(
            .spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08),
            value: showCommandNumbers
        )
    }

    private func navigateToSidebarItem(_ item: SidebarNavigationItem) {
        guard item.view != appState.currentView else { return }
        previousView = appState.currentView
        HapticFeedbackManager.shared.selection()
        appState.navigatedFromSettings = false
        appState.currentView = item.view
    }

    private func installCommandKeyMonitorIfNeeded() {
        guard commandFlagsMonitor == nil else { return }

        commandFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let isCommandHeld = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            if isCommandHeld != showCommandNumbers {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)) {
                    showCommandNumbers = isCommandHeld
                }
            }
            return event
        }
    }

    private func removeCommandKeyMonitor() {
        guard let monitor = commandFlagsMonitor else { return }
        NSEvent.removeMonitor(monitor)
        commandFlagsMonitor = nil
        showCommandNumbers = false
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

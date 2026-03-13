import SwiftUI
import AppKit
#if canImport(SortyLib)
import SortyLib
#endif

struct MainWindowRootView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var personaManager: PersonaManager
    @EnvironmentObject private var customPersonaStore: CustomPersonaStore
    @EnvironmentObject private var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject private var storageLocationsManager: StorageLocationsManager
    @EnvironmentObject private var exclusionRules: ExclusionRulesManager
    @EnvironmentObject private var extensionListener: ExtensionListener
    @EnvironmentObject private var deeplinkHandler: DeeplinkHandler
    @EnvironmentObject private var learningsManager: LearningsManager
    @EnvironmentObject private var automationManager: AutomationManager
    @EnvironmentObject private var notificationSettings: NotificationSettingsManager
    @EnvironmentObject private var loginItemManager: LoginItemManager
    @EnvironmentObject private var namingPresetManager: NamingPresetManager
    @EnvironmentObject private var globalShortcutManager: GlobalShortcutManager
    @EnvironmentObject private var steeringPromptManager: SteeringPromptManager
    @EnvironmentObject private var menuBarController: MenuBarController

    @StateObject private var windowSession = WindowSession()
    @State private var handledLaunchRequestID: UUID?
    @State private var handledUITestDeepLink = false

    let launchRequest: WindowLaunchRequest?
    let coordinator: AppCoordinator?

    var body: some View {
        contentWithLifecycle
            .onReceive(NotificationCenter.default.publisher(for: .importLearningsProfile)) { _ in
                windowSession.appState.currentView = .learnings
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    learningsManager.showingImportPicker = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearLearningsData)) { _ in
                Task { @MainActor in
                    await learningsManager.clearAllData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOrganizationDetails)) { _ in
                withAnimation(.pageTransition) {
                    windowSession.appState.currentView = .history
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOrganizationPreview)) { _ in
                withAnimation(.pageTransition) {
                    if windowSession.appState.selectedDirectory == nil,
                       let currentDirectory = windowSession.organizer.currentDirectory {
                        windowSession.appState.selectedDirectory = currentDirectory
                    }
                    windowSession.appState.currentView = .organize
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .redoOrganizationWithModel)) { _ in
                withAnimation(.pageTransition) {
                    if windowSession.appState.selectedDirectory == nil,
                       let currentDirectory = windowSession.organizer.currentDirectory {
                        windowSession.appState.selectedDirectory = currentDirectory
                    }
                    windowSession.appState.currentView = .organize
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                Task { @MainActor in
                    settingsViewModel.forceSave()
                    await learningsManager.forceSave()
                }
            }
            .alert("Delete All Usage Data?", isPresented: $windowSession.appState.showDeleteUsageDataConfirmation) {
                Button("Delete", role: .destructive) {
                    windowSession.appState.deleteUsageData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all organization history, learnings data, and cached sessions. This action cannot be undone.")
            }
    }

    private var contentWithLifecycle: some View {
        contentWithEnvironment
            .task {
                let calibrate: ((WatchedFolder) -> Void)? = coordinator.map { coord in
                    { folder in coord.calibrateFolder(folder) }
                }
                await windowSession.configureIfNeeded(
                    settingsViewModel: settingsViewModel,
                    personaManager: personaManager,
                    customPersonaStore: customPersonaStore,
                    exclusionRules: exclusionRules,
                    storageLocationsManager: storageLocationsManager,
                    learningsManager: learningsManager,
                    automationManager: automationManager,
                    calibrateAction: calibrate
                )
                processLaunchRequestIfNeeded()
                processUITestDeeplinkIfNeeded()
            }
            .onChange(of: launchRequest?.id) { _, _ in
                processLaunchRequestIfNeeded()
            }
            .onChange(of: settingsViewModel.config) { _, newConfig in
                Task { @MainActor in
                    await windowSession.applyConfiguration(newConfig, learningsManager: learningsManager)
                }
            }
            .onChange(of: windowSession.organizer.isAIConfigured) { oldValue, newValue in
                if oldValue == true && newValue == false {
                    watchedFoldersManager.disableAutoOrganizeForAll(
                        reason: "AI provider is no longer configured"
                    )
                }
            }
            .onChange(of: watchedFoldersManager.folders) { _, _ in
                coordinator?.syncWatchedFolders()
            }
            .onOpenURL { url in
                SortyAppDelegate.pendingDeeplinkActivation = true
                handleExternalDeeplink(url)
            }
    }

    private var contentWithEnvironment: some View {
        ContentView()
            .environmentObject(settingsViewModel)
            .environmentObject(windowSession.appState)
            .environmentObject(personaManager)
            .environmentObject(customPersonaStore)
            .environmentObject(watchedFoldersManager)
            .environmentObject(windowSession.organizer)
            .environmentObject(exclusionRules)
            .environmentObject(extensionListener)
            .environmentObject(deeplinkHandler)
            .environmentObject(learningsManager)
            .environmentObject(storageLocationsManager)
            .environmentObject(automationManager)
            .environmentObject(notificationSettings)
            .environmentObject(windowSession.healthManager)
            .environmentObject(loginItemManager)
            .environmentObject(namingPresetManager)
            .environmentObject(globalShortcutManager)
            .environmentObject(steeringPromptManager)
            .environmentObject(windowSession.batchManager)
            .environmentObject(windowSession.appState.duplicateManager)
            .environmentObject(windowSession.appState.duplicateSettings)
            .focusedSceneValue(\.appState, windowSession.appState)
            .focusedSceneValue(\.organizer, windowSession.organizer)
            .trafficLightInactiveBorders()
            .trafficLightUpdateButton(updateManager: windowSession.appState.updateManager)
    }

    private func processLaunchRequestIfNeeded() {
        guard let launchRequest,
              handledLaunchRequestID != launchRequest.id,
              let url = launchRequest.deeplinkURL else {
            return
        }

        handledLaunchRequestID = launchRequest.id
        processDeeplink(url)
    }

    private func processUITestDeeplinkIfNeeded() {
        guard !handledUITestDeepLink,
              let urlString = ProcessInfo.processInfo.environment["XCUITEST_DEEPLINK"],
              let url = URL(string: urlString) else {
            return
        }

        handledUITestDeepLink = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            processDeeplink(url)
        }
    }

    private func handleExternalDeeplink(_ url: URL) {
        guard ExternalDeeplinkDeduper.shouldHandle(url) else { return }

        // Always reuse this window for deeplink navigation — never open a second one.
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        }

        processDeeplink(url)
    }

    private func processDeeplink(_ url: URL) {
        deeplinkHandler.handle(url: url)

        guard let destination = deeplinkHandler.pendingDestination else { return }

        windowSession.handle(
            destination: destination,
            settingsViewModel: settingsViewModel,
            personaManager: personaManager,
            customPersonaStore: customPersonaStore,
            watchedFoldersManager: watchedFoldersManager,
            exclusionRules: exclusionRules,
            storageLocationsManager: storageLocationsManager,
            learningsManager: learningsManager
        )
        deeplinkHandler.clearPending()
    }


}

import SwiftUI
import AppKit
#if canImport(SortyLib)
import SortyLib
#endif

struct MainWindowRootView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var openAIAuth: SubscriptionAuthManager
    @EnvironmentObject private var codexAuth: CodexCLIAuthManager
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

    @StateObject private var windowSession: WindowSession
    @ObservedObject private var copilotAuth = GitHubCopilotAuthManager.shared
    @State private var handledLaunchRequestID: UUID?
    @State private var handledUITestDeepLink = false
    @State private var setupRepairTask: Task<Void, Never>?

    let launchRequest: WindowLaunchRequest?
    let coordinator: AppCoordinator?

    init(
        launchRequest: WindowLaunchRequest?,
        coordinator: AppCoordinator?,
        updateManager: SparkleUpdateManager
    ) {
        self.launchRequest = launchRequest
        self.coordinator = coordinator
        _windowSession = StateObject(wrappedValue: WindowSession(updateManager: updateManager))
    }

    var body: some View {
        contentWithLifecycle
            .onReceive(NotificationCenter.default.publisher(for: .routeDeeplinkInMainWindow)) { notification in
                guard notification.targetsWindowSession(windowSession.id),
                      let url = notification.routedDeeplinkURL else {
                    return
                }

                processDeeplink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .presentSteeringPromptsInMainWindow)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
                withAnimation(.pageTransition) {
                    windowSession.appState.currentView = .organize
                }
                windowSession.appState.shouldPresentSteeringPrompts = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .importLearningsProfile)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
                windowSession.appState.currentView = .learnings
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    learningsManager.showingImportPicker = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearLearningsData)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
                Task { @MainActor in
                    await learningsManager.clearAllData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOrganizationDetails)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
                withAnimation(.pageTransition) {
                    windowSession.appState.currentView = .history
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOrganizationPreview)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
                withAnimation(.pageTransition) {
                    if windowSession.appState.selectedDirectory == nil,
                       let currentDirectory = windowSession.organizer.currentDirectory {
                        windowSession.appState.selectedDirectory = currentDirectory
                    }
                    windowSession.appState.currentView = .organize
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestApplyOrganizationConfirmation)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
                routeNotificationActionRequest(
                    kind: .applyConfirmation,
                    notification: notification
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .requestRedoOrganizationWithModelConfirmation)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
                routeNotificationActionRequest(
                    kind: .redoWithModelConfirmation,
                    notification: notification
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .redoOrganizationWithModel)) { notification in
                guard notification.targetsWindowSession(windowSession.id) else { return }
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
                scheduleSetupRepairReconciliation()
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
                scheduleSetupRepairReconciliation()
            }
            .onChange(of: windowSession.appState.hasCompletedOnboarding) { _, _ in
                scheduleSetupRepairReconciliation()
            }
            .onChange(of: windowSession.appState.requiresSetupRepair) { _, _ in
                scheduleSetupRepairReconciliation()
            }
            .onChange(of: codexAuth.isAuthenticated) { _, _ in
                scheduleSetupRepairReconciliation()
            }
            .onChange(of: copilotAuth.isAuthenticated) { _, _ in
                scheduleSetupRepairReconciliation()
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
            .background(MainWindowSessionTracker(sessionID: windowSession.id).frame(width: 0, height: 0))
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

        if MainWindowRouter.shared.routeDeeplink(url) {
            return
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

    private func routeNotificationActionRequest(
        kind: AppState.PendingNotificationActionRequest.Kind,
        notification: Notification
    ) {
        let folderPath = notification.userInfo?["folderPath"] as? String
        let notificationType = notification.userInfo?["notificationType"] as? String

        withAnimation(.pageTransition) {
            if let folderPath {
                windowSession.appState.selectedDirectory = URL(fileURLWithPath: folderPath)
            } else if windowSession.appState.selectedDirectory == nil,
                      let currentDirectory = windowSession.organizer.currentDirectory {
                windowSession.appState.selectedDirectory = currentDirectory
            }

            switch kind {
            case .applyConfirmation:
                windowSession.appState.currentView = .organize
            case .redoWithModelConfirmation:
                if notificationType == "previewReady" {
                    windowSession.appState.currentView = .organize
                } else {
                    windowSession.appState.currentView = .history
                }
            }
        }

        windowSession.appState.queueNotificationActionRequest(
            kind,
            folderPath: folderPath,
            notificationType: notificationType
        )
    }

    private var providerSetupContext: ProviderSetupContext {
        ProviderSetupContext(
            config: settingsViewModel.config,
            isGitHubCopilotAuthenticated: copilotAuth.isAuthenticated,
            isCodexAuthenticated: codexAuth.isAuthenticated,
            isCodexInstalled: codexAuth.isCodexInstalled,
            isAppleFoundationModelAvailable: settingsViewModel.isAppleModelAvailable,
            appleFoundationModelStatus: settingsViewModel.appleModelStatus
        )
    }

    private func scheduleSetupRepairReconciliation() {
        setupRepairTask?.cancel()
        setupRepairTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await reconcileSetupRepairState()
        }
    }

    @MainActor
    private func reconcileSetupRepairState() async {
        let appState = windowSession.appState

        guard appState.hasCompletedOnboarding else { return }

        codexAuth.checkStatus()
        openAIAuth.checkAuthenticationStatus()
        copilotAuth.checkAuthenticationStatus()
        settingsViewModel.refreshAppleModelStatus()

        let providerStatus = OnboardingSetupValidator.providerStatus(context: providerSetupContext)
        if !providerStatus.isReady {
            appState.startSetupRepair(message: providerStatus.message)
            return
        }

        guard appState.requiresSetupRepair else { return }

        do {
            try await settingsViewModel.testConnection()
            appState.clearSetupRepairState()
        } catch {
            appState.startSetupRepair(
                message: "Sorty could not verify \(settingsViewModel.config.provider.displayName): \(error.localizedDescription)"
            )
        }
    }

}

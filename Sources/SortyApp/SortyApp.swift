//
//  SortyApp.swift
//  Sorty
//
//  Created on macOS
//

import SwiftUI

#if canImport(SortyLib)
    import SortyLib
#endif

@MainActor
class SortyAppDelegate: NSObject, NSApplicationDelegate {
    private static let confirmQuitWhileOrganizingKey = "confirmQuitWhileOrganizing"
    private static let buildAutoCloseRequestKey = "buildAutoCloseRequest"
    @MainActor static var forceQuit = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .forceQuitSorty,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SortyAppDelegate.forceQuit = true
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.forceQuit {
            Self.forceQuit = false
            return .terminateNow
        }

        #if canImport(SortyLib)
            guard shouldWarnBeforeQuitForActiveAutomation,
                let warningContext = quitWarningContext
            else {
                return .terminateNow
            }

            return presentQuitWarning(for: warningContext)
        #else
            return .terminateNow
        #endif
    }

    #if canImport(SortyLib)
        private enum QuitWarningContext {
            case runningActivities(Int)
            case watchedFolders(Int)
        }

        private var shouldWarnBeforeQuitForActiveAutomation: Bool {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: Self.confirmQuitWhileOrganizingKey) == nil {
                return true
            }
            return defaults.bool(forKey: Self.confirmQuitWhileOrganizingKey)
        }

        private var shouldAllowBuildRequestedQuit: Bool {
            UserDefaults.standard.bool(forKey: Self.buildAutoCloseRequestKey)
        }

        private var quitWarningContext: QuitWarningContext? {
            if shouldAllowBuildRequestedQuit && !FolderOrganizer.hasRunningOrganizations {
                return nil
            }

            if FolderOrganizer.hasRunningOrganizations {
                return .runningActivities(FolderOrganizer.runningOrganizationCount)
            }

            guard shouldContinueRunningWhenLastWindowCloses else {
                return nil
            }

            let watchedCount = activeWatchedAutoOrganizeFolderCount
            guard watchedCount > 0 else {
                return nil
            }

            return .watchedFolders(watchedCount)
        }

        private var activeWatchedAutoOrganizeFolderCount: Int {
            guard let data = UserDefaults.standard.data(forKey: "watchedFolders"),
                let folders = try? JSONDecoder().decode([WatchedFolder].self, from: data)
            else {
                return 0
            }

            return folders.filter { $0.isEnabled && $0.autoOrganize }.count
        }

        private var shouldContinueRunningWhenLastWindowCloses: Bool {
            let defaults = UserDefaults.standard
            let keepInBackground = defaults.bool(forKey: "keepInBackground")
            let showMenuBarExtra = defaults.bool(forKey: "showMenuBarExtra")
            return keepInBackground || showMenuBarExtra
        }

        private func presentQuitWarning(for context: QuitWarningContext)
            -> NSApplication.TerminateReply
        {
            let alert = NSAlert()
            let backgroundHint =
                shouldContinueRunningWhenLastWindowCloses
                ? " To keep automation running, close the window instead of quitting."
                : ""

            alert.alertStyle = .warning
            switch context {
            case .runningActivities(let runningCount):
                let areIs = runningCount == 1 ? "is" : "are"
                let noun = runningCount == 1 ? "activity" : "activities"
                let activitySummary =
                    runningCount == 1
                    ? "An organize, rename, or watched-folder activity is"
                    : "\(runningCount) organize, rename, or watched-folder activities are"
                alert.messageText = "Quit Sorty while \(noun) \(areIs) running?"
                alert.informativeText =
                    "\(activitySummary) still in progress. Quitting now will interrupt active work and stop watched-folder automations until Sorty is reopened.\(backgroundHint)"

            case .watchedFolders(let watchedCount):
                let areIs = watchedCount == 1 ? "is" : "are"
                let noun = watchedCount == 1 ? "watched folder" : "watched folders"
                alert.messageText = "Quit Sorty and stop watched-folder automation?"
                alert.informativeText =
                    "\(watchedCount) \(noun) \(areIs) currently active for auto-organization. Quitting now will stop monitoring until Sorty is reopened.\(backgroundHint)"
            }

            alert.addButton(withTitle: "Quit Sorty")
            alert.addButton(withTitle: "Cancel")

            let dontAskAgainCheckbox = NSButton(
                checkboxWithTitle: "Don't ask again before quitting during activity",
                target: nil,
                action: nil
            )
            dontAskAgainCheckbox.state = .off
            alert.accessoryView = dontAskAgainCheckbox

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if dontAskAgainCheckbox.state == .on {
                    UserDefaults.standard.set(false, forKey: Self.confirmQuitWhileOrganizingKey)
                }
                return .terminateNow
            }

            return .terminateCancel
        }
    #endif

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let keepInBackground = UserDefaults.standard.bool(forKey: "keepInBackground")
        let showMenuBarExtra = UserDefaults.standard.bool(forKey: "showMenuBarExtra")

        return !keepInBackground && !showMenuBarExtra
    }

    /// Track whether a deeplink URL is being handled so the app can suppress
    /// the extra window that SwiftUI creates when activated via URL scheme.
    @MainActor static var pendingDeeplinkActivation = false

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if Self.pendingDeeplinkActivation {
            Self.pendingDeeplinkActivation = false
            // If we already have a visible window, suppress creating another one.
            if flag { return false }
        }
        return true
    }

    @MainActor
    func updateActivationPolicy(hideDockIcon: Bool) {
        if hideDockIcon {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }
    }
}

@main
struct SortyApp: App {
    @NSApplicationDelegateAdaptor(SortyAppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("keepInBackground") private var keepInBackground = false
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("finderIntegrationEnabled") private var finderIntegrationEnabled = true

    @StateObject private var settingsViewModel: SettingsViewModel
    @StateObject private var personaManager = PersonaManager()
    @StateObject private var customPersonaStore = CustomPersonaStore()
    @StateObject private var watchedFoldersManager = WatchedFoldersManager()
    @StateObject private var storageLocationsManager = StorageLocationsManager()
    @StateObject private var exclusionRules = ExclusionRulesManager()
    @StateObject private var extensionListener = ExtensionListener()
    @StateObject private var deeplinkHandler = DeeplinkHandler.shared
    @StateObject private var learningsManager = LearningsManager()
    @StateObject private var automationManager = AutomationManager()
    @StateObject private var openAIAuthManager: SubscriptionAuthManager
    @StateObject private var codexAuthManager: CodexCLIAuthManager
    @StateObject private var notificationSettings = NotificationSettingsManager.shared
    @StateObject private var loginItemManager = LoginItemManager.shared
    @StateObject private var namingPresetManager = NamingPresetManager.shared
    @StateObject private var globalShortcutManager = GlobalShortcutManager.shared
    @StateObject private var steeringPromptManager = SteeringPromptManager.shared
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var updateManager = SparkleUpdateManager()
    @StateObject private var automationOrganizer = FolderOrganizer()

    @State private var coordinator: AppCoordinator?
    @State private var hasConfiguredGlobals = false

    private let widgetSyncManager = SortyWidgetSyncManager.shared

    init() {
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel())

        let codexAuthManager = CodexCLIAuthManager()
        _codexAuthManager = StateObject(wrappedValue: codexAuthManager)
        _openAIAuthManager = StateObject(
            wrappedValue: SubscriptionAuthManager(
                provider: .openAI, codexAuthManager: codexAuthManager)
        )

        UserDefaults.standard.register(defaults: [
            "showMenuBarExtra": true,
            "keepInBackground": false,
            "hideDockIcon": false,
            "launchAtLogin": false,
            "confirmQuitWhileOrganizing": true,
            "finderIntegrationEnabled": true,
        ])

        configureUITestStateIfNeeded()
    }

    @SceneBuilder
    var body: some Scene {
        Window("Sorty", id: "main") {
            mainWindowContent(launchRequest: .constant(nil))
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .defaultLaunchBehavior(.presented)

        WindowGroup(for: WindowLaunchRequest.self) { launchRequest in
            mainWindowContent(launchRequest: launchRequest)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .commands {
            SortyCommands()
        }

        MenuBarExtra(
            isInserted: Binding(
                get: { showMenuBarExtra || keepInBackground },
                set: { showMenuBarExtra = $0 }
            )
        ) {
            MenuBarView()
                .tint(SortyDesignSystem.Colors.resolvedAccent)
                .accentColor(SortyDesignSystem.Colors.resolvedAccent)
                .environmentObject(watchedFoldersManager)
                .environmentObject(loginItemManager)
                .environmentObject(notificationSettings)
                .environmentObject(menuBarController)
                .task {
                    configureGlobalsIfNeeded()
                }
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private func mainWindowContent(launchRequest: Binding<WindowLaunchRequest?>) -> some View {
        mainWindowIntegrationHandlers(
            mainWindowConfigurationHandlers(
                mainWindowRootView(launchRequest: launchRequest)
            )
        )
    }

    private func mainWindowConfigurationHandlers<Content: View>(_ content: Content) -> some View {
        content
            .task {
                configureGlobalsIfNeeded()
            }
            .onChange(of: settingsViewModel.config) { _, newConfig in
                Task { @MainActor in
                    try? await automationOrganizer.configure(with: newConfig)
                    learningsManager.configure(with: newConfig)
                }
            }
            .onChange(of: hideDockIcon) { _, newValue in
                appDelegate.updateActivationPolicy(hideDockIcon: newValue)
            }
            .onChange(of: launchAtLogin) { _, _ in
                syncLoginItemState()
            }
            .onChange(of: keepInBackground) { _, _ in
                syncLoginItemState()
            }
            .onChange(of: showMenuBarExtra) { _, _ in
                syncLoginItemState()
            }
    }

    private func mainWindowIntegrationHandlers<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: finderIntegrationEnabled) { _, newValue in
                if newValue {
                    ExtensionCommunication.beginMonitoringFinderSyncRuntime()
                    Task {
                        _ = await ExtensionCommunication.ensureQuickActionInstalledAsync()
                        await ExtensionCommunication.autoRepairFinderSyncIfNeeded()
                    }
                }
            }
            .onChange(of: watchedFoldersManager.folders) { _, _ in
                coordinator?.syncWatchedFolders()
                widgetSyncManager.sync(
                    watchedFoldersManager: watchedFoldersManager,
                    storageLocationsManager: storageLocationsManager
                )
            }
            .onChange(of: storageLocationsManager.locations) { _, _ in
                widgetSyncManager.sync(
                    watchedFoldersManager: watchedFoldersManager,
                    storageLocationsManager: storageLocationsManager
                )
            }
    }

    private func mainWindowRootView(launchRequest: Binding<WindowLaunchRequest?>) -> some View {
        MainWindowRootView(
            launchRequest: launchRequest.wrappedValue,
            coordinator: coordinator,
            updateManager: updateManager
        )
        .tint(SortyDesignSystem.Colors.resolvedAccent)
        .accentColor(SortyDesignSystem.Colors.resolvedAccent)
        .environmentObject(settingsViewModel)
        .environmentObject(personaManager)
        .environmentObject(customPersonaStore)
        .environmentObject(watchedFoldersManager)
        .environmentObject(storageLocationsManager)
        .environmentObject(exclusionRules)
        .environmentObject(extensionListener)
        .environmentObject(deeplinkHandler)
        .environmentObject(learningsManager)
        .environmentObject(automationManager)
        .environmentObject(openAIAuthManager)
        .environmentObject(codexAuthManager)
        .environmentObject(notificationSettings)
        .environmentObject(loginItemManager)
        .environmentObject(namingPresetManager)
        .environmentObject(globalShortcutManager)
        .environmentObject(steeringPromptManager)
        .environmentObject(menuBarController)
    }

    @MainActor
    private func configureGlobalsIfNeeded() {
        guard !hasConfiguredGlobals else { return }
        hasConfiguredGlobals = true

        // Harness mode: skip heavy initialization for fast iteration
        if FeatureFlags.harnessMode {
            configureHarnessMode()
            return
        }

        appDelegate.updateActivationPolicy(hideDockIcon: hideDockIcon)
        syncLoginItemState()

        watchedFoldersManager.restoreSecurityScopedAccess()
        storageLocationsManager.restoreSecurityScopedAccess()
        widgetSyncManager.startIfNeeded(
            watchedFoldersManager: watchedFoldersManager,
            storageLocationsManager: storageLocationsManager
        )

        ExtensionCommunication.beginMonitoringFinderSyncRuntime()
        Task {
            _ = await ExtensionCommunication.ensureQuickActionInstalledAsync()
            await ExtensionCommunication.autoRepairFinderSyncIfNeeded()
        }

        if coordinator == nil {
            coordinator = AppCoordinator(
                organizer: automationOrganizer,
                watchedFoldersManager: watchedFoldersManager,
                learningsManager: learningsManager
            )
        }

        automationOrganizer.exclusionRules = exclusionRules
        automationOrganizer.personaManager = personaManager
        automationOrganizer.customPersonaStore = customPersonaStore
        automationOrganizer.storageLocationsManager = storageLocationsManager
        automationOrganizer.learningsManager = learningsManager
        automationOrganizer.automationManager = automationManager

        Task<Void, Never> { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            automationManager.startUp()
            try? await automationOrganizer.configure(with: settingsViewModel.config)
            learningsManager.configure(with: settingsViewModel.config)
            menuBarController.configure(settings: settingsViewModel)
        }

        if ProcessInfo.processInfo.environment["XCUITEST_NOTIFICATION_ACTION"] == "showDetails" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                NotificationCenter.default.post(name: .showOrganizationDetails, object: nil)
            }
        }
    }

    @MainActor
    private func configureHarnessMode() {
        appDelegate.updateActivationPolicy(hideDockIcon: false)
    }

    @MainActor
    private func syncLoginItemState() {
        loginItemManager.syncServiceRegistration(
            launchAtLogin: launchAtLogin,
            keepInBackground: keepInBackground,
            showMenuBarExtra: showMenuBarExtra
        )
    }

    private func configureUITestStateIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting") else { return }

        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        let aiConfigKey = "aiConfig"

        defaults.set(
            env["XCUITEST_DISABLE_STORED_PROVIDER_CREDENTIALS"] == "1",
            forKey: "uitestDisableStoredProviderCredentials"
        )
        defaults.set(
            env["XCUITEST_ASSUME_FILES_PERMISSION"] == "1",
            forKey: "uitestAssumeFilesAndFoldersPermission"
        )
        defaults.removeObject(forKey: "uitestProviderHealthCheckFailedOnce")

        if let healthCheckMode = env["XCUITEST_PROVIDER_HEALTHCHECK"], !healthCheckMode.isEmpty {
            defaults.set(healthCheckMode, forKey: "uitestProviderHealthCheckMode")
        } else {
            defaults.removeObject(forKey: "uitestProviderHealthCheckMode")
        }

        if env["XCUITEST_FORCE_ONBOARDING"] == "1" {
            defaults.removeObject(forKey: "lastLaunchedVersion")
            defaults.set(false, forKey: "hasCompletedOnboarding")
            defaults.set(false, forKey: "requiresSetupRepair")
            defaults.removeObject(forKey: "setupRepairMessage")

            var config = AIConfig.default
            config.provider = .openAICompatible
            config.apiKey = nil
            config.apiURL = AIProvider.openAICompatible.defaultAPIURL
            config.requiresAPIKey = true
            if let encoded = try? JSONEncoder().encode(config) {
                defaults.set(encoded, forKey: aiConfigKey)
            }
        }

        if env["XCUITEST_FORCE_SETUP_REPAIR"] == "1" {
            defaults.set(BuildInfo.version, forKey: "lastLaunchedVersion")
            defaults.set(true, forKey: "hasCompletedOnboarding")
            defaults.set(true, forKey: "requiresSetupRepair")
            defaults.set(
                "Finish setting up your AI provider before organizing files.",
                forKey: "setupRepairMessage"
            )

            var config = AIConfig.default
            config.provider = .openAICompatible
            config.apiKey = nil
            config.apiURL = AIProvider.openAICompatible.defaultAPIURL
            config.requiresAPIKey = true
            if let encoded = try? JSONEncoder().encode(config) {
                defaults.set(encoded, forKey: aiConfigKey)
            }
        }

        if let consentValue = env["XCUITEST_LEARNINGS_CONSENT"] {
            defaults.set(consentValue == "1", forKey: "learnings_consent_granted")
        }

        if let setupCompleteValue = env["XCUITEST_LEARNINGS_SETUP_COMPLETE"] {
            defaults.set(setupCompleteValue == "1", forKey: "learnings_initial_setup_complete")
        }

        if env["XCUITEST_SEED_LEARNINGS_PROFILE"] == "active_rule" {
            defaults.set(true, forKey: "learnings_consent_granted")

            var seededProfile = LearningsProfile()
            seededProfile.consentGranted = true
            seededProfile.sessions = [
                OrganizationSession(
                    id: "ui-seed-session",
                    folderPath: "/tmp",
                    historyEntryId: "ui-seed-history"
                )
            ]
            seededProfile.inferredRules = [
                InferredRule(
                    pattern: ".*\\.pdf$",
                    template: "Documents/{filename}",
                    priority: 80,
                    explanation: "Seeded UI test rule",
                    scope: .folder("/tmp"),
                    status: .active
                )
            ]

            try? LearningsFileManager.save(profile: seededProfile)
        }

        if env["XCUITEST_SEED_HISTORY_ENTRY"] == "1" {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
            let historyDirectory = appSupport?.appendingPathComponent(
                "Sorty/History", isDirectory: true)
            let historyURL = historyDirectory?.appendingPathComponent("organization-history.json")
            let backupHistoryURL = historyDirectory?.appendingPathComponent(
                "organization-history.json.bak")

            if let historyDirectory {
                try? FileManager.default.createDirectory(
                    at: historyDirectory, withIntermediateDirectories: true)
            }

            let seededEntries = [
                OrganizationHistoryEntry(
                    id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
                    timestamp: Date(),
                    directoryPath: "/tmp",
                    filesOrganized: 4,
                    foldersCreated: 2,
                    success: true,
                    status: .completed,
                    source: .manual
                )
            ]

            if let data = try? JSONEncoder().encode(seededEntries) {
                if let historyURL {
                    try? data.write(to: historyURL)
                }
                if let backupHistoryURL {
                    try? data.write(to: backupHistoryURL)
                }
            }
        }
    }
}

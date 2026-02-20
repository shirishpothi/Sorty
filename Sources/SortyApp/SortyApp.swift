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

class SortyAppDelegate: NSObject, NSApplicationDelegate {
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
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let keepInBackground = UserDefaults.standard.bool(forKey: "keepInBackground")
        let showMenuBarExtra = UserDefaults.standard.bool(forKey: "showMenuBarExtra")

        return !keepInBackground && !showMenuBarExtra
    }

    /// Track whether a deeplink URL is being handled so the app can suppress
    /// the extra window that SwiftUI creates when activated via URL scheme.
    @MainActor static var pendingDeeplinkActivation = false

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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
    @AppStorage("finderIntegrationEnabled") private var finderIntegrationEnabled = false

    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var personaManager = PersonaManager()
    @StateObject private var customPersonaStore = CustomPersonaStore()
    @StateObject private var watchedFoldersManager = WatchedFoldersManager()
    @StateObject private var storageLocationsManager = StorageLocationsManager()
    @StateObject private var exclusionRules = ExclusionRulesManager()
    @StateObject private var extensionListener = ExtensionListener()
    @StateObject private var deeplinkHandler = DeeplinkHandler.shared
    @StateObject private var learningsManager = LearningsManager()
    @StateObject private var automationManager = AutomationManager()
    @StateObject private var notificationSettings = NotificationSettingsManager.shared
    @StateObject private var loginItemManager = LoginItemManager.shared
    @StateObject private var namingPresetManager = NamingPresetManager.shared
    @StateObject private var globalShortcutManager = GlobalShortcutManager.shared
    @StateObject private var steeringPromptManager = SteeringPromptManager.shared
    @StateObject private var menuBarController = MenuBarController()

    @StateObject private var automationOrganizer = FolderOrganizer()

    @State private var coordinator: AppCoordinator?
    @State private var hasConfiguredGlobals = false

    private var backgroundActivity: NSObjectProtocol?

    init() {
        UserDefaults.standard.register(defaults: [
            "showMenuBarExtra": true,
            "keepInBackground": false,
            "hideDockIcon": false,
            "launchAtLogin": false
        ])

        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Monitoring watched folders for automatic organization"
        )
    }

    @SceneBuilder
    var body: some Scene {
        WindowGroup(for: WindowLaunchRequest.self) { launchRequest in
            mainWindowContent(launchRequest: launchRequest)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .commands {
            SortyCommands()
        }

        MenuBarExtra(isInserted: Binding(
            get: { showMenuBarExtra || keepInBackground },
            set: { showMenuBarExtra = $0 }
        )) {
            MenuBarView()
                .environmentObject(watchedFoldersManager)
                .environmentObject(loginItemManager)
                .environmentObject(notificationSettings)
                .environmentObject(menuBarController)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private func mainWindowContent(launchRequest: Binding<WindowLaunchRequest?>) -> some View {
        MainWindowRootView(
            launchRequest: launchRequest.wrappedValue,
            coordinator: coordinator
        )
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
        .environmentObject(notificationSettings)
        .environmentObject(loginItemManager)
        .environmentObject(namingPresetManager)
        .environmentObject(globalShortcutManager)
        .environmentObject(steeringPromptManager)
        .environmentObject(menuBarController)
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
        .onChange(of: finderIntegrationEnabled) { _, newValue in
            if newValue {
                Task {
                    _ = await ExtensionCommunication.ensureQuickActionInstalledAsync()
                }
            }
        }
        .onChange(of: watchedFoldersManager.folders) { _, _ in
            coordinator?.syncWatchedFolders()
        }
    }

    @MainActor
    private func configureGlobalsIfNeeded() {
        guard !hasConfiguredGlobals else { return }
        hasConfiguredGlobals = true

        appDelegate.updateActivationPolicy(hideDockIcon: hideDockIcon)
        syncLoginItemState()

        watchedFoldersManager.restoreSecurityScopedAccess()
        storageLocationsManager.restoreSecurityScopedAccess()

        if finderIntegrationEnabled {
            Task {
                _ = await ExtensionCommunication.ensureQuickActionInstalledAsync()
            }
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
    private func syncLoginItemState() {
        loginItemManager.syncServiceRegistration(
            launchAtLogin: launchAtLogin,
            keepInBackground: keepInBackground,
            showMenuBarExtra: showMenuBarExtra
        )
    }
}

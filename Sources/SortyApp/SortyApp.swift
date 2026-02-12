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
        
        // Only terminate if BOTH background and menu bar are disabled
        return !keepInBackground && !showMenuBarExtra
    }

    /// Updates the application activation policy to show or hide the Dock icon
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
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var appState = AppState()
    @StateObject private var personaManager = PersonaManager()
    @StateObject private var customPersonaStore = CustomPersonaStore()
    @StateObject private var watchedFoldersManager = WatchedFoldersManager()
    @StateObject private var storageLocationsManager = StorageLocationsManager()
    @StateObject private var organizer = FolderOrganizer()
    @StateObject private var exclusionRules = ExclusionRulesManager()
    @StateObject private var extensionListener = ExtensionListener()
    @StateObject private var deeplinkHandler = DeeplinkHandler.shared
    @StateObject private var learningsManager = LearningsManager() // Promoted to App State
    @StateObject private var automationManager = AutomationManager()
    @StateObject private var notificationSettings = NotificationSettingsManager.shared
    @StateObject private var healthManager = WorkspaceHealthManager()
    @StateObject private var loginItemManager = LoginItemManager.shared
    @StateObject private var namingPresetManager = NamingPresetManager.shared
    @StateObject private var globalShortcutManager = GlobalShortcutManager.shared
    @StateObject private var steeringPromptManager = SteeringPromptManager.shared
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var batchManager = BatchOrganizationManager()

    private var activeWatchedFoldersCount: Int {
        watchedFoldersManager.folders.filter { $0.isEnabled && $0.autoOrganize }.count
    }

    @State private var coordinator: AppCoordinator?
    
    /// Background activity token to prevent app suspension during folder watching
    private var backgroundActivity: NSObjectProtocol?
    
    init() {
        UserDefaults.standard.register(defaults: [
            "showMenuBarExtra": true,
            "keepInBackground": false,
            "hideDockIcon": false,
            "launchAtLogin": false
        ])
        
        // Begin background activity to keep FolderWatcher alive when window is closed
        // Include .userInitiated to prevent App Nap from throttling the process
        backgroundActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Monitoring watched folders for automatic organization"
        )
    }
    
    @ViewBuilder
    private var mainView: some View {
        ContentView()
            .environmentObject(settingsViewModel)
            .environmentObject(appState)
            .environmentObject(personaManager)
            .environmentObject(customPersonaStore)
            .environmentObject(watchedFoldersManager)
            .environmentObject(organizer)
            .environmentObject(exclusionRules)
            .environmentObject(extensionListener)
            .environmentObject(deeplinkHandler)
            .environmentObject(learningsManager) // Inject
            .environmentObject(storageLocationsManager)
            .environmentObject(automationManager)
            .environmentObject(notificationSettings)
            .environmentObject(healthManager)
            .environmentObject(loginItemManager)
            .environmentObject(namingPresetManager)
            .environmentObject(globalShortcutManager)
            .environmentObject(steeringPromptManager)
            .environmentObject(batchManager)
            .environmentObject(appState.duplicateManager)
            .environmentObject(appState.duplicateSettings)
            .onAppear {
                appDelegate.updateActivationPolicy(hideDockIcon: hideDockIcon)
                
                // Sync login item/background status
                loginItemManager.syncServiceRegistration(
                    launchAtLogin: launchAtLogin,
                    keepInBackground: keepInBackground,
                    showMenuBarExtra: showMenuBarExtra
                )

                // Restore sandbox access for watched folders
                watchedFoldersManager.restoreSecurityScopedAccess()
                // Restore sandbox access for storage locations
                storageLocationsManager.restoreSecurityScopedAccess()
                
                if coordinator == nil {
                    coordinator = AppCoordinator(
                        organizer: organizer, 
                        watchedFoldersManager: watchedFoldersManager,
                        learningsManager: learningsManager // Pass to Coordinator
                    )
                }
                
                // Setup organizer
                organizer.exclusionRules = exclusionRules
                organizer.personaManager = personaManager
                organizer.customPersonaStore = customPersonaStore
                organizer.storageLocationsManager = storageLocationsManager
                organizer.learningsManager = learningsManager
                organizer.automationManager = automationManager
                appState.organizer = organizer

                appState.calibrateAction = { folder in
                    coordinator?.calibrateFolder(folder)
                }
                
                // Initial configuration of organizer
                Task<Void, Never> { @MainActor in
                    // Defer automation startup slightly to ensure UI is ready
                    // This prevents crashes on macOS 15+ related to early AppleScript execution
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    automationManager.startUp()
                    
                    try? await organizer.configure(with: settingsViewModel.config)
                    learningsManager.configure(with: settingsViewModel.config)
                    menuBarController.configure(organizer: organizer, settings: settingsViewModel)
                    
                    // Check for updates on launch (once per 24 hours)
                    appState.updateManager.checkOnLaunchIfNeeded()

                    // Global shortcut disabled
                }
                
                // Testability Hook for UI Tests to trigger deeplinks reliably
                if let urlString = ProcessInfo.processInfo.environment["XCUITEST_DEEPLINK"],
                   let url = URL(string: urlString) {
                    // Delay slightly to ensure app is ready
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s
                        processDeepLink(url)
                    }
                }

                if ProcessInfo.processInfo.environment["XCUITEST_NOTIFICATION_ACTION"] == "showDetails" {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                        NotificationCenter.default.post(name: .showOrganizationDetails, object: nil)
                    }
                }
            }
            .onChange(of: settingsViewModel.config) { _, newConfig in
                Task<Void, Never> { @MainActor in
                    try? await organizer.configure(with: newConfig)
                    learningsManager.configure(with: newConfig)
                }
            }
            .onChange(of: organizer.isAIConfigured) { oldValue, newValue in
                if oldValue == true && newValue == false {
                    // AI became invalid - disable auto-organize on all folders
                    watchedFoldersManager.disableAutoOrganizeForAll(
                        reason: "AI provider is no longer configured"
                    )
                }
            }
            .onChange(of: watchedFoldersManager.folders) { oldValue, newValue in
                coordinator?.syncWatchedFolders()
            }
            .onChange(of: hideDockIcon) { _, newValue in
                appDelegate.updateActivationPolicy(hideDockIcon: newValue)
            }
            .onOpenURL { url in
                processDeepLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .importLearningsProfile)) { _ in
                appState.currentView = .learnings
                // Small delay to ensure view transition happens before showing picker
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    learningsManager.showingImportPicker = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                Task<Void, Never> { @MainActor in
                    settingsViewModel.forceSave()
                    await learningsManager.forceSave()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearLearningsData)) { _ in
                Task { @MainActor in
                    await learningsManager.clearAllData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showOrganizationDetails)) { _ in
                withAnimation(.pageTransition) {
                    appState.currentView = .history
                }
            }
            .alert("Delete All Usage Data?", isPresented: $appState.showDeleteUsageDataConfirmation) {
                Button("Delete", role: .destructive) {
                    appState.deleteUsageData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all organization history, learnings data, and cached sessions. This action cannot be undone.")
            }
    }

    @SceneBuilder
    var body: some Scene {
        WindowGroup {
            mainView
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .commands {
            SortyCommands(appState: appState)
        }
        
        MenuBarExtra(isInserted: Binding(
            get: { showMenuBarExtra || keepInBackground },
            set: { showMenuBarExtra = $0 }
        )) {
            MenuBarView()
                .environmentObject(watchedFoldersManager)
                .environmentObject(appState)
                .environmentObject(organizer)
                .environmentObject(settingsViewModel)
                .environmentObject(loginItemManager)
                .environmentObject(notificationSettings)
                .environmentObject(menuBarController)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }

    private func processDeepLink(_ url: URL) {
        // Handle deeplinks
        deeplinkHandler.handle(url: url)
        
        // Navigate based on destination
        if let destination = deeplinkHandler.pendingDestination {
            switch destination {
            case .organize(let path, let personaId, let autostart):
                if let path = path {
                    appState.selectedDirectory = URL(fileURLWithPath: path)
                }
                if let personaId = personaId {
                    // Try built-in first
                    if let persona = PersonaType(rawValue: personaId) {
                        personaManager.selectPersona(persona)
                    } else {
                        // Then custom
                        personaManager.selectCustomPersona(personaId)
                    }
                }
                appState.currentView = .organize
                if autostart {
                    // Trigger organization via coordinator
                    Task<Void, Never> { @MainActor in
                        // Small delay to allow view to load
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if let directory = appState.selectedDirectory {
                            try? await appState.organizer?.organize(directory: directory)
                        }
                    }
                }
                
            case .duplicates(let path, let autostart):
                if let path = path {
                    appState.selectedDirectory = URL(fileURLWithPath: path)
                }
                appState.currentView = .duplicates
                if autostart {
                    Task<Void, Never> { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        // Trigger duplicate scan logic if accessible
                        // appState.duplicatesManager.scan(directory) -> if available
                    }
                }
                
            case .learnings(let action, _):
                switch action {
                case .honing:
                    appState.startHoningSession()
                case .stats:
                    appState.showLearningsStats()
                case .withdraw:
                    appState.currentView = .learnings
                    appState.pauseLearning()
                case .export:
                    appState.exportLearningsProfile()
                case .importProfile:
                    appState.importLearningsProfile()
                case .clear:
                    appState.currentView = .learnings
                    Task { @MainActor in
                        await learningsManager.clearAllData()
                    }
                case .none:
                    appState.currentView = .learnings
                }
                
            case .settings(let section):
                if let section = section?.lowercased() {
                    switch section {
                    case "watched", "watched-folders", "folders":
                        appState.currentView = .watchedFolders
                    case "exclusions", "rules":
                        appState.currentView = .exclusions
                    case "storage", "storage-locations":
                        appState.currentView = .storageLocations
                    case "health", "workspace-health":
                        appState.currentView = .workspaceHealth
                    default:
                        appState.currentView = .settings
                        let category = SettingsCategory.allCases.first {
                            $0.rawValue.lowercased().contains(section) ||
                            String(describing: $0).lowercased() == section
                        }
                        appState.selectedSettingsSection = category
                    }
                } else {
                    appState.currentView = .settings
                    appState.selectedSettingsSection = nil
                }
                
            case .help:
                appState.showHelp()
                
            case .history:
                appState.currentView = .history
                
            case .health:
                appState.currentView = .workspaceHealth
                
            case .persona(let action, let prompt, let generate):
                appState.currentView = .settings
                // settingsViewModel.selectedSection = .advanced // Not supported
                if action == "create" || generate {
                    if generate, let prompt = prompt {
                        Task<Void, Never> {
                            // "Agentic" persona generation
                            let generator = PersonaGenerator()
                            do {
                                let result = try await generator.generatePersona(from: prompt, config: settingsViewModel.config)
                                await MainActor.run {
                                    let newPersona = CustomPersona(
                                        name: result.name,
                                        description: prompt,
                                        promptModifier: result.prompt
                                    )
                                    customPersonaStore.addPersona(newPersona)
                                    personaManager.selectCustomPersona(newPersona.id)
                                    // Ideally notify user success
                                }
                            } catch {
                                print("Failed to generate persona: \(error)")
                            }
                        }
                    } else {
                        // Just show UI for manual creation
                    }
                }
                
            case .watched(let action, let path):
                appState.currentView = .watchedFolders
                if action == "add", let path = path {
                    watchedFoldersManager.addFolder(WatchedFolder(path: path))
                }
                
            case .rules(let action, _, let pattern):
                appState.currentView = .exclusions
                if action == "add", let pattern = pattern {
                    let rule = ExclusionRule(type: .pathContains, pattern: pattern)
                    exclusionRules.addRule(rule)
                }
                
            case .exclusions(let action, let pattern):
                appState.currentView = .exclusions
                if action == "add", let pattern = pattern {
                    let rule = ExclusionRule(type: .pathContains, pattern: pattern)
                    exclusionRules.addRule(rule)
                }
                
            case .scan(let path):
                if let path = path {
                    appState.selectedDirectory = URL(fileURLWithPath: path)
                }
                appState.currentView = .workspaceHealth
                
            case .storage(let action, let path):
                appState.currentView = .storageLocations
                if action == "add", let path = path {
                    let url = URL(fileURLWithPath: path)
                    try? storageLocationsManager.addLocation(url: url)
                }
            }
            deeplinkHandler.clearPending()
        }
    }

}

//
//  SortyApp.swift
//  Sorty
//
//  Created on macOS
//

import Darwin
import SwiftUI

#if canImport(SortyLib)
    import SortyLib
#endif

@MainActor
class SortyAppDelegate: NSObject, NSApplicationDelegate {
    private static let confirmQuitWhileOrganizingKey = "confirmQuitWhileOrganizing"
    private static let buildAutoCloseRequestKey = "buildAutoCloseRequest"
    @MainActor static var forceQuit = false
    private var recoveryWindowController: NSWindowController?
    private let launchStartedAt = Date()

    var launchDuration: TimeInterval {
        Date().timeIntervalSince(launchStartedAt)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        ApplicationMover.offerToMoveToApplicationsIfNeeded()
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: .forceQuitSorty,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
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
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "activeWatchedFolderCount") != nil {
                return defaults.integer(forKey: "activeWatchedFolderCount")
            }

            guard let data = UserDefaults.standard.data(forKey: "watchedFolders"),
                let folders = try? JSONDecoder().decode([WatchedFolder].self, from: data)
            else {
                return 0
            }

            return folders.filter(\.isEnabled).count
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

    func presentRecoveryWindow<Content: View>(rootView: Content) {
        guard recoveryWindowController == nil else {
            recoveryWindowController?.showWindow(nil)
            return
        }

        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sorty"
        window.contentViewController = hostingController
        window.center()

        let controller = NSWindowController(window: window)
        recoveryWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func scheduleRecoveryWindow(rootView: @escaping @MainActor () -> AnyView) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(750))
            let hasMainWindow = NSApplication.shared.windows.contains { window in
                window.canBecomeMain && (window.isVisible || window.isMiniaturized)
            }
            guard !hasMainWindow else { return }
            presentRecoveryWindow(rootView: rootView())
        }
    }
}

@MainActor
private enum ApplicationMover {
    private static let applicationsPath = "/Applications"

    static let shouldLaunchMainUI: Bool = {
        if ProcessInfo.processInfo.arguments.contains("--release-launch-smoke-test") {
            return true
        }
        #if DEBUG
        return true
        #else
        return isInApplicationsFolder(originalBundleURL())
        #endif
    }()

    static func offerToMoveToApplicationsIfNeeded() {
        guard !shouldLaunchMainUI else { return }

        // Resolve Gatekeeper app translocation first: a quarantined copy in
        // /Applications launches from a randomized /private/var/.../AppTranslocation
        // path, which used to make this check fail (and re-prompt) forever.
        let sourceURL = originalBundleURL()

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Move Sorty to Applications"
        alert.informativeText =
            "To install updates and keep Finder features working reliably, Sorty must run from the Applications folder. macOS requires an administrator password to move the app into this protected folder; Sorty will replace any older copy, remove this copy from its current location, and reopen."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit Sorty")

        NSApplication.shared.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            quitImmediately()
            return
        }
        moveAndRelaunch(from: sourceURL)
    }

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.path
        if path.hasPrefix(applicationsPath + "/") { return true }
        let userApplicationsPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .path
        return path.hasPrefix(userApplicationsPath + "/")
    }

    /// Returns the app's real on-disk location, resolving Gatekeeper app
    /// translocation back to the original path when necessary.
    private static func originalBundleURL() -> URL {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard bundleURL.path.contains("/AppTranslocation/") else { return bundleURL }

        guard
            let handle = dlopen(
                "/System/Library/Frameworks/Security.framework/Security",
                RTLD_LAZY
            )
        else {
            return bundleURL
        }
        defer { dlclose(handle) }

        typealias CreateOriginalPath = @convention(c) (
            CFURL,
            UnsafeMutablePointer<Unmanaged<CFError>?>?
        ) -> Unmanaged<CFURL>?
        guard let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else {
            return bundleURL
        }
        let createOriginalPath = unsafeBitCast(symbol, to: CreateOriginalPath.self)
        guard let original = createOriginalPath(bundleURL as CFURL, nil)?.takeRetainedValue() else {
            return bundleURL
        }
        return (original as URL).resolvingSymlinksInPath()
    }

    private static func moveAndRelaunch(from sourceURL: URL) {
        let destinationURL = URL(fileURLWithPath: applicationsPath, isDirectory: true)
            .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
        // Move instead of copying so the downloaded app is not left behind,
        // then strip quarantine so the installed app launches without
        // Gatekeeper translocation (which would re-trigger this prompt).
        let script = """
        set sourcePath to \(appleScriptString(sourceURL.path))
        set destinationPath to \(appleScriptString(destinationURL.path))
        do shell script "/bin/rm -rf " & quoted form of destinationPath & " && /bin/mv " & quoted form of sourcePath & " " & quoted form of destinationPath & " && (/usr/bin/xattr -dr com.apple.quarantine " & quoted form of destinationPath & " || /usr/bin/true)" with administrator privileges
        """

        var error: NSDictionary?
        guard NSAppleScript(source: script)?.executeAndReturnError(&error) != nil else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Sorty couldn’t be moved"
            alert.informativeText = error?[NSAppleScript.errorMessage] as? String
                ?? "Move Sorty to Applications in Finder, then reopen it."
            alert.runModal()
            quitImmediately()
            return
        }

        relaunch(at: destinationURL)
        quitImmediately()
    }

    /// Waits for this instance to exit, then opens the moved copy. Opening
    /// while the old instance is still running would just re-activate it.
    private static func relaunch(at destinationURL: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let quotedPath =
            "'" + destinationURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.1; done; "
                + "/usr/bin/open \(quotedPath)",
        ]
        try? process.run()
    }

    private static func quitImmediately() {
        SortyAppDelegate.forceQuit = true
        NSApplication.shared.terminate(nil)
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
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

        SortyUninstaller.discardLegacyRequest()

        configureUITestStateIfNeeded()
    }

    @SceneBuilder
    var body: some Scene {
        WindowGroup("Sorty", id: "main") {
            if ApplicationMover.shouldLaunchMainUI {
                mainWindowContent(launchRequest: .constant(nil))
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .defaultLaunchBehavior(.presented)

        WindowGroup(for: WindowLaunchRequest.self) { launchRequest in
            if ApplicationMover.shouldLaunchMainUI {
                mainWindowContent(launchRequest: launchRequest)
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .commands {
            SortyCommands()
        }

        MenuBarExtra(
            isInserted: Binding(
                get: {
                    ApplicationMover.shouldLaunchMainUI
                        && (showMenuBarExtra || keepInBackground)
                },
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
            .onAppear {
                appDelegate.scheduleRecoveryWindow {
                    AnyView(mainWindowContent(launchRequest: .constant(nil)))
                }
            }
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
            .onChange(of: watchedFoldersManager.activeFolderCount) { _, _ in
                widgetSyncManager.scheduleSync(
                    watchedFoldersManager: watchedFoldersManager,
                    storageLocationsManager: storageLocationsManager
                )
            }
            .onChange(of: storageLocationsManager.locations) { _, _ in
                widgetSyncManager.scheduleSync(
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

        AnalyticsManager.shared.startIfAuthorized(launchDuration: appDelegate.launchDuration)
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
                learningsManager: learningsManager,
                exclusionRules: exclusionRules
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
                "Finish setting up your provider before organizing files.",
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

        if let historySeed = env["XCUITEST_SEED_HISTORY_ENTRY"] {
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

            let seededEntries: [OrganizationHistoryEntry]
            if historySeed == "filter_set" {
                seededEntries = [
                    OrganizationHistoryEntry(
                        directoryPath: "/tmp/completed-manual",
                        filesOrganized: 4,
                        foldersCreated: 2,
                        status: .completed,
                        source: .manual
                    ),
                    OrganizationHistoryEntry(
                        directoryPath: "/tmp/failed-manual",
                        filesOrganized: 0,
                        foldersCreated: 0,
                        success: false,
                        status: .failed,
                        source: .manual
                    ),
                    OrganizationHistoryEntry(
                        directoryPath: "/tmp/skipped-manual",
                        filesOrganized: 0,
                        foldersCreated: 0,
                        success: false,
                        status: .skipped,
                        source: .manual
                    ),
                    OrganizationHistoryEntry(
                        directoryPath: "/tmp/cancelled-manual",
                        filesOrganized: 0,
                        foldersCreated: 0,
                        success: false,
                        status: .cancelled,
                        source: .manual
                    ),
                    OrganizationHistoryEntry(
                        directoryPath: "/tmp/completed-watched",
                        filesOrganized: 3,
                        foldersCreated: 1,
                        status: .completed,
                        source: .watchedFolder
                    ),
                ]
            } else {
                seededEntries = [
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
            }

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

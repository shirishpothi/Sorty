//
//  AppCommands.swift
//  Sorty
//
//  Comprehensive menu bar commands with keyboard shortcuts
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import AppKit

// MARK: - App Commands

public struct AppStateFocusedKey: FocusedValueKey {
    public typealias Value = AppState
}

public struct OrganizerFocusedKey: FocusedValueKey {
    public typealias Value = FolderOrganizer
}

public extension FocusedValues {
    var appState: AppState? {
        get { self[AppStateFocusedKey.self] }
        set { self[AppStateFocusedKey.self] = newValue }
    }

    var organizer: FolderOrganizer? {
        get { self[OrganizerFocusedKey.self] }
        set { self[OrganizerFocusedKey.self] = newValue }
    }
}

public struct SortyCommands: Commands {
    @FocusedValue(\.appState) private var appState

    private var sidebarItems: [SidebarNavigationItem] {
        SidebarNavigationItem.mainItems
    }

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sorty", systemImage: "info.circle") {
                appState?.showAbout()
            }
            .disabled(appState == nil)
            
            Button("Check for Updates...", systemImage: "arrow.triangle.2.circlepath") {
                appState?.checkForUpdatesInteractive()
            }
            .disabled(appState == nil)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...", systemImage: "gearshape") {
                appState?.openSettingsWindow()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(appState == nil)
        }

        // Replace default New/Open with custom commands
        CommandGroup(replacing: .newItem) {
            Button("New Session", systemImage: "plus.square") {
                appState?.resetSession()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(appState == nil)

            Button("Open Directory...", systemImage: "folder") {
                appState?.showDirectoryPicker = true
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(appState == nil)

            Divider()

            Button("Export Results...", systemImage: "square.and.arrow.up") {
                appState?.exportResults()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!(appState?.hasResults ?? false))
        }

        // Edit menu additions
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Select All Files", systemImage: "checkmark.circle") {
                appState?.selectAllFiles()
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(!(appState?.hasFiles ?? false))
        }

        // View menu - use CommandGroup to add to existing View menu, not create a new one
        CommandGroup(replacing: .sidebar) {
            Button((appState?.showingSidebar ?? true) ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left") {
                appState?.showingSidebar.toggle()
            }
            .keyboardShortcut("\\", modifiers: .command)
            .disabled(appState == nil)
        }
        
        // Navigation commands added to View menu
        CommandGroup(after: .sidebar) {
            Divider()
            
            // Main Views section
            Text("Navigation")
                .font(.caption)

            ForEach(Array(sidebarItems.prefix(9).enumerated()), id: \.element.id) { index, item in
                Button(item.title, systemImage: item.systemImage) {
                    appState?.currentView = item.view
                }
                .keyboardShortcut(Self.commandKeyEquivalent(for: index), modifiers: .command)
                .disabled(appState == nil)
            }
        }

        // Organize menu
        CommandMenu("Organize") {
            Button("Start Organization", systemImage: "play.circle") {
                appState?.startOrganization()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!(appState?.canStartOrganization ?? false))

            Button("Regenerate Organization", systemImage: "arrow.clockwise") {
                appState?.regenerateOrganization()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!(appState?.hasCurrentPlan ?? false))

            Divider()

            Button("Apply Changes", systemImage: "checkmark.circle.fill") {
                appState?.applyChanges()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!(appState?.canApply ?? false))

            Button("Preview Changes", systemImage: "eye") {
                appState?.previewChanges()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!(appState?.hasCurrentPlan ?? false))

            Divider()

            Button("Cancel", systemImage: "xmark.circle") {
                appState?.cancelOperation()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!(appState?.isOperationInProgress ?? false))
        }

        // Learnings menu
        CommandMenu("Learnings") {
            Button("Open Dashboard", systemImage: "chart.bar") {
                appState?.currentView = .learnings
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(appState == nil)
            
            Divider()
            
            Button("Start Honing Session", systemImage: "target") {
                appState?.startHoningSession()
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
            .disabled(appState == nil)
            
            Button("View Statistics", systemImage: "chart.pie") {
                appState?.showLearningsStats()
            }
            .disabled(appState == nil)
            
            Divider()
            
            Button("Pause Learning", systemImage: "pause.circle") {
                appState?.pauseLearning()
            }
            .disabled(appState == nil)
            
            Button("Export Learning Profile...", systemImage: "square.and.arrow.up") {
                appState?.exportLearningsProfile()
            }
            .disabled(appState == nil)
            
            Button("Import Learning Profile...", systemImage: "square.and.arrow.down") {
                appState?.importLearningsProfile()
            }
            .disabled(appState == nil)
        }

        // History menu
        CommandMenu("History") {
            Button("Open History", systemImage: "clock") {
                appState?.currentView = .history
            }
            .disabled(appState == nil)

            Divider()

            Button("Export History as CSV...", systemImage: "tablecells") {
                appState?.exportHistory(format: .csv)
            }
            .disabled(!(appState?.hasHistoryEntries ?? false))

            Button("Export History as JSON...", systemImage: "curlybraces") {
                appState?.exportHistory(format: .json)
            }
            .disabled(!(appState?.hasHistoryEntries ?? false))

            Button("Import History...", systemImage: "square.and.arrow.down") {
                appState?.importHistory()
            }
            .disabled(appState == nil)

            Divider()

            Button("Clear History...", systemImage: "trash") {
                appState?.clearHistoryWithConfirmation()
            }
            .disabled(!(appState?.hasHistoryEntries ?? false))
        }

        CommandGroup(replacing: .help) {
            Button("Accreditations", systemImage: "rosette") {
                appState?.showAccreditations(entryPoint: .help)
            }
                .keyboardShortcut("©", modifiers: .command)
                .disabled(appState == nil)

            Button("Internet Access Policy", systemImage: "network") {
                appState?.showInternetAccessPolicy()
            }
            .keyboardShortcut("🌐", modifiers: .command)
            .disabled(appState == nil)

            Divider()

            Button("Sorty Help", systemImage: "questionmark.circle") {
                appState?.showHelp()
            }
            .keyboardShortcut("?", modifiers: .command)
            .disabled(appState == nil)
            
            Link(destination: URL(string: "https://github.com/shirishpothi/Sorty/blob/main/HELP.md")!) { Label("Documentation", systemImage: "book") }
            
            Link(destination: URL(string: "https://github.com/shirishpothi/Sorty/issues")!) { Label("Report Issue", systemImage: "ladybug") }

            Link(destination: URL(string: "https://github.com/sponsors/shirishpothi")!) { Label("Support the Developer", systemImage: "heart") }
            
            Divider()
            
            Button("Restart Onboarding...", systemImage: "sparkles") {
                appState?.showOnboarding()
            }
            .disabled(appState == nil)
            
            Button("Delete All Usage Data...", systemImage: "trash") {
                appState?.requestDeleteUsageDataConfirmation()
            }
            .disabled(appState == nil)
            
            Divider()
            
            Link(destination: URL(string: "https://github.com/shirishpothi/Sorty")!) { Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right") }

            Button("Check for Updates...", systemImage: "arrow.triangle.2.circlepath") {
                appState?.checkForUpdatesInteractive()
            }
            .disabled(appState == nil)

            Divider()

            Button("Thank you for using Sorty", systemImage: "heart.fill") {
                appState?.showThanksForUsingSorty()
            }
            .keyboardShortcut("♥", modifiers: .command)
            .disabled(appState == nil)
        }
    }

    private static func commandKeyEquivalent(for index: Int) -> KeyEquivalent {
        KeyEquivalent(Character("\(index + 1)"))
    }
}

@MainActor
private final class HelpMenuHoverHapticsController: NSObject, NSMenuDelegate {
    private let center: NotificationCenter
    private let targetItemTitle = "Thank you for using Sorty"
    private var didFireForCurrentMenuOpen = false

    init(center: NotificationCenter = .default) {
        self.center = center
        super.init()

        installDelegateOnHelpMenuIfNeeded()

        center.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        center.addObserver(
            self,
            selector: #selector(handleMenuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
    }

    @objc private func handleDidBecomeActive() {
        installDelegateOnHelpMenuIfNeeded()
    }

    @objc private func handleMenuDidBeginTracking(_ notification: Notification) {
        guard
            let menu = notification.object as? NSMenu,
            menu.item(withTitle: targetItemTitle) != nil
        else { return }

        installDelegate(on: menu)
        didFireForCurrentMenuOpen = false
    }

    func menuWillOpen(_ menu: NSMenu) {
        didFireForCurrentMenuOpen = false
    }

    func menuDidClose(_ menu: NSMenu) {
        didFireForCurrentMenuOpen = false
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard item?.title == targetItemTitle else { return }
        guard didFireForCurrentMenuOpen == false else { return }

        didFireForCurrentMenuOpen = true
        HapticFeedbackManager.shared.selection()
    }

    private func installDelegateOnHelpMenuIfNeeded() {
        let mainMenu = NSApplication.shared.mainMenu
        guard let mainMenu else { return }

        for menu in allMenus(in: mainMenu) where menu.item(withTitle: targetItemTitle) != nil {
            installDelegate(on: menu)
        }
    }

    private func installDelegate(on menu: NSMenu) {
        if menu.delegate == nil || (menu.delegate as AnyObject?) === self {
            menu.delegate = self
        }
    }

    private func allMenus(in rootMenu: NSMenu) -> [NSMenu] {
        var menus: [NSMenu] = [rootMenu]
        for item in rootMenu.items {
            if let submenu = item.submenu {
                menus.append(contentsOf: allMenus(in: submenu))
            }
        }
        return menus
    }
}

// MARK: - App State

@MainActor
public class AppState: ObservableObject {
    public enum HistoryExportFormat {
        case csv
        case json

        var fileExtension: String {
            switch self {
            case .csv:
                return "csv"
            case .json:
                return "json"
            }
        }
    }

    private static let requiresSetupRepairKey = "requiresSetupRepair"
    private static let setupRepairMessageKey = "setupRepairMessage"
    private let userDefaults: UserDefaults
    private let sensitiveActionSecurityManager = SecurityManager.shared
    public let windowSessionID: UUID

    @Published public var currentView: AppView = .organize
    @Published public var showingSidebar: Bool = true
    @Published public var showDirectoryPicker: Bool = false
    public var hasPresentedReadyToOrganize = false
    @Published public var selectedDirectory: URL? {
        didSet {
            if let url = selectedDirectory {
                selectedDirectoryBookmark = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } else {
                selectedDirectoryBookmark = nil
            }
        }
    }
    /// Security-scoped bookmark for the selected directory, ensuring sandbox access persists.
    public private(set) var selectedDirectoryBookmark: Data?
    @Published public var updateManager: SparkleUpdateManager
    @Published public var selectedSettingsSection: SettingsCategory?
    @Published public var settingsFocusTarget: SettingsFocusTarget?
    @Published public var duplicateManager = DuplicateDetectionManager()
    @Published public var duplicateSettings = DuplicateSettingsManager()
    @Published public var duplicateSelectedDirectory: URL?
    @Published public var duplicateSelectedGroup: UnifiedDuplicateGroup?
    @Published public var workspaceHealthSelectedDirectory: URL?
    @Published public var workspaceHealthSelectedOpportunity: CleanupOpportunity?
    @Published public var workspaceHealthIsAnalyzing = false
    @Published public var workspaceHealthAnalysisStage: String?
    @Published public var workspaceHealthAnalysisError: String?
    @Published public var workspaceHealthAnalysisStartedAt: Date?
    @Published public var debugMode: Bool = false
    @Published public var lastOrganizedDirectory: URL?
    @Published public var navigatedFromSettings: Bool = false
    @Published public var showDeleteUsageDataConfirmation: Bool = false
    @Published public var pendingDuplicatesHandoff: DuplicatesHandoff?
    @Published public var highlightedWatchedFolderID: UUID?
    @Published public var pendingNotificationActionRequest: PendingNotificationActionRequest?
    @Published public var requiresSetupRepair: Bool {
        didSet {
            userDefaults.set(requiresSetupRepair, forKey: Self.requiresSetupRepairKey)
        }
    }
    @Published public var setupRepairMessage: String? {
        didSet {
            if let setupRepairMessage, !setupRepairMessage.isEmpty {
                userDefaults.set(setupRepairMessage, forKey: Self.setupRepairMessageKey)
            } else {
                userDefaults.removeObject(forKey: Self.setupRepairMessageKey)
            }
        }
    }
    
    /// Trigger update check with visible UI feedback.
    /// In debug builds this rebuilds and relaunches from source via `make now`.
    /// In release builds it uses Sparkle's native UI.
    public func checkForUpdatesInteractive() {
        #if DEBUG
        DevRebuilder.shared.rebuild()
        #else
        updateManager.checkForUpdates()
        #endif
    }
    
    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            userDefaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding")
        }
    }
    @Published public var shouldPresentSteeringPrompts = false

    // State derived from FolderOrganizer
    public weak var organizer: FolderOrganizer?
    public var calibrateAction: ((WatchedFolder) -> Void)?
    
    // Window controllers - retained to prevent use-after-free crashes
    // These MUST be retained to keep windows alive during animations
    private var aboutWindowController: NSWindowController?
    private var accreditationsWindowController: NSWindowController?
    private var internetAccessPolicyWindowController: NSWindowController?
    private var thanksWindowController: NSWindowController?
    private let helpMenuHoverHapticsController = HelpMenuHoverHapticsController()

    public enum AppView: Hashable, Sendable {
        case settings
        case organize
        case history
        case workspaceHealth
        case duplicates
        case exclusions
        case watchedFolders
        case learnings
        case storageLocations
    }

    public enum AccreditationsEntryPoint: Sendable {
        case about
        case help
    }

    public enum InternetAccessPolicyEntryPoint: Sendable {
        case about
        case appMenu
    }

    public struct DuplicatesHandoff: Equatable, Sendable {
        public let id: UUID
        public let directory: URL?
        public let filePaths: [String]
        public let autoStart: Bool

        public init(
            id: UUID = UUID(),
            directory: URL?,
            filePaths: [String] = [],
            autoStart: Bool
        ) {
            self.id = id
            self.directory = directory
            self.filePaths = filePaths
            self.autoStart = autoStart
        }
    }

    public struct PendingNotificationActionRequest: Identifiable, Equatable, Sendable {
        public enum Kind: String, Equatable, Sendable {
            case applyConfirmation
            case redoWithModelConfirmation
        }

        public let id: UUID
        public let kind: Kind
        public let folderPath: String?
        public let notificationType: String?

        public init(
            id: UUID = UUID(),
            kind: Kind,
            folderPath: String? = nil,
            notificationType: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.folderPath = folderPath
            self.notificationType = notificationType
        }
    }

    public init(
        windowSessionID: UUID = UUID(),
        updateManager: SparkleUpdateManager = SparkleUpdateManager(),
        userDefaults: UserDefaults = .standard
    ) {
        self.windowSessionID = windowSessionID
        self.updateManager = updateManager
        self.userDefaults = userDefaults

        // Detect fresh install vs in-app update
        // Fresh install: no previous version stored AND onboarding not completed
        // In-app update: previous version exists, so skip onboarding even if flag was reset
        let previousVersion = userDefaults.string(forKey: "lastLaunchedVersion")
        let onboardingCompleted = userDefaults.bool(forKey: "hasCompletedOnboarding")
        let requiresSetupRepair = userDefaults.bool(forKey: Self.requiresSetupRepairKey)
        let setupRepairMessage = userDefaults.string(forKey: Self.setupRepairMessageKey)
        let currentVersion = BuildInfo.version
        
        if previousVersion == nil {
            // First ever launch - show onboarding if not completed
            self.hasCompletedOnboarding = onboardingCompleted
        } else {
            // Returning user (update or re-launch) - skip onboarding
            // Even if hasCompletedOnboarding was somehow reset, don't show it
            self.hasCompletedOnboarding = true
        }
        self.requiresSetupRepair = requiresSetupRepair
        self.setupRepairMessage = setupRepairMessage
        
        // Always store current version for future launches
        userDefaults.set(currentVersion, forKey: "lastLaunchedVersion")
    }

    public var hasResults: Bool {
        organizer?.currentPlan != nil && organizer?.state == .completed
    }

    public var hasFiles: Bool {
        organizer?.currentPlan != nil
    }

    public var hasHistoryEntries: Bool {
        !(organizer?.history.entries.isEmpty ?? true)
    }

    public var canStartOrganization: Bool {
        selectedDirectory != nil && (organizer?.state == .idle || organizer?.state == .completed)
    }

    public var hasCurrentPlan: Bool {
        organizer?.currentPlan != nil
    }

    public var canApply: Bool {
        organizer?.state == .ready
    }

    public var isOperationInProgress: Bool {
        guard let state = organizer?.state else { return false }
        switch state {
        case .scanning, .organizing, .applying:
            return true
        default:
            return false
        }
    }

    /// Resolve the security-scoped bookmark for the selected directory.
    /// Returns a URL with active security scope, or falls back to the stored URL.
    public func resolveSelectedDirectoryWithAccess() -> URL? {
        if let bookmark = selectedDirectoryBookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = resolved.startAccessingSecurityScopedResource()
                if isStale {
                    selectedDirectoryBookmark = try? resolved.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
                return resolved
            }
        }
        return selectedDirectory
    }

    public func resetSession() {
        selectedDirectory = nil
        organizer?.reset()
    }

    public func handoffToDuplicates(
        directory: URL?,
        filePaths: [String] = [],
        autoStart: Bool = true
    ) {
        let normalizedDirectory = directory?.standardizedFileURL ?? selectedDirectory?.standardizedFileURL
        let normalizedFilePaths = Self.normalizedFilePaths(filePaths)
        if let normalizedDirectory {
            selectedDirectory = normalizedDirectory
        }
        pendingDuplicatesHandoff = DuplicatesHandoff(
            directory: normalizedDirectory,
            filePaths: normalizedFilePaths,
            autoStart: autoStart
        )
        withAnimation(.pageTransition) {
            currentView = .duplicates
        }
    }

    public func handoffToDuplicates(
        forFilePaths filePaths: [String],
        preferredDirectory: URL? = nil,
        autoStart: Bool = true
    ) {
        let normalizedFilePaths = Self.normalizedFilePaths(filePaths)
        let pathDerivedDirectory = Self.commonParentDirectory(forFilePaths: normalizedFilePaths)
        let targetDirectory = preferredDirectory?.standardizedFileURL ?? pathDerivedDirectory
        handoffToDuplicates(
            directory: targetDirectory,
            filePaths: normalizedFilePaths,
            autoStart: autoStart
        )
    }

    private static func commonParentDirectory(forFilePaths filePaths: [String]) -> URL? {
        let directories = filePaths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.deletingLastPathComponent() }

        guard let firstDirectory = directories.first else { return nil }
        var commonComponents = firstDirectory.pathComponents

        for directory in directories.dropFirst() {
            let components = directory.pathComponents
            var index = 0
            while index < commonComponents.count && index < components.count && commonComponents[index] == components[index] {
                index += 1
            }
            commonComponents = Array(commonComponents.prefix(index))
            if commonComponents.isEmpty {
                break
            }
        }

        guard !commonComponents.isEmpty else { return firstDirectory }
        let commonPath = NSString.path(withComponents: commonComponents)
        return URL(fileURLWithPath: commonPath, isDirectory: true).standardizedFileURL
    }

    private static func normalizedFilePaths(_ filePaths: [String]) -> [String] {
        var seenPaths: Set<String> = []
        var normalizedPaths: [String] = []

        for path in filePaths {
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            if seenPaths.insert(normalizedPath).inserted {
                normalizedPaths.append(normalizedPath)
            }
        }

        return normalizedPaths
    }

    public func queueNotificationActionRequest(
        _ kind: PendingNotificationActionRequest.Kind,
        folderPath: String? = nil,
        notificationType: String? = nil
    ) {
        pendingNotificationActionRequest = PendingNotificationActionRequest(
            kind: kind,
            folderPath: folderPath,
            notificationType: notificationType
        )
    }

    public func clearNotificationActionRequest(id: UUID? = nil) {
        guard let id else {
            pendingNotificationActionRequest = nil
            return
        }

        if pendingNotificationActionRequest?.id == id {
            pendingNotificationActionRequest = nil
        }
    }
    
    /// Show the onboarding flow again (for revisiting setup)
    public func showOnboarding() {
        withAnimation(.spring()) {
            clearSetupRepairState()
            hasCompletedOnboarding = false
        }
    }

    public func openProviderSettingsForRepair() {
        openSettingsWindow(section: .provider)
        navigatedFromSettings = false
    }

    public func openSettingsWindow(
        section: SettingsCategory? = nil,
        focusTarget: SettingsFocusTarget? = nil
    ) {
        selectedSettingsSection = section
        settingsFocusTarget = focusTarget
        withAnimation(.pageTransition) {
            currentView = .settings
        }
    }

    public func startSetupRepair(message: String, navigateToSettings: Bool = false) {
        requiresSetupRepair = true
        setupRepairMessage = message
        if navigateToSettings {
            openProviderSettingsForRepair()
        }
    }

    public func clearSetupRepairState() {
        requiresSetupRepair = false
        setupRepairMessage = nil
    }
    
    public func exportResults() {
        guard let plan = organizer?.currentPlan else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json, .html]
        panel.nameFieldStringValue = "organization_results_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-"))"
        panel.message = "Export Organization Results"
        panel.canSelectHiddenExtension = true
        
        // Add accessory view for format selection
        let formatPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 30), pullsDown: false)
        formatPopup.addItems(withTitles: ["CSV (Spreadsheet)", "JSON (Machine-readable)", "HTML (Report)"])
        panel.accessoryView = formatPopup

        if panel.runModal() == .OK, let url = panel.url {
            let selectedFormat = formatPopup.indexOfSelectedItem
            
            do {
                let content: String
                var finalURL = url
                
                switch selectedFormat {
                case 0: // CSV
                    content = generateCSV(from: plan)
                    if !finalURL.pathExtension.lowercased().contains("csv") {
                        finalURL = finalURL.deletingPathExtension().appendingPathExtension("csv")
                    }
                case 1: // JSON
                    content = generateJSON(from: plan)
                    if !finalURL.pathExtension.lowercased().contains("json") {
                        finalURL = finalURL.deletingPathExtension().appendingPathExtension("json")
                    }
                case 2: // HTML
                    content = generateHTML(from: plan)
                    if !finalURL.pathExtension.lowercased().contains("html") {
                        finalURL = finalURL.deletingPathExtension().appendingPathExtension("html")
                    }
                default:
                    content = generateCSV(from: plan)
                }
                
                try content.write(to: finalURL, atomically: true, encoding: .utf8)
                HapticFeedbackManager.shared.success()
                
                // Open the exported file
                NSWorkspace.shared.open(finalURL)
            } catch {
                DebugLogger.log("Failed to export results: \(error)")
                HapticFeedbackManager.shared.error()
            }
        }
    }

    public func exportHistory(format: HistoryExportFormat) {
        guard let history = organizer?.history.entries, !history.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
        panel.nameFieldStringValue = "sorty-history.\(format.fileExtension)"
        panel.title = "Export History"
        panel.message = "Choose where to save your history export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content: String
            switch format {
            case .csv:
                content = generateHistoryCSV(from: history)
            case .json:
                content = try generateHistoryJSON(from: history)
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            HapticFeedbackManager.shared.success()
        } catch {
            DebugLogger.log("Failed to export history: \(error.localizedDescription)")
            HapticFeedbackManager.shared.error()
            presentHistoryAlert(
                title: "Export Failed",
                message: "Sorty couldn't export history. Please try again."
            )
        }
    }

    public func importHistory() {
        guard let historyStore = organizer?.history else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = "Import History"
        panel.message = "Choose a history JSON file exported from Sorty"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let importedEntries = try decodeHistoryImportEntries(from: data)
            guard !importedEntries.isEmpty else {
                throw HistoryImportError.noEntries
            }

            let importedCount = historyStore.importEntries(importedEntries)
            currentView = .history
            HapticFeedbackManager.shared.success()

            presentHistoryAlert(
                title: "Import Complete",
                message: "Imported \(importedCount) history entr\(importedCount == 1 ? "y" : "ies")."
            )
        } catch {
            DebugLogger.log("Failed to import history: \(error.localizedDescription)")
            HapticFeedbackManager.shared.error()

            presentHistoryAlert(
                title: "Import Failed",
                message: (error as? LocalizedError)?.errorDescription ?? "Sorty couldn't import this file."
            )
        }
    }

    public func clearHistoryWithConfirmation() {
        guard let historyStore = organizer?.history, !historyStore.entries.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear History?"
        alert.informativeText = "This will permanently remove all history entries. This cannot be undone."
        alert.addButton(withTitle: "Clear All History")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            historyStore.clearHistory()
            currentView = .history
            HapticFeedbackManager.shared.success()
        }
    }

    private func generateCSV(from plan: OrganizationPlan) -> String {
        var csv = "Original File,Original Path,New Location,Reasoning,Tags\n"

        func processSuggestion(_ suggestion: FolderSuggestion, parentPath: String) {
            let folderPath = parentPath + "/" + suggestion.folderName
            for file in suggestion.files {
                let originalName = file.displayName
                let originalPath = file.path
                let destination = folderPath + "/" + (suggestion.renameMapping(for: file)?.suggestedName ?? originalName)
                let reasoning = suggestion.reasoning
                let tags = suggestion.semanticTags.joined(separator: "; ")
                
                csv += "\(csvEscape(originalName)),\"\(csvEscape(originalPath))\",\(csvEscape(destination)),\(csvEscape(reasoning)),\"\(csvEscape(tags))\"\n"
            }
            for sub in suggestion.subfolders {
                processSuggestion(sub, parentPath: folderPath)
            }
        }

        for suggestion in plan.suggestions {
            processSuggestion(suggestion, parentPath: "")
        }

        return csv
    }
    
    private func generateJSON(from plan: OrganizationPlan) -> String {
        struct ExportEntry: Codable {
            let originalFile: String
            let originalPath: String
            let destinationPath: String
            let reasoning: String
            let tags: [String]
        }
        
        struct ExportData: Codable {
            let exportDate: String
            let totalFiles: Int
            let totalFolders: Int
            let entries: [ExportEntry]
        }
        
        var entries: [ExportEntry] = []
        var folderCount = 0
        
        func processSuggestion(_ suggestion: FolderSuggestion, parentPath: String) {
            let folderPath = parentPath + "/" + suggestion.folderName
            folderCount += 1
            
            for file in suggestion.files {
                let destination = folderPath + "/" + (suggestion.renameMapping(for: file)?.suggestedName ?? file.displayName)
                entries.append(ExportEntry(
                    originalFile: file.displayName,
                    originalPath: file.path,
                    destinationPath: destination,
                    reasoning: suggestion.reasoning,
                    tags: suggestion.semanticTags
                ))
            }
            for sub in suggestion.subfolders {
                processSuggestion(sub, parentPath: folderPath)
            }
        }
        
        for suggestion in plan.suggestions {
            processSuggestion(suggestion, parentPath: "")
        }
        
        let exportData = ExportData(
            exportDate: ISO8601DateFormatter().string(from: Date()),
            totalFiles: entries.count,
            totalFolders: folderCount,
            entries: entries
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let jsonData = try? encoder.encode(exportData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{\"error\": \"Failed to encode\"}"
    }
    
    private func generateHTML(from plan: OrganizationPlan) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Sorty Export</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; background: #f5f5f7; }
                h1 { color: #1d1d1f; margin-bottom: 10px; }
                .meta { color: #6e6e73; margin-bottom: 30px; }
                .folder { background: white; border-radius: 12px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .folder-name { font-size: 18px; font-weight: 600; color: #1d1d1f; margin-bottom: 8px; }
                .reasoning { color: #6e6e73; font-size: 14px; margin-bottom: 12px; font-style: italic; }
                .files { font-size: 14px; }
                .file { padding: 8px 0; border-bottom: 1px solid #e5e5e5; display: flex; justify-content: space-between; }
                .file:last-child { border-bottom: none; }
                .file-name { font-weight: 500; }
                .file-path { color: #6e6e73; font-size: 12px; }
                .tag { background: #007aff; color: white; padding: 2px 8px; border-radius: 10px; font-size: 11px; margin-right: 4px; }
            </style>
        </head>
        <body>
            <h1>📁 Sorty Export</h1>
            <p class="meta">Generated on \(Date().formatted(date: .long, time: .shortened))</p>
        """
        
        func processSuggestion(_ suggestion: FolderSuggestion, parentPath: String, depth: Int) {
            let folderPath = parentPath.isEmpty ? suggestion.folderName : parentPath + "/" + suggestion.folderName
            
            html += """
            <div class="folder" style="margin-left: \(depth * 20)px;">
                <div class="folder-name">📂 \(suggestion.folderName)</div>
                <div class="reasoning">\(suggestion.reasoning)</div>
            """
            
            if !suggestion.semanticTags.isEmpty {
                html += "<div class=\"tags\">"
                for tag in suggestion.semanticTags {
                    html += "<span class=\"tag\">\(tag)</span>"
                }
                html += "</div>"
            }
            
            if !suggestion.files.isEmpty {
                html += "<div class=\"files\">"
                for file in suggestion.files {
                    let newName = suggestion.renameMapping(for: file)?.suggestedName
                    html += """
                    <div class="file">
                        <div>
                            <span class="file-name">\(htmlEscape(file.displayName))</span>
                            \(newName != nil ? "<span style='color:#6e6e73;'> → \(htmlEscape(newName!))</span>" : "")
                        </div>
                        <span class="file-path">\(htmlEscape(file.path))</span>
                    </div>
                    """
                }
                html += "</div>"
            }
            
            html += "</div>"
            
            for sub in suggestion.subfolders {
                processSuggestion(sub, parentPath: folderPath, depth: depth + 1)
            }
        }
        
        for suggestion in plan.suggestions {
            processSuggestion(suggestion, parentPath: "", depth: 0)
        }
        
        html += """
        </body>
        </html>
        """
        
        return html
    }

    public func selectAllFiles() {
        // Select all implementation handled by focused view via responder chain
    }

    private enum HistoryImportError: LocalizedError {
        case unsupportedFormat
        case noEntries

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "This file isn't a supported Sorty history export."
            case .noEntries:
                return "This history file does not contain any entries."
            }
        }
    }

    private struct HistoryArchiveExport: Codable {
        let schemaVersion: Int
        let exportedAt: String
        let entries: [OrganizationHistoryEntry]
    }

    private struct LegacyHistoryExportEntry: Decodable {
        let id: String?
        let timestamp: String?
        let folderPath: String
        let status: String?
        let source: String?
        let filesOrganized: Int
        let foldersCreated: Int
        let errorMessage: String?

        func toHistoryEntry(dateFormatter: ISO8601DateFormatter) -> OrganizationHistoryEntry {
            let parsedID = id.flatMap(UUID.init(uuidString:)) ?? UUID()
            let parsedTimestamp = timestamp.flatMap { dateFormatter.date(from: $0) } ?? Date()
            let parsedStatus = status.flatMap(OrganizationStatus.init(rawValue:)) ?? .completed
            let parsedSource = source.flatMap(OrganizationEntrySource.init(rawValue:)) ?? .manual

            return OrganizationHistoryEntry(
                id: parsedID,
                timestamp: parsedTimestamp,
                directoryPath: folderPath,
                filesOrganized: filesOrganized,
                foldersCreated: foldersCreated,
                success: parsedStatus == .completed,
                status: parsedStatus,
                errorMessage: errorMessage,
                source: parsedSource
            )
        }
    }

    private func presentHistoryAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func decodeHistoryImportEntries(from data: Data) throws -> [OrganizationHistoryEntry] {
        let decoder = JSONDecoder()

        if let archive = try? decoder.decode(HistoryArchiveExport.self, from: data) {
            return archive.entries
        }

        if let entries = try? decoder.decode([OrganizationHistoryEntry].self, from: data) {
            return entries
        }

        if let legacyEntries = try? decoder.decode([LegacyHistoryExportEntry].self, from: data) {
            let dateFormatter = ISO8601DateFormatter()
            return legacyEntries.map { $0.toHistoryEntry(dateFormatter: dateFormatter) }
        }

        throw HistoryImportError.unsupportedFormat
    }

    private func generateHistoryCSV(from entries: [OrganizationHistoryEntry]) -> String {
        var lines: [String] = []
        lines.append("ID,Timestamp,Folder Path,Folder Name,Status,Source,Files Organized,Folders Created,Error Message")

        let dateFormatter = ISO8601DateFormatter()

        for entry in entries {
            let folderName = URL(fileURLWithPath: entry.directoryPath).lastPathComponent
            let row = [
                entry.id.uuidString,
                dateFormatter.string(from: entry.timestamp),
                csvEscape(entry.directoryPath),
                csvEscape(folderName),
                entry.status.rawValue,
                entry.source.rawValue,
                String(entry.filesOrganized),
                String(entry.foldersCreated),
                csvEscape(entry.errorMessage ?? "")
            ].joined(separator: ",")
            lines.append(row)
        }

        return lines.joined(separator: "\n")
    }

    private func generateHistoryJSON(from entries: [OrganizationHistoryEntry]) throws -> String {
        let payload = HistoryArchiveExport(
            schemaVersion: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            entries: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    public func startOrganization() {
        guard let organizer = organizer, let directory = selectedDirectory else { return }
        Task {
            try? await organizer.organize(directory: directory)
        }
    }

    public func regenerateOrganization() {
        guard let organizer = organizer else { return }
        Task {
            try? await organizer.regeneratePreview()
        }
    }

    public func applyChanges() {
        guard let organizer = organizer, let directory = selectedDirectory else { return }
        Task {
            try? await organizer.apply(at: directory)
        }
    }

    public func previewChanges() {
        // Navigation to preview is handled by view logic
    }

    public func cancelOperation() {
        organizer?.reset()
    }

    public func showHelp() {
        openSettingsWindow(section: .help)
        navigatedFromSettings = true
        HapticFeedbackManager.shared.selection()
    }
    
    // MARK: - Learnings Actions

    private func postWindowScopedNotification(
        _ name: Notification.Name,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: MainWindowRouter.scopedUserInfo(userInfo, targetSessionID: windowSessionID)
        )
    }
    
    public func startHoningSession() {
        currentView = .learnings
        postWindowScopedNotification(.startHoningSession)
    }
    
    public func showLearningsStats() {
        currentView = .learnings
        postWindowScopedNotification(.showLearningsStats)
    }
    
    public func pauseLearning() {
        authenticateForSensitiveAction(
            reason: "Authenticate to pause learning and review your learnings controls."
        ) { [weak self] in
            self?.postWindowScopedNotification(.pauseLearning)
        }
    }
    
    public func exportLearningsProfile() {
        authenticateForSensitiveAction(
            reason: "Authenticate to export your learnings profile."
        ) { [weak self] in
            self?.currentView = .learnings
            self?.postWindowScopedNotification(.exportLearningsProfile)
        }
    }
    
    public func importLearningsProfile() {
        authenticateForSensitiveAction(
            reason: "Authenticate to import a learnings profile."
        ) { [weak self] in
            self?.currentView = .learnings
            self?.postWindowScopedNotification(.importLearningsProfile)
        }
    }

    public func requestDeleteUsageDataConfirmation() {
        authenticateForSensitiveAction(
            reason: "Authenticate to delete all Sorty usage data."
        ) { [weak self] in
            self?.showDeleteUsageDataConfirmation = true
        }
    }
    
    public func deleteUsageData() {
        var deletionFailures: [Error] = []

        if !KeychainManager.deleteAll() {
            deletionFailures.append(UsageDataDeletionError.keychain)
        }
        GitHubCopilotAuthManager.shared.signOut()

        deletionFailures.append(contentsOf: SortyUsageDataEraser.erase())

        DuplicateRestorationManager.shared.clearAllData()
        SortyWidgetSnapshotStore.clear()

        organizer?.reset()
        duplicateManager.clearResults()
        selectedDirectory = nil
        duplicateSelectedDirectory = nil
        duplicateSelectedGroup = nil
        workspaceHealthSelectedDirectory = nil
        workspaceHealthSelectedOpportunity = nil
        workspaceHealthIsAnalyzing = false
        workspaceHealthAnalysisStage = nil
        workspaceHealthAnalysisError = nil
        workspaceHealthAnalysisStartedAt = nil
        pendingDuplicatesHandoff = nil
        highlightedWatchedFolderID = nil
        pendingNotificationActionRequest = nil
        lastOrganizedDirectory = nil
        settingsFocusTarget = nil
        requiresSetupRepair = false
        setupRepairMessage = nil

        withAnimation(.spring()) {
            hasCompletedOnboarding = false
        }

        postWindowScopedNotification(.clearLearningsData)
        NotificationCenter.default.post(name: .clearAllUsageData, object: nil)

        userDefaults.dictionaryRepresentation().keys.forEach(userDefaults.removeObject(forKey:))
        UserDefaults(suiteName: SortyWidgetSnapshotStore.appGroupIdentifier)?
            .removePersistentDomain(forName: SortyWidgetSnapshotStore.appGroupIdentifier)

        if let failure = deletionFailures.first {
            HapticFeedbackManager.shared.error()
            NotificationManager.shared.showError(
                message: "Some Sorty data could not be deleted: \(failure.localizedDescription)",
                isCritical: true
            )
        } else {
            HapticFeedbackManager.shared.success()
        }
    }

    private enum UsageDataDeletionError: LocalizedError {
        case keychain

        var errorDescription: String? {
            "Sorty could not remove all Keychain data."
        }
    }

    public func authenticateForSensitiveAction(
        reason: String,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        if !FeatureFlags.sensitiveActionAuthenticationEnabled {
            onSuccess()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let didAuthenticate = await sensitiveActionSecurityManager.authenticateForSensitiveAction(reason: reason)
            guard didAuthenticate else {
                HapticFeedbackManager.shared.error()
                return
            }
            onSuccess()
        }
    }
    
    public func showAbout() {
        // If window already exists and is visible, just bring it to front
        if let existingWindow = aboutWindowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new About window
        let aboutView = AboutView(openAccreditations: { [weak self] in
            self?.showAccreditations(entryPoint: .about)
        })
        let hostingView = NSHostingView(rootView: aboutView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "About Sorty"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        if #available(macOS 26.0, *) {
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        window.center()
        
        // Retain the window controller to prevent deallocation
        aboutWindowController = NSWindowController(window: window)
        aboutWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func showInternetAccessPolicy(entryPoint: InternetAccessPolicyEntryPoint = .appMenu) {
        let policyView = InternetAccessPolicyView(
            showBackButton: entryPoint == .about,
            onBack: entryPoint == .about ? { [weak self] in
                self?.internetAccessPolicyWindowController?.close()
                self?.showAbout()
                HapticFeedbackManager.shared.selection()
            } : nil
        )
        let hostingView = NSHostingView(rootView: policyView)

        if let existingWindow = internetAccessPolicyWindowController?.window {
            existingWindow.contentView = hostingView
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            HapticFeedbackManager.shared.selection()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Internet Access Policy"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        if #available(macOS 26.0, *) {
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        window.center()

        internetAccessPolicyWindowController = NSWindowController(window: window)
        internetAccessPolicyWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        HapticFeedbackManager.shared.selection()
    }

    public func showAccreditations(entryPoint: AccreditationsEntryPoint = .help) {
        let accreditationsView = AccreditationsView(
            showBackButton: entryPoint == .about,
            onBack: entryPoint == .about ? { [weak self] in
                self?.accreditationsWindowController?.close()
                self?.showAbout()
                HapticFeedbackManager.shared.selection()
            } : nil
        )
        let hostingView = NSHostingView(rootView: accreditationsView)

        if let existingWindow = accreditationsWindowController?.window {
            existingWindow.contentView = hostingView
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            HapticFeedbackManager.shared.selection()
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Sorty Accreditations"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        if #available(macOS 26.0, *) {
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        window.center()

        accreditationsWindowController = NSWindowController(window: window)
        accreditationsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        HapticFeedbackManager.shared.selection()
    }

    public func showThanksForUsingSorty() {
        // If window already exists and is visible, just bring it to front
        if let existingWindow = thanksWindowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            HapticFeedbackManager.shared.selection()
            return
        }

        let thanksView = ThanksForUsingSortyView()
        let hostingView = NSHostingView(rootView: thanksView)

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: ThanksForUsingSortyView.preferredWindowWidth,
                height: ThanksForUsingSortyView.preferredWindowHeight
            ),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Thanks for Using Sorty"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        if #available(macOS 26.0, *) {
            window.backgroundColor = .clear
            window.isOpaque = false
        }
        window.center()

        thanksWindowController = NSWindowController(window: window)
        thanksWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        HapticFeedbackManager.shared.selection()
    }
    
    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    private func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

struct SortyUsageDataEraser {
    struct Locations {
        let applicationSupportDirectory: URL?
        let cachesDirectory: URL?
        let temporaryDirectory: URL
        let appGroupContainer: URL?
    }

    static func erase(
        fileManager: FileManager = .default,
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.sorty.app",
        locations: Locations? = nil
    ) -> [Error] {
        let locations = locations ?? defaultLocations(fileManager: fileManager)
        var failures: [Error] = []

        let removableRoots = ownedRoots(
            bundleIdentifier: bundleIdentifier,
            locations: locations
        )
        for root in removableRoots where fileManager.fileExists(atPath: root.path) {
            do {
                try fileManager.removeItem(at: root)
            } catch {
                failures.append(error)
            }
        }

        if let appGroupContainer = locations.appGroupContainer {
            failures.append(contentsOf: removeContents(
                of: appGroupContainer,
                fileManager: fileManager
            ))
        }

        failures.append(contentsOf: removeOwnedTemporaryItems(
            from: locations.temporaryDirectory,
            fileManager: fileManager
        ))
        return failures
    }

    static func ownedRoots(
        bundleIdentifier: String,
        locations: Locations
    ) -> [URL] {
        var roots: [URL] = []

        if let applicationSupportDirectory = locations.applicationSupportDirectory {
            roots.append(applicationSupportDirectory.appendingPathComponent("Sorty", isDirectory: true))
            roots.append(applicationSupportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true))
        }

        if let cachesDirectory = locations.cachesDirectory {
            roots.append(cachesDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true))
            roots.append(cachesDirectory.appendingPathComponent("Sorty", isDirectory: true))
        }

        var seenPaths = Set<String>()
        return roots.filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }

    private static func defaultLocations(fileManager: FileManager) -> Locations {
        Locations(
            applicationSupportDirectory: fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first,
            cachesDirectory: fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first,
            temporaryDirectory: fileManager.temporaryDirectory,
            appGroupContainer: fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: SortyWidgetSnapshotStore.appGroupIdentifier
            )
        )
    }

    private static func removeContents(
        of directory: URL,
        fileManager: FileManager
    ) -> [Error] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        do {
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).compactMap { item in
                do {
                    try fileManager.removeItem(at: item)
                    return nil
                } catch {
                    return error
                }
            }
        } catch {
            return [error]
        }
    }

    private static func removeOwnedTemporaryItems(
        from directory: URL,
        fileManager: FileManager
    ) -> [Error] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let prefixes = ["sorty-", "Sorty_", "SortyNotificationIcon-"]
        do {
            let items = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { item in
                prefixes.contains { item.lastPathComponent.hasPrefix($0) }
            }

            return items.compactMap { item in
                do {
                    try fileManager.removeItem(at: item)
                    return nil
                } catch {
                    return error
                }
            }
        } catch {
            return [error]
        }
    }
}

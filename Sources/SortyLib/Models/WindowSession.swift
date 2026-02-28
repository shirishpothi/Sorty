import Foundation
import AppKit
import Combine

@MainActor
public final class WindowSession: ObservableObject {
    @Published public var appState = AppState()
    @Published public var organizer = FolderOrganizer()
    @Published public var healthManager = WorkspaceHealthManager()
    @Published public var batchManager = BatchOrganizationManager()

    private var didConfigure = false

    public init() {}

    public func configureIfNeeded(
        settingsViewModel: SettingsViewModel,
        personaManager: PersonaManager,
        customPersonaStore: CustomPersonaStore,
        exclusionRules: ExclusionRulesManager,
        storageLocationsManager: StorageLocationsManager,
        learningsManager: LearningsManager,
        automationManager: AutomationManager,
        calibrateAction: ((WatchedFolder) -> Void)?
    ) async {
        guard !didConfigure else { return }
        didConfigure = true

        organizer.exclusionRules = exclusionRules
        organizer.personaManager = personaManager
        organizer.customPersonaStore = customPersonaStore
        organizer.storageLocationsManager = storageLocationsManager
        organizer.learningsManager = learningsManager
        organizer.automationManager = automationManager

        appState.organizer = organizer
        appState.calibrateAction = calibrateAction

        await applyConfiguration(settingsViewModel.config, learningsManager: learningsManager)
        appState.updateManager.checkOnLaunchIfNeeded()
    }

    public func applyConfiguration(_ config: AIConfig, learningsManager: LearningsManager) async {
        try? await organizer.configure(with: config)
        learningsManager.configure(with: config)
    }

    public func handle(destination: DeeplinkDestination,
                settingsViewModel: SettingsViewModel,
                personaManager: PersonaManager,
                customPersonaStore: CustomPersonaStore,
                watchedFoldersManager: WatchedFoldersManager,
                exclusionRules: ExclusionRulesManager,
                storageLocationsManager: StorageLocationsManager,
                learningsManager: LearningsManager) {
        switch destination {
        case .organize(let path, let personaId, _, let autostart):
            if let path {
                appState.selectedDirectory = URL(fileURLWithPath: path)
            }
            if let personaId {
                if let persona = PersonaType(rawValue: personaId) {
                    personaManager.selectPersona(persona)
                } else {
                    personaManager.selectCustomPersona(personaId)
                }
            }
            // Reset organizer to idle so user sees ReadyToOrganize page
            if !autostart {
                appState.organizer?.reset()
            }
            appState.currentView = .organize
            if autostart {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let directory = appState.selectedDirectory {
                        try? await appState.organizer?.organize(directory: directory)
                    }
                }
            }

        case .duplicates(let path, _):
            if let path {
                appState.selectedDirectory = URL(fileURLWithPath: path)
            }
            appState.currentView = .duplicates

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
            appState.currentView = .settings
            Task { @MainActor in
                // Avoid mutating @Published navigation state during the same render transaction.
                await Task.yield()
                applySettingsDestination(section: section)
            }

        case .help:
            appState.showHelp()

        case .open(let path):
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
            if let path {
                var isDirectory = ObjCBool(false)
                if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    appState.selectedDirectory = URL(fileURLWithPath: path)
                }
            }

        case .history:
            appState.currentView = .history

        case .health:
            appState.currentView = .workspaceHealth

        case .persona(let action, let prompt, let generate):
            appState.currentView = .settings
            if action == "create" || generate {
                if generate, let prompt {
                    Task<Void, Never> {
                        let generator = PersonaGenerator()
                        do {
                            let result = try await generator.generatePersona(from: prompt, config: settingsViewModel.config)
                            await MainActor.run {
                                let newPersona = CustomPersona(
                                    name: result.name,
                                    icon: result.icon,
                                    description: prompt,
                                    promptModifier: result.prompt
                                )
                                customPersonaStore.addPersona(newPersona)
                                personaManager.selectCustomPersona(newPersona.id)
                            }
                        } catch {
                            print("Failed to generate persona: \(error)")
                        }
                    }
                }
            }

        case .watched(let action, let path):
            appState.currentView = .watchedFolders
            if action == "add", let path {
                let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
                let highlightedID: UUID

                if let existingFolder = watchedFoldersManager.folders.first(where: { $0.path == normalizedPath }) {
                    highlightedID = existingFolder.id
                } else {
                    let folder = watchedFolderFromDeeplinkPath(path)
                    watchedFoldersManager.addFolder(folder)
                    highlightedID = folder.id
                }

                appState.highlightedWatchedFolderID = highlightedID
                // Clear highlight after animation
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if appState.highlightedWatchedFolderID == highlightedID {
                        appState.highlightedWatchedFolderID = nil
                    }
                }
            }

        case .rules(let action, _, let pattern):
            appState.currentView = .exclusions
            if action == "add", let pattern {
                let rule = ExclusionRule(type: .pathContains, pattern: pattern)
                exclusionRules.addRule(rule)
            }

        case .exclusions(let action, let pattern):
            appState.currentView = .exclusions
            if action == "add", let pattern {
                let rule = ExclusionRule(type: .pathContains, pattern: pattern)
                exclusionRules.addRule(rule)
            }

        case .scan(let path):
            if let path {
                appState.selectedDirectory = URL(fileURLWithPath: path)
            }
            appState.currentView = .workspaceHealth

        case .storage(let action, let path):
            appState.currentView = .storageLocations
            if action == "add", let path {
                let url = URL(fileURLWithPath: path)
                try? storageLocationsManager.addLocation(url: url)
            }
        }
    }

    private func watchedFolderFromDeeplinkPath(_ path: String) -> WatchedFolder {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var watchedFolder = WatchedFolder(path: url.path)

        guard FileManager.default.fileExists(atPath: url.path) else {
            watchedFolder.accessStatus = .lost
            return watchedFolder
        }

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        if let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            watchedFolder.bookmarkData = bookmarkData
            watchedFolder.accessStatus = .valid
        } else {
            watchedFolder.accessStatus = .lost
        }

        return watchedFolder
    }

    private func applySettingsDestination(section: String?) {
        guard let section = section?.lowercased() else {
            appState.selectedSettingsSection = nil
            appState.settingsFocusTarget = nil
            return
        }

        switch section {
        case "watched", "watched-folders", "folders", "exclusions", "rules":
            appState.selectedSettingsSection = .rules
            appState.settingsFocusTarget = nil
        case "storage", "storage-locations":
            appState.selectedSettingsSection = .rules
            appState.settingsFocusTarget = .rulesStorageLocations
        case "health", "workspace-health":
            appState.selectedSettingsSection = .rules
            appState.settingsFocusTarget = nil
        default:
            let category = SettingsCategory.allCases.first {
                $0.rawValue.lowercased().contains(section) ||
                    String(describing: $0).lowercased() == section
            }
            appState.selectedSettingsSection = category
            appState.settingsFocusTarget = nil
        }
    }
}

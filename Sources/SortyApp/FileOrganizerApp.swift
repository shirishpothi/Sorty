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

@main
struct SortyApp: App {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var appState = AppState()
    @StateObject private var personaManager = PersonaManager()
    @StateObject private var customPersonaStore = CustomPersonaStore()
    @StateObject private var watchedFoldersManager = WatchedFoldersManager()
    @StateObject private var organizer = FolderOrganizer()
    @StateObject private var exclusionRules = ExclusionRulesManager()
    @StateObject private var extensionListener = ExtensionListener()
    @StateObject private var deeplinkHandler = DeeplinkHandler.shared
    @StateObject private var learningsManager = LearningsManager() // Promoted to App State
    
    @State private var coordinator: AppCoordinator?
    
    var body: some Scene {
        WindowGroup {
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
                .onAppear {
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
                    appState.organizer = organizer
                    
                    appState.calibrateAction = { folder in
                        coordinator?.calibrateFolder(folder)
                    }
                    
                    // Initial configuration of organizer
                    // Initial configuration of organizer
                    Task {
                        try? await organizer.configure(with: settingsViewModel.config)
                        learningsManager.configure(with: settingsViewModel.config)
                    }
                }
                .onChange(of: settingsViewModel.config) { _, newConfig in
                    Task {
                        try? await organizer.configure(with: newConfig)
                        learningsManager.configure(with: newConfig)
                    }
                }
                .onChange(of: watchedFoldersManager.folders) { oldValue, newValue in
                    coordinator?.syncWatchedFolders()
                }
                .onOpenURL { url in
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
                                Task {
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
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    // Trigger duplicate scan logic if accessible
                                    // appState.duplicatesManager.scan(directory) -> if available
                                }
                            }
                            
                        case .learnings:
                            appState.currentView = .learnings
                            
                        case .settings: // Removed section param support as ViewModel doesn't support it
                            appState.currentView = .settings
                            
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
                                    Task {
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
                            appState.currentView = .settings
                            // settingsViewModel.selectedSection = .watchedFolders // Not supported
                            if action == "add", let path = path {
                                watchedFoldersManager.addFolder(WatchedFolder(path: path))
                            }
                            
                        case .rules(let action, _, let pattern):
                            appState.currentView = .settings
                            if action == "add", let pattern = pattern {
                                let rule = ExclusionRule(type: .pathContains, pattern: pattern)
                                exclusionRules.addRule(rule)
                            }
                        }
                        deeplinkHandler.clearPending()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .importLearningsProfile)) { _ in
                    appState.currentView = .learnings
                    // Small delay to ensure view transition happens before showing picker
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        learningsManager.showingImportPicker = true
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .commands {
            SortyCommands(appState: appState)
        }
    }
}

//
//  FileOrganizerApp.swift
//  FileOrganizer
//
//  Created on macOS
//

import SwiftUI
#if canImport(FileOrganizerLib)
import FileOrganizerLib
#endif

@main
struct FileOrganizerApp: App {
    @StateObject private var settingsViewModel = SettingsViewModel()
    @StateObject private var appState = AppState()
    @StateObject private var personaManager = PersonaManager()
    @StateObject private var watchedFoldersManager = WatchedFoldersManager()
    @StateObject private var organizer = FolderOrganizer()
    @StateObject private var exclusionRules = ExclusionRulesManager()
    @StateObject private var extensionListener = ExtensionListener()
    @StateObject private var deeplinkHandler = DeeplinkHandler.shared
    
    @State private var coordinator: AppCoordinator?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsViewModel)
                .environmentObject(appState)
                .environmentObject(personaManager)
                .environmentObject(watchedFoldersManager)
                .environmentObject(organizer)
                .environmentObject(exclusionRules)
                .environmentObject(extensionListener)
                .environmentObject(deeplinkHandler)
                .onAppear {
                    if coordinator == nil {
                        coordinator = AppCoordinator(organizer: organizer, watchedFoldersManager: watchedFoldersManager)
                    }
                    
                    // Setup organizer
                    organizer.exclusionRules = exclusionRules
                    organizer.personaManager = personaManager
                    appState.organizer = organizer
                    
                    // Setup callback for calibration
                    appState.calibrateAction = { folder in
                        coordinator?.calibrateFolder(folder)
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
                        case .organize(let path):
                            if let path = path {
                                appState.selectedDirectory = URL(fileURLWithPath: path)
                            }
                            appState.currentView = .organize
                        case .duplicates(let path):
                            if let path = path {
                                appState.selectedDirectory = URL(fileURLWithPath: path)
                            }
                            appState.currentView = .duplicates
                        case .learnings:
                            appState.currentView = .learnings
                        case .settings:
                            appState.currentView = .settings
                        case .help:
                            appState.showHelp()
                        case .history:
                            appState.currentView = .history
                        case .health:
                            appState.currentView = .workspaceHealth
                        }
                        deeplinkHandler.clearPending()
                    }
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1100, height: 750)
        .commands {
            FileOrganizerCommands(appState: appState)
        }
    }
}

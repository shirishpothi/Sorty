//
//  FileOrganizerActionExtension.swift
//  FileOrganizer
//
//  Finder Action Extension
//

import Cocoa
import FinderSync

class FileOrganizerActionExtension: FIFinderSync {
    
    override init() {
        super.init()
        
        // Set the directories to monitor
        let finderSync = FIFinderSyncController.default()
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: .skipHiddenVolumes) {
            finderSync.directoryURLs = Set(mountedVolumes)
        }
        
        // Monitor the user's home directory
        if let homeURL = FileManager.default.homeDirectoryForCurrentUser as URL? {
            finderSync.directoryURLs.insert(homeURL)
        }
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu()
        
        if menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer {
            let menuItem = NSMenuItem(
                title: "Organize with AI...",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menu.addItem(menuItem)
        }
        
        return menu
    }
    
    @objc func organizeAction(_ sender: AnyObject?) {
        guard let items = FIFinderSyncController.default().selectedItemURLs(), !items.isEmpty else {
            return
        }
        
        // Get the first selected directory
        let selectedURL = items.first!
        
        // Send directory to main app via App Groups
        ExtensionCommunication.sendDirectoryToApp(selectedURL)
        
        // Launch or activate the main app
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.fileorganizer.app") {
            NSWorkspace.shared.open([selectedURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            // Fallback: try to open the app bundle
            // Fallback: try to open the app bundle
            let bundleURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            NSWorkspace.shared.open(bundleURL)
        }
    }
}




//
//  SortyActionExtension.swift
//  Sorty
//
//  Finder Sync Extension (requires code signing with proper entitlements)
//  For unsigned builds, use the Quick Action from ExtensionCommunication instead
//

import Cocoa
import FinderSync

class SortyActionExtension: FIFinderSync {
    
    override init() {
        super.init()
        
        let finderSync = FIFinderSyncController.default()
        
        // Monitor all mounted volumes
        if let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil,
            options: .skipHiddenVolumes
        ) {
            finderSync.directoryURLs = Set(mountedVolumes)
        }
        
        // Always include user's home directory
        finderSync.directoryURLs.insert(FileManager.default.homeDirectoryForCurrentUser)
    }
    
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu()
        
        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForContainer:
            // Main organize action
            let organizeItem = NSMenuItem(
                title: "Organize with Sorty",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
            organizeItem.target = self
            menu.addItem(organizeItem)
            
        case .toolbarItemMenu:
            let organizeItem = NSMenuItem(
                title: "Organize Folder",
                action: #selector(organizeAction(_:)),
                keyEquivalent: ""
            )
            organizeItem.target = self
            menu.addItem(organizeItem)
            
        case .contextualMenuForSidebar:
            break
            
        @unknown default:
            break
        }
        
        return menu
    }
    
    @objc func organizeAction(_ sender: AnyObject?) {
        // Get selected items or container directory
        let selectedURLs = FIFinderSyncController.default().selectedItemURLs() ?? []
        let targetURL = FIFinderSyncController.default().targetedURL()
        
        // Determine what to organize
        let urlToOrganize: URL?
        if let firstSelected = selectedURLs.first {
            urlToOrganize = firstSelected
        } else {
            urlToOrganize = targetURL
        }
        
        guard let url = urlToOrganize else { return }
        
        // Use URL scheme to open the app with the selected path
        // This is more reliable than App Groups for unsigned apps
        if let organizeURL = ExtensionCommunication.urlForOrganizing(path: url.path) {
            NSWorkspace.shared.open(organizeURL)
        } else {
            // Fallback: use distributed notification
            ExtensionCommunication.sendDirectoryToApp(url)
            
            // Try to launch the app
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.sorty.app") {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)
            }
        }
    }
}




//
//  ExtensionCommunication.swift
//  FileOrganizer
//
//  App-to-extension communication
//

import Foundation
import AppKit

public struct ExtensionCommunication {
    private static let appGroupIdentifier = "group.com.fileorganizer.app"
    private static let directoryKey = "selectedDirectory"
    public static let notificationName = Notification.Name("FileOrganizerDirectorySelected")
    
    public static func sendDirectoryToApp(_ directoryURL: URL) {
        // Store directory path in shared UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(directoryURL.path, forKey: directoryKey)
            sharedDefaults.synchronize()
        }
        
        // Post distributed notification
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.post(
            name: notificationName,
            object: nil,
            userInfo: ["path": directoryURL.path]
        )
    }
    
    public static func receiveFromExtension() -> URL? {
        // Check shared UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let path = sharedDefaults.string(forKey: directoryKey) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
    
    public static func setupNotificationObserver(handler: @escaping @Sendable @MainActor (URL) -> Void) {
        let notificationCenter = DistributedNotificationCenter.default()
        notificationCenter.addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let path = userInfo["path"] as? String {
                let url = URL(fileURLWithPath: path)
                Task { @MainActor in
                    handler(url)
                }
            }
        }
    }
}




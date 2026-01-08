//
//  WatchedFolder.swift
//  Sorty
//
//  Model for folders being monitored for automatic organization
//

import Foundation
import Combine

public struct WatchedFolder: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var path: String
    public var name: String
    public var isEnabled: Bool
    public var autoOrganize: Bool
    public var lastTriggered: Date?
    public var triggerDelay: TimeInterval // Seconds to wait after file changes before organizing
    public var customPrompt: String?
    public var temperature: Double?
    
    public init(
        id: UUID = UUID(),
        path: String,
        name: String? = nil,
        isEnabled: Bool = true,
        autoOrganize: Bool = true,
        lastTriggered: Date? = nil,
        triggerDelay: TimeInterval = 5.0,
        customPrompt: String? = nil,
        temperature: Double? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.isEnabled = isEnabled
        self.autoOrganize = autoOrganize
        self.lastTriggered = lastTriggered
        self.triggerDelay = triggerDelay
        self.customPrompt = customPrompt
        self.temperature = temperature
    }
    
    public var url: URL {
        URL(fileURLWithPath: path)
    }
    
    public var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// Manager for persisting watched folders
@MainActor
public class WatchedFoldersManager: ObservableObject {
    @Published public private(set) var folders: [WatchedFolder] = []
    private let userDefaults = UserDefaults.standard
    private let storageKey = "watchedFolders"
    
    public init() {
        loadFolders()
    }
    
    public func addFolder(_ folder: WatchedFolder) {
        // Avoid duplicates
        guard !folders.contains(where: { $0.path == folder.path }) else { return }
        folders.append(folder)
        saveFolders()
    }
    
    public func removeFolder(_ folder: WatchedFolder) {
        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }
    
    public func updateFolder(_ folder: WatchedFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
            saveFolders()
        }
    }
    
    public func toggleEnabled(for folder: WatchedFolder) {
        if var updated = folders.first(where: { $0.id == folder.id }) {
            updated.isEnabled.toggle()
            updateFolder(updated)
        }
    }
    
    public func toggleAutoOrganize(for folder: WatchedFolder) {
        if var updated = folders.first(where: { $0.id == folder.id }) {
            updated.autoOrganize.toggle()
            updateFolder(updated)
        }
    }
    
    public func markTriggered(_ folder: WatchedFolder) {
        if var updated = folders.first(where: { $0.id == folder.id }) {
            updated.lastTriggered = Date()
            updateFolder(updated)
        }
    }
    
    private func loadFolders() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
            folders = decoded
        }
    }
    
    private func saveFolders() {
        if let encoded = try? JSONEncoder().encode(folders) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}

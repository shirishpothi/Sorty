//
//  AutomationManager.swift
//  Sorty
//
//  Manager for automation permissions and Finder integration
//  Handles Automation (Finder control) permissions
//

import Foundation
import AppKit
import Combine

/// Manager for automation features and permissions
/// Injected via @EnvironmentObject at app root
@MainActor
public final class AutomationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public private(set) var automationStatus: PermissionStatus = .unknown
    @Published public private(set) var selectedFinderItems: [URL] = []
    @Published public private(set) var hasValidFinderSelection: Bool = false
    
    // MARK: - Private Properties
    
    private var selectionCheckTimer: Timer?
    private let selectionCheckInterval: TimeInterval = 2.0
    
    // MARK: - UserDefaults Keys
    
    private let enableSelectionMonitoringKey = "automation.enableSelectionMonitoring"
    private let autoSelectOrganizedFoldersKey = "automation.autoSelectOrganizedFolders"
    
    // MARK: - Settings
    
    @Published public var enableSelectionMonitoring: Bool {
        didSet {
            UserDefaults.standard.set(enableSelectionMonitoring, forKey: enableSelectionMonitoringKey)
            if enableSelectionMonitoring {
                startSelectionMonitoring()
            } else {
                stopSelectionMonitoring()
            }
        }
    }
    
    @Published public var autoSelectOrganizedFolders: Bool {
        didSet {
            UserDefaults.standard.set(autoSelectOrganizedFolders, forKey: autoSelectOrganizedFoldersKey)
        }
    }
    
    // MARK: - Initialization
    
    public init() {
        // Load settings from UserDefaults
        self.enableSelectionMonitoring = UserDefaults.standard.bool(forKey: enableSelectionMonitoringKey)
        self.autoSelectOrganizedFolders = UserDefaults.standard.bool(forKey: autoSelectOrganizedFoldersKey)
        
        // Default autoSelectOrganizedFolders to true if not set
        if !UserDefaults.standard.bool(forKey: "automation.settingsInitialized") {
            self.autoSelectOrganizedFolders = true
            UserDefaults.standard.set(true, forKey: "automation.settingsInitialized")
        }
        
        // Check permissions
        checkPermissions()
        
        // Setup monitoring if enabled
        if enableSelectionMonitoring {
            startSelectionMonitoring()
        }
        
        // Listen for app activation to refresh status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    // MARK: - Permission Management
    
    /// Check Automation permission status
    public func checkPermissions() {
        automationStatus = FinderAutomation.checkAutomationPermission()
    }
    
    /// Open System Settings to Automation permissions
    public func openAutomationSettings() {
        FinderAutomation.openAutomationSettings()
    }
    
    // MARK: - Finder Selection
    
    /// Start monitoring Finder selection periodically
    public func startSelectionMonitoring() {
        guard automationStatus == .granted else {
            DebugLogger.log("Cannot start selection monitoring: Automation permission not granted")
            return
        }
        
        stopSelectionMonitoring()
        
        // Check immediately
        updateFinderSelection()
        
        // Setup timer for periodic checks
        selectionCheckTimer = Timer.scheduledTimer(
            withTimeInterval: selectionCheckInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFinderSelection()
            }
        }
    }
    
    /// Stop monitoring Finder selection
    public func stopSelectionMonitoring() {
        selectionCheckTimer?.invalidate()
        selectionCheckTimer = nil
        selectedFinderItems = []
        hasValidFinderSelection = false
    }
    
    /// Manually update the Finder selection
    public func updateFinderSelection() {
        guard automationStatus == .granted else { return }
        
        if let selection = FinderAutomation.getSelectedFiles() {
            selectedFinderItems = selection
            hasValidFinderSelection = !selection.isEmpty
        } else {
            selectedFinderItems = []
            hasValidFinderSelection = false
        }
    }
    
    /// Get the path of the frontmost Finder window
    public func getFrontmostFinderWindow() -> URL? {
        guard automationStatus == .granted else { return nil }
        return FinderAutomation.getFrontmostFinderWindowPath()
    }
    
    /// Check if current selection is a valid organization target
    public func canOrganizeSelection() -> Bool {
        return hasValidFinderSelection && automationStatus == .granted
    }
    
    // MARK: - Post-Organization Actions
    
    /// Select organized folders in Finder after organization completes
    public func selectOrganizedFolders(folderURLs: [URL]) {
        guard automationStatus == .granted else { return }
        guard autoSelectOrganizedFolders else { return }
        guard !folderURLs.isEmpty else { return }
        
        FinderAutomation.selectInFinder(urls: folderURLs, reveal: true)
        DebugLogger.log("Selected \(folderURLs.count) organized folders in Finder")
    }
    
    /// Reveal a specific file or folder in Finder
    public func revealInFinder(url: URL) {
        guard automationStatus == .granted else { return }
        FinderAutomation.revealInFinder(url: url)
    }
    
    /// Open a folder in a new Finder window
    public func openInNewFinderWindow(url: URL) {
        guard automationStatus == .granted else { return }
        FinderAutomation.openInNewFinderWindow(url: url)
    }
    
    /// Refresh Finder windows showing the organized path
    public func refreshFinder(at url: URL) {
        guard automationStatus == .granted else { return }
        FinderAutomation.refreshFinder(at: url)
    }
    
    // MARK: - Notification Handler
    
    @objc private func appDidBecomeActive() {
        // Refresh permission status when app becomes active
        checkPermissions()
        
        // Refresh selection if monitoring is enabled
        if enableSelectionMonitoring && automationStatus == .granted {
            updateFinderSelection()
        }
    }
}

// MARK: - PermissionStatus Extension

extension PermissionStatus: Equatable {
    public static func == (lhs: PermissionStatus, rhs: PermissionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.granted, .granted), (.denied, .denied), (.unknown, .unknown):
            return true
        default:
            return false
        }
    }
}

extension PermissionStatus: CustomStringConvertible {
    public var description: String {
        switch self {
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .unknown:
            return "Unknown"
        }
    }
}

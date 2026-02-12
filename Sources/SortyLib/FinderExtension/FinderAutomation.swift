//
//  FinderAutomation.swift
//  Sorty
//
//  Service for advanced Finder automation using AppleScript
//  Requires Automation permission for Finder control
//  Requires Accessibility permission for global hotkeys
//

import Foundation
import AppKit
import Carbon
import ApplicationServices

/// Service for automating Finder interactions
/// Uses AppleScript which requires Automation permission
@MainActor
public final class FinderAutomation {
    
    private static var checksEnabled = false
    private static var isAppReady = false
    
    public static func enableAutomationChecks() {
        checksEnabled = true
    }
    
    public static func markAppReady() {
        isAppReady = true
    }
    
    // MARK: - Permission Status
    
    /// Check if the app has Automation permission (can control Finder via AppleScript)
    public static func checkAutomationPermission(prompt: Bool = false) -> PermissionStatus {
        guard checksEnabled, isAppReady else { return .unknown }
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        
        let status = AEDeterminePermissionToAutomateTarget(
            targetDesc.aeDesc,
            AEEventClass(kCoreEventClass),
            AEEventID(kAEOpenApplication),
            prompt
        )
        
        switch status {
        case noErr:
            return .granted
        case -1743:
            // errAEEventNotPermitted: Not authorized to send Apple events to Finder
            return .denied
        case -1744:
            // Would require user consent (no decision yet)
            return .unknown
        case -600:
            // procNotFound: Finder not running
            return .unknown
        default:
            DebugLogger.log("Unexpected automation permission status: \(status)")
            return .unknown
        }
    }
    
    /// Open System Settings to the Automation permission pane
    public static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open System Settings to the Accessibility permission pane
    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Finder Selection
    
    /// Get the currently selected files in the frontmost Finder window
    /// Returns nil if no Finder window is open or no selection
    public static func getSelectedFiles() -> [URL]? {
        guard checksEnabled else { return nil }
        guard checkAutomationPermission() == .granted else {
            return nil
        }
        
        let scriptSource = """
        tell application "Finder"
            try
                set selectedItems to selection
                set filePaths to {}
                repeat with anItem in selectedItems
                    set end of filePaths to POSIX path of (anItem as alias)
                end repeat
                return filePaths as string
            on error
                return ""
            end try
        end tell
        """
        
        guard let script = NSAppleScript(source: scriptSource) else {
            return nil
        }
        
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            DebugLogger.log("AppleScript error getting selection: \(error)")
            return nil
        }
        
        guard let resultString = result.stringValue, !resultString.isEmpty else {
            return nil
        }
        
        // Parse the result - it's a comma-separated or newline-separated list
        let paths = resultString.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        return paths.map { URL(fileURLWithPath: $0) }
    }
    
    /// Get the path of the frontmost Finder window
    /// Returns nil if no Finder window is open
    public static func getFrontmostFinderWindowPath() -> URL? {
        guard checksEnabled else { return nil }
        guard checkAutomationPermission() == .granted else {
            return nil
        }
        
        let scriptSource = """
        tell application "Finder"
            try
                set targetFolder to target of front window as alias
                return POSIX path of targetFolder
            on error
                return ""
            end try
        end tell
        """
        
        guard let script = NSAppleScript(source: scriptSource) else {
            return nil
        }
        
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            DebugLogger.log("AppleScript error getting front window: \(error)")
            return nil
        }
        
        guard let path = result.stringValue, !path.isEmpty else {
            return nil
        }
        
        return URL(fileURLWithPath: path)
    }
    
    /// Get the frontmost Finder window's folder path for organizing
    public static func organizeCurrentFinderFolder() -> URL? {
        return getFrontmostFinderWindowPath()
    }
    
    /// Check if there's a valid Finder selection we can use for organization
    public static func canOrganizeSelection() -> Bool {
        guard let selection = getSelectedFiles() else { return false }
        return !selection.isEmpty
    }
    
    // MARK: - Finder Selection Control
    
    /// Select items in the frontmost Finder window
    /// - Parameters:
    ///   - urls: URLs of items to select
    ///   - reveal: Whether to reveal the items (scroll to them)
    public static func selectInFinder(urls: [URL], reveal: Bool = true) {
        guard checksEnabled else { return }
        guard !urls.isEmpty else { return }
        guard checkAutomationPermission() == .granted else { return }
        
        let pathsString = urls.map { $0.path }.joined(separator: "\n")
        
        let scriptSource = """
        tell application "Finder"
            try
                set filePaths to paragraphs of "\(pathsString)"
                set itemsToSelect to {}
                
                repeat with filePath in filePaths
                    if filePath is not "" then
                        try
                            set theItem to POSIX file filePath as alias
                            set end of itemsToSelect to theItem
                        end try
                    end if
                end repeat
                
                if length of itemsToSelect > 0 then
                    select itemsToSelect
                    \(reveal ? "reveal itemsToSelect" : "")
                end if
            on error errMsg
                return "Error: " & errMsg
            end try
        end tell
        """
        
        guard let script = NSAppleScript(source: scriptSource) else {
            return
        }
        
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            DebugLogger.log("AppleScript error selecting in Finder: \(error)")
        }
    }
    
    /// Reveal a single file or folder in Finder
    public static func revealInFinder(url: URL) {
        selectInFinder(urls: [url], reveal: true)
    }
    
    /// Open a folder in a new Finder window
    public static func openInNewFinderWindow(url: URL) {
        guard checksEnabled else { return }
        guard checkAutomationPermission() == .granted else { return }
        
        let scriptSource = """
        tell application "Finder"
            try
                set targetFolder to POSIX file "\(url.path)" as alias
                make new Finder window to targetFolder
                activate
            on error errMsg
                return "Error: " & errMsg
            end try
        end tell
        """
        
        guard let script = NSAppleScript(source: scriptSource) else {
            return
        }
        
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            DebugLogger.log("AppleScript error opening Finder window: \(error)")
        }
    }
    
    // MARK: - Global Hotkeys (Disabled - requires complex C API integration)
    
    /// NOTE: Global hotkey registration requires Carbon APIs which have limitations
    /// with Swift closures. This feature is disabled for now.
    /// 
    /// To implement global hotkeys properly, you would need to:
    /// 1. Use a global singleton to store the handler
    /// 2. Use a C function pointer that calls back to Swift via the singleton
    /// 3. Or use a library like MASShortcut or HotKey
    ///
    /// For now, users can organize via:
    /// - The "Organize Finder Selection" button in the app
    /// - The Finder Quick Action (right-click menu)
    /// - The URL scheme (sorty://organize?path=...)
    
    /// Check if Accessibility permission is granted
    @MainActor
    public static func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        // Use the known constant string value to avoid Swift 6 concurrency issues with kAXTrustedCheckOptionPrompt
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
    
    // MARK: - Finder Refresh
    
    /// Refresh all Finder windows showing the specified path
    public static func refreshFinder(at url: URL) {
        guard checksEnabled, checkAutomationPermission() == .granted else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        
        let scriptSource = """
        tell application "Finder"
            try
                set theFolder to POSIX file "\(url.path)" as alias
                repeat with theWindow in (every window)
                    try
                        if (target of theWindow as alias) is theFolder then
                            update theWindow
                        end if
                    end try
                end repeat
            on error
                -- Ignore errors
            end try
        end tell
        """
        
        guard let script = NSAppleScript(source: scriptSource) else {
            return
        }
        
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        
        if let error = errorInfo {
            DebugLogger.log("AppleScript error refreshing Finder: \(error)")
        }
    }
}

// MARK: - Supporting Types

public enum PermissionStatus {
    case granted
    case denied
    case unknown
    
    public var isGranted: Bool {
        return self == .granted
    }
}

// MARK: - String Extension for FourCharCode

extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        let chars = Array(self.utf8)
        if chars.count >= 4 {
            result = FourCharCode(chars[0]) << 24 |
                     FourCharCode(chars[1]) << 16 |
                     FourCharCode(chars[2]) << 8 |
                     FourCharCode(chars[3])
        }
        return result
    }
}

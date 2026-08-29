//
//  FinderAutomation.swift
//  Sorty
//
//  Service for advanced Finder automation using AppleScript
//  Requires Automation permission for Finder control
//

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import Permiso

/// Service for automating Finder interactions
/// Uses AppleScript which requires Automation permission
@MainActor
public final class FinderAutomation {
    
    private static var checksEnabled = false
    nonisolated static let permissionEventClass = AEEventClass(kAECoreSuite)
    nonisolated static let permissionEventID = AEEventID(kAEGetData)
    
    public static func enableAutomationChecks() {
        checksEnabled = true
    }
    
    // MARK: - Permission Status
    
    /// Check if the app has Automation permission (can control Finder via AppleScript)
    public static func checkAutomationPermission() -> PermissionStatus {
        guard canCheckPermission(checksEnabled: checksEnabled) else { return .unknown }

        return determineAutomationPermission(prompt: false)
    }

    /// Requests Finder Automation with macOS's native Allow / Don't Allow alert.
    public static func requestAutomationPermission() async -> PermissionStatus {
        guard canCheckPermission(checksEnabled: checksEnabled) else { return .unknown }

        let scriptSource = """
        tell application "Finder"
            return name of startup disk
        end tell
        """

        guard let script = NSAppleScript(source: scriptSource) else {
            return determineAutomationPermission(prompt: true)
        }

        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return .granted }
        let errorCode = errorInfo[NSAppleScript.errorNumber] as? Int
        switch errorCode {
        case -1743:
            return .denied
        case -600:
            return .unknown
        default:
            DebugLogger.log("Unexpected Finder automation request error: \(errorInfo)")
            return determineAutomationPermission(prompt: false)
        }
    }

    nonisolated private static func determineAutomationPermission(
        prompt: Bool
    ) -> PermissionStatus {
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        
        let status = AEDeterminePermissionToAutomateTarget(
            targetDesc.aeDesc,
            permissionEventClass,
            permissionEventID,
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

    nonisolated static func canCheckPermission(
        checksEnabled: Bool
    ) -> Bool {
        checksEnabled
    }
    
    /// Open System Settings to the Automation permission pane
    public static func openAutomationSettings(
        sourceFrameInScreen: CGRect? = nil,
        onMissingApp: @escaping () -> Void = {}
    ) {
        Task { @MainActor in
            PermisoAssistant.shared.present(
                panel: .automation,
                sourceFrameInScreen: sourceFrameInScreen,
                onMissingApp: onMissingApp
            )
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

    /// Selects an item in Finder and opens its contextual menu.
    ///
    /// macOS only exposes this UI automation path when Sorty has Accessibility
    /// permission. Callers should reveal the item themselves if this returns false.
    public static func openContextMenu(for url: URL) async -> Bool {
        guard hasAccessibilityPermission() else {
            DebugLogger.log("Finder context menu unavailable: Accessibility permission is not granted")
            return false
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        var selectedFrame: CGRect?
        for _ in 0..<10 {
            guard !Task.isCancelled else { return false }
            if let item = selectedFinderItemElement(matching: url.lastPathComponent),
               let itemFrame = frame(of: item) {
                selectedFrame = itemFrame
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard let selectedFrame else {
            DebugLogger.log("Finder context menu unavailable: selected item was not found")
            return false
        }

        return postContextClick(at: CGPoint(x: selectedFrame.midX, y: selectedFrame.midY))
    }

    private static func hasAccessibilityPermission() -> Bool {
        guard !AXIsProcessTrusted() else { return true }

        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
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

    private static func selectedFinderItemElement(matching itemName: String) -> AXUIElement? {
        guard let finderApplication = finderApplicationElement(),
              let focusedWindow = axElement(from: copyAttribute(
                  from: finderApplication,
                  attribute: kAXFocusedWindowAttribute as CFString
              )) else {
            return nil
        }

        var selectedItems: [AXUIElement] = []
        collectSelectedItems(in: focusedWindow, depth: 8, into: &selectedItems)

        return selectedItems
            .filter { finderItem($0, matches: itemName) }
            .max { left, right in
                (frame(of: left)?.minX ?? 0) < (frame(of: right)?.minX ?? 0)
            }
    }

    private static func finderApplicationElement() -> AXUIElement? {
        guard let finderProcess = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first(where: { !$0.isTerminated }) else {
            return nil
        }
        return AXUIElementCreateApplication(finderProcess.processIdentifier)
    }

    private static func collectSelectedItems(
        in element: AXUIElement,
        depth: Int,
        into selectedItems: inout [AXUIElement]
    ) {
        guard depth >= 0 else { return }

        selectedItems.append(contentsOf: elements(from: copyAttribute(
            from: element,
            attribute: kAXSelectedChildrenAttribute as CFString
        )).filter { frame(of: $0) != nil })

        if boolAttribute(from: element, attribute: kAXSelectedAttribute as CFString),
           frame(of: element) != nil {
            selectedItems.append(element)
        }

        guard depth > 0 else { return }
        let children = elements(from: copyAttribute(from: element, attribute: kAXChildrenAttribute as CFString))
        for child in children {
            collectSelectedItems(in: child, depth: depth - 1, into: &selectedItems)
        }
    }

    private static func finderItem(_ element: AXUIElement, matches itemName: String) -> Bool {
        guard !itemName.isEmpty else { return false }
        return accessibilityText(in: element, depth: 2).contains { text in
            text.localizedCaseInsensitiveCompare(itemName) == .orderedSame
                || text.localizedCaseInsensitiveContains(itemName)
        }
    }

    private static func accessibilityText(in element: AXUIElement, depth: Int) -> [String] {
        let ownText = [
            stringAttribute(from: element, attribute: kAXTitleAttribute as CFString),
            stringAttribute(from: element, attribute: kAXDescriptionAttribute as CFString),
            stringAttribute(from: element, attribute: kAXValueAttribute as CFString)
        ].compactMap { $0 }

        guard depth > 0 else { return ownText }
        let childText = elements(from: copyAttribute(
            from: element,
            attribute: kAXChildrenAttribute as CFString
        )).flatMap { accessibilityText(in: $0, depth: depth - 1) }
        return ownText + childText
    }

    private static func postContextClick(at point: CGPoint) -> Bool {
        guard let mouseDown = CGEvent(
                  mouseEventSource: nil,
                  mouseType: .rightMouseDown,
                  mouseCursorPosition: point,
                  mouseButton: .right
              ),
              let mouseUp = CGEvent(
                  mouseEventSource: nil,
                  mouseType: .rightMouseUp,
                  mouseCursorPosition: point,
                  mouseButton: .right
              ) else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        return true
    }

    private static func copyAttribute(from element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func axElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return value as! AXUIElement
    }

    private static func elements(from value: CFTypeRef?) -> [AXUIElement] {
        guard let value else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func stringAttribute(from element: AXUIElement, attribute: CFString) -> String? {
        copyAttribute(from: element, attribute: attribute) as? String
    }

    private static func boolAttribute(from element: AXUIElement, attribute: CFString) -> Bool {
        (copyAttribute(from: element, attribute: attribute) as? Bool) ?? false
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(from: element, attribute: kAXPositionAttribute as CFString),
              let sizeValue = copyAttribute(from: element, attribute: kAXSizeAttribute as CFString),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue

        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &dimensions) else {
            return nil
        }
        return CGRect(origin: origin, size: dimensions)
    }
}

// MARK: - Supporting Types

public enum PermissionStatus: Sendable {
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

import Foundation
import AppKit
import Combine
import Permiso

@MainActor
public class GlobalShortcutManager: ObservableObject {
    @Published public var isRegistered = false
    @Published public var shortcutDescription: String = "⌘⇧O"
    @Published public var requiresAccessibility = false

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public static let shared = GlobalShortcutManager()

    private init() {}

    // Check if accessibility permission is granted
    public var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    // Request accessibility access (shows system prompt)
    public func requestAccessibilityPermission() {
        Task { @MainActor in
            PermisoAssistant.shared.present(panel: .accessibility)
        }
    }

    // Register global shortcut (Cmd+Shift+O by default)
    // NOTE: Global shortcut is currently disabled. Kept for potential future use.
    public func register() {
        // Disabled - no-op
    }

    public func unregister() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isRegistered = false
    }

    private func handleShortcut() {
        // Get the frontmost Finder window path using AppleScript
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                return POSIX path of (target of front Finder window as alias)
            end if
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)

            if let path = result.stringValue, !path.isEmpty {
                // Open Sorty with this path via deeplink
                if let url = URL(string: "sorty://organize?path=\(path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path)") {
                    NSWorkspace.shared.open(url)
                }
            } else {
                // No Finder window - just activate Sorty
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    // Open Accessibility settings
    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

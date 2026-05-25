import Foundation
import AppKit
import Combine

@MainActor
public class GlobalShortcutManager: ObservableObject {
    @Published public var isRegistered = false
    @Published public var shortcutDescription: String = "⌘⇧O"

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public static let shared = GlobalShortcutManager()

    private init() {}

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
}

//
//  QuickOrganizePanel.swift
//  Sorty
//
//  A floating panel that can be triggered from Finder toolbar or menu bar
//  Provides quick organization without opening the full app
//

import SwiftUI
import AppKit

// MARK: - Quick Organize Window Controller

public class QuickOrganizePanelController: NSObject, ObservableObject {
    public static let shared = QuickOrganizePanelController()
    
    private var panelWindow: NSPanel?
    @Published public var selectedDirectory: URL?
    @Published public var isOrganizing = false
    @Published public var progress: Double = 0
    @Published public var status: String = "Ready"
    @Published public var lastResult: QuickOrganizeResult?
    
    private override init() {
        super.init()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleQuickOrganizeRequest(_:)),
            name: NSNotification.Name("com.sorty.quickOrganize"),
            object: nil
        )
    }
    
    @objc private func handleQuickOrganizeRequest(_ notification: Notification) {
        if let path = notification.userInfo?["path"] as? String {
            DispatchQueue.main.async {
                self.selectedDirectory = URL(fileURLWithPath: path)
                self.showPanel()
            }
        }
    }
    
    public func showPanel(for directory: URL? = nil) {
        if let directory = directory {
            selectedDirectory = directory
        }
        
        if panelWindow == nil {
            createPanel()
        }
        
        panelWindow?.makeKeyAndOrderFront(nil)
        panelWindow?.center()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func hidePanel() {
        panelWindow?.orderOut(nil)
    }
    
    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.title = "Quick Organize"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        
        let contentView = QuickOrganizeView(controller: self)
        panel.contentView = NSHostingView(rootView: contentView)
        
        panelWindow = panel
    }
    
    public func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to organize"
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
        }
    }
}

// MARK: - Quick Organize Result

public struct QuickOrganizeResult {
    public let success: Bool
    public let filesOrganized: Int
    public let foldersCreated: Int
    public let message: String
    public let timestamp: Date
    
    public init(success: Bool, filesOrganized: Int, foldersCreated: Int, message: String) {
        self.success = success
        self.filesOrganized = filesOrganized
        self.foldersCreated = foldersCreated
        self.message = message
        self.timestamp = Date()
    }
}

// MARK: - Quick Organize View

struct QuickOrganizeView: View {
    @ObservedObject var controller: QuickOrganizePanelController
    @State private var customInstructions: String = ""
    @State private var useQuickMode: Bool = true
    @State private var showAdvancedOptions: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    directorySection
                    
                    if controller.selectedDirectory != nil {
                        optionsSection
                        
                        if showAdvancedOptions {
                            advancedOptionsSection
                        }
                    }
                    
                    if let result = controller.lastResult {
                        resultSection(result)
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer with action buttons
            footer
        }
        .frame(minWidth: 400, minHeight: 450)
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.title)
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Organize")
                    .font(.headline)
                Text("AI-powered file organization")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if controller.isOrganizing {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var directorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Target Folder", systemImage: "folder.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            if let directory = controller.selectedDirectory {
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: directory.path))
                        .resizable()
                        .frame(width: 32, height: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(directory.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(directory.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    
                    Spacer()
                    
                    Button("Change") {
                        controller.selectDirectory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(10)
            } else {
                Button(action: { controller.selectDirectory() }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Select a folder to organize")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Organization Mode", systemImage: "slider.horizontal.3")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            HStack(spacing: 12) {
                ModeButton(
                    title: "Quick",
                    subtitle: "Fast, automatic",
                    icon: "bolt.fill",
                    isSelected: useQuickMode
                ) {
                    useQuickMode = true
                }
                
                ModeButton(
                    title: "Custom",
                    subtitle: "With instructions",
                    icon: "text.bubble.fill",
                    isSelected: !useQuickMode
                ) {
                    useQuickMode = false
                }
            }
            
            if !useQuickMode {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Instructions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $customInstructions)
                        .font(.body)
                        .frame(height: 80)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            
            Button(action: { showAdvancedOptions.toggle() }) {
                HStack {
                    Text("Advanced Options")
                        .font(.caption)
                    Spacer()
                    Image(systemName: showAdvancedOptions ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Use Learnings", isOn: .constant(true))
                .font(.subheadline)
            
            Toggle("Preview before applying", isOn: .constant(false))
                .font(.subheadline)
            
            Toggle("Create backup", isOn: .constant(true))
                .font(.subheadline)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }
    
    private func resultSection(_ result: QuickOrganizeResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.success ? .green : .red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.success ? "Organization Complete" : "Organization Failed")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(result.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            if result.success && (result.filesOrganized > 0 || result.foldersCreated > 0) {
                HStack(spacing: 20) {
                    StatPill(value: "\(result.filesOrganized)", label: "Files", color: .blue)
                    StatPill(value: "\(result.foldersCreated)", label: "Folders", color: .green)
                }
            }
        }
        .padding()
        .background(result.success ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
        .cornerRadius(10)
    }
    
    private var footer: some View {
        HStack {
            Button("Open Full App") {
                NSWorkspace.shared.open(URL(string: "sorty://open")!)
                controller.hidePanel()
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("Cancel") {
                controller.hidePanel()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
            
            Button(action: startOrganization) {
                if controller.isOrganizing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 80)
                } else {
                    Text("Organize")
                        .frame(width: 80)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.selectedDirectory == nil || controller.isOrganizing)
            .keyboardShortcut(.return)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func startOrganization() {
        guard let directory = controller.selectedDirectory else { return }
        
        controller.isOrganizing = true
        controller.status = "Opening in Sorty..."
        
        // Send organization request to main app
        let url = ExtensionCommunication.urlForOrganizing(path: directory.path)
        if let url = url {
            NSWorkspace.shared.open(url)
            
            // Just indicate handoff to main app
            controller.isOrganizing = false
            controller.lastResult = QuickOrganizeResult(
                success: true,
                filesOrganized: 0,
                foldersCreated: 0,
                message: "Handed off to Sorty - check the main app for results"
            )
        } else {
            controller.isOrganizing = false
            controller.status = "Failed to launch Sorty"
        }
    }
}

// MARK: - Supporting Views

struct ModeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .accentColor)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct StatPill: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(16)
    }
}

// MARK: - Finder Toolbar Button Helper

public class FinderToolbarHelper {
    
    /// Install a script that can be added to Finder toolbar
    /// This creates an .app bundle that can be dragged to the Finder toolbar
    public static func createToolbarApp() -> (success: Bool, path: String?, message: String) {
        let appName = "Organize with Sorty"
        let applicationsSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sortyDir = applicationsSupport.appendingPathComponent("Sorty")
        let appPath = sortyDir.appendingPathComponent("\(appName).app")
        
        do {
            // Create directory structure
            let contentsPath = appPath.appendingPathComponent("Contents")
            let macOSPath = contentsPath.appendingPathComponent("MacOS")
            let resourcesPath = contentsPath.appendingPathComponent("Resources")
            
            try FileManager.default.createDirectory(at: macOSPath, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: resourcesPath, withIntermediateDirectories: true)
            
            // Create Info.plist
            let infoPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleExecutable</key>
                <string>organize</string>
                <key>CFBundleIdentifier</key>
                <string>com.sorty.toolbar-helper</string>
                <key>CFBundleName</key>
                <string>\(appName)</string>
                <key>CFBundlePackageType</key>
                <string>APPL</string>
                <key>CFBundleShortVersionString</key>
                <string>1.0</string>
                <key>LSMinimumSystemVersion</key>
                <string>12.0</string>
                <key>CFBundleIconFile</key>
                <string>AppIcon</string>
                <key>LSUIElement</key>
                <true/>
            </dict>
            </plist>
            """
            try infoPlist.write(to: contentsPath.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
            
            // Create shell script executable
            let script = """
            #!/bin/bash
            
            # Get the frontmost Finder window's path
            FINDER_PATH=$(osascript -e 'tell application "Finder"
                if (count of Finder windows) > 0 then
                    set thePath to POSIX path of (target of front Finder window as alias)
                    return thePath
                else
                    return ""
                end if
            end tell')
            
            if [ -n "$FINDER_PATH" ]; then
                # Encode the path for URL (using sys.argv to handle special characters safely)
                ENCODED_PATH=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$FINDER_PATH")
                open "sorty://organize?path=$ENCODED_PATH"
            else
                # No Finder window, just open the app
                open "sorty://open"
            fi
            """
            
            let scriptPath = macOSPath.appendingPathComponent("organize")
            try script.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            // Make executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
            
            return (true, appPath.path, "Toolbar app created! Drag '\(appName).app' from \(sortyDir.path) to your Finder toolbar while holding Command.")
            
        } catch {
            return (false, nil, "Failed to create toolbar app: \(error.localizedDescription)")
        }
    }
    
    /// Open the folder containing the toolbar app
    public static func revealToolbarApp() {
        let applicationsSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let sortyDir = applicationsSupport.appendingPathComponent("Sorty")
        let appPath = sortyDir.appendingPathComponent("Organize with Sorty.app")
        
        if FileManager.default.fileExists(atPath: appPath.path) {
            NSWorkspace.shared.selectFile(appPath.path, inFileViewerRootedAtPath: sortyDir.path)
        } else {
            _ = createToolbarApp()
            NSWorkspace.shared.selectFile(appPath.path, inFileViewerRootedAtPath: sortyDir.path)
        }
    }
    
    /// Check if toolbar app is installed
    public static func isToolbarAppInstalled() -> Bool {
        let applicationsSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appPath = applicationsSupport
            .appendingPathComponent("Sorty")
            .appendingPathComponent("Organize with Sorty.app")
        return FileManager.default.fileExists(atPath: appPath.path)
    }
}

// MARK: - Menu Bar Helper

public class MenuBarHelper: NSObject {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    
    public static let shared = MenuBarHelper()
    
    private override init() {
        super.init()
    }
    
    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Sorty")
            button.image?.isTemplate = true
        }
        
        setupMenu()
    }
    
    public func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    
    private func setupMenu() {
        menu = NSMenu()
        
        let organizeItem = NSMenuItem(
            title: "Organize Current Folder",
            action: #selector(organizeCurrentFolder),
            keyEquivalent: "o"
        )
        organizeItem.target = self
        menu?.addItem(organizeItem)
        
        let selectItem = NSMenuItem(
            title: "Organize...",
            action: #selector(selectAndOrganize),
            keyEquivalent: "O"
        )
        selectItem.target = self
        menu?.addItem(selectItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        let quickPanelItem = NSMenuItem(
            title: "Quick Organize Panel",
            action: #selector(showQuickPanel),
            keyEquivalent: "q"
        )
        quickPanelItem.target = self
        menu?.addItem(quickPanelItem)
        
        menu?.addItem(NSMenuItem.separator())
        
        let openAppItem = NSMenuItem(
            title: "Open Sorty",
            action: #selector(openMainApp),
            keyEquivalent: ""
        )
        openAppItem.target = self
        menu?.addItem(openAppItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func organizeCurrentFolder() {
        // Get frontmost Finder window path via AppleScript
        let script = """
        tell application "Finder"
            if (count of Finder windows) > 0 then
                set thePath to POSIX path of (target of front Finder window as alias)
                return thePath
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script),
           let result = appleScript.executeAndReturnError(&error).stringValue {
            if let url = ExtensionCommunication.urlForOrganizing(path: result) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc private func selectAndOrganize() {
        QuickOrganizePanelController.shared.selectDirectory()
        QuickOrganizePanelController.shared.showPanel()
    }
    
    @objc private func showQuickPanel() {
        QuickOrganizePanelController.shared.showPanel()
    }
    
    @objc private func openMainApp() {
        NSWorkspace.shared.open(URL(string: "sorty://open")!)
    }
}

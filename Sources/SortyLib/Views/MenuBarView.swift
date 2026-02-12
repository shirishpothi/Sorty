//
//  MenuBarView.swift
//  Sorty
//
//  Menu bar extra view for persistent background presence
//

import SwiftUI
import AppKit

// MARK: - Menu Bar Mascot Icon

private struct MenuBarMascotIcon: View {
    var size: CGSize = CGSize(width: 18, height: 18)
    
    private var mascotImage: Image {
        Image(nsImage: SortyResources.menuBarNSImage())
            .renderingMode(.template)
    }
    
    var body: some View {
        mascotImage
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Menu Bar Label (Icon for menu bar)

public struct MenuBarLabel: View {
    public init() {}
    
    private static func menuBarImage() -> NSImage {
        let img = SortyResources.menuBarNSImage()
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        return img
    }
    
    public var body: some View {
        Image(nsImage: Self.menuBarImage())
            .accessibilityLabel("Sorty")
    }
}

public struct MenuBarView: View {
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var notificationSettings: NotificationSettingsManager
    @EnvironmentObject var menuBarController: MenuBarController

    @AppStorage("keepInBackground") private var keepInBackground = false
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var isAllPaused: Bool = false
    @State private var isOrganizing: Bool = false
    @State private var isDropTargeted: Bool = false
    
    public init() {}
    
    private var activeWatchedCount: Int {
        watchedFoldersManager.folders.filter { $0.isEnabled && $0.autoOrganize }.count
    }
    
    private var foldersWithIssues: [WatchedFolder] {
        watchedFoldersManager.folders.filter { $0.accessStatus == .lost || $0.accessStatus == .stale }
    }
    
    private var isAIConfigured: Bool {
        organizer.isAIConfigured
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            
            Divider()
                .padding(.vertical, 4)
            
            quickActions
            
            if !watchedFoldersManager.folders.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                watchedFoldersList
            }
            
            Divider()
                .padding(.vertical, 4)
            
            backgroundToggle
            
            Divider()
                .padding(.vertical, 4)
            
            bottomActions
        }
        .padding(.vertical, 8)
        .frame(width: 280)
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.05))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task {
                await menuBarController.handleDrop(providers: providers)
            }
            return true
        }
        .popover(isPresented: $menuBarController.showPopover) {
            LiquidGlassPopover(controller: menuBarController)
        }
    }
    
    // MARK: - Status Header
    
    private var statusHeader: some View {
        HStack(spacing: 8) {
            MenuBarMascotIcon(size: CGSize(width: 22, height: 20))
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Sorty")
                        .font(.headline)
                    
                    Circle()
                        .fill(isAIConfigured ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                        .help(isAIConfigured ? "AI configured" : "AI not configured")
                }
                
                if activeWatchedCount > 0 {
                    Text("\(activeWatchedCount) folder\(activeWatchedCount == 1 ? "" : "s") active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No folders watching")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if !foldersWithIssues.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("\(foldersWithIssues.count) folder(s) need attention")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
    
    // MARK: - Quick Actions
    
    private var quickActions: some View {
        VStack(spacing: 2) {
            MenuBarButton(title: "Open Sorty", icon: "macwindow") {
                openMainWindow()
            }
            
            MenuBarButton(title: "Organize Current Folder", icon: "wand.and.stars") {
                organizeCurrentFolder()
            }
            .disabled(isOrganizing)
            
            MenuBarButton(title: "Quick Organize Panel", icon: "uiwindow.split.2x1") {
                QuickOrganizePanelController.shared.showPanel()
            }
            
            if let lastDir = appState.lastOrganizedDirectory {
                MenuBarButton(
                    title: "Organize \(lastDir.lastPathComponent)",
                    icon: "arrow.clockwise"
                ) {
                    organizeDirectory(lastDir)
                }
                .disabled(isOrganizing)
            }
            
            MenuBarButton(title: "Organize Desktop", icon: "desktopcomputer") {
                let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                if let desktop = desktopURL {
                    organizeDirectory(desktop)
                }
            }
            .disabled(isOrganizing)
            
            MenuBarButton(title: "View History", icon: "clock.arrow.circlepath") {
                openMainWindow()
                appState.currentView = .history
            }
            
            MenuBarButton(title: "Workspace Health", icon: "heart.text.square") {
                openMainWindow()
                appState.currentView = .workspaceHealth
            }
            
            MenuBarButton(title: "Learnings", icon: "lightbulb.fill") {
                openMainWindow()
                appState.currentView = .learnings
            }
            
            MenuBarButton(title: "Storage Locations", icon: "externaldrive.fill") {
                openMainWindow()
                appState.currentView = .storageLocations
            }
            
            Divider()
                .padding(.vertical, 2)
            
            MenuBarButton(
                title: isAllPaused ? "Resume All" : "Pause All",
                icon: isAllPaused ? "play.fill" : "pause.fill"
            ) {
                togglePauseAll()
            }
            .disabled(watchedFoldersManager.folders.isEmpty)
        }
    }
    
    // MARK: - Watched Folders List
    
    private var watchedFoldersList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Watched Folders")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            
            ForEach(watchedFoldersManager.folders.prefix(5)) { folder in
                WatchedFolderMenuItem(folder: folder)
            }
            
            if watchedFoldersManager.folders.count > 5 {
                Text("+ \(watchedFoldersManager.folders.count - 5) more...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
    }
    
    // MARK: - Background Toggle
    
    private var backgroundToggle: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $notificationSettings.settings.notifyOnAutoOrganize) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .frame(width: 16)
                    Text("Automation Notifications")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 4)

            Toggle(isOn: $launchAtLogin) {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill")
                        .frame(width: 16)
                    Text("Launch at Login")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Toggle(isOn: $keepInBackground) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .frame(width: 16)
                    Text("Keep in Background")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Toggle(isOn: $hideDockIcon) {
                HStack(spacing: 8) {
                    Image(systemName: "dock.rectangle")
                        .frame(width: 16)
                    Text("Hide Dock Icon")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            if keepInBackground || launchAtLogin || hideDockIcon {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Running as Background Activity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    MenuBarButton(title: "System Settings...", icon: "gear.badge") {
                        loginItemManager.openLoginItemsSettings()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
            }
        }
    }
    
    // MARK: - Bottom Actions
    
    private var bottomActions: some View {
        VStack(spacing: 2) {
            MenuBarButton(title: "Settings...", icon: "gear") {
                openSettings()
            }
            
            Divider()
                .padding(.vertical, 4)
            
            if keepInBackground {
                MenuBarButton(title: "Close Window", icon: "xmark.rectangle") {
                    for window in NSApp.windows where window.canBecomeMain {
                        window.close()
                    }
                }

                MenuBarButton(title: "Quit Sorty", icon: "power") {
                    NotificationCenter.default.post(name: .forceQuitSorty, object: nil)
                    NSApplication.shared.terminate(nil)
                }
            } else {
                MenuBarButton(title: "Quit Sorty", icon: "power") {
                    NotificationCenter.default.post(name: .forceQuitSorty, object: nil)
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func openSettings() {
        openMainWindow()
        appState.currentView = .settings
    }
    
    private func togglePauseAll() {
        isAllPaused.toggle()
        
        for folder in watchedFoldersManager.folders {
            var updated = folder
            updated.isEnabled = !isAllPaused
            watchedFoldersManager.updateFolder(updated)
        }
    }
    
    private func organizeDirectory(_ directory: URL) {
        isOrganizing = true
        appState.selectedDirectory = directory

        // Capture class references explicitly to survive view teardown
        let organizer = self.organizer
        let config = self.settingsViewModel.config
        let appState = self.appState

        Task { @MainActor in
            do {
                try await organizer.configure(with: config)
                try await organizer.organize(directory: directory)
            } catch {
                DebugLogger.log("Menu bar organize failed: \(error.localizedDescription)")
            }
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
                window.makeKeyAndOrderFront(nil)
            } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
            appState.currentView = .organize
            isOrganizing = false
        }
    }

    private func organizeCurrentFolder() {
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
            let url = URL(fileURLWithPath: result)
            organizeDirectory(url)
        }
    }
}

// MARK: - Menu Bar Button

private struct MenuBarButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Watched Folder Menu Item

private struct WatchedFolderMenuItem: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState

    @State private var isHovered = false

    private var statusIcon: String {
        switch folder.accessStatus {
        case .valid:
            return folder.isEnabled && folder.autoOrganize ? "checkmark.circle.fill" : "pause.circle.fill"
        case .stale:
            return "exclamationmark.circle.fill"
        case .lost:
            return "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch folder.accessStatus {
        case .valid:
            return folder.isEnabled && folder.autoOrganize ? .green : .orange
        case .stale:
            return .yellow
        case .lost:
            return .red
        case .unknown:
            return .gray
        }
    }

    private var folderIcon: NSImage {
        // Fetch at 32x32 for Retina crispness, display at 18x18
        let icon = NSWorkspace.shared.icon(forFile: folder.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    var body: some View {
        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: folderIcon)
                        .interpolation(.high)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)

                    Image(systemName: statusIcon)
                        .font(.system(size: 8))
                        .foregroundStyle(statusColor)
                        .background(
                            Circle()
                                .fill(.background)
                                .frame(width: 10, height: 10)
                        )
                        .offset(x: 3, y: 3)
                }
                .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.name)
                        .font(.callout)
                        .lineLimit(1)

                    Text(folder.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            Button {
                organizeFolder()
            } label: {
                Label("Organize Now", systemImage: "wand.and.stars")
            }
            .disabled(organizer.state != .idle)

            Divider()

            Button {
                var updated = folder
                updated.isEnabled.toggle()
                watchedFoldersManager.updateFolder(updated)
            } label: {
                Label(
                    folder.isEnabled ? "Pause Watching" : "Resume Watching",
                    systemImage: folder.isEnabled ? "pause.fill" : "play.fill"
                )
            }

            Divider()

            Button(role: .destructive) {
                watchedFoldersManager.removeFolder(folder)
            } label: {
                Label("Remove from Watch List", systemImage: "trash")
            }
        }
    }

    private func organizeFolder() {
        let folderURL = URL(fileURLWithPath: folder.path)
        appState.selectedDirectory = folderURL

        // Capture class references explicitly to survive view teardown
        let organizer = self.organizer
        let config = self.settingsViewModel.config
        let appState = self.appState

        Task { @MainActor in
            do {
                try await organizer.configure(with: config)
                try await organizer.organize(directory: folderURL)
            } catch {
                DebugLogger.log("Menu bar organize failed: \(error.localizedDescription)")
            }
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
            appState.currentView = .organize
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(WatchedFoldersManager())
        .environmentObject(AppState())
        .environmentObject(MenuBarController())
}

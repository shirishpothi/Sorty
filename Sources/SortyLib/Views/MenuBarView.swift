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
        // For menu bar, prefer template image (auto-adapts to light/dark mode)
        if let nsImage = SortyResources.image(named: "SortyMascotTemplate") {
            nsImage.isTemplate = true
            return Image(nsImage: nsImage)
                .renderingMode(.template)
        } else if let nsImage = SortyResources.image(named: "SortyMascot") {
            return Image(nsImage: nsImage)
                .renderingMode(.template)
        } else {
            return Image(systemName: "folder.fill.badge.gearshape")
        }
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
    let activeCount: Int
    
    public init(activeCount: Int) {
        self.activeCount = activeCount
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            MenuBarMascotIcon(size: CGSize(width: 18, height: 18))
            
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
        }
    }
}

public struct MenuBarView: View {
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @State private var isAllPaused: Bool = false
    @State private var isOrganizing: Bool = false
    
    public init() {}
    
    private var activeWatchedCount: Int {
        watchedFoldersManager.folders.filter { $0.isEnabled && $0.autoOrganize }.count
    }
    
    private var foldersWithIssues: [WatchedFolder] {
        watchedFoldersManager.folders.filter { $0.accessStatus == .lost || $0.accessStatus == .stale }
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
            
            bottomActions
        }
        .padding(.vertical, 8)
        .frame(width: 280)
    }
    
    // MARK: - Status Header
    
    private var statusHeader: some View {
        HStack(spacing: 8) {
            MenuBarMascotIcon(size: CGSize(width: 22, height: 20))
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Sorty")
                    .font(.headline)
                
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
            
            // Organize Recent Folder
            if let lastDir = appState.lastOrganizedDirectory {
                MenuBarButton(
                    title: "Organize \(lastDir.lastPathComponent)",
                    icon: "arrow.clockwise"
                ) {
                    organizeDirectory(lastDir)
                }
                .disabled(isOrganizing)
            }
            
            // Quick Organize Desktop
            MenuBarButton(title: "Organize Desktop", icon: "desktopcomputer") {
                let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                if let desktop = desktopURL {
                    organizeDirectory(desktop)
                }
            }
            .disabled(isOrganizing)
            
            // View History
            MenuBarButton(title: "View History", icon: "clock.arrow.circlepath") {
                openMainWindow()
                appState.currentView = .history
            }
            
            // Workspace Health
            MenuBarButton(title: "Workspace Health", icon: "heart.text.square") {
                openMainWindow()
                appState.currentView = .workspaceHealth
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
    
    // MARK: - Bottom Actions
    
    private var bottomActions: some View {
        VStack(spacing: 2) {
            MenuBarButton(title: "Settings...", icon: "gear") {
                openSettings()
            }
            
            Divider()
                .padding(.vertical, 4)
            
            MenuBarButton(title: "Quit Sorty", icon: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    // MARK: - Actions
    
    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
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
        
        Task {
            do {
                try await organizer.configure(with: settingsViewModel.config)
                try await organizer.organize(directory: directory)
            } catch {
                DebugLogger.log("Menu bar organize failed: \(error.localizedDescription)")
            }
            await MainActor.run {
                isOrganizing = false
                // Open main window to show results
                openMainWindow()
                appState.currentView = .organize
            }
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
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
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
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)
            
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(WatchedFoldersManager())
        .environmentObject(AppState())
}

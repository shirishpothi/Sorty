//
//  MenuBarView.swift
//  Sorty
//
//  Menu bar extra view for persistent background presence
//

import AppKit
import SwiftUI

// MARK: - Menu Bar Mascot Icon

private struct MenuBarMascotIcon: View {
    var size: CGSize = CGSize(width: 18, height: 18)

    private var mascotImage: Image {
        Image(nsImage: SortyResources.menuBarLabelNSImage())
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

    private static let menuBarImage: NSImage = {
        let source = SortyResources.menuBarLabelNSImage()
        let image = (source.copy() as? NSImage) ?? source
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }()

    public var body: some View {
        Image(nsImage: Self.menuBarImage)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .accessibilityLabel("Sorty")
    }
}

public struct MenuBarView: View {
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var notificationSettings: NotificationSettingsManager
    @EnvironmentObject var menuBarController: MenuBarController

    @AppStorage("keepInBackground") private var keepInBackground = false
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @State private var isAllPaused: Bool = false
    @State private var isDropTargeted: Bool = false

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

            backgroundToggle

            Divider()
                .padding(.vertical, 4)

            bottomActions
        }
        .padding(.vertical, 8)
        .frame(width: 280)
        .siriDropZone(cornerRadius: 10, isTargeted: $isDropTargeted) { providers in
            Task {
                await menuBarController.handleDrop(providers: providers)
            }
            return true
        }
        .popover(isPresented: $menuBarController.showPopover) {
            LiquidGlassPopover(controller: menuBarController)
                .systemLiquidGlassPopover(cornerRadius: 12)
        }
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 8) {
            MenuBarMascotIcon(size: CGSize(width: 22, height: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text("Sorty")
                    .font(.headline)

                if activeWatchedCount > 0 {
                    Text("\(activeWatchedCount) folder\(activeWatchedCount == 1 ? "" : "s") active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No watched folders active")
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

            MenuBarButton(title: "View History", icon: "clock") {
                openDestination(.history)
            }

            MenuBarButton(title: "Workspace Health", icon: "heart.text.square") {
                openDestination(.health)
            }

            MenuBarButton(title: "Learnings", icon: "brain") {
                openDestination(.learnings(action: nil, project: nil))
            }

            MenuBarButton(title: "Storage Locations", icon: "externaldrive.fill") {
                openDestination(.storage(action: nil, path: nil))
            }

            MenuBarButton(title: "Watched Folders", icon: "eye") {
                openDestination(.watched(action: nil, path: nil))
            }

            if !watchedFoldersManager.folders.isEmpty {
                Divider()
                    .padding(.vertical, 2)

                MenuBarButton(
                    title: isAllPaused ? "Resume All" : "Pause All",
                    icon: isAllPaused ? "play.fill" : "pause.fill"
                ) {
                    togglePauseAll()
                }
            }
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
            Toggle(isOn: Binding(
                get: { notificationSettings.settings.notifyOnAutoOrganize },
                set: { newValue in
                    notificationSettings.settings.notifyOnAutoOrganize = newValue
                    HapticFeedbackManager.shared.tap()
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge.fill")
                        .frame(width: 16)
                    Text("Notifications")
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()
                .padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    launchAtLogin = newValue
                    HapticFeedbackManager.shared.tap()
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "sunrise.fill")
                        .frame(width: 16)
                    Text("Launch at Login")
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { keepInBackground },
                set: { newValue in
                    keepInBackground = newValue
                    HapticFeedbackManager.shared.tap()
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill")
                        .frame(width: 16)
                    Text("Keep in Background")
                    Spacer()
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Toggle(isOn: Binding(
                get: { hideDockIcon },
                set: { newValue in
                    hideDockIcon = newValue
                    HapticFeedbackManager.shared.tap()
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: "dock.rectangle")
                        .frame(width: 16)
                    Text("Hide Dock Icon")
                    Spacer()
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

            MenuBarButton(title: "AI Provider Settings", icon: "cpu") {
                openSettings(section: "provider")
            }

            MenuBarButton(title: "Automation Settings", icon: "bolt.circle") {
                openSettings(section: "automation")
            }

            MenuBarButton(title: "Notification Settings", icon: "bell") {
                openSettings(section: "notifications")
            }

            MenuBarButton(title: "Support the Developer", icon: "heart.fill") {
                openSupportDeveloper()
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
                    NSApplication.shared.terminate(nil)
                }
            } else {
                MenuBarButton(title: "Quit Sorty", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    // MARK: - Actions

    private func openMainWindow() {
        openDestination(.open(path: nil))
    }

    private func openSettings(section: String? = nil) {
        openDestination(.settings(section: section))
    }

    private func openSupportDeveloper() {
        guard let url = URL(string: "https://github.com/sponsors/shirishpothi") else { return }
        NSWorkspace.shared.open(url)
    }

    private func togglePauseAll() {
        isAllPaused.toggle()

        for folder in watchedFoldersManager.folders {
            var updated = folder
            updated.isEnabled = !isAllPaused
            watchedFoldersManager.updateFolder(updated)
        }
    }

    private func openDestination(_ destination: DeeplinkDestination) {
        guard let url = DeeplinkHandler.url(for: destination) else { return }
        if MainWindowRouter.shared.routeDeeplink(url) {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Menu Bar Button

private struct MenuBarButton: View {
    let title: String
    var icon: String? = nil
    var customImage: Image? = nil
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                if let customImage = customImage {
                    customImage
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .frame(width: 16)
                }
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
    }
}

// MARK: - Watched Folder Menu Item

private struct WatchedFolderMenuItem: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager

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
            HapticFeedbackManager.shared.tap()
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    AppKitImageView(image: folderIcon, size: CGSize(width: 18, height: 18))
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

                    PrivacySensitivePathText(path: folder.path)
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
                    .fill(isHovered ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.1) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    HapticFeedbackManager.shared.selection()
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
}

#Preview {
    MenuBarView()
        .environmentObject(WatchedFoldersManager())
        .environmentObject(MenuBarController())
}

//
//  PermissionsSettingsView.swift
//  Sorty
//
//  Central place to review and manage macOS permissions used by Sorty
//

import AppKit
import SwiftUI
import UserNotifications

import Permiso

struct PermissionsSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var automationManager: AutomationManager
    @ObservedObject private var notificationManager = NotificationManager.shared

    @State private var permissionStates: [PermissionType: PermissionState] = [:]
    @State private var selectedEducationPermission: PermissionType?
    @State private var isFullDiskAccessConfirmationPresented = false
    @State private var fullDiskAccessSourceFrameInScreen: CGRect?
    @State private var didOpenFullDiskAccessSettings = false

    private var readyPermissionCount: Int {
        PermissionType.allCases.filter { type in
            let state = permissionStates[type]
            return state == .granted || state == .restartRequired
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(
                title: "Permission Status",
                icon: "hand.raised.fill",
                color: .blue,
                headerAccessory: {
                    statusSummary
                }
            ) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Review the macOS access Sorty uses for folder organization, Finder actions, and notifications. Optional permissions can stay off until you need their features.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PermissionRow(
                        type: .filesAndFolders,
                        state: permissionStates[.filesAndFolders] ?? .unknown,
                        isRequired: true,
                        onExplain: { selectedEducationPermission = .filesAndFolders },
                        onRequest: { _ in requestFilesAndFoldersPermission() }
                    )
                    .settingsFocusableSetting(.permissionsFilesAndFolders)

                    PermissionRow(
                        type: .fullDiskAccess,
                        state: permissionStates[.fullDiskAccess] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .fullDiskAccess },
                        onRequest: { sourceFrame in
                            fullDiskAccessSourceFrameInScreen = sourceFrame
                            isFullDiskAccessConfirmationPresented = true
                        }
                    )
                    .settingsFocusableSetting(.permissionsFullDiskAccess)

                    PermissionRow(
                        type: .automation,
                        state: permissionStates[.automation] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .automation },
                        onRequest: { _ in requestAutomationPermission() }
                    )
                    .settingsFocusableSetting(.permissionsAutomation)

                    PermissionRow(
                        type: .notifications,
                        state: permissionStates[.notifications] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .notifications },
                        onRequest: { _ in requestNotificationPermission() }
                    )
                    .settingsFocusableSetting(.permissionsNotifications)

                    Divider()
                        .opacity(0.35)

                    HStack(spacing: 10) {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            refreshPermissions()
                        } label: {
                            Label("Refresh Status", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.sortySecondary(size: .regular))

                        Button {
                            HapticFeedbackManager.shared.tap()
                            openPrivacyAndSecuritySettings()
                        } label: {
                            Label("Open Privacy & Security", systemImage: "gearshape")
                        }
                        .buttonStyle(.sortySecondary(size: .regular))

                        Spacer()
                    }
                }
            }

            SettingsCard(title: "How Sorty Uses Access", icon: "lock.shield", color: .green) {
                VStack(alignment: .leading, spacing: 10) {
                    permissionNote(
                        icon: "folder.badge.checkmark",
                        text: "Files & Folders access is granted only for folders you choose in the macOS picker."
                    )
                    permissionNote(
                        icon: "lock.open",
                        text: "Full Disk Access is optional and only helps with protected folders you explicitly select."
                    )
                    permissionNote(
                        icon: "hand.raised",
                        text: "You can revoke any system permission at any time in Privacy & Security."
                    )
                }
            }
        }
        .task {
            refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .sheet(item: $selectedEducationPermission) { permission in
            PermissionEducationView(pages: [permission]) {
                selectedEducationPermission = nil
            }
        }
        .alert("Set up Full Disk Access?", isPresented: $isFullDiskAccessConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                fullDiskAccessSourceFrameInScreen = nil
            }
            Button("Open System Settings") {
                openFullDiskAccessSettings()
            }
        } message: {
            Text("Full Disk Access is optional and only needed for protected folders. macOS may relaunch Sorty after you turn it on.")
        }
    }

    private var statusSummary: some View {
        Text("\(readyPermissionCount) of \(PermissionType.allCases.count) ready")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(readyPermissionCount == PermissionType.allCases.count ? .green : .secondary)
            .numericTextTransition(animationValue: readyPermissionCount)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.07), in: Capsule(style: .continuous))
    }

    private func permissionNote(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 18)
                .accessibilityHidden(true)

            Text(LocalizedStringKey(text))
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshPermissions() {
        permissionStates[.filesAndFolders] = filesAndFoldersState
        permissionStates[.fullDiskAccess] = fullDiskAccessState()

        automationManager.checkPermissions(enableChecksIfNeeded: true)
        permissionStates[.automation] = permissionState(for: automationManager.automationStatus)

        Task { @MainActor in
            await notificationManager.checkNotificationPermission()
            permissionStates[.notifications] = notificationState(
                for: notificationManager.notificationPermissionStatus
            )
        }
    }

    private func requestFilesAndFoldersPermission() {
        HapticFeedbackManager.shared.tap()
        permissionStates[.filesAndFolders] = .pending

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose a folder you want Sorty to organize."
        panel.prompt = "Grant Access"

        guard panel.runModal() == .OK, let url = panel.url else {
            permissionStates[.filesAndFolders] = filesAndFoldersState
            return
        }

        _ = url.startAccessingSecurityScopedResource()
        appState.selectedDirectory = url
        permissionStates[.filesAndFolders] = .granted
        HapticFeedbackManager.shared.success()
    }

    private var filesAndFoldersState: PermissionState {
        appState.hasCompletedOnboarding || appState.selectedDirectory != nil ? .granted : .unknown
    }

    private func openFullDiskAccessSettings() {
        HapticFeedbackManager.shared.tap()
        didOpenFullDiskAccessSettings = true
        permissionStates[.fullDiskAccess] = .pending
        PermisoAssistant.shared.present(
            panel: .fullDiskAccess,
            sourceFrameInScreen: fullDiskAccessSourceFrameInScreen,
            onCancel: {
                permissionStates[.fullDiskAccess] = fullDiskAccessState()
                fullDiskAccessSourceFrameInScreen = nil
            }
        )
    }

    private func requestAutomationPermission() {
        HapticFeedbackManager.shared.tap()
        permissionStates[.automation] = .pending
        automationManager.requestAutomationPermissionCheck()
        permissionStates[.automation] = permissionState(for: automationManager.automationStatus)

        if automationManager.automationStatus == .denied {
            automationManager.openAutomationSettings()
        } else if automationManager.automationStatus == .granted {
            HapticFeedbackManager.shared.success()
        }
    }

    private func requestNotificationPermission() {
        HapticFeedbackManager.shared.tap()

        Task { @MainActor in
            await notificationManager.checkNotificationPermission()

            if notificationManager.notificationPermissionStatus == .denied {
                permissionStates[.notifications] = .denied
                openNotificationSettings()
                return
            }

            permissionStates[.notifications] = .pending
            let granted = await notificationManager.requestPermission()
            permissionStates[.notifications] = notificationState(
                for: notificationManager.notificationPermissionStatus
            )

            if granted {
                HapticFeedbackManager.shared.success()
            } else {
                HapticFeedbackManager.shared.error()
            }
        }
    }

    private func fullDiskAccessState() -> PermissionState {
        if canReadProtectedFullDiskAccessLocation() {
            return didOpenFullDiskAccessSettings ? .restartRequired : .granted
        }

        return didOpenFullDiskAccessSettings ? .pending : .unknown
    }

    private func canReadProtectedFullDiskAccessLocation() -> Bool {
        let fileManager = FileManager.default
        let protectedDirectories = [
            "Library/Mail",
            "Library/Messages",
            "Library/Safari",
            "Library/Calendars"
        ]

        return protectedDirectories.contains { relativePath in
            let url = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: url.path) else { return false }
            return (try? fileManager.contentsOfDirectory(atPath: url.path)) != nil
        }
    }

    private func permissionState(for status: PermissionStatus) -> PermissionState {
        switch status {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .unknown:
            return .unknown
        }
    }

    private func notificationState(for status: UNAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized, .provisional:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    private func openNotificationSettings() {
        openFirstAvailableSettingsURL([
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ])
    }

    private func openPrivacyAndSecuritySettings() {
        openFirstAvailableSettingsURL([
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
        ])
    }

    private func openFirstAvailableSettingsURL(_ candidates: [String]) {
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

#Preview {
    PermissionsSettingsView()
        .environmentObject(AppState())
        .environmentObject(AutomationManager())
        .padding(24)
        .frame(width: 700, height: 700)
}

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
    @ObservedObject private var notificationSettings = NotificationSettingsManager.shared

    @State private var permissionStates: [PermissionType: PermissionState] = [:]
    @State private var selectedEducationPermission: PermissionType?
    @State private var fullDiskAccessSourceFrameInScreen: CGRect?
    @State private var didOpenFullDiskAccessSettings = false
    @State private var activeAlert: PermissionsSettingsAlert?

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
                        onRequest: { _ in requestFilesAndFoldersPermission() },
                        removePermissionTitle: "Remove Current Folder Access…",
                        onRemovePermission: { activeAlert = .revoke(.filesAndFolders) }
                    )
                    .settingsFocusableSetting(.permissionsFilesAndFolders)

                    PermissionRow(
                        type: .fullDiskAccess,
                        state: permissionStates[.fullDiskAccess] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .fullDiskAccess },
                        onRequest: { sourceFrame in
                            fullDiskAccessSourceFrameInScreen = sourceFrame
                            activeAlert = .fullDiskAccessSetup
                        },
                        onRemovePermission: { activeAlert = .revoke(.fullDiskAccess) }
                    )
                    .settingsFocusableSetting(.permissionsFullDiskAccess)

                    PermissionRow(
                        type: .automation,
                        state: permissionStates[.automation] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .automation },
                        onRequest: { _ in requestAutomationPermission() },
                        onRemovePermission: { activeAlert = .revoke(.automation) }
                    )
                    .settingsFocusableSetting(.permissionsAutomation)

                    PermissionRow(
                        type: .notifications,
                        state: permissionStates[.notifications] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .notifications },
                        onRequest: { _ in requestNotificationPermission() },
                        removePermissionTitle: "Disable & Open Notification Settings…",
                        onRemovePermission: { activeAlert = .revoke(.notifications) }
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
        .alert(item: $activeAlert) { alert in
            permissionAlert(for: alert)
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
        appState.selectedDirectory != nil ? .granted : .unknown
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

    private func permissionAlert(for alert: PermissionsSettingsAlert) -> Alert {
        switch alert {
        case .fullDiskAccessSetup:
            return Alert(
                title: Text("Set up Full Disk Access?"),
                message: Text("Full Disk Access is optional and only needed for protected folders. macOS may relaunch Sorty after you turn it on."),
                primaryButton: .default(Text("Open System Settings")) {
                    openFullDiskAccessSettings()
                },
                secondaryButton: .cancel {
                    fullDiskAccessSourceFrameInScreen = nil
                }
            )

        case .revoke(let type):
            return Alert(
                title: Text(revocationTitle(for: type)),
                message: Text(revocationMessage(for: type)),
                primaryButton: .destructive(Text(revocationButtonTitle(for: type))) {
                    revokePermission(type)
                },
                secondaryButton: .cancel()
            )

        case .failure(let message):
            return Alert(
                title: Text("Permission Couldn’t Be Removed"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func revocationTitle(for type: PermissionType) -> String {
        switch type {
        case .filesAndFolders:
            return "Remove Current Folder Access?"
        case .fullDiskAccess:
            return "Remove Full Disk Access?"
        case .automation:
            return "Remove Finder Automation?"
        case .notifications:
            return "Disable System Notifications?"
        }
    }

    private func revocationMessage(for type: PermissionType) -> String {
        switch type {
        case .filesAndFolders:
            return "Sorty will release the currently selected folder and reset its macOS access decisions for protected folders and external volumes. Your files won’t be changed."
        case .fullDiskAccess:
            return "macOS requires Sorty to quit before the revoked Full Disk Access takes effect. Your files and settings won’t be changed."
        case .automation:
            return "Sorty will no longer be able to read Finder selections. macOS will ask again the next time you enable Finder Automation."
        case .notifications:
            return "Sorty will stop sending system notifications immediately, clear its pending and delivered notifications, and open macOS Settings so you can turn off the system authorization."
        }
    }

    private func revocationButtonTitle(for type: PermissionType) -> String {
        switch type {
        case .fullDiskAccess:
            return "Remove & Quit Sorty"
        case .notifications:
            return "Disable & Open Settings"
        default:
            return "Remove Permission"
        }
    }

    private func revokePermission(_ type: PermissionType) {
        if type == .notifications {
            disableSystemNotifications()
            return
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        Task { @MainActor in
            let result = await SystemPermissionRevoker.revoke(
                type,
                bundleIdentifier: bundleIdentifier
            )

            guard result.succeeded else {
                HapticFeedbackManager.shared.error()
                activeAlert = .failure(result.message)
                return
            }

            switch type {
            case .filesAndFolders:
                if let selectedDirectory = appState.selectedDirectory {
                    selectedDirectory.stopAccessingSecurityScopedResource()
                }
                appState.selectedDirectory = nil
                permissionStates[.filesAndFolders] = .unknown
                HapticFeedbackManager.shared.success()

            case .fullDiskAccess:
                permissionStates[.fullDiskAccess] = .unknown
                HapticFeedbackManager.shared.success()
                NSApp.terminate(nil)

            case .automation:
                automationManager.markAutomationPermissionReset()
                permissionStates[.automation] = .unknown
                HapticFeedbackManager.shared.success()

            case .notifications:
                break
            }
        }
    }

    private func disableSystemNotifications() {
        notificationSettings.settings.systemNotifications = false

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        notificationCenter.setNotificationCategories([])

        HapticFeedbackManager.shared.success()
        openNotificationSettings()
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

private enum PermissionsSettingsAlert: Identifiable {
    case fullDiskAccessSetup
    case revoke(PermissionType)
    case failure(String)

    var id: String {
        switch self {
        case .fullDiskAccessSetup:
            return "full-disk-access-setup"
        case .revoke(let type):
            return "revoke-\(type.id)"
        case .failure(let message):
            return "failure-\(message)"
        }
    }
}

private enum SystemPermissionRevoker {
    struct Result: Sendable {
        let succeeded: Bool
        let message: String
    }

    static func revoke(
        _ type: PermissionType,
        bundleIdentifier: String
    ) async -> Result {
        let services: [String]
        switch type {
        case .filesAndFolders:
            services = [
                "SystemPolicyDesktopFolder",
                "SystemPolicyDocumentsFolder",
                "SystemPolicyDownloadsFolder",
                "SystemPolicyNetworkVolumes",
                "SystemPolicyRemovableVolumes"
            ]
        case .fullDiskAccess:
            services = ["SystemPolicyAllFiles"]
        case .automation:
            services = ["AppleEvents"]
        case .notifications:
            return Result(
                succeeded: false,
                message: "macOS requires notification authorization to be changed in System Settings."
            )
        }

        return await Task.detached(priority: .userInitiated) {
            var failures: [String] = []

            for service in services {
                if let failure = reset(service: service, bundleIdentifier: bundleIdentifier) {
                    failures.append(failure)
                }
            }

            if failures.isEmpty {
                return Result(succeeded: true, message: "")
            }

            return Result(
                succeeded: false,
                message: failures.joined(separator: "\n")
            )
        }.value
    }

    private static func reset(
        service: String,
        bundleIdentifier: String
    ) -> String? {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, bundleIdentifier]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus != 0 else { return nil }
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let detail = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return detail?.isEmpty == false
                ? detail!
                : "macOS couldn’t reset \(service)."
        } catch {
            return "macOS couldn’t run the permission reset: \(error.localizedDescription)"
        }
    }
}

#Preview {
    PermissionsSettingsView()
        .environmentObject(AppState())
        .environmentObject(AutomationManager())
        .padding(24)
        .frame(width: 700, height: 700)
}

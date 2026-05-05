//
//  PermissionsStepView.swift
//  Sorty
//
//  Permissions step of the onboarding flow
//

import AppKit
import SwiftUI
import UserNotifications

import Beam
import Permiso

public struct PermissionsStepView: View {
    private let assumeFilesPermissionForUITestsKey = "uitestAssumeFilesAndFoldersPermission"
    @Binding var hasRequiredPermissions: Bool
    @State private var hasAppeared = false
    @State private var permissionStates: [PermissionType: PermissionState] = [:]
    @EnvironmentObject private var automationManager: AutomationManager

    public init(hasRequiredPermissions: Binding<Bool>) {
        self._hasRequiredPermissions = hasRequiredPermissions
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Left side - explanation
            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("Permissions")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(
                        "Sorty needs a few permissions to organize your files effectively. You can grant these now or later when needed."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why these permissions?")
                            .font(.subheadline.bold())

                        Text(
                            "• **Files & Folders** *(Required)*: To read and move your files\n• **Full Disk Access** *(Recommended)*: To organize files in any folder\n• **Automation** *(Optional)*: For Finder integration\n• **Notifications** *(Optional)*: To alert you when organization completes"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 350)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -20)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            // Right side - permission requests
            VStack(spacing: 24) {
                Text("Grant Permissions")
                    .font(.title3)
                    .fontWeight(.semibold)

                VStack(spacing: 16) {
                    PermissionRow(
                        type: .filesAndFolders,
                        state: permissionStates[.filesAndFolders] ?? .unknown,
                        onRequest: { requestPermission(.filesAndFolders, sourceFrameInScreen: $0) }
                    )

                    PermissionRow(
                        type: .fullDiskAccess,
                        state: permissionStates[.fullDiskAccess] ?? .unknown,
                        onRequest: { requestPermission(.fullDiskAccess, sourceFrameInScreen: $0) }
                    )

                    PermissionRow(
                        type: .automation,
                        state: permissionStates[.automation] ?? .unknown,
                        onRequest: { requestPermission(.automation, sourceFrameInScreen: $0) }
                    )

                    PermissionRow(
                        type: .notifications,
                        state: permissionStates[.notifications] ?? .unknown,
                        onRequest: { requestPermission(.notifications, sourceFrameInScreen: $0) }
                    )
                }
                .frame(maxWidth: 400)

                if permissionStates[.filesAndFolders] == .granted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Files & Folders permission granted. You can continue.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Files & Folders permission is required to continue")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("Full Disk Access is recommended · Automation and Notifications are optional")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 40)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.985)
            .animation(.easeInOut(duration: 0.22).delay(0.12), value: hasAppeared)
        }
        .onAppear {
            withAnimation { hasAppeared = true }
            checkPermissions()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permissions Step")
    }

    private func checkPermissions() {
        if UserDefaults.standard.bool(forKey: assumeFilesPermissionForUITestsKey) {
            permissionStates[.filesAndFolders] = .granted
            hasRequiredPermissions = true
        }

        // Check notification permission
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized:
                    permissionStates[.notifications] = .granted
                case .denied:
                    permissionStates[.notifications] = .denied
                default:
                    permissionStates[.notifications] = .unknown
                }
            }
        }

        // Check Files & Folders permission by testing access to user's home directory
        // If we can list the contents of Documents, we likely have access
        if !UserDefaults.standard.bool(forKey: assumeFilesPermissionForUITestsKey) {
            let documentsPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Documents")
            if FileManager.default.isReadableFile(atPath: documentsPath.path) {
                // Try to actually list contents to confirm access
                if (try? FileManager.default.contentsOfDirectory(atPath: documentsPath.path)) != nil
                {
                    permissionStates[.filesAndFolders] = .granted
                    hasRequiredPermissions = true
                } else {
                    permissionStates[.filesAndFolders] = .unknown
                    hasRequiredPermissions = false
                }
            } else {
                permissionStates[.filesAndFolders] = .unknown
                hasRequiredPermissions = false
            }
        }

        // Check Full Disk Access by probing a protected directory
        let protectedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari")
        if (try? FileManager.default.contentsOfDirectory(atPath: protectedPath.path)) != nil {
            permissionStates[.fullDiskAccess] = .granted
        } else {
            permissionStates[.fullDiskAccess] = .unknown
        }

        // Check Automation permission using FinderAutomation service
        automationManager.requestAutomationPermissionCheck()
        switch automationManager.automationStatus {
        case .granted:
            permissionStates[.automation] = .granted
        case .denied:
            permissionStates[.automation] = .denied
        case .unknown:
            permissionStates[.automation] = .unknown
        }
    }

    private func requestPermission(_ type: PermissionType, sourceFrameInScreen: CGRect?) {
        HapticFeedbackManager.shared.tap()

        switch type {
        case .filesAndFolders:
            // Use NSOpenPanel to trigger the Files & Folders permission dialog
            // This is the proper way to request file access permissions
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Select any folder to grant Sorty access to your files"
            panel.prompt = "Grant Access"
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

            if panel.runModal() == .OK, panel.url != nil {
                // User granted access - the permission is now active
                permissionStates[.filesAndFolders] = .granted
                hasRequiredPermissions = true
                HapticFeedbackManager.shared.success()
            } else {
                // User cancelled - still unknown/not granted
                permissionStates[.filesAndFolders] = .unknown
                hasRequiredPermissions = false
            }

        case .fullDiskAccess:
            // Open System Settings to Full Disk Access using Permiso
            PermisoAssistant.shared.present(
                panel: .fullDiskAccess,
                sourceFrameInScreen: sourceFrameInScreen,
                onCancel: { permissionStates[.fullDiskAccess] = .unknown }
            )
            permissionStates[.fullDiskAccess] = .pending

        case .automation:
            // Open System Settings to Automation using Permiso
            PermisoAssistant.shared.present(
                panel: .automation,
                sourceFrameInScreen: sourceFrameInScreen,
                onCancel: { permissionStates[.automation] = .unknown }
            )
            permissionStates[.automation] = .pending

        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [
                .alert, .sound, .badge,
            ]) { granted, error in
                Task { @MainActor in
                    permissionStates[.notifications] = granted ? .granted : .denied
                    if granted {
                        HapticFeedbackManager.shared.success()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Types

enum PermissionType: String {
    case filesAndFolders = "Files & Folders"
    case fullDiskAccess = "Full Disk Access"
    case automation = "Automation"
    case notifications = "Notifications"

    var icon: String {
        switch self {
        case .filesAndFolders: return "folder.fill"
        case .fullDiskAccess: return "lock.open.fill"
        case .automation: return "gearshape.2.fill"
        case .notifications: return "bell.fill"
        }
    }

    var description: String {
        switch self {
        case .filesAndFolders: return "Access to read and organize your files"
        case .fullDiskAccess: return "Move files to any folder without restrictions"
        case .automation: return "Control Finder for seamless integration"
        case .notifications: return "Get notified when organization completes"
        }
    }

    var color: Color {
        switch self {
        case .filesAndFolders: return .blue
        case .fullDiskAccess: return .green
        case .automation: return .orange
        case .notifications: return .purple
        }
    }
}

enum PermissionState {
    case unknown
    case pending
    case granted
    case denied
}

struct PermissionRow: View {
    let type: PermissionType
    let state: PermissionState
    let onRequest: (CGRect?) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.headline)

                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            case .denied:
                PermissionActionButton(title: "Open Settings", style: .bordered, action: onRequest)
                    .fixedSize()
            case .pending:
                Text("Check Settings")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .unknown:
                PermissionActionButton(title: "Grant", style: .primary, action: onRequest)
                    .fixedSize()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(state == .granted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}

private struct PermissionActionButton: View {
    enum Style {
        case primary
        case bordered
    }

    let title: String
    let style: Style
    let action: (CGRect?) -> Void

    @State private var frameInScreen: CGRect = .zero
    @State private var isHovering = false

    var body: some View {
        Button {
            action(frameInScreen.isEmpty ? nil : frameInScreen.integral)
        } label: {
            Text(title)
                .font(.system(size: style == .primary ? 14 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(style == .primary ? .white : .primary)
                .frame(minWidth: style == .primary ? 74 : 96)
                .padding(.horizontal, style == .primary ? 18 : 14)
                .padding(.vertical, style == .primary ? 10 : 7)
                .background {
                    if style == .primary {
                        PermissionGrantBeamBackground(isHovering: isHovering)
                    } else {
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.95))
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                            }
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            ScreenFrameReader(frameInScreen: $frameInScreen)
                .allowsHitTesting(false)
        )
        .scaleEffect(isHovering ? 1.03 : 1)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            if hovering && !isHovering {
                HapticFeedbackManager.shared.selection()
            }
            isHovering = hovering
        }
        .accessibilityLabel(title)
    }
}

private struct PermissionGrantBeamBackground: View {
    let isHovering: Bool

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [
                        Color.green.opacity(0.92),
                        Color.teal.opacity(0.95),
                        Color.blue.opacity(0.86)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), .clear, Color.black.opacity(0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(isHovering ? 0.24 : 0.16), lineWidth: 1)
            }
            .beam(
                .small,
                palette: .ocean,
                theme: .dark,
                active: true,
                shape: .capsule,
                duration: 1.9,
                strength: isHovering ? 0.92 : 0.76,
                lensStrength: isHovering ? 2.8 : 1.6
            )
            .shadow(color: Color.teal.opacity(isHovering ? 0.30 : 0.18), radius: isHovering ? 14 : 10, y: 5)
            .shadow(color: Color.blue.opacity(isHovering ? 0.20 : 0.10), radius: isHovering ? 18 : 10)
    }
}

// MARK: - Preview

#Preview {
    PermissionsStepView(hasRequiredPermissions: .constant(false))
}

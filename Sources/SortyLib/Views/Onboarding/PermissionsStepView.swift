//
//  PermissionsStepView.swift
//  Sorty
//
//  Permissions step of the onboarding flow
//

import SwiftUI
import UserNotifications

public struct PermissionsStepView: View {
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
                    
                    Text("Sorty needs a few permissions to organize your files effectively. You can grant these now or later when needed.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why these permissions?")
                            .font(.subheadline.bold())
                        
                        Text("• **Files & Folders** *(Required)*: To read and move your files\n• **Automation** *(Optional)*: For Finder integration\n• **Notifications** *(Optional)*: To alert you when organization completes")
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
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
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
                        onRequest: { requestPermission(.filesAndFolders) }
                    )
                    
                    PermissionRow(
                        type: .automation,
                        state: permissionStates[.automation] ?? .unknown,
                        onRequest: { requestPermission(.automation) }
                    )
                    
                    PermissionRow(
                        type: .notifications,
                        state: permissionStates[.notifications] ?? .unknown,
                        onRequest: { requestPermission(.notifications) }
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
                
                Text("Automation and Notifications are optional")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 40)
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
        }
        .onAppear {
            withAnimation { hasAppeared = true }
            checkPermissions()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permissions Step")
    }
    
    private func checkPermissions() {
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
        let documentsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        if FileManager.default.isReadableFile(atPath: documentsPath.path) {
            // Try to actually list contents to confirm access
            if let _ = try? FileManager.default.contentsOfDirectory(atPath: documentsPath.path) {
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
    
    private func requestPermission(_ type: PermissionType) {
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
            
            if panel.runModal() == .OK, let _ = panel.url {
                // User granted access - the permission is now active
                permissionStates[.filesAndFolders] = .granted
                hasRequiredPermissions = true
                HapticFeedbackManager.shared.success()
            } else {
                // User cancelled - still unknown/not granted
                permissionStates[.filesAndFolders] = .unknown
                hasRequiredPermissions = false
            }
            
        case .automation:
            // Open System Preferences to Automation
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
            permissionStates[.automation] = .pending
            
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
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
    case automation = "Automation"
    case notifications = "Notifications"
    
    var icon: String {
        switch self {
        case .filesAndFolders: return "folder.fill"
        case .automation: return "gearshape.2.fill"
        case .notifications: return "bell.fill"
        }
    }
    
    var description: String {
        switch self {
        case .filesAndFolders: return "Access to read and organize your files"
        case .automation: return "Control Finder for seamless integration"
        case .notifications: return "Get notified when organization completes"
        }
    }
    
    var color: Color {
        switch self {
        case .filesAndFolders: return .blue
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
    let onRequest: () -> Void
    
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
                Button("Open Settings") {
                    onRequest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .pending:
                Text("Check Settings")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .unknown:
                Button("Grant") {
                    onRequest()
                }
                .buttonStyle(.onboardingPill)
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

// MARK: - Preview

#Preview {
    PermissionsStepView(hasRequiredPermissions: .constant(false))
}

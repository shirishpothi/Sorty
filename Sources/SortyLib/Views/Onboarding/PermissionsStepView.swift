//
//  PermissionsStepView.swift
//  Sorty
//
//  Permissions step of the onboarding flow
//

import AppKit
import SwiftUI
import UserNotifications

import Permiso

public struct PermissionsStepView: View {
    private let assumeFilesPermissionForUITestsKey = "uitestAssumeFilesAndFoldersPermission"
    @Binding var hasRequiredPermissions: Bool
    @State private var hasAppeared = false
    @State private var permissionStates: [PermissionType: PermissionState] = [:]
    @State private var selectedEducationPermission: PermissionType?
    @EnvironmentObject private var automationManager: AutomationManager

    public init(hasRequiredPermissions: Binding<Bool>) {
        self._hasRequiredPermissions = hasRequiredPermissions
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("Permissions")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(
                        "Sorty can work without extra setup. Grant optional permissions now if you want Finder actions, broader folder access, or system notifications."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What is requested here?")
                            .font(.subheadline.bold())

                        Text(
                            "• **Full Disk Access**: Organize protected folders without repeated prompts\n• **Automation**: Read Finder selections for Finder Integration\n• **Notifications**: Alert you when organization completes"
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

            VStack(spacing: 20) {
                Text("Optional Permissions")
                    .font(.title3.weight(.semibold))

                VStack(spacing: 16) {
                    PermissionRow(
                        type: .fullDiskAccess,
                        state: permissionStates[.fullDiskAccess] ?? .unknown,
                        onExplain: { selectedEducationPermission = .fullDiskAccess },
                        onRequest: { requestPermission(.fullDiskAccess, sourceFrameInScreen: $0) }
                    )

                    PermissionRow(
                        type: .automation,
                        state: permissionStates[.automation] ?? .unknown,
                        onExplain: { selectedEducationPermission = .automation },
                        onRequest: { requestPermission(.automation, sourceFrameInScreen: $0) }
                    )

                    PermissionRow(
                        type: .notifications,
                        state: permissionStates[.notifications] ?? .unknown,
                        onExplain: { selectedEducationPermission = .notifications },
                        onRequest: { requestPermission(.notifications, sourceFrameInScreen: $0) }
                    )
                }
                .frame(maxWidth: 400)

                Text("Folder access is requested when you choose a folder to organize.")
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
            hasRequiredPermissions = true
            checkPermissions()
        }
        .sheet(item: $selectedEducationPermission) { permission in
            PermissionEducationView(pages: [permission]) {
                selectedEducationPermission = nil
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permissions Step")
    }

    private func checkPermissions() {
        if UserDefaults.standard.bool(forKey: assumeFilesPermissionForUITestsKey) {
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

        permissionStates[.fullDiskAccess] = .unknown

        automationManager.checkPermissions(enableChecksIfNeeded: false)
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

enum PermissionType: String, Identifiable {
    case fullDiskAccess = "Full Disk Access"
    case automation = "Automation"
    case notifications = "Notifications"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .fullDiskAccess: return "lock.open.fill"
        case .automation: return "gearshape.2.fill"
        case .notifications: return "bell.fill"
        }
    }

    var description: String {
        switch self {
        case .fullDiskAccess: return "Access protected folders when you choose them"
        case .automation: return "Read Finder selections for Finder Integration"
        case .notifications: return "Get notified when organization completes"
        }
    }

    var color: Color {
        switch self {
        case .fullDiskAccess: return .green
        case .automation: return .orange
        case .notifications: return .purple
        }
    }

    var educationTitle: String {
        switch self {
        case .fullDiskAccess:
            return "Full Disk Access"
        case .automation:
            return "Finder Automation"
        case .notifications:
            return "Notifications"
        }
    }

    var educationDescription: String {
        switch self {
        case .fullDiskAccess:
            return "Lets Sorty organize protected folders you explicitly choose, such as Desktop, Documents, Downloads, or external locations macOS protects."
        case .automation:
            return "Lets Sorty read the current Finder selection for Finder Integration actions. Sorty only asks when you use Finder-driven workflows."
        case .notifications:
            return "Lets Sorty send completion and error alerts through macOS Notification Center. In-app HUD alerts still work without it."
        }
    }

    var educationActionTitle: String {
        switch self {
        case .fullDiskAccess, .automation:
            return "Open System Settings"
        case .notifications:
            return "Enable Notifications"
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
    let onExplain: () -> Void
    let onRequest: (CGRect?) -> Void
    @State private var approvalPulse = false
    @State private var approvalSpin = false

    var body: some View {
        HStack(spacing: 16) {
            permissionIcon

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
                HStack(spacing: 8) {
                    Button {
                        onExplain()
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Show what Sorty asks for")

                    PermissionActionButton(title: "Grant", style: .primary, action: onRequest)
                        .fixedSize()
                }
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
        .onChange(of: state) { _, newState in
            guard newState == .granted else { return }
            playApprovalAnimation()
        }
    }

    private var permissionIcon: some View {
        ZStack {
            Circle()
                .fill(type.color.opacity(state == .granted ? 0.16 : 0.1))
                .frame(width: 44, height: 44)
                .scaleEffect(approvalPulse ? 1.08 : 1)

            Image(systemName: type.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(type.color)
                .scaleEffect(approvalPulse ? 1.08 : 1)
                .rotationEffect(iconRotation)
                .symbolEffect(.bounce, value: approvalPulse)

            if state == .granted {
                Circle()
                    .stroke(type.color.opacity(0.28), lineWidth: 1)
                    .frame(width: 52, height: 52)
                    .scaleEffect(approvalPulse ? 1.12 : 0.86)
                    .opacity(approvalPulse ? 0 : 1)
            }
        }
        .frame(width: 52, height: 52)
        .animation(.spring(response: 0.28, dampingFraction: 0.62), value: approvalPulse)
        .animation(.easeInOut(duration: 0.42), value: approvalSpin)
    }

    private var iconRotation: Angle {
        switch type {
        case .notifications:
            return .degrees(approvalPulse ? -12 : 0)
        case .automation:
            return .degrees(approvalSpin ? 32 : 0)
        case .fullDiskAccess:
            return .degrees(approvalPulse ? -5 : 0)
        }
    }

    private func playApprovalAnimation() {
        approvalSpin.toggle()
        withAnimation(.spring(response: 0.22, dampingFraction: 0.48)) {
            approvalPulse = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.spring(response: 0.26, dampingFraction: 0.66)) {
                approvalPulse = false
            }
        }
    }
}

struct PermissionEducationView: View {
    let pages: [PermissionType]
    let onFinish: () -> Void
    @State private var currentPage = 0
    @State private var previousPage = 0

    private var page: PermissionType {
        pages[min(currentPage, max(pages.count - 1, 0))]
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                educationPage(page)
                    .id(page.id)
                    .transition(.opacity.combined(with: .scale(scale: 1.01)))
            }

            if pages.count > 1 {
                pageIndicator
            }
        }
        .padding(.vertical, 16)
        .frame(width: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.24), value: currentPage)
    }

    private func educationPage(_ permission: PermissionType) -> some View {
        let direction: CGFloat = currentPage >= previousPage ? 1 : -1

        return VStack(spacing: 0) {
            permissionVideoPlaceholder(permission)
                .frame(width: 640, height: 360)
                .blur(radius: currentPage == previousPage ? 0 : 3)
                .offset(x: currentPage == previousPage ? 0 : 10 * direction)

            VStack(spacing: 8) {
                Text(permission.educationTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(permission.educationDescription)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)

                HStack(spacing: 10) {
                    if currentPage > 0 {
                        Button {
                            previousPage = currentPage
                            currentPage -= 1
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                    }

                    Button {
                        if currentPage == pages.count - 1 {
                            onFinish()
                        } else {
                            previousPage = currentPage
                            currentPage += 1
                        }
                    } label: {
                        Label(currentPage == pages.count - 1 ? "Done" : "Continue", systemImage: currentPage == pages.count - 1 ? "checkmark" : "chevron.right")
                    }
                    .buttonStyle(.sortyPrimary(size: .regular))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 10)
            }
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .frame(width: 640)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func permissionVideoPlaceholder(_ permission: PermissionType) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(white: 0.16),
                    permission.color.opacity(0.22),
                    Color(white: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 14) {
                Image(systemName: permission.icon)
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))

                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .foregroundStyle(permission.color)
                    Text("Permission video")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule(style: .continuous))
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentPage ? Color.primary.opacity(0.82) : Color.secondary.opacity(0.28))
                    .frame(width: index == currentPage ? 22 : 7, height: 7)
            }
        }
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
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
                .frame(minWidth: style == .primary ? 74 : 96)
        }
        .buttonStyle(buttonStyle)
        .overlay {
            if style == .primary {
                Color.clear.onboardingBeamBorder(variant: .standard)
            }
        }
        .contentShape(Capsule())
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

    private var buttonStyle: OnboardingPillButtonStyle {
        switch style {
        case .primary:
            return .init()
        case .bordered:
            return .init(isSecondary: true, size: .small)
        }
    }
}

// MARK: - Preview

#Preview {
    PermissionsStepView(hasRequiredPermissions: .constant(false))
}

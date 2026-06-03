//
//  PermissionsStepView.swift
//  Sorty
//
//  Permissions step of the onboarding flow
//

import AppKit
import AVFoundation
import SwiftUI
import UserNotifications

import Permiso

public struct PermissionsStepView: View {
    private let assumeFilesPermissionForUITestsKey = "uitestAssumeFilesAndFoldersPermission"
    @Binding var hasRequiredPermissions: Bool
    @State private var hasAppeared = false
    @State private var permissionStates: [PermissionType: PermissionState] = [:]
    @State private var selectedEducationPermission: PermissionType?
    @State private var isFullDiskAccessConfirmationPresented = false
    @State private var fullDiskAccessSourceFrameInScreen: CGRect?
    @State private var didOpenFullDiskAccessSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var notificationManager = NotificationManager.shared
    @EnvironmentObject private var automationManager: AutomationManager

    public init(hasRequiredPermissions: Binding<Bool>) {
        self._hasRequiredPermissions = hasRequiredPermissions
    }

    public var body: some View {
        HStack(spacing: 36) {
            VStack(alignment: .leading, spacing: 22) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)

                    Text("Permissions")
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(
                        "Sorty needs Files & Folders access before organizing. Grant optional permissions now if you want Finder actions, broader folder access, or system notifications."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        PrivacyFeatureRow(icon: "folder.fill", text: "Files & Folders is required")
                        PrivacyFeatureRow(icon: "lock.open", text: "Full Disk Access is optional")
                        PrivacyFeatureRow(icon: "gearshape.2", text: "Finder Automation is optional")
                        PrivacyFeatureRow(icon: "bell", text: "Notifications are optional")
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: 350)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -20)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 72)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Grant Access")
                            .font(.title3.weight(.semibold))

                        Text("Choose a folder to continue. Optional permissions can wait.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(grantedPermissionCount) of \(PermissionType.allCases.count) granted")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(grantedPermissionCount == PermissionType.allCases.count ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.07), in: Capsule(style: .continuous))
                }

                PermissionRow(
                    type: .filesAndFolders,
                    state: permissionStates[.filesAndFolders] ?? .unknown,
                    isRequired: true,
                    onExplain: { selectedEducationPermission = .filesAndFolders },
                    onRequest: { requestPermission(.filesAndFolders, sourceFrameInScreen: $0) }
                )

                Text("Optional")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                VStack(spacing: 10) {
                    PermissionRow(
                        type: .fullDiskAccess,
                        state: permissionStates[.fullDiskAccess] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .fullDiskAccess },
                        onRequest: { requestPermission(.fullDiskAccess, sourceFrameInScreen: $0) }
                    )

                    PermissionRow(
                        type: .automation,
                        state: permissionStates[.automation] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .automation },
                        onRequest: { requestPermission(.automation, sourceFrameInScreen: $0) }
                    )

                    PermissionRow(
                        type: .notifications,
                        state: permissionStates[.notifications] ?? .unknown,
                        isRequired: false,
                        onExplain: { selectedEducationPermission = .notifications },
                        onRequest: { requestPermission(.notifications, sourceFrameInScreen: $0) }
                    )
                }

                Text("Files & Folders unlocks Continue after macOS grants access.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: 430)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.trailing, 72)
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : 18)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86).delay(0.12), value: hasAppeared)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86)) {
                hasAppeared = true
            }
            checkPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
        .sheet(item: $selectedEducationPermission) { permission in
            PermissionEducationView(pages: [permission]) {
                selectedEducationPermission = nil
            }
        }
        .alert("Set up Full Disk Access?", isPresented: $isFullDiskAccessConfirmationPresented) {
            Button("Skip for Now", role: .cancel) {
                permissionStates[.fullDiskAccess] = .unknown
                fullDiskAccessSourceFrameInScreen = nil
                didOpenFullDiskAccessSettings = false
            }

            Button("Open System Settings") {
                openFullDiskAccessSettings()
            }
        } message: {
            Text("Full Disk Access is optional and only needed for protected folders. macOS may relaunch Sorty after you turn it on, so it is safe to finish onboarding first and enable this later in Settings.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Permissions Step")
    }

    private func checkPermissions() {
        if UserDefaults.standard.bool(forKey: assumeFilesPermissionForUITestsKey) {
            hasRequiredPermissions = true
        }
        permissionStates[.filesAndFolders] = hasRequiredPermissions ? .granted : .unknown

        Task { @MainActor in
            await notificationManager.checkNotificationPermission()
            permissionStates[.notifications] = notificationState(for: notificationManager.notificationPermissionStatus)
        }

        permissionStates[.fullDiskAccess] = fullDiskAccessState()

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

    private var grantedPermissionCount: Int {
        PermissionType.allCases.filter { permissionStates[$0] == .granted }.count
    }

    private func requestPermission(_ type: PermissionType, sourceFrameInScreen: CGRect?) {
        HapticFeedbackManager.shared.tap()

        switch type {
        case .filesAndFolders:
            requestFilesAndFoldersPermission()

        case .fullDiskAccess:
            fullDiskAccessSourceFrameInScreen = sourceFrameInScreen
            isFullDiskAccessConfirmationPresented = true

        case .automation:
            permissionStates[.automation] = .pending
            automationManager.requestAutomationPermissionCheck()
            permissionStates[.automation] = permissionState(for: automationManager.automationStatus)

            if automationManager.automationStatus == .denied {
                openAutomationSettings()
            }

        case .notifications:
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
                }
            }
        }
    }

    private func openFullDiskAccessSettings() {
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

    private func fullDiskAccessState() -> PermissionState {
        if canReadProtectedFullDiskAccessLocation() {
            return .restartRequired
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

    private func openAutomationSettings() {
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for urlString in candidateURLs {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
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
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]

        for urlString in candidateURLs {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    private func requestFilesAndFoldersPermission() {
        permissionStates[.filesAndFolders] = .pending

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose any folder you want Sorty to organize."
        panel.prompt = "Grant Access"

        if panel.runModal() == .OK, let url = panel.url {
            _ = url.startAccessingSecurityScopedResource()
            hasRequiredPermissions = true
            permissionStates[.filesAndFolders] = .granted
            HapticFeedbackManager.shared.success()
        } else {
            hasRequiredPermissions = false
            permissionStates[.filesAndFolders] = .unknown
        }
    }
}

// MARK: - Supporting Types

enum PermissionType: String, CaseIterable, Identifiable {
    case filesAndFolders = "Files & Folders"
    case fullDiskAccess = "Full Disk Access"
    case automation = "Automation"
    case notifications = "Notifications"

    var id: String { rawValue }

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
        case .filesAndFolders: return "Choose a folder so Sorty can organize files"
        case .fullDiskAccess: return "Optional for protected folders; may relaunch Sorty"
        case .automation: return "Read Finder selections for Finder Integration"
        case .notifications: return "Get notified when organization completes"
        }
    }

    func description(for state: PermissionState) -> String {
        if self == .fullDiskAccess, state == .restartRequired {
            return "Full Disk Access is on. Restart Sorty to use it."
        }

        return description
    }

    var color: Color {
        switch self {
        case .filesAndFolders: return .blue
        case .fullDiskAccess: return .green
        case .automation: return .orange
        case .notifications: return .purple
        }
    }

    var educationTitle: String {
        switch self {
        case .filesAndFolders:
            return "Files & Folders"
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
        case .filesAndFolders:
            return "Lets Sorty access folders you explicitly choose with the macOS picker. This is required before Sorty can scan and organize files."
        case .fullDiskAccess:
            return "Lets Sorty organize protected folders you explicitly choose, such as Desktop, Documents, Downloads, or external locations macOS protects. macOS may relaunch Sorty after this is enabled, so it is usually better to finish onboarding first."
        case .automation:
            return "Lets Sorty read the current Finder selection for Finder Integration actions. Sorty only asks when you use Finder-driven workflows."
        case .notifications:
            return "Lets Sorty send completion and error alerts through macOS Notification Center. In-app HUD alerts still work without it."
        }
    }

    var educationActionTitle: String {
        switch self {
        case .filesAndFolders:
            return "Choose Folder"
        case .fullDiskAccess:
            return "Review Restart Note"
        case .automation:
            return "Enable Finder Automation"
        case .notifications:
            return "Enable Notifications"
        }
    }

    var compactActionTitle: String {
        switch self {
        case .filesAndFolders:
            return "Choose Folder"
        case .fullDiskAccess:
            return "Review"
        case .automation:
            return "Enable"
        case .notifications:
            return "Enable"
        }
    }
}

enum PermissionState {
    case unknown
    case pending
    case granted
    case restartRequired
    case denied

    var title: String {
        switch self {
        case .unknown: return "Not granted"
        case .pending: return "Check Settings"
        case .granted: return "Granted"
        case .restartRequired: return "Restart Sorty"
        case .denied: return "Needs Attention"
        }
    }

    func title(for type: PermissionType) -> String {
        guard self == .pending else { return title }

        switch type {
        case .filesAndFolders:
            return "Choosing Folder"
        case .fullDiskAccess:
            return "Finish in Settings"
        case .automation:
            return "Requesting"
        case .notifications:
            return "Enabling"
        }
    }

    var symbol: String {
        switch self {
        case .unknown: return "circle"
        case .pending: return "arrow.clockwise"
        case .granted: return "checkmark"
        case .restartRequired: return "arrow.clockwise"
        case .denied: return "exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .unknown: return .secondary
        case .pending: return .orange
        case .granted: return .green
        case .restartRequired: return .blue
        case .denied: return .red
        }
    }
}

struct PermissionRow: View {
    let type: PermissionType
    let state: PermissionState
    let isRequired: Bool
    let onExplain: () -> Void
    let onRequest: (CGRect?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var grantFlash = false

    var body: some View {
        HStack(spacing: 14) {
            permissionIcon

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(type.rawValue)
                        .font(.headline)

                    if isRequired {
                        Text("Required")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(SortyDesignSystem.Colors.resolvedAccent.opacity(0.12), in: Capsule(style: .continuous))
                    }
                }

                Text(type.description(for: state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            trailingControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(rowFill)
        )
        .systemLiquidGlassBackground(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: state == .granted || grantFlash ? 1.2 : 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: isHovering ? 12 : 7, x: 0, y: isHovering ? 6 : 3)
        .scaleEffect(grantFlash ? 1.012 : (isHovering ? 1.006 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.86), value: isHovering)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: grantFlash)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: state) { _, newState in
            guard newState == .granted else { return }
            playApprovalAnimation()
        }
        .accessibilityElement(children: .contain)
    }

    private var iconTint: Color {
        state == .granted || state == .restartRequired ? state.tint : type.color
    }

    private var rowFill: Color {
        if state == .granted {
            return Color.green.opacity(colorScheme == .dark ? 0.12 : 0.08)
        }

        return Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? (isHovering ? 0.82 : 0.68) : (isHovering ? 0.94 : 0.82))
    }

    private var rowStroke: Color {
        if grantFlash || state == .granted {
            return Color.green.opacity(grantFlash ? 0.72 : 0.34)
        }

        if isHovering {
            return type.color.opacity(0.30)
        }

        return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
    }

    private var permissionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(iconTint.opacity(state == .granted ? 0.18 : 0.13))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(iconTint.opacity(state == .granted ? 0.28 : 0.18), lineWidth: 1)
                }

            Image(systemName: state == .granted ? "checkmark" : type.icon)
                .font(.system(size: state == .granted ? 18 : 19, weight: .semibold))
                .foregroundStyle(iconTint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 46, height: 46)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch state {
        case .granted, .pending, .restartRequired:
            statusChip
        case .denied:
            PermissionActionButton(title: deniedActionTitle, style: .bordered, action: onRequest)
                .fixedSize()
        case .unknown:
            HStack(spacing: 8) {
                Button {
                    onExplain()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Show what Sorty asks for")
                .accessibilityLabel("Learn about \(type.rawValue)")

                PermissionActionButton(
                    title: type.compactActionTitle,
                    style: isRequired ? .primary : .bordered,
                    action: onRequest
                )
                .fixedSize()
            }
        }
    }

    private var deniedActionTitle: String {
        switch type {
        case .automation:
            return "Enable in Settings"
        case .notifications:
            return "Enable in Settings"
        default:
            return type.compactActionTitle
        }
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Image(systemName: state.symbol)
                .font(.system(size: 11, weight: .bold))
            Text(state.title(for: type))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(state.tint.opacity(0.12), in: Capsule(style: .continuous))
        .accessibilityLabel(state.title(for: type))
    }

    private func playApprovalAnimation() {
        HapticFeedbackManager.shared.success()
        guard !reduceMotion else { return }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            grantFlash = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.easeOut(duration: 0.24)) {
                grantFlash = false
            }
        }
    }
}

struct PermissionEducationView: View {
    let pages: [PermissionType]
    let onFinish: () -> Void
    @State private var currentPage = 0

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
        .animation(.easeOut(duration: 0.18), value: currentPage)
    }

    private func educationPage(_ permission: PermissionType) -> some View {
        VStack(spacing: 0) {
            permissionHero(permission)
                .frame(width: 640, height: 360)

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

    @ViewBuilder
    private func permissionHero(_ permission: PermissionType) -> some View {
        if let resourceName = permission.demoVideoResourceName {
            PermissionDemoVideoView(permission: permission, resourceName: resourceName)
        } else {
            permissionExplanationHero(permission)
        }
    }

    private func permissionExplanationHero(_ permission: PermissionType) -> some View {
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
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(permission.color)
                    Text(permission.educationTitle)
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

private struct PermissionDemoVideoView: View {
    let permission: PermissionType
    let resourceName: String

    var body: some View {
        ZStack {
            Color.black

            if let videoURL {
                LoopingPermissionVideoView(url: videoURL)
            } else {
                permissionDemoFallback
            }
        }
        .accessibilityLabel("\(permission.educationTitle) permission demo video")
    }

    private var videoURL: URL? {
        SortyResources.bundle.url(forResource: resourceName, withExtension: "mp4")
    }

    private var permissionDemoFallback: some View {
        VStack(spacing: 14) {
            Image(systemName: permission.icon)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))

            Text(permission.educationTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule(style: .continuous))
        }
    }
}

private extension PermissionType {
    var demoVideoResourceName: String? {
        switch self {
        case .filesAndFolders:
            return "files-and-folders-demo"
        case .fullDiskAccess:
            return "full-disk-access-demo"
        case .automation:
            return "automation-demo"
        case .notifications:
            return nil
        }
    }
}

private struct LoopingPermissionVideoView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        context.coordinator.configure(url: url, playerLayer: view.playerLayer)
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        context.coordinator.configure(url: url, playerLayer: nsView.playerLayer)
    }

    static func dismantleNSView(_ nsView: PlayerLayerView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.playerLayer.player = nil
    }

    final class Coordinator {
        private var currentURL: URL?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?

        func configure(url: URL, playerLayer: AVPlayerLayer) {
            if currentURL == url, let player {
                playerLayer.player = player
                player.play()
                return
            }

            let queuePlayer = AVQueuePlayer()
            queuePlayer.isMuted = true
            queuePlayer.actionAtItemEnd = .none

            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            player = queuePlayer
            currentURL = url
            playerLayer.player = queuePlayer
            queuePlayer.play()
        }

        func stop() {
            player?.pause()
            player?.removeAllItems()
            player = nil
            looper = nil
            currentURL = nil
        }
    }
}

private final class PlayerLayerView: NSView {
    override var wantsUpdateLayer: Bool { true }

    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = playerLayer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            Color.clear.onboardingBeamBorder(variant: style == .primary ? .standard : .info)
        }
        .contentShape(Capsule())
        .background(
            ScreenFrameReader(frameInScreen: $frameInScreen)
                .allowsHitTesting(false)
        )
        .scaleEffect(isHovering && !reduceMotion ? 1.015 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovering)
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
            return .init(size: .small)
        case .bordered:
            return .init(isSecondary: true, size: .small)
        }
    }
}

// MARK: - Preview

#Preview {
    PermissionsStepView(hasRequiredPermissions: .constant(false))
}

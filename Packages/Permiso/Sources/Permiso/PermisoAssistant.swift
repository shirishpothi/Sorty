import AppKit
import Foundation
import UserNotifications

@MainActor
public final class PermisoAssistant {
    public static let shared = PermisoAssistant()

    private var overlayController: OverlayWindowController?
    private var trackingTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var activePanel: PermisoPanel?
    private var pendingSourceFrameInScreen: CGRect?
    private var pendingSourceSnapshot: NSImage?
    private var didPresentCurrentOverlay = false
    private var permissionMonitorTask: Task<Void, Never>?

    public init() {}

    public func present(
        panel: PermisoPanel,
        hostApp: PermisoHostApp = .current(),
        sourceFrameInScreen: CGRect? = nil,
        onCancel: @escaping () -> Void = {},
        onMissingApp: @escaping () -> Void = {},
        onPermissionGranted: (() -> Void)? = nil
    ) {
        permissionMonitorTask?.cancel()
        permissionMonitorTask = nil
        activePanel = panel
        pendingSourceFrameInScreen = sourceFrameInScreen
        pendingSourceSnapshot = sourceFrameInScreen.flatMap {
            InProcessScreenSnapshot.capture(screenRect: $0)
        }
        didPresentCurrentOverlay = false
        overlayController = OverlayWindowController(
            hostApp: hostApp,
            panel: panel,
            onBack: { [weak self] in
                self?.cancelAndReturnToApp(hostApp: hostApp, onCancel: onCancel)
            },
            onDrop: { [weak self] in
                self?.dismiss()
            },
            onMissingApp: { [weak self] in
                self?.cancelAndReturnToApp(hostApp: hostApp, onCancel: onMissingApp)
            }
        )
        NSWorkspace.shared.open(panel.settingsURL)
        startTracking()
        if panel == .notifications, let onPermissionGranted {
            startNotificationPermissionMonitor(
                hostApp: hostApp,
                onPermissionGranted: onPermissionGranted
            )
        }
    }

    public func dismiss() {
        stopTracking()
        overlayController?.close()
        clearActiveRequest()
    }

    private func cancelAndReturnToApp(hostApp: PermisoHostApp, onCancel: @escaping () -> Void) {
        returnToApp(hostApp: hostApp, completion: onCancel)
    }

    private func returnToApp(hostApp: PermisoHostApp, completion: @escaping () -> Void) {
        stopTracking()
        permissionMonitorTask?.cancel()
        permissionMonitorTask = nil
        let controller = overlayController
        controller?.returnToSource { [weak self] in
            NSWorkspace.shared.open(hostApp.bundleURL)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            completion()
            controller?.close()
            self?.clearActiveRequest()
        }
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func startNotificationPermissionMonitor(
        hostApp: PermisoHostApp,
        onPermissionGranted: @escaping () -> Void
    ) {
        permissionMonitorTask = Task { @MainActor [weak self] in
            let notificationCenter = UNUserNotificationCenter.current()

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                var status = await notificationCenter.notificationSettings().authorizationStatus
                if status == .notDetermined {
                    let granted = (try? await notificationCenter.requestAuthorization(
                        options: [.alert, .sound, .badge]
                    )) == true
                    if granted {
                        status = .authorized
                    }
                }
                guard status == .authorized || status == .provisional else { continue }

                self?.returnToApp(hostApp: hostApp, completion: onPermissionGranted)
                return
            }
        }
    }

    private func clearActiveRequest() {
        overlayController = nil
        activePanel = nil
        pendingSourceFrameInScreen = nil
        pendingSourceSnapshot = nil
        didPresentCurrentOverlay = false
    }

    private func startTracking() {
        trackingTimer?.invalidate()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.refreshPosition()
            }
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPosition()
            }
        }
        refreshPosition()
    }

    private func refreshPosition() {
        guard let snapshot = SettingsWindowLocator.frontmostWindow() else {
            overlayController?.hide()
            return
        }
        if didPresentCurrentOverlay {
            overlayController?.updatePosition(
                with: snapshot.frame, visibleFrame: snapshot.visibleFrame)
            return
        }

        overlayController?.present(
            from: pendingSourceFrameInScreen,
            sourceSnapshot: pendingSourceSnapshot,
            settingsFrame: snapshot.frame,
            visibleFrame: snapshot.visibleFrame
        )
        didPresentCurrentOverlay = true
    }
}

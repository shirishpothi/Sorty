import AppKit
import Foundation

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

    public init() {}

    public func present(
        panel: PermisoPanel,
        hostApp: PermisoHostApp = .current(),
        sourceFrameInScreen: CGRect? = nil,
        onCancel: @escaping () -> Void = {}
    ) {
        activePanel = panel
        pendingSourceFrameInScreen = sourceFrameInScreen
        pendingSourceSnapshot = sourceFrameInScreen.flatMap {
            InProcessScreenSnapshot.capture(screenRect: $0)
        }
        didPresentCurrentOverlay = false
        overlayController = OverlayWindowController(hostApp: hostApp, panel: panel) { [weak self] in
            self?.cancelAndReturnToApp(hostApp: hostApp, onCancel: onCancel)
        }
        NSWorkspace.shared.open(panel.settingsURL)
        startTracking()
    }

    public func dismiss() {
        stopTracking()
        overlayController?.close()
        clearActiveRequest()
    }

    private func cancelAndReturnToApp(hostApp: PermisoHostApp, onCancel: @escaping () -> Void) {
        stopTracking()
        let controller = overlayController
        controller?.returnToSource { [weak self] in
            NSWorkspace.shared.open(hostApp.bundleURL)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            onCancel()
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

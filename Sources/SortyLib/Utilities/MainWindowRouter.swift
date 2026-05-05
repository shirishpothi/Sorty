import SwiftUI
import AppKit

public enum WindowRoutingUserInfoKey {
    public static let targetSessionID = "targetSessionID"
    public static let deeplinkURLString = "deeplinkURLString"
}

public extension Notification.Name {
    static let routeDeeplinkInMainWindow = Notification.Name("SortyRouteDeeplinkInMainWindow")
    static let presentSteeringPromptsInMainWindow = Notification.Name("SortyPresentSteeringPromptsInMainWindow")
}

public extension Notification {
    func targetsWindowSession(_ sessionID: UUID) -> Bool {
        guard let targetSessionID = userInfo?[WindowRoutingUserInfoKey.targetSessionID] as? String else {
            return true
        }

        return targetSessionID == sessionID.uuidString
    }

    var routedDeeplinkURL: URL? {
        guard let urlString = userInfo?[WindowRoutingUserInfoKey.deeplinkURLString] as? String else {
            return nil
        }

        return URL(string: urlString)
    }
}

@MainActor
public final class MainWindowRouter {
    public static let shared = MainWindowRouter()

    private final class SessionRecord {
        weak var window: NSWindow?
        var lastFocusedAt: Date

        init(window: NSWindow, lastFocusedAt: Date = Date()) {
            self.window = window
            self.lastFocusedAt = lastFocusedAt
        }
    }

    private var sessions: [UUID: SessionRecord] = [:]

    private init() {}

    public static func scopedUserInfo(
        _ userInfo: [AnyHashable: Any] = [:],
        targetSessionID: UUID
    ) -> [AnyHashable: Any] {
        var scopedUserInfo = userInfo
        scopedUserInfo[WindowRoutingUserInfoKey.targetSessionID] = targetSessionID.uuidString
        return scopedUserInfo
    }

    public func register(window: NSWindow, for sessionID: UUID) {
        pruneClosedSessions()
        if let record = sessions[sessionID] {
            record.window = window
            if window.isKeyWindow || window.isMainWindow {
                record.lastFocusedAt = Date()
            }
            return
        }

        sessions[sessionID] = SessionRecord(window: window)
    }

    public func unregister(sessionID: UUID) {
        sessions.removeValue(forKey: sessionID)
    }

    public func markFocused(sessionID: UUID) {
        pruneClosedSessions()
        sessions[sessionID]?.lastFocusedAt = Date()
    }

    public var preferredSessionID: UUID? {
        pruneClosedSessions()

        if let keyWindowID = sessions.first(where: { $0.value.window?.isKeyWindow == true })?.key {
            return keyWindowID
        }

        if let mainWindowID = sessions.first(where: { $0.value.window?.isMainWindow == true })?.key {
            return mainWindowID
        }

        return sessions
            .filter { $0.value.window?.isVisible == true }
            .max(by: { lhs, rhs in lhs.value.lastFocusedAt < rhs.value.lastFocusedAt })?
            .key
    }

    @discardableResult
    public func post(name: Notification.Name, userInfo: [AnyHashable: Any] = [:]) -> Bool {
        guard let preferredSessionID else { return false }

        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: Self.scopedUserInfo(userInfo, targetSessionID: preferredSessionID)
        )
        return true
    }

    @discardableResult
    public func routeDeeplink(_ url: URL) -> Bool {
        guard let preferredSessionID else { return false }

        NotificationCenter.default.post(
            name: .routeDeeplinkInMainWindow,
            object: nil,
            userInfo: Self.scopedUserInfo(
                [WindowRoutingUserInfoKey.deeplinkURLString: url.absoluteString],
                targetSessionID: preferredSessionID
            )
        )

        activateWindow(for: preferredSessionID)
        return true
    }

    @discardableResult
    public func activatePreferredWindow() -> Bool {
        guard let preferredSessionID else { return false }
        return activateWindow(for: preferredSessionID)
    }

    @discardableResult
    public func activateWindow(for sessionID: UUID) -> Bool {
        pruneClosedSessions()

        guard let window = sessions[sessionID]?.window else { return false }

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        markFocused(sessionID: sessionID)
        return true
    }

    private func pruneClosedSessions() {
        sessions = sessions.filter { _, record in
            guard let window = record.window else { return false }
            return window.isVisible || window.isMiniaturized || window.isKeyWindow || window.isMainWindow
        }
    }
}

public struct MainWindowSessionTracker: NSViewRepresentable {
    private let sessionID: UUID

    public init(sessionID: UUID) {
        self.sessionID = sessionID
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Task { @MainActor in
                context.coordinator.observe(window: window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            Task { @MainActor in
                context.coordinator.observe(window: window)
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(sessionID: sessionID)
    }

    public final class Coordinator: NSObject {
        private let sessionID: UUID
        private weak var observedWindow: NSWindow?
        private var observations: [NSObjectProtocol] = []

        init(sessionID: UUID) {
            self.sessionID = sessionID
        }

        @MainActor
        func observe(window: NSWindow) {
            guard observedWindow !== window else { return }

            removeObservations()
            observedWindow = window
            MainWindowRouter.shared.register(window: window, for: sessionID)

            let notificationCenter = NotificationCenter.default
            let sessionID = sessionID

            observations.append(
                notificationCenter.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        MainWindowRouter.shared.markFocused(sessionID: sessionID)
                    }
                }
            )

            observations.append(
                notificationCenter.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        MainWindowRouter.shared.unregister(sessionID: sessionID)
                    }
                }
            )

            if window.isKeyWindow || window.isMainWindow {
                MainWindowRouter.shared.markFocused(sessionID: sessionID)
            }
        }

        private func removeObservations() {
            for observation in observations {
                NotificationCenter.default.removeObserver(observation)
            }
            observations.removeAll()
        }

        deinit {
            let observations = observations
            let sessionID = sessionID

            for observation in observations {
                NotificationCenter.default.removeObserver(observation)
            }

            Task { @MainActor in
                MainWindowRouter.shared.unregister(sessionID: sessionID)
            }
        }
    }
}

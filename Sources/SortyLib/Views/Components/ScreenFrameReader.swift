import AppKit
import SwiftUI

struct ScreenFrameReader: NSViewRepresentable {
    @Binding var frameInScreen: CGRect

    func makeCoordinator() -> Coordinator {
        Coordinator(frameInScreen: $frameInScreen)
    }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onFrameChange = context.coordinator.update(frameInScreen:)
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.onFrameChange = context.coordinator.update(frameInScreen:)
        nsView.reportFrameIfNeeded()
    }

    @MainActor
    final class Coordinator {
        private var frameInScreen: Binding<CGRect>

        init(frameInScreen: Binding<CGRect>) {
            self.frameInScreen = frameInScreen
        }

        func update(frameInScreen: CGRect) {
            guard self.frameInScreen.wrappedValue != frameInScreen else { return }
            DispatchQueue.main.async { @MainActor [weak self] in
                self?.frameInScreen.wrappedValue = frameInScreen
            }
        }
    }
}

final class ProbeView: NSView {
    var onFrameChange: ((CGRect) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installObservers()
        reportFrameIfNeeded()
    }

    override func layout() {
        super.layout()
        reportFrameIfNeeded()
    }

    deinit {
        removeObservers()
    }

    func reportFrameIfNeeded() {
        guard let window, !bounds.isEmpty else { return }
        let frameInWindow = convert(bounds, to: nil)
        onFrameChange?(window.convertToScreen(frameInWindow))
    }

    private func installObservers() {
        removeObservers()
        guard let window else { return }
        let notificationCenter = NotificationCenter.default
        let names: [NSNotification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
        ]

        observers = names.map { name in
            notificationCenter.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in
                self?.reportFrameIfNeeded()
            }
        }
    }

    private func removeObservers() {
        let notificationCenter = NotificationCenter.default
        observers.forEach(notificationCenter.removeObserver)
        observers.removeAll()
    }
}

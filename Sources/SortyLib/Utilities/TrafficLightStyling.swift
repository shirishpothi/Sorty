//
//  TrafficLightStyling.swift
//  Sorty
//

import SwiftUI
import AppKit

/// Customizes the standard window traffic light buttons so they show
/// colored border rings (red / yellow / green) when the window is
/// not key, instead of the default plain-gray appearance.
public struct TrafficLightStyling: NSViewRepresentable {
    @SortyHotReload private var hotReload
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.observe(window: window)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {}

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator: NSObject {
        private var observations: [NSObjectProtocol] = []
        private weak var observedWindow: NSWindow?

        func observe(window: NSWindow) {
            guard observedWindow !== window else { return }
            removeObservations()
            observedWindow = window

            let nc = NotificationCenter.default

            observations.append(
                nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.restoreButtons(in: window)
                }
            )

            observations.append(
                nc.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.styleInactiveButtons(in: window)
                }
            )

            if !window.isKeyWindow {
                styleInactiveButtons(in: window)
            }
        }

        private func removeObservations() {
            for obs in observations {
                NotificationCenter.default.removeObserver(obs)
            }
            observations.removeAll()
        }

        deinit {
            removeObservations()
        }

        // MARK: - Styling

        private static let buttonTypes: [(NSWindow.ButtonType, NSColor)] = [
            (.closeButton, NSColor(red: 0.55, green: 0.15, blue: 0.15, alpha: 1)),
            (.miniaturizeButton, NSColor(red: 0.60, green: 0.50, blue: 0.10, alpha: 1)),
            (.zoomButton, NSColor(red: 0.15, green: 0.50, blue: 0.15, alpha: 1)),
        ]

        private func styleInactiveButtons(in window: NSWindow) {
            for (type, borderColor) in Self.buttonTypes {
                guard let button = window.standardWindowButton(type) else { continue }
                let layer = button.layer ?? {
                    button.wantsLayer = true
                    return button.layer!
                }()
                layer.cornerRadius = button.bounds.height / 2
                layer.borderWidth = 1.0
                layer.borderColor = borderColor.cgColor
            }
        }

        private func restoreButtons(in window: NSWindow) {
            for (type, _) in Self.buttonTypes {
                guard let button = window.standardWindowButton(type) else { continue }
                button.layer?.borderWidth = 0
                button.layer?.borderColor = nil
            }
        }
    }
}

extension View {
    /// Adds colored border rings to the window's traffic light buttons
    /// when the window is inactive.
    public func trafficLightInactiveBorders() -> some View {
        background(TrafficLightStyling().frame(width: 0, height: 0))
    }
}

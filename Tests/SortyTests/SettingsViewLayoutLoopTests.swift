import XCTest
@testable import SortyLib

#if canImport(AppKit)
import AppKit
import SwiftUI

@MainActor
final class SettingsViewLayoutLoopTests: XCTestCase {
    func testSettingsViewRendersAtSmallAndLargeSizesWithoutCrashing() {
        _ = NSApplication.shared

        let settingsViewModel = SettingsViewModel()
        let personaManager = PersonaManager()
        let appState = AppState()

        let rootView = SettingsView()
            .environmentObject(settingsViewModel)
            .environmentObject(personaManager)
            .environmentObject(appState)

        // Two sizes that historically trigger AppKit/SwiftUI constraint churn.
        let sizes: [CGSize] = [
            CGSize(width: 700, height: 500),
            CGSize(width: 1400, height: 900)
        ]

        // Use an offscreen hosting view. Creating NSWindow in `swift test` can be unstable
        // (no real app lifecycle); resizing the hosting view still exercises SwiftUI layout.
        let hostingView = NSHostingView(rootView: rootView)
        let container = NSView(frame: .zero)
        container.addSubview(hostingView)

        for size in sizes {
            autoreleasepool {
                container.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
                hostingView.frame = container.bounds

                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))

                // Shrink and expand to catch size-dependent feedback loops.
                container.frame = NSRect(x: 0, y: 0, width: size.width * 0.9, height: size.height * 0.9)
                hostingView.frame = container.bounds
                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))

                container.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
                hostingView.frame = container.bounds
                hostingView.needsLayout = true
                hostingView.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            }
        }
    }
}
#endif

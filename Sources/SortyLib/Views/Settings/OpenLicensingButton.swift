import SwiftUI

struct OpenLicensingButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @State private var isHovering = false

    let title: String
    var size: ControlSize

    init(title: String = "Upgrade", size: ControlSize = .small) {
        self.title = title
        self.size = size
    }

    var body: some View {
        Button(title, systemImage: "sparkles", action: openLicensing)
            .buttonStyle(.onboardingPill(isSecondary: false, size: size))
            .scaleEffect(isHovering && !reduceMotion ? 1.03 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.84), value: isHovering)
            .onHover { hovering in
                if hovering && !isHovering {
                    HapticFeedbackManager.shared.selection()
                }
                isHovering = hovering
            }
    }

    private func openLicensing() {
        HapticFeedbackManager.shared.tap()
        appState.openSettingsWindow(section: .licensing)
    }
}

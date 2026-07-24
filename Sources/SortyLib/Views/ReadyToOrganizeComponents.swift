import SwiftUI

struct ReadyToOrganizeTitle: View {
    let mode: OrganizationMode

    var body: some View {
        VStack(spacing: 6) {
            Text("Ready to \(mode.actionVerb)")
                .font(.title2.weight(.semibold))
            Text(LocalizedStringKey(mode.description))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct ReadyToOrganizeStartButton: View {
    let mode: OrganizationMode
    let isConnecting: Bool
    let hasAppeared: Bool
    let reduceMotion: Bool
    let compression: CGFloat
    let onStart: () -> Void

    private var horizontalScale: CGFloat {
        1 + compression * 0.025
    }

    private var verticalScale: CGFloat {
        1 - compression * 0.045
    }

    private var helpText: String {
        isConnecting
            ? "Connecting to AI provider. Start is enabled when connection is ready."
            : "Start \(mode.gerund) files using your current settings"
    }

    var body: some View {
        Button(action: onStart) {
            ReadyToOrganizeStartLabel(
                actionVerb: mode.actionVerb,
                isConnecting: isConnecting
            )
        }
        .buttonStyle(.metalFxPrimary(isPaused: isConnecting, usesSubtleIdleBeam: true))
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: [])
        .disabled(isConnecting)
        .scaleEffect(x: horizontalScale, y: verticalScale, anchor: .center)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 10)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.45).delay(0.22),
            value: hasAppeared
        )
        .help(helpText)
        .accessibilityIdentifier("StartOrganizationButton")
        .accessibilityLabel(isConnecting ? "Connecting to provider" : "Start \(mode.gerund)")
        .accessibilityHint(isConnecting ? "Please wait until connection completes" : "Press Enter to start")
        .accessibilityValue(isConnecting ? "Connecting" : "Ready")
        .accessibilityAddTraits(.isButton)
    }
}

private struct ReadyToOrganizeStartLabel: View {
    let actionVerb: String
    let isConnecting: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isConnecting {
                SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    .frame(width: 12, height: 12)
                Text("Connecting...")
            } else {
                Image(systemName: "play.fill")
                    .font(.caption)
                    .accessibilityHidden(true)
                Text("Start \(actionVerb)")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ReadyToOrganizeKeyboardHint: View {
    let actionVerb: String
    let isConnecting: Bool
    let hasAppeared: Bool
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("⏎")
                .font(.caption2.weight(.medium))
            Text(isConnecting ? "Waiting..." : actionVerb)
                .font(.caption2)
        }
        .foregroundStyle(.quaternary)
        .opacity(hasAppeared ? 1 : 0)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.45).delay(0.28),
            value: hasAppeared
        )
        .accessibilityHidden(true)
    }
}

//
//  CompletionStepView.swift
//  Sorty
//
//  Completion step of the onboarding flow
//

import AVFoundation
import SwiftUI

@MainActor
private enum CompletionPalette {
    static var accent: Color { SortyDesignSystem.Colors.resolvedAccent }
    static let softRose = Color(red: 1.0, green: 0.48, blue: 0.58)
    static let deepRose = Color(red: 0.42, green: 0.19, blue: 0.25)
    static let shadowRose = Color(red: 0.22, green: 0.10, blue: 0.14)
}

// MARK: - Completion Reveal Blob

/// A vibrant gradient blob that expands from center for the completion celebration
private struct CompletionRevealBlob: View {
    let scale: CGFloat
    let opacity: Double
    @State private var colorPhase: Double = 0

    var body: some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            CompletionPalette.accent.opacity(0.30),
                            CompletionPalette.softRose.opacity(0.18),
                            CompletionPalette.deepRose.opacity(0.08),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 500)
                .blur(radius: 60)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            CompletionPalette.softRose.opacity(0.18),
                            CompletionPalette.accent.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 450, height: 400)
                .offset(x: 30 * sin(colorPhase), y: -20 * cos(colorPhase))
                .blur(radius: 50)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            CompletionPalette.accent.opacity(0.16),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .blur(radius: 30)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                colorPhase = .pi * 2
            }
        }
    }
}

// MARK: - Completion Glow Ring

/// A pulsing glow ring behind the checkmark icon during reveal
private struct CompletionGlowRing: View {
    let isActive: Bool
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        CompletionPalette.softRose.opacity(0.86),
                        CompletionPalette.accent.opacity(0.78),
                        CompletionPalette.deepRose.opacity(0.46),
                        CompletionPalette.softRose.opacity(0.86)
                    ],
                    center: .center
                ),
                lineWidth: 3
            )
            .frame(width: 140, height: 140)
            .scaleEffect(isActive ? pulseScale : 0.5)
            .opacity(isActive ? 0.6 : 0)
            .blur(radius: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.15
                }
            }
    }
}

// MARK: - Completion Step View

public struct CompletionStepView: View {
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var codexAuth: CodexCLIAuthManager
    @ObservedObject private var copilotAuth = GitHubCopilotAuthManager.shared

    let onFinish: () -> Void

    // Entry animation states
    @State private var revealScale: CGFloat = 0.05
    @State private var revealOpacity: Double = 0
    @State private var backgroundRevealed = false
    @State private var hasAppeared = false
    @State private var showGlowRing = false
    @State private var showParticles = false
    @State private var tipsAppeared = false
    @State private var animationTask: Task<Void, Never>?

    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioFadeTask: Task<Void, Never>?
    @State private var readinessState: ReadinessState = .idle

    // Exit animation states
    @State private var exitTriggered = false
    @State private var contentDismissed = false

    private enum ReadinessState: Equatable {
        case idle
        case checking
        case failed(String)
    }

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            CompletionContrastBackdrop()
                .allowsHitTesting(false)

            CompletionRevealBlob(scale: revealScale, opacity: revealOpacity)
                .allowsHitTesting(false)

            if showParticles {
                ZStack {
                    ForEach(0..<7, id: \.self) { i in
                        FloatingParticle(
                            delay: Double(i) * 0.4,
                            size: CGFloat.random(in: 3...6),
                            xPosition: CGFloat.random(in: -200...200)
                        )
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            VStack(spacing: 22) {
                ZStack {
                    CompletionGlowRing(isActive: showGlowRing)

                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(
                                CompletionPalette.softRose.opacity(0.18 - Double(index) * 0.04),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(140 + index * 30), height: CGFloat(140 + index * 30))
                            .scaleEffect(hasAppeared ? 1.2 : 0.8)
                            .opacity(hasAppeared ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.3),
                                value: hasAppeared
                            )
                    }

                    Circle()
                        .fill(CompletionPalette.shadowRose.opacity(0.30))
                        .frame(width: 118, height: 118)

                    Circle()
                        .fill(CompletionPalette.softRose)
                        .frame(width: 72, height: 72)

                    Image(systemName: "checkmark")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(CompletionPalette.deepRose.opacity(0.92))
                        .symbolEffect(.bounce, value: hasAppeared)
                }
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.3)
                .animation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                // Exit: scale down and fade
                .scaleEffect(contentDismissed ? 0.8 : 1.0)
                .opacity(contentDismissed ? 0 : 1)
                VStack(spacing: 10) {
                    Text("Ready to Organize")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 20)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.2), value: hasAppeared)

                    Text("Drop in a folder, preview the plan, and undo anything you change.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 420)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 15)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.4), value: hasAppeared)
                }
                .opacity(contentDismissed ? 0 : 1)
                .offset(y: contentDismissed ? 30 : 0)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    QuickTipRow(icon: "folder.badge.plus", text: "Drag a folder")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.6), value: tipsAppeared)

                    QuickTipRow(icon: "keyboard", text: "Press \u{2318}O")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.8), value: tipsAppeared)

                    QuickTipRow(icon: "arrow.uturn.backward", text: "Undo changes")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(1.0), value: tipsAppeared)

                    QuickTipRow(icon: "gearshape", text: "Tune settings")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(1.2), value: tipsAppeared)
                }
                .frame(maxWidth: 430)
                .opacity(contentDismissed ? 0 : 1)
                .offset(y: contentDismissed ? 40 : 0)

                Button {
                    verifyAndFinish()
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Using Sorty")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.onboardingPill(size: .large))
                .onboardingBeamBorder(variant: .featured, active: readinessState != .checking)
                .keyboardShortcut(.defaultAction)
                .disabled(readinessState == .checking)
                .opacity(tipsAppeared && !contentDismissed ? 1 : 0)
                .offset(y: tipsAppeared ? (contentDismissed ? 50 : 0) : 20)
                .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(1.4), value: tipsAppeared)
                .accessibilityIdentifier("OnboardingCompleteButton")

                if case .failed(let message) = readinessState {
                    completionFailureCard(message: message)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityIdentifier("OnboardingCompletionHealthError")
                }
            }
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -6)
        }
        .onAppear {
            startRevealSequence()
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            fadeOutAndStopAudio(duration: 0.25)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion Step")
    }

    // MARK: - Reveal Sequence

    private func startRevealSequence() {
        // Play audio immediately
        playFinalOnboardingSound()

        // Phase 1: Gradient blob reveal (0 - 1.0s)
        withAnimation(.easeOut(duration: 1.0)) {
            revealScale = 1.2
            revealOpacity = 1.0
        }

        // Phase 2+: async sequence stored for cancellation on disappear
        animationTask = Task { @MainActor in
            // Phase 2: Background fades in, blob fades/expands (0.5s after start)
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 1.2)) {
                backgroundRevealed = true
                revealOpacity = 0.3
                revealScale = 1.5
            }

            // Phase 3: Checkmark + glow ring appear (0.6s after start)
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
                hasAppeared = true
                showGlowRing = true
            }

            // Play a subtle system sound as the checkmark appears
            if let sound = NSSound(named: "Glass") {
                sound.volume = 0.15
                sound.play()
            }

            // Phase 4: Particles + tips stagger in (0.9s after start)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeIn(duration: 0.8)) {
                showParticles = true
            }

            withAnimation {
                tipsAppeared = true
            }
        }
    }

    // MARK: - Audio

    private func playFinalOnboardingSound() {
        audioFadeTask?.cancel()
        audioFadeTask = nil

        let soundURL: URL? = {
            if let url = SortyResources.finalOnboardingSoundURL() {
                return url
            }
            if let url = Bundle.main.url(forResource: "Final Onboarding", withExtension: "wav") {
                return url
            }
            return nil
        }()

        guard let url = soundURL else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0.3
            player.play()
            audioPlayer = player
        } catch {
            print("[CompletionStepView] Failed to play Final Onboarding sound: \(error)")
        }
    }

    private func fadeOutAndStopAudio(duration: TimeInterval) {
        audioFadeTask?.cancel()

        guard let player = audioPlayer else { return }

        player.setVolume(0, fadeDuration: duration)
        audioFadeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }

            player.stop()
            audioPlayer = nil
            audioFadeTask = nil
        }
    }

    // MARK: - Exit Transition

    @ViewBuilder
    private func completionFailureCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider check failed")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Text("Retry now, or skip verification and land in provider setup repair before your first organization.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Retry") {
                    verifyAndFinish()
                }
                .buttonStyle(.sortyProminent)
                .controlSize(.small)
                .accessibilityIdentifier("OnboardingCompletionRetryButton")

                Button("Skip for Now") {
                    skipVerificationAndFinish()
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.small)
                .accessibilityIdentifier("OnboardingCompletionSkipButton")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
        )
    }

    private var providerSetupStatus: ProviderSetupStatus {
        OnboardingSetupValidator.providerStatus(
            context: ProviderSetupContext(
                config: settingsViewModel.config,
                isGitHubCopilotAuthenticated: copilotAuth.isAuthenticated,
                isCodexAuthenticated: codexAuth.isAuthenticated,
                isCodexInstalled: codexAuth.isCodexInstalled,
                isAppleFoundationModelAvailable: settingsViewModel.isAppleModelAvailable,
                appleFoundationModelStatus: settingsViewModel.appleModelStatus
            )
        )
    }

    private func verifyAndFinish() {
        let configurationStatus = providerSetupStatus
        guard configurationStatus.isReady else {
            readinessState = .failed(configurationStatus.message)
            HapticFeedbackManager.shared.error()
            return
        }

        // Start the transition immediately — the previous flow blocked on a
        // network round-trip (`testConnection()`) before fading out, which
        // made "Start Using Sorty" feel sluggish/laggy. We now fire the
        // verification in the background; if it fails, the main app surfaces
        // the issue through the existing setup-repair channel.
        readinessState = .idle
        startTransition()

        let viewModel = settingsViewModel
        let state = appState
        Task { @MainActor in
            do {
                try await viewModel.testConnection()
                state.clearSetupRepairState()
            } catch {
                state.startSetupRepair(
                    message: "Sorty could not verify \(viewModel.config.provider.displayName). "
                        + error.localizedDescription,
                    navigateToSettings: false
                )
            }
        }
    }

    private func skipVerificationAndFinish() {
        appState.startSetupRepair(
            message: "Sorty could not verify \(settingsViewModel.config.provider.displayName) during onboarding. Finish provider setup in Settings before organizing files.",
            navigateToSettings: true
        )
        readinessState = .idle
        startTransition()
    }

    private func startTransition() {
        guard !exitTriggered else { return }
        exitTriggered = true
        HapticFeedbackManager.shared.success()
        fadeOutAndStopAudio(duration: 0.45)

        // Fade out all content smoothly, but hand off quickly so the main
        // organize page can start rendering while the old frame is still
        // visually settling.
        withAnimation(.easeInOut(duration: 0.24)) {
            contentDismissed = true
            backgroundRevealed = false
            showParticles = false
            showGlowRing = false
            revealOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            onFinish()
        }
    }
}

private struct CompletionContrastBackdrop: View {
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).opacity(0.38)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    CompletionPalette.softRose.opacity(0.18),
                    CompletionPalette.accent.opacity(0.08),
                    Color.clear
                ],
                center: UnitPoint(x: 0.50, y: 0.42),
                startRadius: 20,
                endRadius: 520
            )
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.00),
                        .init(color: Color.black.opacity(0.48), location: 0.36),
                        .init(color: Color.black, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 192)

                Color.black
            }
        }
        .ignoresSafeArea()
    }
}

struct QuickTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CompletionPalette.accent.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                CompletionPalette.softRose.opacity(0.24),
                                lineWidth: 0.5
                            )
                    )

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CompletionPalette.softRose)
            }

            Text(text)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let codexAuthManager = CodexCLIAuthManager()

    CompletionStepView(onFinish: {})
        .environmentObject(SettingsViewModel())
        .environmentObject(AppState())
        .environmentObject(codexAuthManager)
}

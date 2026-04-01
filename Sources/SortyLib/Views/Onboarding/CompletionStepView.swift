//
//  CompletionStepView.swift
//  Sorty
//
//  Completion step of the onboarding flow
//

import SwiftUI
import AVFoundation

// MARK: - Completion Reveal Blob

/// A vibrant gradient blob that expands from center for the completion celebration
private struct CompletionRevealBlob: View {
    let scale: CGFloat
    let opacity: Double
    @State private var colorPhase: Double = 0

    var body: some View {
        ZStack {
            // Primary blob - green/teal
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.green.opacity(0.7),
                            Color.teal.opacity(0.5),
                            Color.blue.opacity(0.3),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 300
                    )
                )
                .frame(width: 600, height: 500)
                .blur(radius: 60)

            // Secondary blob - shifting hue
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.teal.opacity(0.5),
                            Color.green.opacity(0.3),
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

            // Bright core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.green.opacity(0.2),
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
                    colors: [.green, .teal, .blue, .green],
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
            // Layer 0: Base background
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            // Layer 1: Reveal gradient blob (expands from center)
            CompletionRevealBlob(scale: revealScale, opacity: revealOpacity)
                .allowsHitTesting(false)

            // Layer 2: Ambient gradient background (fades in after reveal)
            AnimatedGradientBackground(
                revealed: backgroundRevealed,
                color1: .green,
                color2: .blue,
                color3: .teal
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Layer 3: Floating particles (appear after reveal)
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

            // Layer 4: Main content
            VStack(spacing: 28) {
                Spacer()

                // Success icon with glow ring
                ZStack {
                    // Glow ring behind checkmark
                    CompletionGlowRing(isActive: showGlowRing)

                    // Animated expanding rings
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(Color.green.opacity(0.2 - Double(index) * 0.05), lineWidth: 2)
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
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 140, height: 140)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: hasAppeared)
                }
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.3)
                .animation(.spring(response: 0.9, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                // Exit: scale down and fade
                .scaleEffect(contentDismissed ? 0.8 : 1.0)
                .opacity(contentDismissed ? 0 : 1)

                // Title and message
                VStack(spacing: 16) {
                    Text("Sorty is Ready!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 20)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.2), value: hasAppeared)

                    Text("You're all set to start organizing your files with AI.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 15)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.4), value: hasAppeared)
                }
                .opacity(contentDismissed ? 0 : 1)
                .offset(y: contentDismissed ? 30 : 0)

                // Quick tips (staggered slide-in from left)
                VStack(spacing: 12) {
                    QuickTipRow(icon: "folder.badge.plus", text: "Drag any folder to organize it")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.6), value: tipsAppeared)

                    QuickTipRow(icon: "keyboard", text: "Press \u{2318}O to open a folder")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.8), value: tipsAppeared)

                    QuickTipRow(icon: "arrow.uturn.backward", text: "All changes can be undone")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(1.0), value: tipsAppeared)

                    QuickTipRow(icon: "gearshape", text: "Customize everything in Settings")
                        .opacity(tipsAppeared ? 1 : 0)
                        .offset(x: tipsAppeared ? 0 : -30)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85).delay(1.2), value: tipsAppeared)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .opacity(contentDismissed ? 0 : 1)
                .offset(y: contentDismissed ? 40 : 0)

                // Start button
                Button {
                    verifyAndFinish()
                } label: {
                    HStack(spacing: 8) {
                        if readinessState == .checking {
                            BouncingSpinner(size: 12, color: .white)
                            Text("Checking Provider...")
                        } else {
                            Text("Start Using Sorty")
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 16))
                        }
                    }
                }
                .buttonStyle(.onboardingPill)
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

                Spacer()
            }
            .padding(.horizontal, 48)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("OnboardingCompletionRetryButton")

                Button("Skip for Now") {
                    skipVerificationAndFinish()
                }
                .buttonStyle(.bordered)
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

        readinessState = .checking

        Task { @MainActor in
            do {
                try await settingsViewModel.testConnection()
                appState.clearSetupRepairState()
                readinessState = .idle
                startTransition()
            } catch {
                readinessState = .failed(error.localizedDescription)
                HapticFeedbackManager.shared.error()
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

        // Fade out all content smoothly
        withAnimation(.easeIn(duration: 0.4)) {
            contentDismissed = true
            backgroundRevealed = false
            showParticles = false
            showGlowRing = false
            revealOpacity = 0
        }

        // Complete after fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onFinish()
        }
    }
}

struct QuickTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)

            Spacer()
        }
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

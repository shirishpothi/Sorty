//
//  CompletionStepView.swift
//  Sorty
//
//  Completion step of the onboarding flow
//

import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

@MainActor
private enum CompletionPalette {
    static var accent: Color { SortyDesignSystem.Colors.resolvedAccent }
    static let softRose = Color(red: 1.0, green: 0.48, blue: 0.58)
    static let deepRose = Color(red: 0.42, green: 0.19, blue: 0.25)
    static let shadowRose = Color(red: 0.22, green: 0.10, blue: 0.14)
}

private struct CompletionHero: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    let contentDismissed: Bool
    let isButtonHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CompletionBloom(
                hasAppeared: reduceMotion || hasAppeared,
                isExiting: contentDismissed
            )
            CompletionCheckmarkIcon(
                hasAppeared: reduceMotion || hasAppeared,
                isButtonHovered: isButtonHovered
            )
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.9)
        .animation(
            reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9),
            value: hasAppeared
        )
        .scaleEffect(contentDismissed ? 0.8 : 1.0)
        .opacity(contentDismissed ? 0 : 1)
    }
}

private struct CompletionBloom: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isExiting: Bool
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        RetainedCompletionHeroEffects(
            isVisible: hasAppeared,
            reduceMotion: reduceMotion,
            isActive: controlActiveState != .inactive && !isExiting
        )
        .frame(width: 240, height: 240)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RetainedCompletionHeroEffects: NSViewRepresentable {
    @SortyHotReload private var hotReload
    let isVisible: Bool
    let reduceMotion: Bool
    let isActive: Bool

    func makeNSView(context: Context) -> RetainedCompletionHeroEffectsView {
        RetainedCompletionHeroEffectsView()
    }

    func updateNSView(_ nsView: RetainedCompletionHeroEffectsView, context: Context) {
        nsView.update(
            isVisible: isVisible,
            reduceMotion: reduceMotion,
            isActive: isActive
        )
    }
}

@MainActor
private final class RetainedCompletionHeroEffectsView: NSView {
    private let bloom = CAGradientLayer()
    private var isVisible = false
    private var isAnimating = false
    private var isPaused = false
    private var lastReduceMotion: Bool?
    private var lastIsActive: Bool?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)

        bloom.type = .radial
        bloom.startPoint = CGPoint(x: 0.5, y: 0.5)
        bloom.endPoint = CGPoint(x: 1, y: 0.92)
        bloom.colors = [
            NSColor(CompletionPalette.softRose).withAlphaComponent(0.42).cgColor,
            NSColor(CompletionPalette.accent).withAlphaComponent(0.23).cgColor,
            NSColor(CompletionPalette.softRose).withAlphaComponent(0.07).cgColor,
            NSColor(CompletionPalette.softRose).withAlphaComponent(0).cgColor
        ]
        bloom.locations = [0, 0.28, 0.60, 1]
        bloom.opacity = 0
        layer?.addSublayer(bloom)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Share the hero's center; the transparent falloff stays inside its slot.
        bloom.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.94)
        bloom.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func update(isVisible: Bool, reduceMotion: Bool, isActive: Bool) {
        let visibilityChanged = self.isVisible != isVisible
        let motionChanged = lastReduceMotion != reduceMotion
        let activityChanged = lastIsActive != isActive
        self.isVisible = isVisible
        lastReduceMotion = reduceMotion
        lastIsActive = isActive
        guard visibilityChanged || motionChanged || activityChanged else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bloom.opacity = isVisible ? 1 : 0
        CATransaction.commit()

        guard isVisible else {
            stopAnimating()
            return
        }
        guard !reduceMotion else {
            stopAnimating()
            return
        }

        startAnimatingIfNeeded(reveal: visibilityChanged)
        if isActive {
            resumeIfNeeded()
        } else {
            pauseIfNeeded()
        }
    }

    private func startAnimatingIfNeeded(reveal: Bool) {
        guard !isAnimating else { return }
        isAnimating = true

        if reveal {
            let arrival = CABasicAnimation(keyPath: "transform.scale")
            arrival.fromValue = 0.62
            arrival.toValue = 1
            arrival.duration = 0.7
            arrival.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bloom.add(arrival, forKey: "completionBloomArrival")
        }

        // A sixteen-second breath moves only the compositor layer, never view state.
        let breath = CABasicAnimation(keyPath: "transform.scale")
        breath.fromValue = 1
        breath.toValue = 1.025
        breath.duration = 8
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.beginTime = bloom.convertTime(CACurrentMediaTime(), from: nil) + 0.7
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bloom.add(breath, forKey: "completionBloomBreath")
    }

    private func stopAnimating() {
        guard isAnimating || isPaused else { return }
        resumeIfNeeded()
        isAnimating = false
        bloom.removeAllAnimations()
    }

    private func pauseIfNeeded() {
        guard isAnimating, !isPaused, let layer else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
        isPaused = true
    }

    private func resumeIfNeeded() {
        guard isPaused, let layer else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        isPaused = false
    }
}

private struct CompletionCheckmarkIcon: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    let isButtonHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(CompletionPalette.shadowRose.opacity(0.30))
                .frame(width: 118, height: 118)

            Circle()
                .fill(CompletionPalette.softRose)
                .frame(width: 72, height: 72)
                .opacity(isButtonHovered ? 0 : 1)

            ZStack {
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(CompletionPalette.deepRose.opacity(0.92))
                    .opacity(isButtonHovered ? 0 : 1)
                    .scaleEffect(isButtonHovered ? 0.72 : 1)
                    .symbolEffect(.bounce, value: reduceMotion ? false : hasAppeared)

                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                    .opacity(isButtonHovered ? 1 : 0)
                    .scaleEffect(isButtonHovered ? 1 : 0.72)
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82),
                value: isButtonHovered
            )
        }
    }
}

private struct CompletionCopy: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    let contentDismissed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text("Ready to Organize")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.2),
                    value: hasAppeared
                )

            Text("Drop in a folder, preview the plan, and undo anything you change.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 15)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.4),
                    value: hasAppeared
                )
        }
        .opacity(contentDismissed ? 0 : 1)
        .offset(y: contentDismissed ? 30 : 0)
    }
}

private struct CompletionTipsGrid: View {
    @SortyHotReload private var hotReload
    let tipsAppeared: Bool
    let contentDismissed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 14) {
                quickTip(icon: "folder.badge.plus", text: "Organize from Finder", delay: 0)
                quickTip(icon: "arrow.uturn.backward", text: "Undo from History", delay: 0.08)
            }
            VStack(alignment: .leading, spacing: 14) {
                quickTip(icon: "keyboard", text: "⌘O opens a folder", delay: 0.04)
                quickTip(icon: "gearshape", text: "Swap models in Settings", delay: 0.12)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(contentDismissed ? 0 : 1)
        .offset(y: contentDismissed ? 40 : 0)
    }

    private func quickTip(icon: String, text: String, delay: Double) -> some View {
        QuickTipRow(icon: icon, text: text)
            .opacity(tipsAppeared ? 1 : 0)
            .offset(y: tipsAppeared ? 0 : 12)
            .animation(
                reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85).delay(delay),
                value: tipsAppeared
            )
    }
}

private struct CompletionPrimaryAction: View {
    @SortyHotReload private var hotReload
    let tipsAppeared: Bool
    let contentDismissed: Bool
    let isChecking: Bool
    let action: () -> Void
    let onHoverChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Start Using Sorty")
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(.sortyPrimary(size: .large))
        .onboardingBeamBorder(variant: .featured, active: !isChecking)
        .keyboardShortcut(.defaultAction)
        .disabled(isChecking)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .opacity((reduceMotion || tipsAppeared) && !contentDismissed ? 1 : 0)
        .offset(y: tipsAppeared ? (contentDismissed ? 50 : 0) : 16)
        .animation(
            reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.2),
            value: tipsAppeared
        )
        .padding(.top, 6)
        .accessibilityIdentifier("OnboardingCompleteButton")
    }
}

private struct CompletionAnalyticsPreference: View {
    @SortyHotReload private var hotReload
    @Binding var isEnabled: Bool
    @State private var isShowingDetails = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isEnabled) {
                Text("Share anonymous analytics")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("OnboardingAnalyticsToggle")

            Button {
                HapticFeedbackManager.shared.tap()
                isShowingDetails.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    HapticFeedbackManager.shared.selection()
                }
            }
            .help("What anonymous analytics includes")
            .accessibilityLabel("About anonymous analytics")
            .accessibilityIdentifier("OnboardingAnalyticsInfoButton")
            .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                analyticsDetails
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            CompletionPalette.shadowRose.opacity(0.18),
            in: Capsule()
        )
    }

    private var analyticsDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Anonymous analytics")
                .font(.headline)

            Text("When this is on, Sorty sends limited product and reliability events so we can see which parts of the app are useful and where failures occur.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            detailSection(
                title: "What is included",
                systemImage: "checkmark.circle.fill",
                color: .green,
                text: "Screens and features used; broad actions, outcomes, counts, and timings; app and macOS versions and device category; sanitized errors and crashes with messages and sensitive values redacted."
            )

            detailSection(
                title: "What is never included",
                systemImage: "xmark.circle.fill",
                color: .red,
                text: "Your identity, folder or file names, paths, file contents, prompts, custom instructions, AI responses, API keys, or other credentials. Sorty does not record your screen or keystrokes."
            )

            Text("You can change this at any time in Settings → Advanced. Turning it off stops analytics and clears locally stored analytics data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 390, alignment: .leading)
        .systemLiquidGlassPopover(cornerRadius: 12)
    }

    private func detailSection(
        title: String,
        systemImage: String,
        color: Color,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Completion Step View

@MainActor
private final class CompletionAudioController {
    static let shared = CompletionAudioController()
    private var player: AVAudioPlayer?
    private var revealAccent: NSSound?
    private var fadeTask: Task<Void, Never>?

    func prepare() async {
        if revealAccent == nil {
            revealAccent = NSSound(named: "Glass")
            revealAccent?.volume = 0.15
        }
        guard player == nil else { return }
        guard let soundURL = resolvedSoundURL() else { return }
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: soundURL, options: .mappedIfSafe)
        }.value
        guard !Task.isCancelled, player == nil, let data else { return }

        preparePlayer(data: data)
    }

    private func prepareSynchronouslyIfNeeded() {
        guard player == nil else { return }
        let soundURL = resolvedSoundURL()
        guard let soundURL else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.numberOfLoops = 0
            player.volume = 0.3
            player.prepareToPlay()
            self.player = player
        } catch {
            print("[CompletionStepView] Failed to prepare Final Onboarding sound: \(error)")
        }
    }

    private func preparePlayer(data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.numberOfLoops = 0
            player.volume = 0.3
            player.prepareToPlay()
            self.player = player
        } catch {
            print("[CompletionStepView] Failed to prepare Final Onboarding sound: \(error)")
        }
    }

    private func resolvedSoundURL() -> URL? {
        SortyResources.finalOnboardingSoundURL()
            ?? Bundle.main.url(forResource: "Final Onboarding", withExtension: "m4a")
    }

    func play() {
        fadeTask?.cancel()
        fadeTask = nil
        prepareSynchronouslyIfNeeded()
        player?.currentTime = 0
        player?.volume = 0.3
        player?.play()
    }

    func playRevealAccent() {
        if revealAccent == nil {
            revealAccent = NSSound(named: "Glass")
            revealAccent?.volume = 0.15
        }
        revealAccent?.play()
    }

    func fadeOutAndStop(duration: TimeInterval) {
        fadeTask?.cancel()
        guard let player else { return }
        player.setVolume(0, fadeDuration: duration)
        fadeTask = Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            player?.stop()
            self?.player = nil
            self?.fadeTask = nil
        }
    }
}

@MainActor
enum OnboardingCompletionAudio {
    static func prewarm() async {
        await CompletionAudioController.shared.prepare()
    }
}

@MainActor
private final class CompletionRuntimeController {
    var animationTask: Task<Void, Never>?
}

public struct CompletionStepView: View {
    @SortyHotReload private var hotReload
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runtimeController = CompletionRuntimeController()

    let providerSetupStatus: ProviderSetupStatus
    let onFinish: () -> Void

    // Entry animation states
    @State private var hasAppeared = false
    @State private var tipsAppeared = false
    @State private var isCompletionButtonHovered = false
    @State private var completionHoverTask: Task<Void, Never>?
    @State private var lockedHoverForExit: Bool?

    private let audioController = CompletionAudioController.shared
    @State private var readinessState: ReadinessState = .idle
    @State private var isAnalyticsEnabled = true

    // Exit animation states
    @State private var exitTriggered = false
    @State private var finishTask: Task<Void, Never>?
    @State private var contentDismissed = false

    private enum ReadinessState: Equatable {
        case idle
        case checking
        case failed(String)
    }

    public init(
        providerSetupStatus: ProviderSetupStatus,
        onFinish: @escaping () -> Void
    ) {
        self.providerSetupStatus = providerSetupStatus
        self.onFinish = onFinish
        _isAnalyticsEnabled = State(
            initialValue: AnalyticsManager.shared.consent != .denied
        )
    }

    public var body: some View {
        ZStack {
            CompletionContrastBackdrop()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .opacity(contentDismissed ? 0 : 1)

            VStack(spacing: 16) {
                CompletionHero(
                    hasAppeared: reduceMotion || hasAppeared,
                    contentDismissed: contentDismissed,
                    isButtonHovered: lockedHoverForExit ?? isCompletionButtonHovered
                )
                CompletionCopy(hasAppeared: reduceMotion || hasAppeared, contentDismissed: contentDismissed)
                CompletionTipsGrid(tipsAppeared: reduceMotion || tipsAppeared, contentDismissed: contentDismissed)
                CompletionAnalyticsPreference(isEnabled: $isAnalyticsEnabled)
                    .opacity((reduceMotion || tipsAppeared) && !contentDismissed ? 1 : 0)
                    .offset(y: reduceMotion || tipsAppeared ? (contentDismissed ? 40 : 0) : 12)
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.65, dampingFraction: 0.85).delay(0.16),
                        value: tipsAppeared
                    )
                CompletionPrimaryAction(
                    tipsAppeared: reduceMotion || tipsAppeared,
                    contentDismissed: contentDismissed,
                    isChecking: readinessState == .checking,
                    action: verifyAndFinish,
                    onHoverChanged: { isHovered in
                        guard lockedHoverForExit == nil else { return }
                        completionHoverTask?.cancel()
                        // Small enter delay filters a sub-40ms swipe that would
                        // otherwise flash the app icon; leave delay keeps the
                        // exit from jittering when the cursor brushes the edge.
                        let delayMs: Int = isHovered ? 40 : 90
                        completionHoverTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(delayMs))
                            guard !Task.isCancelled else { return }
                            if reduceMotion {
                                isCompletionButtonHovered = isHovered
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    isCompletionButtonHovered = isHovered
                                }
                            }
                        }
                    }
                )

                if case .failed(let message) = readinessState {
                    completionFailureCard(message: message)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityIdentifier("OnboardingCompletionHealthError")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear(perform: startRevealSequence)
        .onDisappear {
            completionHoverTask?.cancel()
            completionHoverTask = nil
            finishTask?.cancel()
            finishTask = nil
            runtimeController.animationTask?.cancel()
            runtimeController.animationTask = nil
            fadeOutAndStopAudio(duration: 0.25)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion Step")
    }

    // MARK: - Reveal Sequence

    private func startRevealSequence() {
        runtimeController.animationTask?.cancel()
        if reduceMotion {
            hasAppeared = true
            tipsAppeared = true
            return
        }

        runtimeController.animationTask = Task { @MainActor in
            // Mount and lay out the lightweight gradient before the shared arrival.
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            await audioController.prepare()
            guard !Task.isCancelled else { return }
            audioController.play()
            audioController.playRevealAccent()
            hasAppeared = true
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            tipsAppeared = true
        }
    }

    private func fadeOutAndStopAudio(duration: TimeInterval) {
        audioController.fadeOutAndStop(duration: duration)
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
                .fill(Color.orange.opacity(0.035))
        )
        .systemLiquidGlassBackground(cornerRadius: 16, interactive: false)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
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
        runtimeController.animationTask?.cancel()
        runtimeController.animationTask = nil
        // Lock the hero icon to its current hover state so a click while
        // showing the Sorty app icon doesn't flick back to the checkmark
        // during the exit animation.
        lockedHoverForExit = isCompletionButtonHovered
        if lockedHoverForExit == false, completionHoverTask != nil {
            // Hover-enter was still in its 40ms debounce (raw hover true but
            // delayed state not yet flipped). Treat as hovered so Sorty stays.
            lockedHoverForExit = true
            completionHoverTask?.cancel()
            completionHoverTask = nil
        }
        AnalyticsManager.shared.setConsent(isAnalyticsEnabled ? .granted : .denied)
        let exitDuration = reduceMotion ? 0 : 0.52
        HapticFeedbackManager.shared.success()
        fadeOutAndStopAudio(duration: exitDuration)

        // Let the completed onboarding settle away before the main window
        // appears, rather than replacing the whole experience in one frame.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: exitDuration)) {
            exitTriggered = true
            contentDismissed = true
        }

        finishTask?.cancel()
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(exitDuration))
            guard !Task.isCancelled, exitTriggered else { return }
            onFinish()
        }
    }
}

private struct CompletionContrastBackdrop: View {
    @SortyHotReload private var hotReload
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
    @SortyHotReload private var hotReload
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
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let codexAuthManager = CodexCLIAuthManager()

    CompletionStepView(
        providerSetupStatus: ProviderSetupStatus(
            isReady: true,
            title: "Setup complete",
            message: "Provider is ready."
        ),
        onFinish: {}
    )
        .environmentObject(SettingsViewModel())
        .environmentObject(AppState())
        .environmentObject(codexAuthManager)
}

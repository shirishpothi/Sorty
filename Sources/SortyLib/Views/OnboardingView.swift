//
//  OnboardingView.swift
//  Sorty
//
//  Interactive onboarding flow for first-time users
//  Steps: Provider Selection → Permissions → Workflow → Demo → Completion
//

import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Onboarding View

public struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var codexAuth: CodexCLIAuthManager
    @ObservedObject private var copilotAuth = GitHubCopilotAuthManager.shared

    @State private var currentStep: OnboardingStep = .provider
    @State private var hasFilesAndFoldersPermission = false
    @State private var advanceValidationMessage: String?
    @State private var isAdvancing = false
    @State private var swipeMonitor: Any?
    @State private var isHoveringStepIndicator = false
    @State private var swipeAccumulatedTranslation: CGFloat = 0
    @State private var hasTriggeredSwipeForGesture = false
    @State private var hasConfiguredWindowChrome = false
    @State private var isIntroVisible = true

    private let swipeThreshold: CGFloat = 42

    public init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !isIntroVisible {
                    Color(NSColor.windowBackgroundColor)
                        .ignoresSafeArea()

                    OnboardingBottomGradient(progress: gradientProgress)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .animation(.easeInOut(duration: 0.65), value: gradientProgress)

                    VStack(spacing: 0) {
                        // Pinned with a fixed top padding so it doesn't shift between steps.
                        // A soft top scrim (instead of a hard opaque strip) prevents scrolled
                        // step content from bleeding behind it while blending seamlessly into
                        // the unified background gradient so there is no visible color seam.
                        OnboardingProgressBar(currentStep: currentStep)
                            .padding(.top, 54)
                            .padding(.bottom, 24)
                            .padding(.horizontal, 48)
                            .opacity(hasConfiguredWindowChrome ? 1 : 0)
                            .animation(nil, value: hasConfiguredWindowChrome)

                        // Main content
                        stepContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .overlay(alignment: .bottom) {
                        if currentStep != .completion {
                            navigationControls
                                .padding(.horizontal, 40)
                                .padding(.top, 24)
                                .padding(.bottom, 16)
                                .background(
                                    OnboardingNavigationBackdrop()
                                        .allowsHitTesting(false)
                                )
                                .transition(.opacity)
                        }
                    }
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.opacity)
                }

                if isIntroVisible {
                    OnboardingIntroView {
                        dismissIntro()
                    }
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 640)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding")
        .accessibilityIdentifier("OnboardingView")
        .onChange(of: currentStep) { _, _ in
            advanceValidationMessage = nil
        }
        .onChange(of: currentStepValidation.canAdvance) { _, canAdvance in
            if canAdvance {
                advanceValidationMessage = nil
            }
        }
        .background(
            OnboardingWindowTitleConfigurator {
                hasConfiguredWindowChrome = true
            }
            .frame(width: 0, height: 0)
        )
        .onAppear {
            installSwipeMonitorIfNeeded()
        }
        .onDisappear {
            removeSwipeMonitor()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .provider:
            ProviderSelectionStepView()
                .transition(TransitionStyles.slideFromRight)
        case .permissions:
            PermissionsStepView(hasRequiredPermissions: $hasFilesAndFoldersPermission)
                .transition(TransitionStyles.slideFromRight)
        case .workflow:
            WorkflowSelectionStepView()
                .transition(TransitionStyles.slideFromRight)
        case .demo:
            DemoStepView(onComplete: {
                withAnimation(.pageTransition) {
                    currentStep = .completion
                }
            })
            .transition(TransitionStyles.slideFromRight)
        case .completion:
            CompletionStepView(onFinish: {
                HapticFeedbackManager.shared.success()
                withAnimation(.easeOut(duration: 0.5)) {
                    hasCompletedOnboarding = true
                }
                if !appState.hasCompletedFeatureTour {
                    appState.isFeatureTourPresented = true
                }
            })
            .transition(TransitionStyles.scaleAndFade)
        }
    }

    private var navigationControls: some View {
        let sideControlWidth: CGFloat = 180
        let backHidden = (currentStep == OnboardingStep.activeCases.first || currentStep == .completion)

        return VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 16) {
                    // Back button - kept in layout on all steps to prevent layout shift.
                    Button {
                        navigateToPreviousStep()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Back")
                        }
                        .frame(minWidth: 80)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .accessibilityIdentifier("OnboardingBackButton")
                    .opacity(backHidden ? 0 : 1)
                    .disabled(backHidden)
                    .allowsHitTesting(!backHidden)
                    .frame(width: sideControlWidth, alignment: .leading)

                    Spacer(minLength: 0)

                    // Next/Skip button
                    Group {
                        if currentStep != .completion {
                            if currentStep == .demo {
                                Button {
                                    navigateForwardFromControls()
                                } label: {
                                    Text("Skip Demo")
                                        .frame(minWidth: 80)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("OnboardingSkipDemoButton")
                            } else {
                                Button {
                                    navigateForwardFromControls()
                                } label: {
                                    HStack(spacing: 6) {
                                        if isAdvancing {
                                            BouncingSpinner(size: 10, color: .white)
                                        }
                                        Text(currentStep == .permissions ? "Continue" : "Next")
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.onboardingPill)
                                .onboardingBeamBorder(
                                    active: currentStepValidation.canAdvance && !isAdvancing
                                )
                                .keyboardShortcut(.rightArrow, modifiers: [])
                                .disabled(!currentStepValidation.canAdvance || isAdvancing)
                                .opacity(
                                    currentStepValidation.canAdvance && !isAdvancing ? 1.0 : 0.5
                                )
                                .accessibilityIdentifier("OnboardingAdvanceButton")
                            }
                        }
                    }
                    .frame(width: sideControlWidth, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onHover { isHovering in
                isHoveringStepIndicator = isHovering
                if !isHovering {
                    resetSwipeTracking()
                }
            }

            if let advanceValidationMessage, !advanceValidationMessage.isEmpty,
                currentStep != .provider
            {
                Text(advanceValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("OnboardingValidationMessage")
            }
        }
    }

    /// Normalized progress (0...1) through the active onboarding steps. Drives
    /// the background gradient so it climbs higher as the user advances.
    private var gradientProgress: Double {
        let active = OnboardingStep.activeCases
        guard active.count > 1, let index = active.firstIndex(of: currentStep) else {
            return 0
        }
        return Double(index) / Double(active.count - 1)
    }

    private var providerSetupContext: ProviderSetupContext {
        ProviderSetupContext(
            config: settingsViewModel.config,
            isGitHubCopilotAuthenticated: copilotAuth.isAuthenticated,
            isCodexAuthenticated: codexAuth.isAuthenticated,
            isCodexInstalled: codexAuth.isCodexInstalled,
            isAppleFoundationModelAvailable: settingsViewModel.isAppleModelAvailable,
            appleFoundationModelStatus: settingsViewModel.appleModelStatus
        )
    }

    private var currentStepValidation: OnboardingStepValidationResult {
        currentStep.synchronousValidation(
            in: OnboardingStepValidationContext(
                providerSetupStatus: OnboardingSetupValidator.providerStatus(
                    context: providerSetupContext),
                hasRequiredPermissions: hasFilesAndFoldersPermission
            )
        )
    }

    private func dismissIntro() {
        guard isIntroVisible else { return }
        HapticFeedbackManager.shared.selection()
        withAnimation(.easeInOut(duration: 0.55)) {
            isIntroVisible = false
        }
    }

    private func navigateToPreviousStep() {
        guard currentStep != OnboardingStep.activeCases.first && currentStep != .completion else { return }
        HapticFeedbackManager.shared.selection()
        withAnimation(.pageTransition) {
            currentStep = currentStep.previous
        }
    }

    private func navigateForwardFromControls() {
        guard currentStep != .completion else { return }

        switch currentStep {
        case .demo:
            HapticFeedbackManager.shared.selection()
            withAnimation(.pageTransition) {
                currentStep = .completion
            }
        case .provider, .permissions, .workflow:
            attemptAdvance()
        case .completion:
            break
        }
    }

    private func attemptAdvance() {
        guard !isAdvancing else { return }

        let validationContext = OnboardingStepValidationContext(
            providerSetupStatus: OnboardingSetupValidator.providerStatus(
                context: providerSetupContext),
            hasRequiredPermissions: hasFilesAndFoldersPermission
        )

        Task { @MainActor in
            isAdvancing = true
            let validation = await currentStep.validateAdvance(in: validationContext)
            isAdvancing = false

            guard validation.canAdvance else {
                advanceValidationMessage = validation.message
                HapticFeedbackManager.shared.error()
                return
            }

            advanceValidationMessage = nil
            HapticFeedbackManager.shared.selection()
            withAnimation(.pageTransition) {
                currentStep = currentStep.next
            }
        }
    }

    private func installSwipeMonitorIfNeeded() {
        guard swipeMonitor == nil else { return }

        swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            handleSwipeEvent(event)
        }
    }

    private func removeSwipeMonitor() {
        if let monitor = swipeMonitor {
            NSEvent.removeMonitor(monitor)
            swipeMonitor = nil
        }
        resetSwipeTracking()
        isHoveringStepIndicator = false
    }

    private func resetSwipeTracking() {
        swipeAccumulatedTranslation = 0
        hasTriggeredSwipeForGesture = false
    }

    private func handleSwipeEvent(_ event: NSEvent) -> NSEvent? {
        guard isHoveringStepIndicator else { return event }

        let deltaX =
            event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 8
        let deltaY =
            event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8

        guard abs(deltaX) > abs(deltaY) else { return event }

        if event.phase == .began {
            resetSwipeTracking()
        }

        if event.momentumPhase != [] {
            if event.momentumPhase == .ended {
                resetSwipeTracking()
            }
            return nil
        }

        guard !hasTriggeredSwipeForGesture else {
            if event.phase == .ended || event.phase == .cancelled {
                resetSwipeTracking()
            }
            return nil
        }

        let physicalDeltaX = event.isDirectionInvertedFromDevice ? deltaX : -deltaX
        swipeAccumulatedTranslation += physicalDeltaX

        if swipeAccumulatedTranslation <= -swipeThreshold {
            hasTriggeredSwipeForGesture = true
            navigateForwardFromControls()
            return nil
        }

        if swipeAccumulatedTranslation >= swipeThreshold {
            hasTriggeredSwipeForGesture = true
            navigateToPreviousStep()
            return nil
        }

        if event.phase == .ended || event.phase == .cancelled {
            resetSwipeTracking()
        }

        return nil
    }
}

// MARK: - Onboarding Step Enum

enum OnboardingStep: Int, CaseIterable {
    case provider = 0
    case permissions = 1
    case workflow = 2
    case demo = 3
    case completion = 4

    @MainActor
    static var activeCases: [OnboardingStep] {
        allCases.filter { step in
            if step == .demo {
                return FeatureFlags.featureDemoEnabled
            }
            return true
        }
    }

    var title: String {
        switch self {
        case .provider: return "AI Provider"
        case .permissions: return "Permissions"
        case .workflow: return "Workflow"
        case .demo: return "Try It Out"
        case .completion: return "Ready!"
        }
    }

    @MainActor
    var next: OnboardingStep {
        let active = OnboardingStep.activeCases
        guard let currentIndex = active.firstIndex(of: self) else { return self }
        let nextIndex = min(currentIndex + 1, active.count - 1)
        return active[nextIndex]
    }

    @MainActor
    var previous: OnboardingStep {
        let active = OnboardingStep.activeCases
        guard let currentIndex = active.firstIndex(of: self) else { return self }
        let prevIndex = max(currentIndex - 1, 0)
        return active[prevIndex]
    }
}

extension OnboardingStep: OnboardingStepValidating {
    func synchronousValidation(in context: OnboardingStepValidationContext)
        -> OnboardingStepValidationResult
    {
        switch self {
        case .provider:
            if context.providerSetupStatus.isReady {
                return .valid
            }
            return .blocked(context.providerSetupStatus.message)
        case .permissions:
            if context.hasRequiredPermissions {
                return .valid
            }
            return .blocked("Grant Files & Folders access before continuing.")
        case .workflow, .demo, .completion:
            return .valid
        }
    }
}

// MARK: - Onboarding Title Bar

private struct OnboardingIntroView: View {
    let onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconScale: CGFloat = 0.78
    @State private var iconOpacity: Double = 0
    @State private var iconBlur: CGFloat = 12
    @State private var glowOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 14
    @State private var glowRadius: CGFloat = 28
    @State private var filesAppeared = false
    @State private var ambientMotionActive = false
    @State private var ambientMotionGeneration = 0
    @State private var isHoveringButton = false
    @State private var hoverExitDebounceGeneration = 0
    @StateObject private var audio = OnboardingAudioManager()

    var body: some View {
        ZStack {
            OnboardingBottomGradient()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(0.92)

            // Real macOS file-type icons drift in a loose orbit, then tuck into
            // the app icon when the user starts onboarding.
            SwiftUI.TimelineView(.animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || !filesAppeared || isHoveringButton || !ambientMotionActive
            )) { context in
                let phase = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(OnboardingOrbitFile.files) { file in
                        OnboardingOrbitFileChip(file: file)
                            .rotationEffect(.degrees(isHoveringButton ? 0 : file.rotation + sin(phase * 0.7 + file.driftPhase) * 3))
                            .scaleEffect(isHoveringButton ? 0.24 : file.scale)
                            .offset(orbitOffset(for: file, phase: phase))
                            .opacity(isHoveringButton ? 0 : (filesAppeared ? 1 : 0))
                            .blur(radius: isHoveringButton ? 16 : 0)
                            .animation(
                                .spring(response: 0.7, dampingFraction: 0.86)
                                    .delay(file.appearDelay),
                                value: filesAppeared
                            )
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isHoveringButton)
                .allowsHitTesting(false)
            }

            VStack(spacing: 26) {
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.30))
                            .frame(width: 220, height: 220)
                            .blur(radius: glowRadius)
                            .opacity(glowOpacity)

                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 156, height: 156)
                            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                            .shadow(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.22), radius: 34, x: 0, y: 0)
                            .shadow(color: .black.opacity(0.28), radius: 26, x: 0, y: 16)
                            .blur(radius: iconBlur)
                            .accessibilityHidden(true)
                    }
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                    Text("Welcome to Sorty")
                        .font(.system(size: 38, weight: .medium, design: .serif))
                        .foregroundStyle(.primary.opacity(0.88))
                        .opacity(textOpacity)
                        .offset(y: textOffset)
                }

                Button {
                    HapticFeedbackManager.shared.success()
                    audio.stopAll()
                    onGetStarted()
                } label: {
                    HStack(spacing: 8) {
                        Text("Get Started")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.onboardingPill(size: .large))
                .onboardingBeamBorder(variant: .featured, isIntensified: isHoveringButton, includesInteriorGlow: isHoveringButton)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("OnboardingAdvanceButton")
                .onHover { hovering in
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        isHoveringButton = hovering
                    }

                    if hovering {
                        hoverExitDebounceGeneration += 1
                        stopAmbientMotion()
                    } else {
                        releaseFileCollapseAfterGracePeriod()
                    }
                }
                .scaleEffect(isHoveringButton ? 1.035 : 1)
                .opacity(textOpacity)
                .offset(y: textOffset)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isHoveringButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Sorty")
        .onAppear {
            audio.startBackgroundMelody()

            // Smooth fade-in for the icon. Springs feel jittery on opacity,
            // so we drive opacity + blur with eases and reserve the spring
            // for scale only. The icon resolves out of a soft blur, which
            // reads as a graceful materialization instead of a jerky pop.
            if reduceMotion {
                iconScale = 1
                iconOpacity = 1
                iconBlur = 0
                glowOpacity = 1
                textOpacity = 1
                textOffset = 0
            } else {
                withAnimation(.easeOut(duration: 0.95)) {
                    iconOpacity = 1
                    iconBlur = 0
                }

                withAnimation(.spring(response: 0.95, dampingFraction: 0.86)) {
                    iconScale = 1
                }

                withAnimation(.easeOut(duration: 1.2).delay(0.10)) {
                    glowOpacity = 1
                }

                // Slow "breathing" glow that blooms once after the icon
                // settles, then eases back — no harder than the eye can
                // follow, no overshoot.
                withAnimation(.easeInOut(duration: 1.4).delay(0.45)) {
                    glowRadius = 46
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.85))
                    withAnimation(.easeInOut(duration: 1.6)) {
                        glowRadius = 38
                    }
                }

                withAnimation(.easeOut(duration: 0.85).delay(0.32)) {
                    textOpacity = 1
                    textOffset = 0
                }
            }

            filesAppeared = true
            beginAmbientMotionWindow(seconds: 8)
        }
        .onDisappear {
            stopAmbientMotion()
            audio.stopAll()
        }
    }

    private func beginAmbientMotionWindow(seconds: TimeInterval) {
        guard !reduceMotion else { return }
        ambientMotionGeneration += 1
        let generation = ambientMotionGeneration
        ambientMotionActive = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard generation == ambientMotionGeneration, !isHoveringButton else { return }
            ambientMotionActive = false
        }
    }

    private func stopAmbientMotion() {
        ambientMotionGeneration += 1
        ambientMotionActive = false
    }

    private func releaseFileCollapseAfterGracePeriod() {
        hoverExitDebounceGeneration += 1
        let generation = hoverExitDebounceGeneration

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard generation == hoverExitDebounceGeneration, !isHoveringButton else { return }
            beginAmbientMotionWindow(seconds: 4)
        }
    }

    private func orbitOffset(for file: OnboardingOrbitFile, phase: Double) -> CGSize {
        if isHoveringButton {
            return CGSize(width: file.collapseX, height: file.collapseY)
        }

        let orbitalAngle = phase * file.driftSpeed + file.driftPhase
        let orbitalX = cos(orbitalAngle) * file.orbitWidth * 1.18
        let orbitalY = sin(orbitalAngle) * file.orbitHeight * 1.22
        let driftX = cos(phase * 0.42 + file.driftPhase) * file.driftRadius * 1.28
        let driftY = sin(phase * 0.35 + file.driftPhase) * file.driftRadius * 1.32
        return CGSize(width: file.baseX + orbitalX + driftX, height: file.baseY + orbitalY + driftY)
    }
}

private struct OnboardingOrbitFile: Identifiable {
    let id = UUID()
    let name: String
    let ext: String
    // Scattered resting position (offset from center).
    let baseX: CGFloat
    let baseY: CGFloat
    // Lazy floating motion.
    let driftPhase: Double
    let driftSpeed: Double
    let driftRadius: CGFloat
    let orbitWidth: CGFloat
    let orbitHeight: CGFloat
    // Messy presentation.
    let rotation: Double
    let scale: CGFloat
    let appearDelay: Double
    // Where the file flies to when the pile collapses into the icon.
    let collapseX: CGFloat
    let collapseY: CGFloat

    // Roughly 2.5–3× larger orbits and drift radii than before, plus more
    // varied phase/speed so the cloud feels alive instead of just twitching
    // in place.
    static let files: [OnboardingOrbitFile] = [
        OnboardingOrbitFile(name: "Q3 Report", ext: "pdf", baseX: -292, baseY: -118, driftPhase: 0.0, driftSpeed: 0.62, driftRadius: 22, orbitWidth: 84, orbitHeight: 46, rotation: -13, scale: 1.04, appearDelay: 0.05, collapseX: -30, collapseY: -18),
        OnboardingOrbitFile(name: "Budget 2024", ext: "xlsx", baseX: 286, baseY: -104, driftPhase: 1.3, driftSpeed: 0.74, driftRadius: 20, orbitWidth: 72, orbitHeight: 52, rotation: 11, scale: 0.96, appearDelay: 0.12, collapseX: 26, collapseY: -22),
        OnboardingOrbitFile(name: "vacation", ext: "jpg", baseX: -244, baseY: 118, driftPhase: 2.1, driftSpeed: 0.68, driftRadius: 24, orbitWidth: 78, orbitHeight: 56, rotation: 8, scale: 1.1, appearDelay: 0.18, collapseX: -34, collapseY: 14),
        OnboardingOrbitFile(name: "Resume", ext: "docx", baseX: 242, baseY: 132, driftPhase: 3.4, driftSpeed: 0.58, driftRadius: 22, orbitWidth: 90, orbitHeight: 48, rotation: -9, scale: 1.0, appearDelay: 0.24, collapseX: 30, collapseY: 20),
        OnboardingOrbitFile(name: "demo", ext: "mp4", baseX: -344, baseY: 8, driftPhase: 0.7, driftSpeed: 0.80, driftRadius: 20, orbitWidth: 68, orbitHeight: 42, rotation: 6, scale: 0.92, appearDelay: 0.3, collapseX: -44, collapseY: 0),
        OnboardingOrbitFile(name: "Keynote", ext: "key", baseX: 350, baseY: 24, driftPhase: 4.2, driftSpeed: 0.66, driftRadius: 24, orbitWidth: 80, orbitHeight: 52, rotation: -7, scale: 0.94, appearDelay: 0.36, collapseX: 44, collapseY: 4),
        OnboardingOrbitFile(name: "logo", ext: "png", baseX: -142, baseY: -194, driftPhase: 5.0, driftSpeed: 0.72, driftRadius: 22, orbitWidth: 68, orbitHeight: 42, rotation: 14, scale: 0.88, appearDelay: 0.1, collapseX: -16, collapseY: -28),
        OnboardingOrbitFile(name: "playlist", ext: "mp3", baseX: 152, baseY: -198, driftPhase: 2.7, driftSpeed: 0.78, driftRadius: 22, orbitWidth: 70, orbitHeight: 48, rotation: -12, scale: 0.9, appearDelay: 0.16, collapseX: 18, collapseY: -30),
        OnboardingOrbitFile(name: "data", ext: "csv", baseX: -126, baseY: 194, driftPhase: 1.8, driftSpeed: 0.64, driftRadius: 20, orbitWidth: 64, orbitHeight: 42, rotation: -5, scale: 0.86, appearDelay: 0.22, collapseX: -14, collapseY: 26),
        OnboardingOrbitFile(name: "archive", ext: "zip", baseX: 128, baseY: 204, driftPhase: 3.9, driftSpeed: 0.76, driftRadius: 24, orbitWidth: 70, orbitHeight: 48, rotation: 10, scale: 0.9, appearDelay: 0.28, collapseX: 16, collapseY: 28)
    ]
}

/// Provides (and caches) the real macOS file-type icon for a given extension.
@MainActor
private enum OnboardingFileIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for ext: String) -> NSImage {
        if let cached = cache[ext] {
            return cached
        }
        let image: NSImage
        if let type = UTType(filenameExtension: ext) {
            image = NSWorkspace.shared.icon(for: type)
        } else {
            image = NSWorkspace.shared.icon(forFileType: ext)
        }
        cache[ext] = image
        return image
    }
}

private struct OnboardingOrbitFileChip: View {
    let file: OnboardingOrbitFile

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: OnboardingFileIconProvider.icon(for: file.ext))
                .resizable()
                .interpolation(.high)
                .frame(width: 46, height: 46)

            Text("\(file.name).\(file.ext)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 16, x: 0, y: 12)
        .accessibilityHidden(true)
    }
}

struct OnboardingBottomGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    /// 0 = gradient hugs the bottom edge, 1 = gradient reaches near the top.
    var progress: Double = 0
    var showsBaseColor = true

    var body: some View {
        let clamped = max(0, min(1, progress))
        // The linear wash climbs from the lower third toward the top as the
        // user progresses. We keep a small top margin (y never reaches 0) so
        // the title/progress region stays calm and the fade is always smooth.
        let linearEnd = UnitPoint(x: 0.5, y: 0.62 - clamped * 0.5)
        let radialCenterY = 1.06 - clamped * 0.36
        let radialEnd = 560 + clamped * 540
        let intensity = 1.0 + clamped * 0.25

        return ZStack(alignment: .bottom) {
            if showsBaseColor {
                Color(NSColor.windowBackgroundColor)
            }

            SortyDesignSystem.Colors.resolvedAccent
                .opacity((colorScheme == .dark ? 0.055 : 0.075) * clamped)

            LinearGradient(
                colors: [
                    SortyDesignSystem.Colors.resolvedAccent.opacity((colorScheme == .dark ? 0.34 : 0.46) * intensity),
                    SortyDesignSystem.Colors.resolvedAccent.opacity((colorScheme == .dark ? 0.16 : 0.20) * intensity),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: linearEnd
            )

            RadialGradient(
                colors: [
                    SortyDesignSystem.Colors.resolvedAccent.opacity((colorScheme == .dark ? 0.24 : 0.30) * intensity),
                    SortyDesignSystem.Colors.resolvedAccent.opacity(0.08 * intensity),
                    Color.clear
                ],
                center: UnitPoint(x: 0.5, y: radialCenterY),
                startRadius: 0,
                endRadius: radialEnd
            )
            .blendMode(.plusLighter)

            LinearGradient(
                colors: [
                    SortyDesignSystem.Colors.resolvedAccent.opacity((colorScheme == .dark ? 0.13 : 0.16) * clamped),
                    SortyDesignSystem.Colors.resolvedAccent.opacity((colorScheme == .dark ? 0.07 : 0.10) * clamped),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.56)
            )
            .blendMode(.plusLighter)
        }
    }
}

private struct OnboardingNavigationBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(NSColor.windowBackgroundColor).opacity(0),
                Color(NSColor.windowBackgroundColor).opacity(0.20),
                Color(NSColor.windowBackgroundColor).opacity(0.34)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct OnboardingTopBar: View {
    var body: some View {
        Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .allowsHitTesting(false)
    }
}

private struct OnboardingWindowTitleConfigurator: NSViewRepresentable {
    let onConfigured: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachedView()
        view.onWindowAttached = { window in
            context.coordinator.configure(window: window)
            notifyAfterWindowLayoutSettles()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            context.coordinator.configure(window: window)
            notifyAfterWindowLayoutSettles()
        }
    }

    private func notifyAfterWindowLayoutSettles() {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                onConfigured()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var configuredWindow: NSWindow?
        private var originalTitleVisibility: NSWindow.TitleVisibility?
        private var originalTitlebarAppearsTransparent: Bool?
        private var originalStyleMask: NSWindow.StyleMask?
        private var originalBackgroundColor: NSColor?
        private var originalIsOpaque: Bool?
        private var originalHasShadow: Bool?
        private var originalAlphaValue: CGFloat?

        func configure(window: NSWindow) {
            guard configuredWindow !== window else { return }
            restore()

            configuredWindow = window
            originalTitleVisibility = window.titleVisibility
            originalTitlebarAppearsTransparent = window.titlebarAppearsTransparent
            originalStyleMask = window.styleMask
            originalBackgroundColor = window.backgroundColor
            originalIsOpaque = window.isOpaque
            originalHasShadow = window.hasShadow
            originalAlphaValue = window.alphaValue

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isMovableByWindowBackground = true

            // Pin the window to the onboarding minimum content size before the
            // first paint so it never visibly resizes/reframes after appearing.
            let targetSize = NSSize(width: 1100, height: 720)
            if window.frame.size.width < targetSize.width || window.frame.size.height < targetSize.height {
                window.setContentSize(targetSize)
                window.center()
            }

            // Start fully transparent and slowly fade the whole window in so the
            // onboarding materializes rather than popping into existence.
            window.alphaValue = 0
            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 1.4
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().alphaValue = 1
                }
            }
        }

        private func restore() {
            guard let window = configuredWindow else { return }
            if let originalStyleMask {
                window.styleMask = originalStyleMask
            }
            if let originalTitlebarAppearsTransparent {
                window.titlebarAppearsTransparent = originalTitlebarAppearsTransparent
            }
            if let originalTitleVisibility {
                window.titleVisibility = originalTitleVisibility
            }
            if let originalBackgroundColor {
                window.backgroundColor = originalBackgroundColor
            }
            if let originalIsOpaque {
                window.isOpaque = originalIsOpaque
            }
            if let originalHasShadow {
                window.hasShadow = originalHasShadow
            }
            if let originalAlphaValue {
                window.alphaValue = originalAlphaValue
            } else {
                window.alphaValue = 1
            }
        }

        deinit {
            restore()
        }
    }

    final class WindowAttachedView: NSView {
        var onWindowAttached: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            onWindowAttached?(window)
        }
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep

    @MainActor
    private var activeSteps: [OnboardingStep] {
        OnboardingStep.activeCases
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<activeSteps.count, id: \.self) { index in
                let step = activeSteps[index]

                if index > 0 {
                    Capsule(style: .continuous)
                        .fill(
                            step.rawValue <= currentStep.rawValue
                                ? SortyDesignSystem.Colors.resolvedAccent : Color.secondary.opacity(0.2)
                        )
                        .frame(width: 56, height: 2)
                }

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(
                                step.rawValue <= currentStep.rawValue
                                    ? SortyDesignSystem.Colors.resolvedAccent : Color.secondary.opacity(0.2)
                            )
                            .frame(width: 24, height: 24)

                        // Treat the completion step as "done" the moment the user lands on it,
                        // so the final step badge celebrates rather than looking like an
                        // unfinished number sitting next to a row of checkmarks.
                        let isComplete = step.rawValue < currentStep.rawValue
                            || (currentStep == .completion && step == .completion)

                        if isComplete {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(
                                    step.rawValue <= currentStep.rawValue ? .white : .secondary)
                        }
                    }

                    Text(step.title)
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 20)
                }
                .frame(width: 82)
            }
        }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    let codexAuthManager = CodexCLIAuthManager()

    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(SettingsViewModel())
        .environmentObject(PersonaManager())
        .environmentObject(FolderOrganizer())
        .environmentObject(AppState())
        .environmentObject(codexAuthManager)
}

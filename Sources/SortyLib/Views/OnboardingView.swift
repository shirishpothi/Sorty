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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var isFlowPrepared = false
    @State private var introTransitionProgress: CGFloat = 0
    @State private var isDismissingIntro = false
    @State private var introTransitionTask: Task<Void, Never>?

    private let swipeThreshold: CGFloat = 42

    public init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
    }

    public var body: some View {
        ZStack {
            if isFlowPrepared {
                onboardingFlow
                    .opacity(introTransitionProgress)
                    .offset(y: reduceMotion ? 0 : 8 * (1 - introTransitionProgress))
                    .allowsHitTesting(!isIntroVisible)
                    .accessibilityHidden(isIntroVisible)
            }

            if isIntroVisible {
                OnboardingIntroView {
                    dismissIntro()
                }
                .opacity(1 - introTransitionProgress)
                .scaleEffect(reduceMotion ? 1 : 1 - (0.008 * introTransitionProgress))
                .allowsHitTesting(!isDismissingIntro)
                .accessibilityHidden(isDismissingIntro)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(
            minWidth: SortyDesignSystem.Sizing.windowOnboardingWidth,
            minHeight: SortyDesignSystem.Sizing.windowOnboardingHeight
        )
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
            ZStack {
                OnboardingWindowTitleConfigurator {
                    hasConfiguredWindowChrome = true
                }
                OnboardingScreenBackdropBlurPresenter()
                OnboardingScreenEdgeGlowPresenter()
            }
            .frame(width: 0, height: 0)
        )
        .onAppear {
            installSwipeMonitorIfNeeded()
        }
        .onDisappear {
            introTransitionTask?.cancel()
            removeSwipeMonitor()
        }
    }

    private var onboardingFlow: some View {
        ZStack {
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
                    .background(
                        // Keep the title/progress rail legible without
                        // stamping a separate color band across the
                        // window.
                        LinearGradient(
                            stops: [
                                .init(color: Color(NSColor.windowBackgroundColor).opacity(0.24), location: 0.00),
                                .init(color: Color(NSColor.windowBackgroundColor).opacity(0.14), location: 0.38),
                                .init(color: Color(NSColor.windowBackgroundColor).opacity(0.04), location: 0.74),
                                .init(color: Color.clear, location: 1.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 220)
                        .offset(y: -34)
                    )
                    .opacity(hasConfiguredWindowChrome ? 1 : 0)
                    .animation(nil, value: hasConfiguredWindowChrome)

                // Main content
                if currentStep == .completion {
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Each step is designed for the enforced onboarding window
                    // minimum. Give it the VStack's finite remaining size instead
                    // of measuring its full-height layout inside a vertical scroll
                    // proposal, which creates a circular ideal-height dependency.
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }

                if currentStep != .completion {
                    navigationControls
                        .padding(.horizontal, 40)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                        .frame(height: 92, alignment: .top)
                        .frame(maxWidth: .infinity)
                        .background(
                            OnboardingNavigationBackdrop()
                                .allowsHitTesting(false)
                        )
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea(.container, edges: .top)
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
                // Skip the staggered ReadyToOrganizeView cascade on first
                // appearance — the user just saw a long reveal animation in
                // the onboarding completion step, so an additional 0.4s of
                // staggered fade-ins on the main screen reads as lag rather
                // than polish.
                appState.hasPresentedReadyToOrganize = true
                hasCompletedOnboarding = true
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
                                            .numericTextTransition(animationValue: currentStep)
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
        guard isIntroVisible, !isDismissingIntro else { return }
        HapticFeedbackManager.shared.selection()

        isDismissingIntro = true
        introTransitionTask?.cancel()
        introTransitionTask = Task { @MainActor in
            // Materialize the first workflow step in a non-animated transaction.
            // The flow is inserted without animation so its fixed window layout
            // settles before the provider page begins its presentation effects.
            var preparation = Transaction(animation: nil)
            preparation.disablesAnimations = true
            withTransaction(preparation) {
                isFlowPrepared = true
            }

            guard !reduceMotion else {
                withTransaction(preparation) {
                    introTransitionProgress = 1
                    isIntroVisible = false
                    isDismissingIntro = false
                }
                return
            }

            // Give the prepared hierarchy one frame to resolve its fixed layout,
            // then animate only presentation properties. The visual crossfade is
            // unchanged, but layout is no longer part of the animation graph.
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.55)) {
                introTransitionProgress = 1
            }

            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            withTransaction(preparation) {
                isIntroVisible = false
                isDismissingIntro = false
            }
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
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var iconScale: CGFloat = 0.86
    @State private var iconOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var glowRadius: CGFloat = 28
    @State private var chromeRevealed = false
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 14
    @State private var filesAppeared = false
    @State private var fileIcons: [String: NSImage] = [:]
    @State private var collapseProgress: CGFloat = 0
    @State private var introFrame: CGRect = .zero
    @State private var getStartedButtonFrame: CGRect = .zero
    @State private var isHoveringButton = false
    @State private var revealGeneration = 0
    @State private var orbitEpoch = Date()
    @State private var orbitPausedAt: Date?
    @State private var iconPrewarmTask: Task<Void, Never>?
    @StateObject private var audio = OnboardingAudioManager()

    var body: some View {
        ZStack {
            // Phase 1 of the reveal shows only the icon and its rose glow on a
            // fully transparent window — no backdrop, no "app window" feel.
            // The gradient fades in later together with the title and button.
            OnboardingBottomGradient()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .opacity(chromeRevealed ? 0.92 : 0)

            // Real macOS file-type icons drift in a loose orbit, then tuck into
            // the Get Started button while it is hovered.
            // While Sorty is active, the timeline stays live so hovering never
            // interrupts the orbit. Inactive windows pause to avoid hidden
            // rendering; `orbitEpoch` excludes that paused time so the chips
            // resume without jumping. 24 fps keeps the visible drift smooth.
            SwiftUI.TimelineView(.animation(
                minimumInterval: 1.0 / 24.0,
                paused: reduceMotion || controlActiveState == .inactive || !filesAppeared
            )) { context in
                let phase = reduceMotion ? 0 : context.date.timeIntervalSince(orbitEpoch)
                ZStack {
                    ForEach(OnboardingOrbitFile.files) { file in
                        OnboardingOrbitFileChip(
                            file: file,
                            icon: fileIcons[file.ext] ?? OnboardingFileIconProvider.placeholder
                        )
                            .equatable()
                            .modifier(
                                OrbitChipPlacement(
                                    collapseProgress: collapseProgress,
                                    orbitOffset: orbitOffset(for: file, phase: phase),
                                    collapseOffset: collapseOffset(for: file),
                                    orbitRotation: file.rotation + sin(phase * 0.7 + file.driftPhase) * 3,
                                    orbitScale: file.scale
                                )
                            )
                            .opacity(filesAppeared ? 1 : 0)
                            .animation(
                                .spring(response: 0.7, dampingFraction: 0.86)
                                    .delay(file.appearDelay),
                                value: filesAppeared
                            )
                    }
                }
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

                        SortyEnergyScanIcon(
                            image: NSApp.applicationIconImage,
                            size: 156,
                            cornerRadius: 34
                        )
                            .shadow(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.22), radius: 34, x: 0, y: 0)
                            .shadow(color: .black.opacity(0.28), radius: 26, x: 0, y: 16)
                            .accessibilityHidden(true)
                    }
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)

                    Text("Welcome to Sorty")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
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
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    getStartedButtonFrame = frame
                }
                .onHover { hovering in
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        isHoveringButton = hovering
                    }
                    // Only the collapse blend is animated; the orbit keeps
                    // running underneath, so entering/leaving hover mid-flight
                    // always springs to the chips' live positions.
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                        collapseProgress = hovering ? 1 : 0
                    }
                }
                .scaleEffect(isHoveringButton ? 1.035 : 1)
                .opacity(textOpacity)
                .offset(y: textOffset)
                .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isHoveringButton)
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            introFrame = frame
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Sorty")
        .onAppear {
            runIntroReveal()
        }
        .onDisappear {
            revealGeneration += 1
            iconPrewarmTask?.cancel()
            audio.stopAll()
        }
        .onChange(of: controlActiveState, initial: true) { _, activeState in
            updateOrbitClock(for: activeState)
        }
    }

    /// Orchestrates the first-screen reveal in three deliberate phases:
    /// 1. Only the icon and its rose glow, floating on a transparent window.
    /// 2. After the icon has had the stage to itself, the gradient backdrop,
    ///    title, and button fade in together.
    /// 3. The orbiting file chips drift in last.
    /// The audio engine is deferred so its AVAudioEngine + AVAudioSourceNode
    /// setup does not block the first paint of the icon, and the
    /// `revealGeneration` counter cancels any in-flight reveal if the view
    /// disappears before the sequence finishes.
    private func runIntroReveal() {
        revealGeneration += 1
        let generation = revealGeneration
        iconPrewarmTask?.cancel()

        if reduceMotion {
            iconScale = 1
            iconOpacity = 1
            glowOpacity = 1
            glowRadius = 38
            chromeRevealed = true
            textOpacity = 1
            textOffset = 0
            fileIcons = OnboardingFileIconProvider.icons(for: OnboardingOrbitFile.files)
            filesAppeared = true
            audio.startBackgroundMelody()
            return
        }

        // Resolve the real workspace icons one at a time during the quiet
        // opening reveal. Doing all cold NSWorkspace lookups on the frame
        // where the chips appear causes a visible hitch, while spreading the
        // same work across existing animation time preserves the reveal.
        iconPrewarmTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard generation == revealGeneration, !Task.isCancelled else { return }
            await OnboardingFileIconProvider.prewarmIcons(
                for: OnboardingOrbitFile.files,
                generationIsCurrent: {
                    generation == revealGeneration && !Task.isCancelled
                }
            )
        }

        // Defer audio so the AVAudioEngine + AVAudioSourceNode setup runs
        // after the first paint settles, not on the same runloop tick as
        // the icon reveal.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard generation == revealGeneration else { return }
            audio.startBackgroundMelody()
        }

        // Phase 1 — the icon materializes with a clean fade + settle (no
        // blur-in) while the glow blooms around it.
        withAnimation(.easeOut(duration: 1.0)) {
            iconOpacity = 1
        }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.88)) {
            iconScale = 1
        }
        withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
            glowOpacity = 1
        }
        withAnimation(.easeInOut(duration: 1.5).delay(0.4)) {
            glowRadius = 38
        }

        Task { @MainActor in
            // Phase 2 — backdrop, title, and button.
            try? await Task.sleep(for: .milliseconds(1700))
            guard generation == revealGeneration else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                chromeRevealed = true
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                textOpacity = 1
                textOffset = 0
            }

            // Phase 3 — file chips drift in once everything has settled.
            try? await Task.sleep(for: .milliseconds(650))
            guard generation == revealGeneration else { return }
            fileIcons = OnboardingFileIconProvider.icons(for: OnboardingOrbitFile.files)
            filesAppeared = true
        }
    }

    private func orbitOffset(for file: OnboardingOrbitFile, phase: Double) -> CGSize {
        let orbitalAngle = phase * file.driftSpeed + file.driftPhase
        let orbitalX = cos(orbitalAngle) * file.orbitWidth * 1.18
        let orbitalY = sin(orbitalAngle) * file.orbitHeight * 1.22
        let driftX = cos(phase * 0.42 + file.driftPhase) * file.driftRadius * 1.28
        let driftY = sin(phase * 0.35 + file.driftPhase) * file.driftRadius * 1.32
        return CGSize(width: file.baseX + orbitalX + driftX, height: file.baseY + orbitalY + driftY)
    }

    private func collapseOffset(for file: OnboardingOrbitFile) -> CGSize {
        CGSize(
            width: getStartedButtonFrame.midX - introFrame.midX + file.collapseX * 0.65,
            height: getStartedButtonFrame.midY - introFrame.midY + file.collapseY * 0.18
        )
    }

    private func updateOrbitClock(for activeState: ControlActiveState) {
        let now = Date()
        if activeState == .inactive {
            orbitPausedAt = orbitPausedAt ?? now
        } else if let orbitPausedAt {
            orbitEpoch = orbitEpoch.addingTimeInterval(now.timeIntervalSince(orbitPausedAt))
            self.orbitPausedAt = nil
        }
    }
}

/// Blends each orbit chip between its live orbital placement and its
/// collapsed position inside the Get Started button. `collapseProgress` is the only
/// animated value — the orbit inputs update on every timeline tick — so the
/// hover collapse can be entered and exited mid-flight without position
/// jumps, and the orbit itself never freezes.
private struct OrbitChipPlacement: ViewModifier, Animatable {
    var collapseProgress: CGFloat
    var orbitOffset: CGSize
    var collapseOffset: CGSize
    var orbitRotation: Double
    var orbitScale: CGFloat

    nonisolated var animatableData: CGFloat {
        get { collapseProgress }
        set { collapseProgress = newValue }
    }

    func body(content: Content) -> some View {
        let t = min(max(collapseProgress, 0), 1)
        let collapseOpacity = 1 - max(0, (t - 0.72) / 0.28)
        content
            .rotationEffect(.degrees(orbitRotation * Double(1 - t)))
            .scaleEffect(orbitScale + (0.08 - orbitScale) * t)
            .offset(
                x: orbitOffset.width + (collapseOffset.width - orbitOffset.width) * t,
                y: orbitOffset.height + (collapseOffset.height - orbitOffset.height) * t
            )
            .opacity(Double(collapseOpacity))
    }
}

struct SortyEnergyScanIcon: View {
    let image: NSImage
    let size: CGFloat
    let cornerRadius: CGFloat
    var startDelay: TimeInterval = 0.8
    var sweepDuration: TimeInterval = 2.8
    var repeats = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearedAt: Date?
    @State private var isSweepRunning = false
    @State private var sweepFinished = false

    var body: some View {
        SwiftUI.TimelineView(.animation(
            minimumInterval: 1.0 / 60.0,
            paused: reduceMotion || !isSweepRunning || sweepFinished
        )) { context in
            EnergyScanIconFrame(
                image: image,
                size: size,
                cornerRadius: cornerRadius,
                phase: phase(at: context.date),
                reduceMotion: reduceMotion
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task {
            guard appearedAt == nil else { return }
            appearedAt = Date()

            // Keep the timeline fully paused during the fixed start delay,
            // when every requested frame would be identical.
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(startDelay))
            guard !Task.isCancelled else { return }
            isSweepRunning = true

            // A single deliberate sweep, then the timeline pauses for good.
            guard !repeats else { return }
            try? await Task.sleep(for: .seconds(sweepDuration + 0.1))
            guard !Task.isCancelled else { return }
            isSweepRunning = false
            sweepFinished = true
        }
    }

    private func phase(at date: Date) -> Double {
        if reduceMotion { return 0.92 }
        guard let appearedAt else { return 0 }

        let elapsed = date.timeIntervalSince(appearedAt) - startDelay
        guard elapsed > 0 else { return 0 }
        if repeats {
            return elapsed.truncatingRemainder(dividingBy: sweepDuration) / sweepDuration
        }
        return min(elapsed / sweepDuration, 1)
    }
}

private struct EnergyScanIconFrame: View {
    let image: NSImage
    let size: CGFloat
    let cornerRadius: CGFloat
    let phase: Double
    let reduceMotion: Bool

    private var scanProgress: CGFloat {
        let linearProgress = CGFloat(min(max((phase - 0.08) / 0.84, 0), 1))
        return linearProgress * linearProgress * (3 - 2 * linearProgress)
    }

    private var scanCenter: CGFloat {
        -0.24 + scanProgress * 1.48
    }

    private var scanStrength: CGFloat {
        guard !reduceMotion, phase >= 0.08, phase <= 0.92 else { return 0 }
        return CGFloat(sin(Double(scanProgress) * .pi))
    }

    private var iconShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var icon: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(iconShape)
    }

    var body: some View {
        ZStack {
            icon

            ZStack {
                LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color(red: 0.84, green: 0.18, blue: 1.00).opacity(0.36), location: 0.20),
                            .init(color: Color.white.opacity(0.90), location: 0.48),
                            .init(color: Color(red: 1.00, green: 0.16, blue: 0.42).opacity(0.82), location: 0.60),
                            .init(color: Color(red: 1.00, green: 0.48, blue: 0.14).opacity(0.32), location: 0.78),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: size * 1.7, height: size * 0.42)
                    .rotationEffect(.degrees(-11))
                    .offset(y: (scanCenter - 0.5) * size)
                    .blur(radius: max(0.6, size * 0.006))

                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.86))
                        .frame(width: size * 1.45, height: max(1.5, size * 0.012))
                        .rotationEffect(.degrees(-11))
                        .offset(y: (scanCenter - 0.5) * size)
                        .blur(radius: max(0.5, size * 0.004))
                        .opacity(0.72)
                }
                .frame(width: size, height: size)
                .mask(icon)
                .blendMode(.plusLighter)
                .opacity(scanStrength * 0.88)
        }
        .clipShape(iconShape)
        .frame(width: size, height: size)
        .compositingGroup()
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
    // Relative placement within the Get Started button when the pile collapses.
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
    private static let placeholderImage = NSWorkspace.shared.icon(forFileType: "")

    static var placeholder: NSImage {
        placeholderImage
    }

    static func icons(for files: [OnboardingOrbitFile]) -> [String: NSImage] {
        Dictionary(
            uniqueKeysWithValues: Set(files.map(\.ext)).map { ext in
                (ext, icon(for: ext))
            }
        )
    }

    static func prewarmIcons(
        for files: [OnboardingOrbitFile],
        generationIsCurrent: () -> Bool
    ) async {
        var resolvedExtensions = Set<String>()
        for file in files where resolvedExtensions.insert(file.ext).inserted {
            guard generationIsCurrent() else { return }
            _ = icon(for: file.ext)
            try? await Task.sleep(for: .milliseconds(45))
        }
    }

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

private struct OnboardingOrbitFileChip: View, @MainActor Equatable {
    let file: OnboardingOrbitFile
    let icon: NSImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.file.id == rhs.file.id && lhs.icon === rhs.icon
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: icon)
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

/// Places a visual-effect surface behind the onboarding window, leaving the
/// Sorty window clear while softening the rest of the current screen.
private struct OnboardingScreenBackdropBlurPresenter: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = ScreenTrackingView()
        view.onWindowChanged = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator {
        private weak var hostWindow: NSWindow?
        private var backdropPanel: NSPanel?
        private var observers: [NSObjectProtocol] = []
        private var pendingDismissal: DispatchWorkItem?
        private var isHostClosing = false

        func attach(to window: NSWindow?) {
            guard hostWindow !== window else {
                updatePanelFrame()
                return
            }

            removeObservers()
            pendingDismissal?.cancel()
            pendingDismissal = nil
            isHostClosing = false
            hostWindow = window

            guard let window else {
                dismissPanel()
                return
            }

            if backdropPanel == nil {
                backdropPanel = makeBackdropPanel()
            }

            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updatePanelFrame() }
                },
                center.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updatePanelFrame() }
                },
                center.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updatePanelFrame() }
                },
                center.addObserver(
                    forName: NSWindow.didChangeScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updatePanelFrame() }
                },
                center.addObserver(
                    forName: NSWindow.didMiniaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.hidePanelImmediately() }
                },
                center.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updatePanelFrame() }
                },
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.hostWillClose() }
                }
            ]

            updatePanelFrame()
            DispatchQueue.main.async { [weak self] in
                self?.updatePanelFrame()
            }
        }

        func dismiss() {
            dismiss(immediately: isHostClosing)
        }

        private func hostWillClose() {
            isHostClosing = true
            dismiss(immediately: true)
        }

        private func dismiss(immediately: Bool) {
            removeObservers()
            dismissPanel(immediately: immediately)
            hostWindow = nil
        }

        private func makeBackdropPanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .normal
            panel.alphaValue = 0
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .stationary
            ]

            let backdrop = NSVisualEffectView()
            backdrop.material = .fullScreenUI
            backdrop.blendingMode = .behindWindow
            backdrop.state = .active

            // A whisper of dimming on top of the blur separates the onboarding
            // window from the desktop without muddying the frosted look.
            let dimmingView = NSView()
            dimmingView.wantsLayer = true
            dimmingView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
            dimmingView.autoresizingMask = [.width, .height]
            dimmingView.frame = backdrop.bounds
            backdrop.addSubview(dimmingView)

            panel.contentView = backdrop
            return panel
        }

        private func updatePanelFrame() {
            guard let window = hostWindow,
                  window.isVisible,
                  !window.isMiniaturized,
                  let screen = window.screen ?? NSScreen.main else {
                hidePanelImmediately()
                return
            }

            if backdropPanel?.frame != screen.frame {
                backdropPanel?.setFrame(screen.frame, display: true)
            }
            backdropPanel?.order(.below, relativeTo: window.windowNumber)
            fadeInPanelIfNeeded()
        }

        private func dismissPanel(immediately: Bool = false) {
            guard let backdropPanel else { return }
            pendingDismissal?.cancel()
            let duration = immediately || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.8

            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                backdropPanel.animator().alphaValue = 0
            }

            let dismissal = DispatchWorkItem { [weak self, weak backdropPanel] in
                guard let self, self.backdropPanel === backdropPanel else { return }
                backdropPanel?.orderOut(nil)
                backdropPanel?.close()
                self.backdropPanel = nil
                self.pendingDismissal = nil
            }
            pendingDismissal = dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
        }

        private func hidePanelImmediately() {
            backdropPanel?.orderOut(nil)
            backdropPanel?.alphaValue = 0
        }

        private func fadeInPanelIfNeeded() {
            guard let backdropPanel, backdropPanel.alphaValue == 0 else { return }
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
                return
            }
            let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.9

            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                backdropPanel.animator().alphaValue = 0.62
            }
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
        }
    }

    private final class ScreenTrackingView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }
}

private struct OnboardingScreenEdgeGlowPresenter: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = ScreenTrackingView()
        view.onWindowChanged = { window in
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor
    final class Coordinator {
        private weak var hostWindow: NSWindow?
        private var glowPanel: NSPanel?
        private var observers: [NSObjectProtocol] = []
        private var pendingDismissal: DispatchWorkItem?
        private var isHostClosing = false

        func attach(to window: NSWindow?) {
            guard hostWindow !== window else {
                showPanelIfPossible()
                return
            }

            removeObservers()
            pendingDismissal?.cancel()
            pendingDismissal = nil
            isHostClosing = false
            hostWindow = window

            guard let window else {
                dismissPanel()
                return
            }

            if glowPanel == nil {
                glowPanel = makeGlowPanel()
            }

            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.showPanelIfPossible() }
                },
                center.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updatePanelFrame() }
                },
                center.addObserver(
                    forName: NSWindow.didChangeScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.updatePanelFrame() }
                },
                center.addObserver(
                    forName: NSWindow.didMiniaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.hidePanelImmediately() }
                },
                center.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.showPanelIfPossible() }
                },
                center.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.showPanelIfPossible() }
                },
                center.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.setGlowAnimationActive(false) }
                },
                center.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.hostWillClose() }
                }
            ]

            showPanelIfPossible()
            DispatchQueue.main.async { [weak self] in
                self?.showPanelIfPossible()
            }
        }

        func dismiss() {
            dismiss(immediately: isHostClosing)
        }

        private func hostWillClose() {
            isHostClosing = true
            dismiss(immediately: true)
        }

        private func dismiss(immediately: Bool) {
            removeObservers()
            dismissPanel(immediately: immediately)
            hostWindow = nil
        }

        private func makeGlowPanel() -> NSPanel {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .normal
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .ignoresCycle,
                .stationary
            ]
            panel.contentView = OnboardingScreenEdgeGlowView()
            return panel
        }

        private func updatePanelFrame() {
            guard let window = hostWindow,
                  window.isVisible,
                  !window.isMiniaturized,
                  let screen = window.screen ?? NSScreen.main else {
                hidePanelImmediately()
                return
            }
            if glowPanel?.frame != screen.frame {
                glowPanel?.setFrame(screen.frame, display: true)
            }
        }

        private func showPanelIfPossible() {
            guard let window = hostWindow, window.isVisible, !window.isMiniaturized else {
                hidePanelImmediately()
                return
            }
            updatePanelFrame()
            glowPanel?.alphaValue = 1
            setGlowAnimationActive(NSApp.isActive)
            glowPanel?.order(.below, relativeTo: window.windowNumber)
        }

        private func setGlowAnimationActive(_ isActive: Bool) {
            guard let glowView = glowPanel?.contentView as? OnboardingScreenEdgeGlowView else { return }
            if isActive {
                glowView.startAnimating()
            } else {
                glowView.stopAnimating()
            }
        }

        private func dismissPanel(immediately: Bool = false) {
            guard let glowPanel else { return }
            pendingDismissal?.cancel()
            let duration = immediately || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.8

            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glowPanel.animator().alphaValue = 0
            }

            let dismissal = DispatchWorkItem { [weak self, weak glowPanel] in
                guard let self, self.glowPanel === glowPanel else { return }
                glowPanel?.orderOut(nil)
                glowPanel?.close()
                self.glowPanel = nil
                self.pendingDismissal = nil
            }
            pendingDismissal = dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: dismissal)
        }

        private func hidePanelImmediately() {
            (glowPanel?.contentView as? OnboardingScreenEdgeGlowView)?.stopAnimating()
            glowPanel?.orderOut(nil)
            glowPanel?.alphaValue = 0
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
        }
    }

    private final class ScreenTrackingView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }
}

/// Draws the animated screen-edge glow with retained Core Animation layers.
/// The previous SwiftUI timeline rebuilt and blurred four screen-sized
/// gradients every frame. These narrow gradient layers produce the same soft
/// pulse while Core Animation updates only their opacity on the render server.
private final class OnboardingScreenEdgeGlowView: NSView {
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()
    private let leadingGradient = CAGradientLayer()
    private let trailingGradient = CAGradientLayer()
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        [topGradient, bottomGradient, leadingGradient, trailingGradient].forEach {
            layer?.addSublayer($0)
        }
        configureGradients()
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let verticalDepth = bounds.height * 0.17
        let horizontalDepth = bounds.width * 0.17
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topGradient.frame = CGRect(
            x: bounds.minX,
            y: bounds.maxY - verticalDepth,
            width: bounds.width,
            height: verticalDepth
        )
        bottomGradient.frame = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: verticalDepth
        )
        leadingGradient.frame = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: horizontalDepth,
            height: bounds.height
        )
        trailingGradient.frame = CGRect(
            x: bounds.maxX - horizontalDepth,
            y: bounds.minY,
            width: horizontalDepth,
            height: bounds.height
        )
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        configureGradients()
    }

    func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        let gradients = [topGradient, bottomGradient, leadingGradient, trailingGradient]
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            gradients.forEach { $0.opacity = 0.86 }
            return
        }

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 0.70
        pulse.toValue = 1.0
        pulse.duration = 2.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradients.forEach { $0.add(pulse, forKey: "onboardingEdgePulse") }
    }

    func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false
        let gradients = [topGradient, bottomGradient, leadingGradient, trailingGradient]
        gradients.forEach {
            $0.removeAnimation(forKey: "onboardingEdgePulse")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradients.forEach { $0.opacity = 0.86 }
        CATransaction.commit()
    }

    private func configureGradients() {
        let accent = resolvedAccentColor
        let colors = [
            accent.withAlphaComponent(0.74).cgColor,
            accent.withAlphaComponent(0.33).cgColor,
            accent.withAlphaComponent(0.10).cgColor,
            accent.withAlphaComponent(0).cgColor
        ]
        let locations: [NSNumber] = [0, 0.24, 0.58, 1]

        [topGradient, bottomGradient, leadingGradient, trailingGradient].forEach {
            $0.colors = colors
            $0.locations = locations
        }
        topGradient.startPoint = CGPoint(x: 0.5, y: 1)
        topGradient.endPoint = CGPoint(x: 0.5, y: 0)
        bottomGradient.startPoint = CGPoint(x: 0.5, y: 0)
        bottomGradient.endPoint = CGPoint(x: 0.5, y: 1)
        leadingGradient.startPoint = CGPoint(x: 0, y: 0.5)
        leadingGradient.endPoint = CGPoint(x: 1, y: 0.5)
        trailingGradient.startPoint = CGPoint(x: 1, y: 0.5)
        trailingGradient.endPoint = CGPoint(x: 0, y: 0.5)
    }

    private var resolvedAccentColor: NSColor {
        let raw = UserDefaults.standard.object(forKey: "AppleAccentColor")
        if let value = raw as? Int, value >= 0 {
            return .controlAccentColor
        }
        return NSColor(srgbRed: 0.850, green: 0.235, blue: 0.353, alpha: 1)
    }
}

struct OnboardingBottomGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    /// 0 = gradient hugs the bottom edge, 1 = gradient reaches near the top.
    var progress: Double = 0
    var showsBaseColor = true

    var body: some View {
        let clamped = max(0, min(1, progress))
        // Let the accent grow through the flow, then settle into a single
        // rose field on completion with the strongest color around the final
        // call to action.
        let completion = clamped * clamped
        let linearEnd = UnitPoint(x: 0.5, y: 0.68 - clamped * 0.56)
        let radialCenter = UnitPoint(x: 0.5, y: 1.02 - clamped * 0.18)
        let radialEnd = 680 + completion * 560
        let intensity = 0.98 + completion * 0.28
        let bottomOpacity = colorScheme == .dark ? 0.42 : 0.52
        let midOpacity = colorScheme == .dark ? 0.22 : 0.28
        let glowOpacity = colorScheme == .dark ? 0.28 : 0.36

        return ZStack(alignment: .bottom) {
            if showsBaseColor {
                Color(NSColor.windowBackgroundColor)
            }

            LinearGradient(
                stops: [
                    .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(bottomOpacity * intensity), location: 0.00),
                    .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(midOpacity * intensity), location: 0.42),
                    .init(color: Color.clear, location: 1.00)
                ],
                startPoint: .bottom,
                endPoint: linearEnd
            )

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.10), location: 0.00),
                    .init(color: Color.black.opacity(colorScheme == .dark ? 0.04 : 0.02), location: 0.32),
                    .init(color: Color.clear, location: 0.64)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                stops: [
                    .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(glowOpacity * intensity), location: 0.00),
                    .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.16 * intensity), location: 0.42),
                    .init(color: Color.clear, location: 1.00)
                ],
                center: radialCenter,
                startRadius: 0,
                endRadius: radialEnd
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
        private var originalContentMinSize: NSSize?

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
            originalContentMinSize = window.contentMinSize

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.isMovableByWindowBackground = true

            // Pin the window to the onboarding minimum content size before the
            // first paint so it never visibly resizes/reframes after appearing.
            let targetSize = NSSize(
                width: SortyDesignSystem.Sizing.windowOnboardingWidth,
                height: SortyDesignSystem.Sizing.windowOnboardingHeight
            )
            window.contentMinSize = targetSize
            if window.contentLayoutRect.width < targetSize.width
                || window.contentLayoutRect.height < targetSize.height
            {
                window.setContentSize(targetSize)
            }
            window.center()
            if let screen = window.screen ?? NSScreen.main {
                let centeredOrigin = window.frame.origin
                let loweredY = max(screen.visibleFrame.minY + 24, centeredOrigin.y - 32)
                window.setFrameOrigin(NSPoint(x: centeredOrigin.x, y: loweredY))
            }

            // Keep the window itself fully opaque so the opening screen is crisp.
            // OnboardingIntroView owns the staged reveal of its individual elements.
            window.alphaValue = 1
            window.makeKey()
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
            if let originalContentMinSize {
                window.contentMinSize = originalContentMinSize
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

                        let isComplete = step.rawValue < currentStep.rawValue

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

                    Text(LocalizedStringKey(step.title))
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

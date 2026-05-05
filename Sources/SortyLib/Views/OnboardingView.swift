//
//  OnboardingView.swift
//  Sorty
//
//  Interactive onboarding flow for first-time users
//  Steps: Welcome → Provider Selection → Permissions → Workflow → Demo → Completion
//

import AppKit
import SwiftUI

// MARK: - Main Onboarding View

public struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var codexAuth: CodexCLIAuthManager
    @ObservedObject private var copilotAuth = GitHubCopilotAuthManager.shared

    @State private var currentStep: OnboardingStep = .welcome
    @State private var hasFilesAndFoldersPermission = false
    @State private var advanceValidationMessage: String?
    @State private var isAdvancing = false
    @State private var swipeMonitor: Any?
    @State private var isHoveringStepIndicator = false
    @State private var swipeAccumulatedTranslation: CGFloat = 0
    @State private var hasTriggeredSwipeForGesture = false

    private let swipeThreshold: CGFloat = 42

    public init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Pinned with a fixed top padding so it doesn't shift between steps.
                    // Opaque background prevents scrolled step content from bleeding behind it.
                    OnboardingProgressBar(currentStep: currentStep)
                        .padding(.top, 54)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 48)
                        .background(Color(NSColor.windowBackgroundColor))

                    // Main content
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Navigation controls
                    navigationControls
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                }
                .ignoresSafeArea(.container, edges: .top)
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
        .background(OnboardingWindowTitleConfigurator().frame(width: 0, height: 0))
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
        case .welcome:
            WelcomeStepView()
                .transition(TransitionStyles.slideFromRight)
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
        let backHidden = (currentStep == .welcome || currentStep == .completion)

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
                        if currentStep != .completion && currentStep != .welcome {
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

                if currentStep == .welcome {
                    Button {
                        navigateForwardFromControls()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Get Started")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(.onboardingPill)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("OnboardingAdvanceButton")
                    .transition(.scale.combined(with: .opacity))
                }
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

    private func navigateToPreviousStep() {
        guard currentStep != .welcome && currentStep != .completion else { return }
        HapticFeedbackManager.shared.selection()
        withAnimation(.pageTransition) {
            currentStep = currentStep.previous
        }
    }

    private func navigateForwardFromControls() {
        guard currentStep != .completion else { return }

        switch currentStep {
        case .welcome:
            HapticFeedbackManager.shared.selection()
            withAnimation(.pageTransition) {
                currentStep = currentStep.next
            }
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
    case welcome = 0
    case provider = 1
    case permissions = 2
    case workflow = 3
    case demo = 4
    case completion = 5

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
        case .welcome: return "Welcome"
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
        case .welcome, .workflow, .demo, .completion:
            return .valid
        }
    }
}

// MARK: - Onboarding Title Bar

private struct OnboardingTopBar: View {
    var body: some View {
        Color.clear
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .allowsHitTesting(false)
    }
}

private struct OnboardingWindowTitleConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = WindowAttachedView()
        view.onWindowAttached = { window in
            context.coordinator.configure(window: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            context.coordinator.configure(window: window)
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

        func configure(window: NSWindow) {
            guard configuredWindow !== window else { return }
            restore()

            configuredWindow = window
            originalTitleVisibility = window.titleVisibility
            originalTitlebarAppearsTransparent = window.titlebarAppearsTransparent
            originalStyleMask = window.styleMask

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true

            // Pin the window to the onboarding minimum content size before the
            // first paint so it never visibly resizes/reframes after appearing.
            let targetSize = NSSize(width: 1100, height: 720)
            if window.frame.size.width < targetSize.width || window.frame.size.height < targetSize.height {
                window.setContentSize(targetSize)
                window.center()
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
                                ? Color.accentColor : Color.secondary.opacity(0.2)
                        )
                        .frame(width: 56, height: 2)
                }

                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(
                                step.rawValue <= currentStep.rawValue
                                    ? Color.accentColor : Color.secondary.opacity(0.2)
                            )
                            .frame(width: 24, height: 24)

                        if step.rawValue < currentStep.rawValue {
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

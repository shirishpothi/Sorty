//
//  OnboardingView.swift
//  Sorty
//
//  Interactive onboarding flow for first-time users
//  Steps: Welcome → Provider Selection → Permissions → Workflow → Demo → Completion
//

import SwiftUI
import AppKit

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
                    // Keep the progress row clear of macOS title bar variants.
                    OnboardingProgressBar(currentStep: currentStep)
                        .padding(.top, max(44, geometry.safeAreaInsets.top + 16))
                        .padding(.horizontal, 60)
                    
                    // Main content
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Navigation controls
                    navigationControls
                        .padding(.horizontal, 40)
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 720)
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

        return VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 16) {
                // Back button - show for all steps except welcome and completion
                    Group {
                        if currentStep != .welcome && currentStep != .completion {
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
                        }
                    }
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
                            } else if currentStep == .welcome {
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
                                .opacity(currentStepValidation.canAdvance && !isAdvancing ? 1.0 : 0.5)
                                .accessibilityIdentifier("OnboardingAdvanceButton")
                            }
                        }
                    }
                    .frame(width: sideControlWidth, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)

                // Step indicators - always centered in the navigation row
                stepIndicator
                    .frame(width: 340, height: 84)
                    .contentShape(Rectangle())
                    .background(Color.clear)
                    .onHover { isHovering in
                        isHoveringStepIndicator = isHovering
                        if !isHovering {
                            resetSwipeTracking()
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)

            if let advanceValidationMessage, !advanceValidationMessage.isEmpty, currentStep != .provider {
                Text(advanceValidationMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("OnboardingValidationMessage")
            }
        }
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.activeCases, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ? Color.accentColor : 
                          step.rawValue < currentStep.rawValue ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: step == currentStep ? 10 : 8, height: step == currentStep ? 10 : 8)
                    .overlay(
                        step.rawValue < currentStep.rawValue ?
                        Image(systemName: "checkmark")
                            .font(.system(size: 5, weight: .bold))
                            .foregroundStyle(.white) : nil
                    )
                    .animation(.subtleBounce, value: currentStep)
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
                providerSetupStatus: OnboardingSetupValidator.providerStatus(context: providerSetupContext),
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
            providerSetupStatus: OnboardingSetupValidator.providerStatus(context: providerSetupContext),
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

        let deltaX = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 8
        let deltaY = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8

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
    func synchronousValidation(in context: OnboardingStepValidationContext) -> OnboardingStepValidationResult {
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

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep
    
    @MainActor
    private var activeSteps: [OnboardingStep] {
        OnboardingStep.activeCases
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<activeSteps.count, id: \.self) { index in
                let step = activeSteps[index]
                
                if index > 0 {
                    Rectangle()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 2)
                }
                
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 24, height: 24)
                        
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : .secondary)
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
                .frame(width: 80)
            }
        }
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

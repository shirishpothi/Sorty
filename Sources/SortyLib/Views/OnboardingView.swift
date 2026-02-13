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
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var hasFilesAndFoldersPermission = false
    
    public init(hasCompletedOnboarding: Binding<Bool>) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
    }
    
    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressBar(currentStep: currentStep)
                    .padding(.top, 28)
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
        .frame(minWidth: 1000, minHeight: 720)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding")
        .accessibilityIdentifier("OnboardingView")
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
            })
            .transition(TransitionStyles.scaleAndFade)
        }
    }
    
    private var navigationControls: some View {
        let sideControlWidth: CGFloat = 180

        return ZStack {
            HStack(spacing: 16) {
                // Back button - show for all steps except welcome and completion
                Group {
                    if currentStep != .welcome && currentStep != .completion {
                        Button {
                            HapticFeedbackManager.shared.selection()
                            withAnimation(.pageTransition) {
                                currentStep = currentStep.previous
                            }
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
                    }
                }
                .frame(width: sideControlWidth, alignment: .leading)

                Spacer(minLength: 0)

                // Next/Skip button
                Group {
                    if currentStep != .completion {
                        if currentStep == .demo {
                            Button {
                                HapticFeedbackManager.shared.selection()
                                withAnimation(.pageTransition) {
                                    currentStep = .completion
                                }
                            } label: {
                                Text("Skip Demo")
                                    .frame(minWidth: 80)
                            }
                            .buttonStyle(.bordered)
                        } else if currentStep == .welcome {
                            Button {
                                HapticFeedbackManager.shared.selection()
                                withAnimation(.pageTransition) {
                                    currentStep = currentStep.next
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Get Started")
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .buttonStyle(.onboardingPill)
                            .keyboardShortcut(.defaultAction)
                        } else {
                            // Determine if Continue should be disabled on permissions step
                            let canProceed = currentStep != .permissions || hasFilesAndFoldersPermission

                            Button {
                                HapticFeedbackManager.shared.selection()
                                withAnimation(.pageTransition) {
                                    currentStep = currentStep.next
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(currentStep == .permissions ? "Continue" : "Next")
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .buttonStyle(.onboardingPill)
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(!canProceed)
                            .opacity(canProceed ? 1.0 : 0.5)
                        }
                    }
                }
                .frame(width: sideControlWidth, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)

            // Step indicators - always centered in the navigation row
            stepIndicator
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
    }
    
    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
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
}

// MARK: - Onboarding Step Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case provider = 1
    case permissions = 2
    case workflow = 3
    case demo = 4
    case completion = 5
    
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
    
    var next: OnboardingStep {
        OnboardingStep(rawValue: min(rawValue + 1, OnboardingStep.allCases.count - 1)) ?? self
    }
    
    var previous: OnboardingStep {
        OnboardingStep(rawValue: max(rawValue - 1, 0)) ?? self
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                if step.rawValue > 0 {
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
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(step.rawValue <= currentStep.rawValue ? .white : .secondary)
                        }
                    }
                    
                    Text(step.title)
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                }
                .frame(width: 80)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(SettingsViewModel())
        .environmentObject(PersonaManager())
        .environmentObject(FolderOrganizer())
        .environmentObject(AppState())
}

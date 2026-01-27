//
//  OnboardingView.swift
//  Sorty
//
//  Interactive onboarding flow for first-time users
//  Steps: Provider Selection → Permissions → Workflow → Demo → Completion
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
    @State private var isAnimating = false
    
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
                    .padding(.top, 20)
                    .padding(.horizontal, 40)
                
                // Main content
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Navigation controls
                navigationControls
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
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
            WelcomeStep()
                .transition(TransitionStyles.slideFromRight)
        case .provider:
            ProviderSelectionStep()
                .transition(TransitionStyles.slideFromRight)
        case .permissions:
            PermissionsStep()
                .transition(TransitionStyles.slideFromRight)
        case .workflow:
            WorkflowSelectionStep()
                .transition(TransitionStyles.slideFromRight)
        case .demo:
            DemoStep(onComplete: {
                withAnimation(.pageTransition) {
                    currentStep = .completion
                }
            })
            .transition(TransitionStyles.slideFromRight)
        case .completion:
            CompletionStep(onFinish: {
                HapticFeedbackManager.shared.success()
                withAnimation(.easeOut(duration: 0.5)) {
                    hasCompletedOnboarding = true
                }
            })
            .transition(TransitionStyles.scaleAndFade)
        }
    }
    
    private var navigationControls: some View {
        HStack(spacing: 16) {
            // Back button - show for all steps except welcome and completion
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
            
            Spacer()
            
            // Step indicators
            stepIndicator
            
            Spacer()
            
            // Next/Skip button
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
                }
            }
        }
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
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    if step.rawValue > 0 {
                        Rectangle()
                            .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: 2)
                    }
                    
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
                }
            }
            
            HStack {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Text(step.title)
                        .font(.caption2)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Step 0: Welcome

struct WelcomeStep: View {
    @State private var hasAppeared = false
    @State private var featuresAppeared = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // App icon and title
            VStack(spacing: 24) {
                // Use the application icon directly which is safer than bundle loading
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
                    .scaleEffect(hasAppeared ? 1 : 0.5)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                
                VStack(spacing: 12) {
                    Text("Welcome to Sorty")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                    
                    Text("AI-powered file organization for your Mac")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 15)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                }
            }
            
            Spacer()
                .frame(height: 48)
            
            // Key features
            VStack(alignment: .leading, spacing: 16) {
                        WelcomeFeatureRow(
                            icon: "wand.and.stars",
                            iconColor: .purple,
                            title: "Smart Organization",
                            description: "AI analyzes your files and creates a logical folder structure"
                        )
                        .opacity(featuresAppeared ? 1 : 0)
                        .offset(x: featuresAppeared ? 0 : -30)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: featuresAppeared)
                        
                        WelcomeFeatureRow(
                            icon: "lock.shield.fill",
                            iconColor: .green,
                            title: "Privacy Focused",
                            description: "File names and metadata are sent to AI for organization - file contents stay on your Mac unless Deep Scan is enabled"
                        )
                        .opacity(featuresAppeared ? 1 : 0)
                        .offset(x: featuresAppeared ? 0 : -30)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: featuresAppeared)
                        
                        WelcomeFeatureRow(
                            icon: "arrow.uturn.backward.circle.fill",
                            iconColor: .blue,
                            title: "Fully Reversible",
                            description: "Every change can be undone with a single click",
                            badge: "Beta"
                        )
                        .opacity(featuresAppeared ? 1 : 0)
                        .offset(x: featuresAppeared ? 0 : -30)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6), value: featuresAppeared)
                        
                        WelcomeFeatureRow(
                            icon: "person.crop.circle.badge.checkmark",
                            iconColor: .orange,
                            title: "Custom Workflows",
                            description: "Create personas tailored to your specific organization needs"
                        )
                        .opacity(featuresAppeared ? 1 : 0)
                        .offset(x: featuresAppeared ? 0 : -30)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.7), value: featuresAppeared)
                    }
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 60)
            
            Spacer()
                .frame(height: 32)
            
            // Important notice
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 18))
                
                Text("Before organizing, always ensure you have backups of important files.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer() // Push content to left
            }
            .padding(16)
            .frame(maxWidth: 500)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.05))
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
            .opacity(featuresAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8), value: featuresAppeared)
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation {
                    featuresAppeared = true
                }
            }
        }
    }
}

struct WelcomeFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    var badge: String? = nil
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                    
                    if let badge = badge {
                        Text(badge.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Step 1: Provider Selection

struct ProviderSelectionStep: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject var copilotAuth = GitHubCopilotAuthManager.shared
    @State private var hasAppeared = false
    @State private var connectionStatus: ConnectionTestStatus = .idle
    @State private var connectionError: String?
    @State private var testDebounceTask: Task<Void, Never>?
    @State private var hasCopiedCode = false
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    
    enum ConnectionTestStatus {
        case idle
        case testing
        case success
        case failed
    }
    
    let providers = AIProvider.allCases
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - messaging
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundStyle(.purple)
                    
                    Text("You choose where your data goes")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("Sorty works with multiple AI providers. Your files are processed locally, and only file names and metadata are sent to the AI for organization suggestions.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        PrivacyFeatureRow(icon: "doc.text", text: "File names and metadata sent to AI")
                        PrivacyFeatureRow(icon: "folder", text: "File contents stay local (unless Deep Scan is enabled)")
                        PrivacyFeatureRow(icon: "arrow.uturn.backward", text: "All changes are reversible", badge: "Beta")
                        PrivacyFeatureRow(icon: "server.rack", text: "Use local models for full privacy")
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 350)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Right side - provider selection and configuration
            ScrollView {
                VStack(spacing: 20) {
                    Text("Select AI Provider")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    // Provider list
                    VStack(spacing: 4) {
                        ForEach(providers, id: \.self) { provider in
                            OnboardingProviderRow(
                                provider: provider,
                                isSelected: settingsViewModel.config.provider == provider
                            ) {
                                selectProvider(provider)
                            }
                        }
                    }
                    .frame(maxWidth: 380)
                    
                    // Configuration section for selected provider
                    if settingsViewModel.config.provider != .appleFoundationModel {
                        // Info Card / Liquid Note style container
                        VStack(spacing: 0) {
                            // Header
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(.secondary)
                                Text("Configuration")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.05))
                            
                            Divider()
                            
                            // Content
                            Group {
                                if settingsViewModel.config.provider == .githubCopilot {
                                    onboardingCopilotConfig
                                } else {
                                    providerConfigSection
                                }
                            }
                            .padding(16)
                        }
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        .frame(maxWidth: 380)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Connection status
                    connectionStatusView
                        .frame(maxWidth: 380)
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
        }
        .onAppear {
            withAnimation { hasAppeared = true }
        }
    }
    
    @ViewBuilder
    private var onboardingCopilotConfig: some View {
        VStack(alignment: .leading, spacing: 16) {
            if copilotAuth.isAuthenticated {
                // Signed in state
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(copilotAuth.username ?? "User")
                            .font(.headline)
                    }
                    
                    Spacer()
                    
                    Button("Sign Out") {
                        copilotAuth.signOut()
                        connectionStatus = .idle
                        availableModels = []
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                
                // Model selector - fetched dynamically from GitHub Copilot API
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack {
                        if !availableModels.isEmpty {
                            Picker("", selection: Binding(
                                get: { settingsViewModel.config.model },
                                set: { settingsViewModel.config.model = $0 }
                            )) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        } else if isLoadingModels {
                            HStack(spacing: 8) {
                                BouncingSpinner(size: 12, color: .secondary)
                                Text("Loading models...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text(settingsViewModel.config.model)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Text("Select the model to use with GitHub Copilot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    if copilotAuth.isAuthenticated && availableModels.isEmpty {
                        fetchCopilotModels()
                    }
                }
                
            } else if let code = copilotAuth.deviceCodeResponse {
                // Device code flow
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Open verification page")
                            .font(.caption).bold()
                        
                        Link(destination: URL(string: code.verificationUri)!) {
                            HStack {
                                Text(code.verificationUri)
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. Enter code")
                            .font(.caption).bold()
                        
                        HStack {
                            Text(code.userCode)
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(code.userCode, forType: .string)
                                hasCopiedCode = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { hasCopiedCode = false }
                            } label: {
                                Image(systemName: hasCopiedCode ? "checkmark" : "doc.on.doc")
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy code")
                        }
                    }
                    
                    HStack(spacing: 8) {
                        BouncingSpinner(size: 8, color: .secondary)
                        Text("Waiting for authorization...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
            } else {
                // Sign in prompt
                VStack(alignment: .leading, spacing: 12) {
                    Text("Access OpenAI models via your GitHub Copilot subscription.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        Task { try? await copilotAuth.startDeviceFlow() }
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                            Text("Sign in with GitHub")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.onboardingPill)
                    
                    if let error = copilotAuth.authError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var providerConfigSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // API URL field for OpenAI-compatible and Ollama
            if settingsViewModel.config.provider == .openAICompatible || settingsViewModel.config.provider == .ollama {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API URL")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField("https://api.example.com", text: Binding(
                        get: { settingsViewModel.config.apiURL ?? settingsViewModel.config.provider.defaultAPIURL ?? "" },
                        set: { 
                            settingsViewModel.config.apiURL = $0.isEmpty ? nil : $0
                            scheduleConnectionTest()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    Text(settingsViewModel.config.provider == .ollama ? 
                         "Default: http://localhost:11434" : 
                         "Enter the base URL of your OpenAI-compatible API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            // API Key field
            if settingsViewModel.config.provider.typicallyRequiresAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    SecureField("Enter your API key", text: Binding(
                        get: { settingsViewModel.config.apiKey ?? "" },
                        set: { 
                            settingsViewModel.config.apiKey = $0.isEmpty ? nil : $0
                            scheduleConnectionTest()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    // Clickable link to get API key
                    if let url = settingsViewModel.config.provider.apiKeyURL {
                        HStack(spacing: 4) {
                            Text("Get your API key at")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Link(destination: url) {
                                Text(settingsViewModel.config.provider.apiKeyLinkLabel)
                                    .font(.caption)
                                    .underline()
                            }
                            
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    } else {
                        Text(settingsViewModel.config.provider.apiKeyHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Model selector
            if settingsViewModel.config.provider != .githubCopilot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextField(settingsViewModel.config.provider.defaultModel, text: Binding(
                        get: { settingsViewModel.config.model },
                        set: { 
                            settingsViewModel.config.model = $0.isEmpty ? settingsViewModel.config.provider.defaultModel : $0
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    
                    HStack(spacing: 4) {
                        Text("Recommended: \(settingsViewModel.config.provider.defaultModel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if let url = settingsViewModel.config.provider.modelDocumentationURL {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Link(destination: url) {
                                HStack(spacing: 2) {
                                    Text("See \(settingsViewModel.config.provider.modelDocsLinkLabel)")
                                        .font(.caption)
                                        .underline()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 8))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    @ViewBuilder
    private var connectionStatusView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                switch connectionStatus {
                case .idle:
                    Button {
                        testConnection()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "network")
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canTestConnection)
                    
                case .testing:
                    HStack(spacing: 8) {
                        BouncingSpinner(size: 14, color: .accentColor)
                        Text("Testing connection...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                case .success:
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connection successful")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                    
                case .failed:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Connection failed")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                            
                            Spacer()
                            
                            Button("Retry") {
                                testConnection()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        if let error = connectionError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        
                        Text("You can continue anyway and fix this later in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(connectionStatusBackgroundColor)
        )
    }
    
    private var connectionStatusBackgroundColor: Color {
        switch connectionStatus {
        case .idle: return Color.secondary.opacity(0.05)
        case .testing: return Color.blue.opacity(0.05)
        case .success: return Color.green.opacity(0.1)
        case .failed: return Color.orange.opacity(0.1)
        }
    }
    
    private var canTestConnection: Bool {
        let provider = settingsViewModel.config.provider
        if provider == .appleFoundationModel {
            return provider.isAvailable
        }
        if provider == .githubCopilot {
            return copilotAuth.isAuthenticated
        }
        if provider == .ollama {
            return true // Ollama doesn't require API key
        }
        if provider.typicallyRequiresAPIKey {
            return (settingsViewModel.config.apiKey ?? "").count >= 10
        }
        return true
    }
    
    private func selectProvider(_ provider: AIProvider) {
        HapticFeedbackManager.shared.selection()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            settingsViewModel.config.provider = provider
            if let defaultURL = provider.defaultAPIURL {
                settingsViewModel.config.apiURL = defaultURL
            }
            settingsViewModel.config.model = provider.defaultModel
            settingsViewModel.config.requiresAPIKey = provider.typicallyRequiresAPIKey
            connectionStatus = .idle
            connectionError = nil
        }
    }
    
    private func scheduleConnectionTest() {
        testDebounceTask?.cancel()
        connectionStatus = .idle
        
        testDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            if !Task.isCancelled && canTestConnection {
                await MainActor.run {
                    testConnection()
                }
            }
        }
    }
    
    private func testConnection() {
        connectionStatus = .testing
        connectionError = nil
        
        Task {
            do {
                try await settingsViewModel.testConnection()
                await MainActor.run {
                    withAnimation {
                        connectionStatus = .success
                    }
                    HapticFeedbackManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        connectionStatus = .failed
                        connectionError = error.localizedDescription
                    }
                    HapticFeedbackManager.shared.error()
                }
            }
        }
    }
    
    private func fetchCopilotModels() {
        guard settingsViewModel.config.provider == .githubCopilot, copilotAuth.isAuthenticated else { return }
        
        isLoadingModels = true
        Task {
            do {
                if let client = try AIClientFactory.createClient(config: settingsViewModel.config) as? GitHubCopilotClient {
                    let models = try await client.fetchAvailableModels()
                    await MainActor.run {
                        availableModels = models
                        // Ensure current model is valid
                        if !models.contains(settingsViewModel.config.model) {
                            settingsViewModel.config.model = models.first ?? "gpt-4"
                        }
                        isLoadingModels = false
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingModels = false
                }
            }
        }
    }
}

struct PrivacyFeatureRow: View {
    let icon: String
    let text: String
    var badge: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            if let badge = badge {
                Text(badge.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

struct OnboardingProviderRow: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            if provider.isAvailable { action() }
        }) {
            HStack(spacing: 12) {
                ProviderLogoView(provider: provider, size: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .foregroundColor(provider.isAvailable ? .primary : .secondary)
                        .fontWeight(isSelected ? .semibold : .regular)
                    
                    if provider == .ollama {
                        Text("Local • No API key needed")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if provider == .appleFoundationModel {
                        Text("On-device • Apple Intelligence")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 18))
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                
                if !provider.isAvailable {
                    Text("Unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .opacity(provider.isAvailable ? 1.0 : 0.6)
    }
}

// MARK: - Step 2: Permissions

struct PermissionsStep: View {
    @State private var hasAppeared = false
    @State private var permissionStates: [PermissionType: PermissionState] = [:]
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - explanation
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    
                    Text("Permissions")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("Sorty needs a few permissions to organize your files effectively. You can grant these now or later when needed.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why these permissions?")
                            .font(.subheadline.bold())
                        
                        Text("• **Files & Folders**: To read and move your files\n• **Automation**: For Finder integration\n• **Notifications**: To alert you when organization completes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 350)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Right side - permission requests
            VStack(spacing: 24) {
                Text("Grant Permissions")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                VStack(spacing: 16) {
                    PermissionRow(
                        type: .filesAndFolders,
                        state: permissionStates[.filesAndFolders] ?? .unknown,
                        onRequest: { requestPermission(.filesAndFolders) }
                    )
                    
                    PermissionRow(
                        type: .automation,
                        state: permissionStates[.automation] ?? .unknown,
                        onRequest: { requestPermission(.automation) }
                    )
                    
                    PermissionRow(
                        type: .notifications,
                        state: permissionStates[.notifications] ?? .unknown,
                        onRequest: { requestPermission(.notifications) }
                    )
                }
                .frame(maxWidth: 400)
                
                Text("You can skip this step and grant permissions later")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 40)
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
        }
        .onAppear {
            withAnimation { hasAppeared = true }
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        // Check notification permission
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized:
                    permissionStates[.notifications] = .granted
                case .denied:
                    permissionStates[.notifications] = .denied
                default:
                    permissionStates[.notifications] = .unknown
                }
            }
        }
        
        // Files and Automation permissions are implicit - just show as requestable
        permissionStates[.filesAndFolders] = .unknown
        permissionStates[.automation] = .unknown
    }
    
    private func requestPermission(_ type: PermissionType) {
        HapticFeedbackManager.shared.tap()
        
        switch type {
        case .filesAndFolders:
            // Open System Preferences to Security & Privacy
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
            permissionStates[.filesAndFolders] = .pending
            
        case .automation:
            // Open System Preferences to Automation
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
            permissionStates[.automation] = .pending
            
        case .notifications:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                DispatchQueue.main.async {
                    permissionStates[.notifications] = granted ? .granted : .denied
                    if granted {
                        HapticFeedbackManager.shared.success()
                    }
                }
            }
        }
    }
}

import UserNotifications

enum PermissionType: String {
    case filesAndFolders = "Files & Folders"
    case automation = "Automation"
    case notifications = "Notifications"
    
    var icon: String {
        switch self {
        case .filesAndFolders: return "folder.fill"
        case .automation: return "gearshape.2.fill"
        case .notifications: return "bell.fill"
        }
    }
    
    var description: String {
        switch self {
        case .filesAndFolders: return "Access to read and organize your files"
        case .automation: return "Control Finder for seamless integration"
        case .notifications: return "Get notified when organization completes"
        }
    }
    
    var color: Color {
        switch self {
        case .filesAndFolders: return .blue
        case .automation: return .orange
        case .notifications: return .purple
        }
    }
}

enum PermissionState {
    case unknown
    case pending
    case granted
    case denied
}

struct PermissionRow: View {
    let type: PermissionType
    let state: PermissionState
    let onRequest: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(type.color.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(type.color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.headline)
                
                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            case .denied:
                Button("Open Settings") {
                    onRequest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .pending:
                Text("Check Settings")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .unknown:
                Button("Grant") {
                    onRequest()
                }
                .buttonStyle(.onboardingPill)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(state == .granted ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Step 3: Workflow Selection

struct WorkflowSelectionStep: View {
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @StateObject private var customPersonaStore = CustomPersonaStore()
    @State private var hasAppeared = false
    @State private var showingPersonaGenerator = false
    @State private var isCreatingCustom = false
    @State private var customDescription = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedPersona: CustomPersona?
    @State private var showingSuccess = false
    
    @StateObject private var generator = PersonaGenerator()
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - explanation
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.teal)
                    
                    Text("Choose Your Workflow")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("Select a persona that matches how you work. This helps the AI understand your organization preferences.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("You can change this anytime in Settings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: 350)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Right side - persona selection
            VStack(spacing: 20) {
                Spacer()
                
                Text("Select Default Persona")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                // Built-in personas grid - 2x2 layout
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PersonaType.allCases, id: \.self) { persona in
                        OnboardingPersonaCard(
                            persona: persona,
                            isSelected: personaManager.selectedPersona == persona && personaManager.selectedCustomPersonaId == nil
                        ) {
                            HapticFeedbackManager.shared.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                personaManager.selectPersona(persona)
                                personaManager.selectedCustomPersonaId = nil
                                isCreatingCustom = false
                            }
                        }
                    }
                }
                .frame(maxWidth: 420)
                
                // Divider with "or"
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                }
                .frame(maxWidth: 420)
                
                // Show "Create Your Own" button
                CreatePersonaButton(isCreatingCustom: $isCreatingCustom)
                    .frame(maxWidth: 420)
                
                // Show generated/selected custom persona if any
                if let persona = generatedPersona {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(persona.name)
                                .font(.headline)
                            Text("Custom persona created successfully")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                    .frame(maxWidth: 420)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
        }
        .overlay {
            // Modal overlay for custom persona creation
            if isCreatingCustom {
                ZStack {
                    // Dimmed background - click to dismiss
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isCreatingCustom = false
                                customDescription = ""
                                generationError = nil
                            }
                        }
                    
                    // Modal content
                    customPersonaCreationView
                        .frame(maxWidth: 450)
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCreatingCustom)
        .onAppear {
            withAnimation { hasAppeared = true }
        }
    }
    
    @ViewBuilder
    private var customPersonaCreationView: some View {
        VStack(spacing: 20) {
            if isGenerating {
                // Generating state - animated loading
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Creating Your Persona")
                            .font(.title3.bold())
                        
                        Text("AI is analyzing your workflow description...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding(.top, 8)
                }
                .frame(minHeight: 200)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if showingSuccess, let persona = generatedPersona {
                // Success state - shown briefly before closing
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Persona Created!")
                            .font(.title3.bold())
                        
                        Text("\"\(persona.name)\" is now your default workflow")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(minHeight: 200)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Input form state
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundStyle(.primary)
                        }
                        
                        Text("Create Custom Persona")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe how you want your files organized:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $customDescription)
                            .font(.body)
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                        
                        Text("Example: \"I'm a photographer. Organize my photos by year, then event name, with RAW files separate from JPEGs.\"")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                    
                    if let error = generationError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isCreatingCustom = false
                                customDescription = ""
                                generationError = nil
                            }
                        } label: {
                            Text("Cancel")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            generateCustomPersona()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Generate")
                            }
                        }
                        .buttonStyle(.onboardingPill)
                        .disabled(customDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isGenerating)
    }
    
    private func generateCustomPersona() {
        isGenerating = true
        generationError = nil
        
        Task {
            do {
                let result = try await generator.generatePersona(
                    from: customDescription,
                    answers: [],
                    config: settingsViewModel.config
                )
                
                let newPersona = CustomPersona(
                    name: result.name,
                    description: customDescription,
                    promptModifier: result.prompt
                )
                
                await MainActor.run {
                    // Save the persona
                    customPersonaStore.addPersona(newPersona)
                    
                    // Select it
                    personaManager.selectedCustomPersonaId = newPersona.id
                    
                    // Update UI - show success state
                    generatedPersona = newPersona
                    isGenerating = false
                    showingSuccess = true
                    
                    HapticFeedbackManager.shared.success()
                    
                    // Auto-close after showing success
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isCreatingCustom = false
                            showingSuccess = false
                            customDescription = ""
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGenerating = false
                    HapticFeedbackManager.shared.error()
                }
            }
        }
    }
}

struct OnboardingPersonaCard: View {
    let persona: PersonaType
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: persona.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                
                VStack(spacing: 4) {
                    Text(persona.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(persona.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.3 : 0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Create Persona Button (matches OnboardingPersonaCard styling)

struct CreatePersonaButton: View {
    @Binding var isCreatingCustom: Bool
    @State private var isHovered = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCreatingCustom = true
            }
            HapticFeedbackManager.shared.selection()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundStyle(.primary)
                }
                
                VStack(spacing: 4) {
                    Text("Create Your Own")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Describe your ideal organization style")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Step 4: Demo

struct DemoStep: View {
    let onComplete: () -> Void
    
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var hasAppeared = false
    @State private var selectedDirectory: URL?
    @State private var demoState: DemoState = .intro
    @State private var showPreviewTree = false
    @State private var showSimulatedDemo = true
    
    enum DemoState {
        case intro
        case simulatedDemo
        case selectDirectory
        case analyzing
        case organizing
        case complete
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - What to expect
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: demoState == .simulatedDemo ? "sparkles" : "wand.and.stars")
                        .font(.system(size: 48))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.pulse.byLayer, options: .repeating, isActive: demoState == .simulatedDemo)
                    
                    Text(demoState == .complete ? "That's Sorty!" : "See the Magic")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text(leftPanelDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        DemoFeatureRow(icon: "magnifyingglass", text: "Deep file analysis", isActive: demoState == .simulatedDemo || demoState == .analyzing)
                        DemoFeatureRow(icon: "brain", text: "AI-powered categorization", isActive: demoState == .simulatedDemo || demoState == .organizing)
                        DemoFeatureRow(icon: "folder.badge.gearshape", text: "Smart folder structure", isActive: demoState == .complete)
                        DemoFeatureRow(icon: "arrow.uturn.backward.circle", text: "Fully reversible changes", isActive: demoState == .complete)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: 350)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Right side - Demo interaction
            VStack(spacing: 32) {
                Spacer()
                
                switch demoState {
                case .intro:
                    introView
                case .simulatedDemo:
                    SimulatedDemoAnimationView(onComplete: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            demoState = .complete
                        }
                        HapticFeedbackManager.shared.success()
                    })
                case .selectDirectory:
                    selectDirectoryView
                case .analyzing, .organizing:
                    processingView
                case .complete:
                    completeView
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, 60)
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
        }
        .onAppear {
            withAnimation { hasAppeared = true }
        }
        .onChange(of: organizer.state) { _, newState in
            handleStateChange(newState)
        }
    }
    
    @ViewBuilder
    private var introView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.15), .blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.pulse.byLayer, options: .repeating)
            }
            
            VStack(spacing: 12) {
                Text("See Sorty in Action")
                    .font(.title2.bold())
                
                Text("Watch a live demo showing how Sorty transforms a messy folder into an organized structure using AI.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            VStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        demoState = .simulatedDemo
                    }
                    HapticFeedbackManager.shared.tap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Watch Demo")
                    }
                }
                .buttonStyle(.onboardingPill)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        demoState = .selectDirectory
                    }
                    HapticFeedbackManager.shared.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                        Text("Or try with your own folder")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var selectDirectoryView: some View {
        VStack(spacing: 24) {
            if let url = selectedDirectory {
                // Selected folder display
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "folder.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button {
                            selectedDirectory = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .frame(maxWidth: 400)
                    
                    HStack(spacing: 12) {
                        Button {
                            selectDirectory()
                        } label: {
                            Text("Change")
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            startDemo()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Organize Now")
                            }
                        }
                        .buttonStyle(.onboardingPill)
                    }
                }
            } else {
                // Folder selection prompt
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .frame(width: 200, height: 140)
                        
                        VStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            
                            Text("Drop a folder here")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        handleDrop(providers: providers)
                    }
                    
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    
                    Button {
                        selectDirectory()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                            Text("Browse...")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    @ViewBuilder
    private var processingView: some View {
        VStack(spacing: 32) {
            // Animated processing indicator
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                BouncingSpinner(size: 40, color: .accentColor)
            }
            
            VStack(spacing: 8) {
                Text(statusText)
                    .font(.title3.bold())
                
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            // Progress steps
            VStack(alignment: .leading, spacing: 12) {
                ProcessingStepRow(
                    icon: "magnifyingglass",
                    text: "Scanning files...",
                    isComplete: demoState == .organizing || demoState == .complete,
                    isActive: demoState == .analyzing
                )
                
                ProcessingStepRow(
                    icon: "brain",
                    text: "AI analyzing patterns...",
                    isComplete: demoState == .complete,
                    isActive: demoState == .organizing
                )
                
                ProcessingStepRow(
                    icon: "folder.badge.gearshape",
                    text: "Creating structure...",
                    isComplete: false,
                    isActive: false
                )
            }
            .frame(maxWidth: 280)
        }
    }
    
    @ViewBuilder
    private var completeView: some View {
        VStack(spacing: 28) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.green.opacity(0.3 - Double(i) * 0.1), lineWidth: 2)
                        .frame(width: CGFloat(100 + i * 20), height: CGFloat(100 + i * 20))
                        .scaleEffect(showPreviewTree ? 1.1 : 0.9)
                        .opacity(showPreviewTree ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.2)
                            .repeatCount(3, autoreverses: false)
                            .delay(Double(i) * 0.2),
                            value: showPreviewTree
                        )
                }
                
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: showPreviewTree)
            }
            
            VStack(spacing: 8) {
                Text("Organization Complete!")
                    .font(.title2.bold())
                
                Text("See how Sorty transformed chaos into order")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 32) {
                if let plan = organizer.currentPlan {
                    DemoStatCard(
                        icon: "doc.fill",
                        value: "\(plan.totalFiles)",
                        label: "files organized",
                        color: .blue
                    )
                    
                    DemoStatCard(
                        icon: "folder.fill",
                        value: "\(plan.totalFolders)",
                        label: "folders created",
                        color: .orange
                    )
                } else {
                    DemoStatCard(
                        icon: "doc.fill",
                        value: "10",
                        label: "files organized",
                        color: .blue
                    )
                    
                    DemoStatCard(
                        icon: "folder.fill",
                        value: "4",
                        label: "folders created",
                        color: .orange
                    )
                    
                    DemoStatCard(
                        icon: "bolt.fill",
                        value: "<1s",
                        label: "time taken",
                        color: .purple
                    )
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.purple)
                    Text("AI-Powered Organization")
                        .font(.subheadline.bold())
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    DemoHighlightRow(icon: "photo.stack", text: "Grouped photos by type", color: .blue)
                    DemoHighlightRow(icon: "doc.text", text: "Organized documents intelligently", color: .green)
                    DemoHighlightRow(icon: "dollarsign.circle", text: "Separated financial files", color: .orange)
                    DemoHighlightRow(icon: "arrow.uturn.backward.circle", text: "100% reversible with one click", color: .purple)
                }
            }
            .padding(16)
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.purple.opacity(0.05))
                    .stroke(Color.purple.opacity(0.1), lineWidth: 1)
            )
            
            Button {
                onComplete()
            } label: {
                HStack(spacing: 8) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.onboardingPill)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                showPreviewTree = true
            }
        }
    }
    
    private var leftPanelDescription: String {
        switch demoState {
        case .intro:
            return "Watch Sorty analyze your files and create an intelligent organization structure in real-time."
        case .simulatedDemo:
            return "Watch as AI scans, categorizes, and organizes files into a clean folder structure."
        case .selectDirectory, .analyzing, .organizing:
            return "Sorty is working on your files. Watch the magic happen!"
        case .complete:
            return "Your files are now beautifully organized. Ready to try it on your own folders?"
        }
    }
    
    private var statusText: String {
        switch organizer.state {
        case .scanning: return "Analyzing Your Files"
        case .organizing: return "Creating Organization Plan"
        case .applying: return "Applying Changes"
        case .ready: return "Preview Ready"
        default: return "Processing"
        }
    }
    
    private var statusDescription: String {
        switch organizer.state {
        case .scanning: return "Examining file names, types, and patterns..."
        case .organizing: return "AI is designing the perfect folder structure..."
        case .applying: return "Moving files to their new homes..."
        case .ready: return "Your organization plan is ready!"
        default: return "Working on your files..."
        }
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select"
        panel.message = "Choose a folder to organize"
        
        if panel.runModal() == .OK, let url = panel.url {
            HapticFeedbackManager.shared.success()
            selectedDirectory = url
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.hasDirectoryPath {
                DispatchQueue.main.async {
                    selectedDirectory = url
                    HapticFeedbackManager.shared.success()
                }
            }
        }
        return true
    }
    
    private func startDemo() {
        guard let directory = selectedDirectory else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            demoState = .analyzing
        }
        HapticFeedbackManager.shared.tap()
        
        Task {
            do {
                try await organizer.configure(with: settingsViewModel.config)
                try await organizer.organize(directory: directory)
                
                // Auto-apply after preview is ready
                if case .ready = organizer.state {
                    try await organizer.apply(at: directory, dryRun: false, enableTagging: settingsViewModel.config.enableFileTagging)
                }
            } catch {
                HapticFeedbackManager.shared.error()
                withAnimation {
                    demoState = .selectDirectory
                }
            }
        }
    }
    
    private func handleStateChange(_ state: OrganizationState) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            switch state {
            case .scanning:
                demoState = .analyzing
            case .organizing:
                demoState = .organizing
            case .completed:
                HapticFeedbackManager.shared.success()
                demoState = .complete
            case .error:
                HapticFeedbackManager.shared.error()
                demoState = .selectDirectory
            default:
                break
            }
        }
    }
}

struct DemoFeatureRow: View {
    let icon: String
    let text: String
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isActive ? "\(icon).fill" : icon)
                .font(.system(size: 14))
                .foregroundStyle(isActive ? .green : .secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isActive ? .primary : .secondary)
            
            Spacer()
            
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }
}

struct ProcessingStepRow: View {
    let icon: String
    let text: String
    let isComplete: Bool
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isComplete ? Color.green.opacity(0.1) : isActive ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                    .frame(width: 28, height: 28)
                
                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                } else if isActive {
                    BouncingSpinner(size: 12, color: .accentColor)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(isComplete ? .green : isActive ? .primary : .secondary)
        }
    }
}

struct DemoStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(.title2.bold())
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DemoHighlightRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - Simulated Demo Animation

struct DemoFileNode: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let targetFolder: String
    var isOrganized: Bool = false
}

struct DemoFolderNode: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    var isVisible: Bool = false
    var files: [DemoFileNode] = []
}

// MARK: - Demo Organization Plan Card
struct DemoOrganizationPlanCard: View {
    let title: String
    let subtitle: String
    let folderCount: Int
    let style: String
    let isSelected: Bool
    let showCheckmark: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showCheckmark)
                }
            }
            
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
            Divider()
            
            HStack(spacing: 12) {
                Label("\(folderCount)", systemImage: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text(style)
                    .font(.caption2.bold())
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.15))
                    )
            }
        }
        .padding(12)
        .frame(width: 160)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                .shadow(color: isSelected ? Color.purple.opacity(0.3) : Color.black.opacity(0.1), radius: isSelected ? 8 : 4, y: 2)
        )
    }
}

// MARK: - Demo Persona Card
struct DemoPersonaCard: View {
    let name: String
    let description: String
    let icon: String
    let color: Color
    @Binding var isApplying: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: isApplying)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.bold())
                    
                    Text("Persona")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color))
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isApplying {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Privacy Badge
struct PrivacyBadge: View {
    let isVisible: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
            Text("Local Processing")
                .font(.caption.bold())
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.15))
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
    }
}

// MARK: - Undo Safety Badge
struct UndoSafetyBadge: View {
    let isVisible: Bool
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 24))
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: isPulsing)
                
                Text("Undo Available")
                    .font(.headline.bold())
            }
            .foregroundStyle(.orange)
            
            Text("All changes can be reversed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .onAppear {
            if isVisible {
                isPulsing = true
            }
        }
        .onChange(of: isVisible) { _, newValue in
            isPulsing = newValue
        }
    }
}

// MARK: - Transition Particle Effect
struct TransitionParticleView: View {
    let isActive: Bool
    let color: Color
    let particleCount: Int
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                Circle()
                    .fill(color.opacity(0.6))
                    .frame(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 4...8))
                    .offset(particleOffset(for: index))
                    .opacity(isActive ? 0 : 0.8)
                    .blur(radius: isActive ? 2 : 0)
            }
        }
        .animation(.easeOut(duration: 0.8), value: isActive)
    }
    
    private func particleOffset(for index: Int) -> CGSize {
        let angle = Double(index) * (360.0 / Double(particleCount)) + Double.random(in: -10...10)
        let radius: CGFloat = isActive ? CGFloat.random(in: 60...100) : 0
        return CGSize(
            width: cos(angle * .pi / 180) * radius,
            height: sin(angle * .pi / 180) * radius
        )
    }
}

struct SimulatedDemoAnimationView: View {
    let onComplete: () -> Void
    
    @State private var phase: DemoPhase = .messy
    @State private var scanProgress: CGFloat = 0
    @State private var currentThought: String = ""
    @State private var thoughtOpacity: Double = 0
    @State private var files: [DemoFileNode] = []
    @State private var folders: [DemoFolderNode] = []
    @State private var organizedCount: Int = 0
    @State private var showStats: Bool = false
    @State private var particleEffect: Bool = false
    
    // New state for enhanced demo
    @State private var showPrivacyBadge: Bool = false
    @State private var showPersonaCard: Bool = false
    @State private var personaApplying: Bool = true
    @State private var selectedPlanIndex: Int = -1
    @State private var showPlanCheckmark: Bool = false
    @State private var showUndoBadge: Bool = false
    @State private var transitionParticles: Bool = false
    @State private var fileRotations: [Double] = []
    
    enum DemoPhase: CaseIterable {
        case messy
        case scanning
        case thinking
        case comparing
        case organizing
        case complete
    }
    
    private let sampleFiles: [DemoFileNode] = [
        DemoFileNode(name: "IMG_2024.jpg", icon: "photo.fill", color: .blue, targetFolder: "Photos"),
        DemoFileNode(name: "receipt_amazon.pdf", icon: "doc.fill", color: .red, targetFolder: "Finances"),
        DemoFileNode(name: "project_notes.docx", icon: "doc.text.fill", color: .blue, targetFolder: "Documents"),
        DemoFileNode(name: "photo_vacation.png", icon: "photo.fill", color: .green, targetFolder: "Photos"),
        DemoFileNode(name: "budget_2024.xlsx", icon: "tablecells.fill", color: .green, targetFolder: "Documents"),
        DemoFileNode(name: "screenshot_123.png", icon: "photo.fill", color: .purple, targetFolder: "Other"),
        DemoFileNode(name: "meeting_notes.md", icon: "doc.text.fill", color: .orange, targetFolder: "Documents"),
        DemoFileNode(name: "invoice_client.pdf", icon: "doc.fill", color: .red, targetFolder: "Finances"),
        DemoFileNode(name: "family_photo.jpg", icon: "photo.fill", color: .pink, targetFolder: "Photos"),
        DemoFileNode(name: "code_backup.zip", icon: "doc.zipper", color: .gray, targetFolder: "Other")
    ]
    
    private let sampleFolders: [DemoFolderNode] = [
        DemoFolderNode(name: "Documents", icon: "folder.fill", color: .blue),
        DemoFolderNode(name: "Photos", icon: "folder.fill", color: .green),
        DemoFolderNode(name: "Finances", icon: "folder.fill", color: .orange),
        DemoFolderNode(name: "Other", icon: "folder.fill", color: .gray)
    ]
    
    // Enhanced AI thoughts with privacy and persona focus
    private let aiThoughts: [String] = [
        "Scanning file types...",
        "Files never leave your device",
        "Found 4 image files",
        "Detected document patterns",
        "Using 'Minimal' persona style...",
        "Organizing with minimal folders",
        "Comparing organization options...",
        "Option A uses fewer folders",
        "Moving files to categories",
        "Creating undo checkpoint..."
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            phaseIndicator
            
            ZStack {
                // Transition particles overlay
                if transitionParticles {
                    TransitionParticleView(isActive: transitionParticles, color: .purple, particleCount: 16)
                }
                
                switch phase {
                case .messy:
                    messyFilesView
                case .scanning:
                    scanningView
                case .thinking:
                    thinkingView
                case .comparing:
                    comparingView
                case .organizing:
                    organizingView
                case .complete:
                    completeAnimationView
                }
            }
            .frame(height: 320)
            
            if phase != .complete {
                aiThoughtBubble
            }
            
            if phase == .complete {
                Button {
                    onComplete()
                } label: {
                    HStack(spacing: 8) {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.onboardingPill)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            files = sampleFiles
            folders = sampleFolders
            fileRotations = (0..<sampleFiles.count).map { _ in Double.random(in: -15...15) }
            startAnimation()
        }
    }
    
    private var phaseIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<6) { index in
                Circle()
                    .fill(phaseIndex >= index ? Color.purple : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phaseIndex == index ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: phaseIndex)
            }
        }
    }
    
    private var phaseIndex: Int {
        switch phase {
        case .messy: return 0
        case .scanning: return 1
        case .thinking: return 2
        case .comparing: return 3
        case .organizing: return 4
        case .complete: return 5
        }
    }
    
    private var messyFilesView: some View {
        ZStack {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                fileIcon(for: file)
                    .offset(messyOffset(for: index))
                    .rotationEffect(.degrees(fileRotations.indices.contains(index) ? fileRotations[index] : 0))
            }
        }
        .transition(.opacity)
    }
    
    private var scanningView: some View {
        ZStack {
            // Files with scanning effect
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                fileIcon(for: file)
                    .offset(messyOffset(for: index))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple, lineWidth: 2)
                            .opacity(scanLinePosition(for: index) ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: scanLinePosition(for: index))
                    )
            }
            
            // Scanning line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0), .purple.opacity(0.5), .purple.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 100, height: 320)
                .offset(x: -200 + scanProgress * 400)
            
            // Privacy badge at bottom
            VStack {
                Spacer()
                PrivacyBadge(isVisible: showPrivacyBadge)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var thinkingView: some View {
        VStack(spacing: 20) {
            // Dimmed files in background
            ZStack {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    fileIcon(for: file)
                        .offset(messyOffset(for: index))
                        .opacity(0.3)
                        .scaleEffect(0.9)
                }
                
                BouncingSpinner(size: 50, color: .purple)
            }
            .frame(height: 200)
            
            // Persona card
            if showPersonaCard {
                DemoPersonaCard(
                    name: "Minimal",
                    description: "Clean, simple folder structure",
                    icon: "square.grid.2x2",
                    color: .purple,
                    isApplying: $personaApplying
                )
                .frame(width: 280)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }
    
    private var comparingView: some View {
        VStack(spacing: 16) {
            Text("Comparing Options")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                DemoOrganizationPlanCard(
                    title: "Plan A",
                    subtitle: "Group by type with minimal nesting",
                    folderCount: 4,
                    style: "Minimal",
                    isSelected: selectedPlanIndex == 0,
                    showCheckmark: selectedPlanIndex == 0 && showPlanCheckmark
                )
                .scaleEffect(selectedPlanIndex == 0 ? 1.02 : 0.98)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedPlanIndex)
                
                DemoOrganizationPlanCard(
                    title: "Plan B",
                    subtitle: "Organize by date and project",
                    folderCount: 7,
                    style: "Detailed",
                    isSelected: selectedPlanIndex == 1,
                    showCheckmark: false
                )
                .scaleEffect(selectedPlanIndex == 1 ? 1.02 : 0.98)
                .opacity(selectedPlanIndex == 0 && showPlanCheckmark ? 0.5 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedPlanIndex)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("AI generates multiple options for you to choose")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .opacity(selectedPlanIndex < 0 ? 1 : 0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private var organizingView: some View {
        HStack(spacing: 40) {
            VStack(spacing: 8) {
                ForEach(files.filter { !$0.isOrganized }) { file in
                    fileIcon(for: file)
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8))
                        ))
                }
            }
            .frame(width: 120)
            
            VStack(spacing: 8) {
                Image(systemName: "arrow.right")
                    .font(.title)
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse.byLayer, options: .repeating)
                
                // Small animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.purple.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .offset(y: organizedCount % 3 == i ? -3 : 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5).delay(Double(i) * 0.1), value: organizedCount)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(folders) { folder in
                    if folder.isVisible {
                        folderRow(for: folder)
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
            .frame(width: 180)
        }
    }
    
    private var completeAnimationView: some View {
        VStack(spacing: 20) {
            ZStack {
                // Particle burst effect
                if particleEffect {
                    TransitionParticleView(isActive: particleEffect, color: .green, particleCount: 20)
                }
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: phase == .complete)
            }
            
            if showStats {
                HStack(spacing: 20) {
                    statBadge(value: "10", label: "Files", icon: "doc.fill", color: .blue)
                    statBadge(value: "4", label: "Folders", icon: "folder.fill", color: .orange)
                    statBadge(value: "100%", label: "Organized", icon: "sparkles", color: .purple)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Undo safety badge - prominent feature highlight
            UndoSafetyBadge(isVisible: showUndoBadge)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
        }
    }
    
    private var aiThoughtBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: thoughtIcon)
                .foregroundStyle(.purple)
            
            Text(currentThought)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.1))
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .opacity(thoughtOpacity)
    }
    
    private var thoughtIcon: String {
        if currentThought.contains("never leave") || currentThought.contains("device") {
            return "lock.shield.fill"
        } else if currentThought.contains("persona") || currentThought.contains("Minimal") {
            return "person.fill"
        } else if currentThought.contains("undo") {
            return "arrow.uturn.backward"
        } else if currentThought.contains("Comparing") || currentThought.contains("Option") {
            return "square.2.layers.3d"
        } else {
            return "brain.head.profile"
        }
    }
    
    private func fileIcon(for file: DemoFileNode) -> some View {
        VStack(spacing: 4) {
            Image(systemName: file.icon)
                .font(.system(size: 24))
                .foregroundStyle(file.color)
            
            Text(file.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 70, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        )
    }
    
    private func folderRow(for folder: DemoFolderNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: folder.icon)
                .foregroundStyle(folder.color)
            
            Text(folder.name)
                .font(.subheadline.bold())
            
            Spacer()
            
            let count = files.filter { $0.targetFolder == folder.name && $0.isOrganized }.count
            if count > 0 {
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(folder.color))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(folder.color.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func statBadge(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func messyOffset(for index: Int) -> CGSize {
        let positions: [CGSize] = [
            CGSize(width: -80, height: -60),
            CGSize(width: 60, height: -80),
            CGSize(width: -40, height: 20),
            CGSize(width: 90, height: -20),
            CGSize(width: -100, height: 60),
            CGSize(width: 20, height: 80),
            CGSize(width: 70, height: 50),
            CGSize(width: -60, height: -100),
            CGSize(width: 100, height: 90),
            CGSize(width: -20, height: -40)
        ]
        return positions[index % positions.count]
    }
    
    private func scanLinePosition(for index: Int) -> Bool {
        let normalizedProgress = scanProgress
        let fileProgress = CGFloat(index) / CGFloat(files.count)
        return abs(normalizedProgress - fileProgress) < 0.15
    }
    
    private func startAnimation() {
        Task { @MainActor in
            // Phase 1: Messy (brief pause to show initial state)
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Phase 2: Scanning with privacy callout
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .scanning
            }
            showThought(aiThoughts[0]) // "Scanning file types..."
            
            withAnimation(.linear(duration: 1.5)) {
                scanProgress = 1.0
            }
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Show privacy badge during scan
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPrivacyBadge = true
            }
            showThought(aiThoughts[1]) // "Files never leave your device"
            
            try? await Task.sleep(nanoseconds: 800_000_000)
            showThought(aiThoughts[2]) // "Found 4 image files"
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Transition particles
            withAnimation(.easeOut(duration: 0.3)) {
                transitionParticles = true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            transitionParticles = false
            
            // Phase 3: Thinking with persona showcase
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .thinking
                showPrivacyBadge = false
            }
            showThought(aiThoughts[3]) // "Detected document patterns"
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Show persona card
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showPersonaCard = true
            }
            showThought(aiThoughts[4]) // "Using 'Minimal' persona style..."
            
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            // Persona applied
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                personaApplying = false
            }
            showThought(aiThoughts[5]) // "Organizing with minimal folders"
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Phase 4: Comparing options (NEW)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .comparing
                showPersonaCard = false
            }
            showThought(aiThoughts[6]) // "Comparing organization options..."
            
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            // Highlight each plan briefly
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedPlanIndex = 1
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedPlanIndex = 0
            }
            showThought(aiThoughts[7]) // "Option A uses fewer folders"
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Show checkmark on selected plan
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPlanCheckmark = true
            }
            HapticFeedbackManager.shared.selection()
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Phase 5: Organizing
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .organizing
            }
            showThought(aiThoughts[8]) // "Moving files to categories"
            
            // Show folders appearing
            for i in 0..<folders.count {
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    folders[i].isVisible = true
                }
            }
            
            // Animate files moving
            for i in 0..<files.count {
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    files[i].isOrganized = true
                    organizedCount += 1
                }
                HapticFeedbackManager.shared.selection()
            }
            
            showThought(aiThoughts[9]) // "Creating undo checkpoint..."
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Phase 6: Complete with undo highlight
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                phase = .complete
                thoughtOpacity = 0
            }
            
            withAnimation(.easeOut(duration: 0.6)) {
                particleEffect = true
            }
            
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showStats = true
            }
            
            try? await Task.sleep(nanoseconds: 400_000_000)
            
            // Show undo safety badge prominently
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showUndoBadge = true
            }
            HapticFeedbackManager.shared.success()
        }
    }
    
    private func showThought(_ thought: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            thoughtOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentThought = thought
            withAnimation(.easeIn(duration: 0.2)) {
                thoughtOpacity = 1
            }
        }
    }
}

// MARK: - Step 5: Completion

struct CompletionStep: View {
    let onFinish: () -> Void
    
    @State private var hasAppeared = false
    @State private var showConfetti = false
    @State private var exitProgress: CGFloat = 0
    
    var body: some View {
        ZStack {
            VStack(spacing: 40) {
                Spacer()
                
                // Success icon
                ZStack {
                    // Animated rings
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(Color.green.opacity(0.2 - Double(index) * 0.05), lineWidth: 2)
                            .frame(width: CGFloat(140 + index * 30), height: CGFloat(140 + index * 30))
                            .scaleEffect(showConfetti ? 1.2 : 0.8)
                            .opacity(showConfetti ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.3),
                                value: showConfetti
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
                .scaleEffect(hasAppeared ? 1 : 0.5)
                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                
                // Title and message
                VStack(spacing: 16) {
                    Text("Sorty is Ready!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    
                    Text("You're all set to start organizing your files with AI.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                
                // Quick tips
                VStack(spacing: 12) {
                    QuickTipRow(icon: "folder.badge.plus", text: "Drag any folder to organize it")
                    QuickTipRow(icon: "keyboard", text: "Press ⌘O to open a folder")
                    QuickTipRow(icon: "arrow.uturn.backward", text: "All changes can be undone")
                    QuickTipRow(icon: "gearshape", text: "Customize everything in Settings")
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                
                // Start button
                Button {
                    startTransition()
                } label: {
                    HStack(spacing: 8) {
                        Text("Start Using Sorty")
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                    }
                }
                .buttonStyle(.onboardingPill)
                .keyboardShortcut(.defaultAction)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
                .scaleEffect(1 + exitProgress * 0.05)
                
                Spacer()
            }
            .padding(.horizontal, 60)
            .scaleEffect(1 - exitProgress * 0.03)
            .opacity(1 - exitProgress)
            .blur(radius: exitProgress * 2)
        }
        .onAppear {
            withAnimation { hasAppeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showConfetti = true
            }
        }
    }
    
    private func startTransition() {
        HapticFeedbackManager.shared.success()
        
        withAnimation(.easeOut(duration: 0.5)) {
            exitProgress = 1
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
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
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .environmentObject(SettingsViewModel())
        .environmentObject(PersonaManager())
        .environmentObject(FolderOrganizer())
        .environmentObject(AppState())
}

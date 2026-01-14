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
    
    @State private var currentStep: OnboardingStep = .provider
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
        .frame(minWidth: 900, minHeight: 650)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding")
        .accessibilityIdentifier("OnboardingView")
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
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
                withAnimation(.pageTransition) {
                    hasCompletedOnboarding = true
                }
            })
            .transition(TransitionStyles.slideFromRight)
        }
    }
    
    private var navigationControls: some View {
        HStack(spacing: 16) {
            // Back button
            if currentStep != .provider && currentStep != .completion {
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
                        .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
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
    case provider = 0
    case permissions = 1
    case workflow = 2
    case demo = 3
    case completion = 4
    
    var title: String {
        switch self {
        case .provider: return "Pick Your Provider"
        case .permissions: return "Permissions"
        case .workflow: return "Default Workflow"
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

// MARK: - Step 1: Provider Selection

struct ProviderSelectionStep: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var hasAppeared = false
    
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
                    
                    Text("Sortly works with multiple AI providers. Your files are processed locally, and only file names and metadata are sent to the AI for organization suggestions.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        PrivacyFeatureRow(icon: "doc.text", text: "Only file names sent to AI")
                        PrivacyFeatureRow(icon: "folder", text: "File contents stay on your Mac")
                        PrivacyFeatureRow(icon: "arrow.uturn.backward", text: "All changes are reversible")
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
            
            // Right side - provider selection
            VStack(spacing: 20) {
                Text("Select AI Provider")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                ScrollView {
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
                }
                .frame(maxWidth: 380)
                
                // API Key field for selected provider
                if settingsViewModel.config.provider.typicallyRequiresAPIKey {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        SecureField("Enter your API key", text: Binding(
                            get: { settingsViewModel.config.apiKey ?? "" },
                            set: { settingsViewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        
                        Text(settingsViewModel.config.provider.apiKeyHelpText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 380)
                    .padding(.top, 8)
                }
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
        }
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
        }
    }
}

struct PrivacyFeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .frame(width: 20)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }
}

struct OnboardingProviderRow: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void
    
    private var providerImage: Image {
        if provider.usesSystemImage {
            return Image(systemName: provider.logoImageName)
        }
        if let resourceURL = Bundle.module.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        return Image(provider.logoImageName, bundle: .module)
    }
    
    var body: some View {
        Button(action: {
            if provider.isAvailable { action() }
        }) {
            HStack(spacing: 12) {
                providerImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                
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
                    
                    Text("Sortly needs a few permissions to organize your files effectively. You can grant these now or later when needed.")
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
    @State private var hasAppeared = false
    
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
            VStack(spacing: 24) {
                Text("Select Default Persona")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(PersonaType.allCases, id: \.self) { persona in
                        OnboardingPersonaCard(
                            persona: persona,
                            isSelected: personaManager.selectedPersona == persona
                        ) {
                            HapticFeedbackManager.shared.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                personaManager.selectPersona(persona)
                            }
                        }
                    }
                }
                .frame(maxWidth: 450)
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

// MARK: - Step 4: Demo

struct DemoStep: View {
    let onComplete: () -> Void
    
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var hasAppeared = false
    @State private var selectedDirectory: URL?
    @State private var demoState: DemoState = .selectDirectory
    
    enum DemoState {
        case selectDirectory
        case organizing
        case complete
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: demoState == .complete ? "checkmark.circle.fill" : "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(demoState == .complete ? .green : .orange)
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
            
            // Title and description
            VStack(spacing: 12) {
                Text(demoState == .complete ? "Organization Complete!" : "Try It Out")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text(demoState == .complete ? 
                     "Your files have been organized. You can undo this anytime." :
                     "Select a folder to see Sortly in action. This will actually organize your files.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
            
            // Demo content based on state
            Group {
                switch demoState {
                case .selectDirectory:
                    VStack(spacing: 16) {
                        if let url = selectedDirectory {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(url.lastPathComponent)
                                    .fontWeight(.medium)
                                Button {
                                    selectedDirectory = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.blue.opacity(0.1))
                            )
                            
                            Button {
                                startDemo()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "play.fill")
                                    Text("Organize This Folder")
                                }
                                .frame(minWidth: 180)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Button {
                                selectDirectory()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder.badge.plus")
                                    Text("Select a Folder")
                                }
                                .frame(minWidth: 180)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                        
                        Text("Choose a small folder (10-50 files) for a quick demo")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                case .organizing:
                    VStack(spacing: 16) {
                        BouncingSpinner(size: 24, color: .accentColor)
                        
                        Text(statusText)
                            .font(.headline)
                        
                        Text("This may take a moment...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                case .complete:
                    VStack(spacing: 16) {
                        if let plan = organizer.currentPlan {
                            HStack(spacing: 24) {
                                StatBadge(icon: "doc.fill", value: "\(plan.totalFiles)", label: "files")
                                StatBadge(icon: "folder.fill", value: "\(plan.totalFolders)", label: "folders")
                            }
                        }
                        
                        Button {
                            onComplete()
                        } label: {
                            HStack(spacing: 8) {
                                Text("Continue")
                                Image(systemName: "arrow.right")
                            }
                            .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
            
            Spacer()
        }
        .padding(.horizontal, 60)
        .onAppear {
            withAnimation { hasAppeared = true }
        }
        .onChange(of: organizer.state) { _, newState in
            handleStateChange(newState)
        }
    }
    
    private var statusText: String {
        switch organizer.state {
        case .scanning: return "Analyzing files..."
        case .organizing: return "Generating organization plan..."
        case .applying: return "Applying changes..."
        case .ready: return "Preview ready"
        default: return "Processing..."
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
    
    private func startDemo() {
        guard let directory = selectedDirectory else { return }
        
        demoState = .organizing
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
                demoState = .selectDirectory
            }
        }
    }
    
    private func handleStateChange(_ state: OrganizationState) {
        switch state {
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

// MARK: - Step 5: Completion

struct CompletionStep: View {
    let onFinish: () -> Void
    
    @State private var hasAppeared = false
    @State private var showConfetti = false
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .scaleEffect(showConfetti ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatCount(3, autoreverses: true), value: showConfetti)
                
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
                Text("Sortly is Ready!")
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
                onFinish()
            } label: {
                HStack(spacing: 8) {
                    Text("Start Using Sortly")
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
            
            Spacer()
        }
        .padding(.horizontal, 60)
        .onAppear {
            withAnimation { hasAppeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showConfetti = true
            }
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

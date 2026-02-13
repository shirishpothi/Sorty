//
//  ProviderSelectionStepView.swift
//  Sorty
//
//  AI Provider selection step of the onboarding flow
//

import SwiftUI

public struct ProviderSelectionStepView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject var copilotAuth = GitHubCopilotAuthManager.shared
    @State private var hasAppeared = false
    @State private var connectionStatus: ConnectionTestStatus = .idle
    @State private var connectionError: String?
    @State private var testDebounceTask: Task<Void, Never>?
    @State private var hasCopiedCode = false
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var isHoveringUsername = false
    @State private var isShowingAPIKey = false
    
    enum ConnectionTestStatus {
        case idle
        case testing
        case success
        case failed
    }
    
    let providers = AIProvider.allCases
    
    public init() {}
    
    public var body: some View {
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider Selection Step")
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
                            .blur(radius: (FeatureFlags.privacyModeEnabled && !isHoveringUsername) ? 4 : 0)
                            .animation(.spring(), value: isHoveringUsername)
                            .onHover { hovering in
                                isHoveringUsername = hovering
                            }
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
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                                    hasCopiedCode = false
                                }
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
                    HStack {
                        Text("API Key")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        if FeatureFlags.privacyModeEnabled {
                            Button {
                                isShowingAPIKey.toggle()
                                HapticFeedbackManager.shared.tap()
                            } label: {
                                Image(systemName: isShowingAPIKey ? "eye.slash" : "eye")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isShowingAPIKey ? "Hide API Key" : "Show API Key")
                        }
                    }
                    
                    Group {
                        if isShowingAPIKey && FeatureFlags.privacyModeEnabled {
                            TextField("Enter your API key", text: Binding(
                                get: { settingsViewModel.config.apiKey ?? "" },
                                set: { 
                                    settingsViewModel.config.apiKey = $0.isEmpty ? nil : $0
                                    scheduleConnectionTest()
                                }
                            ))
                        } else {
                            SecureField("Enter your API key", text: Binding(
                                get: { settingsViewModel.config.apiKey ?? "" },
                                set: { 
                                    settingsViewModel.config.apiKey = $0.isEmpty ? nil : $0
                                    scheduleConnectionTest()
                                }
                            ))
                        }
                    }
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
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.horizontal.circle.fill")
                            Text("Test Connection")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
            } catch let decodingError as DecodingError {
                // Provide a clearer message for JSON decoding errors
                let context: String
                switch decodingError {
                case .dataCorrupted(let ctx):
                    context = ctx.debugDescription
                case .keyNotFound(let key, _):
                    context = "Missing key: \(key.stringValue)"
                case .typeMismatch(let type, _):
                    context = "Type mismatch for: \(type)"
                case .valueNotFound(let type, _):
                    context = "Missing value for: \(type)"
                @unknown default:
                    context = decodingError.localizedDescription
                }
                await MainActor.run {
                    withAnimation {
                        connectionStatus = .failed
                        connectionError = "Invalid response format from server. The API endpoint may be incorrect or the service returned unexpected data. (\(context))"
                    }
                    HapticFeedbackManager.shared.error()
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

// MARK: - Supporting Views

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

// MARK: - Preview

#Preview {
    ProviderSelectionStepView()
        .environmentObject(SettingsViewModel())
}

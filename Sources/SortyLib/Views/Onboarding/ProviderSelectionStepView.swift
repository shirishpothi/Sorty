//
//  ProviderSelectionStepView.swift
//  Sorty
//
//  AI Provider selection step of the onboarding flow
//

import SwiftUI

public struct ProviderSelectionStepView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var openAIAuth: SubscriptionAuthManager
    @EnvironmentObject var codexAuth: CodexCLIAuthManager
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
    @State private var isShowingModelPopover = false
    @State private var codexTerminalButtonState: CodexActionVisualState = .idle
    @State private var codexVerifyButtonState: CodexActionVisualState = .idle
    @State private var isHoveringCodexTerminalButton = false
    @State private var isHoveringCodexVerifyButton = false
    @State private var codexTerminalResetTask: Task<Void, Never>?
    @State private var codexVerifyResetTask: Task<Void, Never>?
    
    enum ConnectionTestStatus {
        case idle
        case testing
        case success
        case failed
    }
    
    let providers = AIProvider.userSelectableProviders
    
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
            if settingsViewModel.config.provider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
            }
            if settingsViewModel.config.provider == .openAI {
                openAIAuth.checkAuthenticationStatus()
                codexAuth.checkStatus()
            }
        }
        .onChange(of: settingsViewModel.config.provider) { _, newProvider in
            if newProvider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
            }
            if newProvider == .openAI {
                openAIAuth.checkAuthenticationStatus()
                codexAuth.checkStatus()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Provider Selection Step")
        .modelSelectionOverlay(
            isPresented: $isShowingModelPopover,
            currentProvider: settingsViewModel.config.provider,
            currentModel: settingsViewModel.config.model
        ) { provider, model in
            settingsViewModel.config.provider = provider
            settingsViewModel.config.model = model
            if let defaultURL = provider.defaultAPIURL {
                settingsViewModel.config.apiURL = defaultURL
            }
            settingsViewModel.config.requiresAPIKey = provider.typicallyRequiresAPIKey
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
                        ZStack {
                            Text(copilotAuth.username ?? "User")
                                .opacity(isHoveringUsername ? 0 : 1)
                                .blur(radius: 10)

                            Text(copilotAuth.username ?? "User")
                                .opacity(isHoveringUsername ? 1 : 0)
                        }
                            .font(.headline)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .clipShape(Capsule())
                            .padding(.vertical, -4)
                            .padding(.horizontal, -6)
                            .animation(
                                isHoveringUsername
                                    ? .easeOut(duration: 0.34)
                                    : .easeInOut(duration: 0.24),
                                value: isHoveringUsername
                            )
                            .onHover { hovering in
                                guard hovering != isHoveringUsername else { return }
                                isHoveringUsername = hovering
                                HapticFeedbackManager.shared.light()
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
                
                // Model selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isLoadingModels {
                        HStack(spacing: 8) {
                            BouncingSpinner(size: 12, color: .secondary)
                            Text("Loading models...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ModelSelectorRow(
                            provider: settingsViewModel.config.provider,
                            model: settingsViewModel.config.model
                        ) {
                            isShowingModelPopover = true
                        }
                        .modelSelectorTriggerBounds()
                    }
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
                    Text("Access frontier AI models via your GitHub Copilot subscription.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        Task {
                            do {
                                try await copilotAuth.startDeviceFlow()
                            } catch {
                                await MainActor.run {
                                    copilotAuth.authError = error.localizedDescription
                                }
                            }
                        }
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
                    if supportsSubscriptionAuthUI {
                        Picker("Authentication", selection: selectedAuthMethod) {
                            ForEach(settingsViewModel.config.provider.supportedAuthMethods, id: \.self) { method in
                                Text(method.displayName).tag(method)
                            }
                        }
                        .pickerStyle(.menu)

                        switch settingsViewModel.config.authMethod(for: settingsViewModel.config.provider) {
                        case .apiKey:
                            apiKeyInputSection
                        case .accountSignIn:
                            onboardingCodexCLISection
                        case .manualSessionToken:
                            apiKeyInputSection
                        }
                    } else {
                        apiKeyInputSection
                    }
                }
            }
            
            // Model selector
            if settingsViewModel.config.provider != .githubCopilot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ModelSelectorRow(
                        provider: settingsViewModel.config.provider,
                        model: settingsViewModel.config.model
                    ) {
                        isShowingModelPopover = true
                    }
                    .modelSelectorTriggerBounds()
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
    private var apiKeyInputSection: some View {
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

    @ViewBuilder
    private var onboardingCodexCLISection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if codexAuth.isAuthenticated {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in via Codex CLI")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let email = codexAuth.accountEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("Sign Out") {
                        codexAuth.signOut()
                        openAIAuth.checkAuthenticationStatus()
                        scheduleConnectionTest()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)
            } else {
                Text("Sign in with your OpenAI account using Codex CLI to enable Codex integration in Sorty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Step 1: Install & sign in")
                        .font(.caption).fontWeight(.semibold)
                    Text("Install Node.js 18+, then:")
                        .font(.caption2).foregroundStyle(.secondary)
                    onboardingCommandBlock("npm i -g @openai/codex")
                    onboardingCommandBlock("codex login")
                }

                Button {
                    startCodexTerminalSignIn()
                } label: {
                    CodexActionButtonLabel(
                        idleTitle: "Open Terminal & Sign In",
                        activatingTitle: "Opening Terminal...",
                        successTitle: "Terminal Opened",
                        failureTitle: "Could Not Open Terminal",
                        idleSymbol: "terminal",
                        state: codexTerminalButtonState,
                        isHovered: isHoveringCodexTerminalButton
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("CodexTerminalSignInButton")
                .onHover { hovering in
                    if hovering && !isHoveringCodexTerminalButton {
                        HapticFeedbackManager.shared.selection()
                    }
                    isHoveringCodexTerminalButton = hovering
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Step 2: Verify")
                        .font(.caption).fontWeight(.semibold)
                    Text("We automatically verify that Codex CLI is installed and auth tokens are present. You can also run a manual verify anytime.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Button {
                    manuallyVerifyCodexCLI()
                } label: {
                    CodexActionButtonLabel(
                        idleTitle: "Verify Codex CLI",
                        activatingTitle: "Verifying...",
                        successTitle: "Verified",
                        failureTitle: "Verification Failed",
                        idleSymbol: "checkmark.shield",
                        state: codexVerifyButtonState,
                        isHovered: isHoveringCodexVerifyButton
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("CodexVerifyButton")
                .onHover { hovering in
                    if hovering && !isHoveringCodexVerifyButton {
                        HapticFeedbackManager.shared.selection()
                    }
                    isHoveringCodexVerifyButton = hovering
                }

                HStack(spacing: 8) {
                    BouncingSpinner(size: 10, color: .secondary)
                    Text("Automatic verification runs every few seconds while this panel is open.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !codexAuth.isCodexInstalled {
                    Label("Codex CLI not detected", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let error = codexAuth.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .task {
            await autoVerifyCodexSignInLoop()
        }
    }

    @ViewBuilder
    private func onboardingCommandBlock(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                HapticFeedbackManager.shared.tap()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Color.black.opacity(0.05))
        .cornerRadius(4)
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
        return ProviderAuthResolver.hasRequiredCredential(for: provider, config: settingsViewModel.config)
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

    private var supportsSubscriptionAuthUI: Bool {
        FeatureFlags.subscriptionAuthEnabled && settingsViewModel.config.provider.supportsSubscriptionAuth
    }

    private var selectedAuthMethod: Binding<ProviderAuthMethod> {
        Binding(
            get: { settingsViewModel.config.authMethod(for: settingsViewModel.config.provider) },
            set: { setAuthMethod($0) }
        )
    }

    private func setAuthMethod(_ method: ProviderAuthMethod) {
        var next = settingsViewModel.config
        let provider = next.provider
        next.setAuthMethod(method, for: provider)
        if method == .apiKey {
            next.apiKey = KeychainManager.get(key: provider.keychainKey)
        } else {
            next.apiKey = nil
        }
        settingsViewModel.config = next
        HapticFeedbackManager.shared.selection()
        settingsViewModel.updateAvailableModels(force: true)
        scheduleConnectionTest()
        openAIAuth.checkAuthenticationStatus()
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

    @MainActor
    @discardableResult
    private func verifyCodexSignInStatus() -> Bool {
        let wasAuthenticated = codexAuth.isAuthenticated
        codexAuth.checkStatus()
        openAIAuth.checkAuthenticationStatus()
        let becameAuthenticated = codexAuth.isAuthenticated && !wasAuthenticated
        if becameAuthenticated {
            settingsViewModel.updateAvailableModels(force: true)
            scheduleConnectionTest()
        }
        return becameAuthenticated
    }

    private func autoVerifyCodexSignInLoop() async {
        while !Task.isCancelled {
            let becameAuthenticated = await MainActor.run {
                verifyCodexSignInStatus()
            }

            if becameAuthenticated {
                await MainActor.run {
                    codexVerifyButtonState = .success
                    HapticFeedbackManager.shared.success()
                    scheduleCodexVerifyButtonReset()
                }
            }

            let shouldContinue = await MainActor.run {
                settingsViewModel.config.provider == .openAI
                    && settingsViewModel.config.authMethod(for: .openAI) == .accountSignIn
                    && !codexAuth.isAuthenticated
            }
            if !shouldContinue {
                break
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    @MainActor
    private func startCodexTerminalSignIn() {
        HapticFeedbackManager.shared.tap()
        codexTerminalButtonState = .activating
        codexAuth.openTerminalWithLogin()

        if codexAuth.authError == nil {
            codexTerminalButtonState = .success
            HapticFeedbackManager.shared.success()
        } else {
            codexTerminalButtonState = .failure
            HapticFeedbackManager.shared.error()
        }

        scheduleCodexTerminalButtonReset()
    }

    @MainActor
    private func manuallyVerifyCodexCLI() {
        HapticFeedbackManager.shared.tap()
        codexVerifyButtonState = .activating

        let becameAuthenticated = verifyCodexSignInStatus()
        if codexAuth.isAuthenticated || becameAuthenticated {
            codexVerifyButtonState = .success
            HapticFeedbackManager.shared.success()
            scheduleCodexVerifyButtonReset()
            return
        }

        codexVerifyButtonState = .failure
        HapticFeedbackManager.shared.error()
        if !codexAuth.isCodexInstalled {
            codexAuth.authError = "Codex CLI not found. Install with: npm i -g @openai/codex"
        } else if codexAuth.authError == nil {
            codexAuth.authError = "Auth tokens not found. Run 'codex login' first."
        }
        scheduleCodexVerifyButtonReset()
    }

    @MainActor
    private func scheduleCodexTerminalButtonReset() {
        codexTerminalResetTask?.cancel()
        codexTerminalResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                codexTerminalButtonState = .idle
            }
        }
    }

    @MainActor
    private func scheduleCodexVerifyButtonReset() {
        codexVerifyResetTask?.cancel()
        codexVerifyResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                codexVerifyButtonState = .idle
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
    let codexAuthManager = CodexCLIAuthManager()

    ProviderSelectionStepView()
        .environmentObject(SettingsViewModel())
        .environmentObject(SubscriptionAuthManager(provider: .openAI, codexAuthManager: codexAuthManager))
        .environmentObject(codexAuthManager)
}

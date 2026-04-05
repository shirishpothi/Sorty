//
//  AIProviderSettingsView.swift
//  Sorty
//
//  AI Provider settings section
//

import SwiftUI

struct AIProviderSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var openAIAuth: SubscriptionAuthManager
    @EnvironmentObject var codexAuth: CodexCLIAuthManager
    @ObservedObject var copilotAuth = GitHubCopilotAuthManager.shared
    
    @State private var testConnectionStatus: String?
    @State private var testConnectionDetails: String?
    @State private var isTestingConnection = false
    @State private var hasCopiedCode = false
    @State private var showModelPicker = false
    @State private var isHoveringUsername = false
    @State private var isDetailsExpanded = false
    @State private var codexTerminalButtonState: CodexActionVisualState = .idle
    @State private var codexVerifyButtonState: CodexActionVisualState = .idle
    @State private var isHoveringCodexTerminalButton = false
    @State private var isHoveringCodexVerifyButton = false
    @State private var codexTerminalResetTask: Task<Void, Never>?
    @State private var codexVerifyResetTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 16) {
            if let setupRepairMessage = appState.setupRepairMessage, appState.requiresSetupRepair {
                SettingsCard(title: "Setup Repair", icon: "wrench.and.screwdriver", color: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(setupRepairMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Update your provider settings below, then use Test Connection to verify the setup.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Provider Selection
            SettingsCard(title: "Select Provider", icon: "cpu", color: .purple) {
                VStack(spacing: 8) {
                    ForEach(Array(AIProvider.userSelectableProviders), id: \.self) { provider in
                        AIProviderRow(
                            provider: provider,
                            isSelected: viewModel.config.provider == provider,
                            action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.config.provider = provider
                                    if let defaultURL = provider.defaultAPIURL {
                                        viewModel.config.apiURL = defaultURL
                                    }
                                    viewModel.config.requiresAPIKey = provider.typicallyRequiresAPIKey
                                    HapticFeedbackManager.shared.selection()
                                }
                            }
                        )
                    }
                }
            }
            .animatedAppearance(delay: 0.05)
            
            // Provider-specific configuration
            if viewModel.config.provider == .githubCopilot {
                copilotConfigSection
                    .animatedAppearance(delay: 0.1)
            } else if viewModel.config.provider == .appleFoundationModel {
                appleConfigSection
                    .animatedAppearance(delay: 0.1)
            } else if [.openAI, .groq, .openAICompatible, .openRouter, .anthropic, .ollama, .gemini].contains(viewModel.config.provider) {
                apiConfigSection
                    .animatedAppearance(delay: 0.1)
            }
            
            // Connection Test
            if [.openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .anthropic, .ollama, .gemini, .appleFoundationModel].contains(viewModel.config.provider) {
                connectionSection
                    .animatedAppearance(delay: 0.15)
            }
        }
        .modelSelectionOverlay(
            isPresented: $showModelPicker,
            currentProvider: viewModel.config.provider,
            currentModel: viewModel.config.model,
            onSelect: { provider, model in
                viewModel.config.provider = provider
                viewModel.config.model = model
            }
        )
        .onAppear {
            if viewModel.config.provider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
            }
            if viewModel.config.provider == .openAI {
                openAIAuth.checkAuthenticationStatus()
                codexAuth.checkStatus()
            }
        }
        .onChange(of: viewModel.config.provider) { _, newProvider in
            if newProvider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
            }
            if newProvider == .openAI {
                openAIAuth.checkAuthenticationStatus()
                codexAuth.checkStatus()
            }
        }
    }
    
    private var copilotConfigSection: some View {
        SettingsCard(title: "GitHub Copilot", icon: "person.badge.key", color: .black) {
            if copilotAuth.isAuthenticated {
                // Signed in state
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in")
                            .font(.headline)
                        if let username = copilotAuth.username {
                            ZStack {
                                Text(username)
                                    .opacity(isHoveringUsername ? 0 : 1)
                                    .blur(radius: 10)

                                Text(username)
                                    .opacity(isHoveringUsername ? 1 : 0)
                            }
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
                    }
                    
                    Spacer()
                    
                    if viewModel.isLoadingModels {
                        BouncingSpinner(size: 12, color: .secondary)
                    } else {
                        ModelSelectorRow(
                            provider: .githubCopilot,
                            model: viewModel.config.model,
                            onTap: { showModelPicker = true }
                        )
                        .frame(maxWidth: 220)
                        .modelSelectorTriggerBounds()
                    }
                    
                    Button("Sign Out") {
                        copilotAuth.signOut()
                    }
                    .buttonStyle(.bordered)
                }
                .onAppear {
                    viewModel.updateAvailableModels()
                }
            } else if let code = copilotAuth.deviceCodeResponse {
                // Device code flow
                VStack(alignment: .leading, spacing: 16) {
                    StepCard(number: 1, title: "Open URL in browser") {
                        Link(destination: URL(string: code.verificationUri)!) {
                            Text(code.verificationUri)
                                .underline()
                                .foregroundColor(.blue)
                        }
                        .trackHoveredURL(URL(string: code.verificationUri)!)
                    }
                    
                    StepCard(number: 2, title: "Enter this code") {
                        HStack(spacing: 8) {
                            Text(code.userCode)
                                .font(.system(.title2, design: .monospaced))
                                .bold()
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            
                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(code.userCode, forType: .string)
                                HapticFeedbackManager.shared.tap()
                                withAnimation { hasCopiedCode = true }
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                                    withAnimation { hasCopiedCode = false }
                                }
                            } label: {
                                Image(systemName: hasCopiedCode ? "checkmark" : "doc.on.doc")
                                    .foregroundColor(hasCopiedCode ? .green : .primary)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        BouncingSpinner(size: 10, color: .secondary)
                        Text("Waiting for authorization...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Sign in prompt
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sign in with GitHub to use Copilot models.")
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
                        HapticFeedbackManager.shared.tap()
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.key.fill")
                            Text("Sign in with GitHub")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.onboardingPill)
                    .tint(.black)
                    
                    if let error = copilotAuth.authError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Divider()
                    
                    Text("Requires an active GitHub Copilot subscription. This is an unofficial integration.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var apiConfigSection: some View {
        SettingsCard(title: "API Configuration", icon: "key", color: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                if [.openAICompatible, .ollama].contains(viewModel.config.provider) {
                    SettingsTextField(
                        title: "API URL",
                        text: Binding(
                            get: { viewModel.config.apiURL ?? (viewModel.config.provider == .ollama ? "http://localhost:11434/v1" : "https://api.openai.com") },
                            set: { viewModel.config.apiURL = $0.isEmpty ? nil : $0 }
                        ),
                        placeholder: viewModel.config.provider == .ollama ? "http://localhost:11434/v1" : "https://api.openai.com"
                    )
                }

                if supportsSubscriptionAuthUI {
                    subscriptionAuthSection
                } else {
                    SettingsSecureField(
                        title: "API Key",
                        text: Binding(
                            get: { viewModel.config.apiKey ?? "" },
                            set: { viewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                        ),
                        isOptional: !viewModel.config.requiresAPIKey
                    )
                }
                
                if let url = viewModel.config.provider.apiKeyURL {
                    HStack(spacing: 4) {
                        Text("Get your API key from")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Link(destination: url) {
                            Text(viewModel.config.provider.apiKeyLinkLabel)
                                .font(.caption)
                                .underline()
                        }
                        .trackHoveredURL(url)
                    }
                } else {
                    Text(viewModel.config.provider.apiKeyHelpText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ModelSelectorRow(
                        provider: viewModel.config.provider,
                        model: viewModel.config.model,
                        onTap: { showModelPicker = true }
                    )
                    .modelSelectorTriggerBounds()
                }
            }
        }
    }

    private var subscriptionAuthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Authentication", selection: selectedAuthMethod) {
                ForEach(viewModel.config.provider.supportedAuthMethods, id: \.self) { method in
                    Text(method.displayName).tag(method)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("ProviderAuthMethodPicker")

            switch viewModel.config.authMethod(for: viewModel.config.provider) {
            case .apiKey:
                SettingsSecureField(
                    title: "API Key",
                    text: Binding(
                        get: { viewModel.config.apiKey ?? "" },
                        set: { viewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                    ),
                    isOptional: false
                )

            case .accountSignIn:
                codexCLISignInSection

            case .manualSessionToken:
                SettingsSecureField(
                    title: "API Key",
                    text: Binding(
                        get: { viewModel.config.apiKey ?? "" },
                        set: { viewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                    ),
                    isOptional: false
                )
            }
        }
    }

    private var codexCLISignInSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if codexAuth.isAuthenticated {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Signed in via Codex CLI")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let email = codexAuth.accountEmail {
                            ZStack {
                                Text(email)
                                    .opacity(isHoveringUsername ? 0 : 1)
                                    .blur(radius: 8)

                                Text(email)
                                    .opacity(isHoveringUsername ? 1 : 0)
                            }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 5)
                                .clipShape(Capsule())
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
                    }

                    Spacer()

                    Button("Sign Out") {
                        codexAuth.signOut()
                        openAIAuth.checkAuthenticationStatus()
                        HapticFeedbackManager.shared.tap()
                        viewModel.updateAvailableModels(force: true)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("ProviderSignOutButton")
                }
                .padding(10)
                .background(Color.green.opacity(0.08))
                .cornerRadius(8)
            } else {
                codexCLISetupInstructions
            }
        }
    }

    private var codexCLISetupInstructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sign in with your OpenAI account using Codex CLI to enable Codex integration in Sorty.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label("Disclaimer", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    disclaimerBullet("This is an unofficial integration and is not affiliated with or endorsed by OpenAI.")
                    disclaimerBullet("You must have an active ChatGPT Plus or Pro subscription")
                    disclaimerBullet("You understand your data will be sent to OpenAI's servers via Codex CLI")
                    disclaimerBullet("You agree to comply with OpenAI's Terms of Service")
                    disclaimerBullet("This is for personal, non-automated use only")
                    disclaimerBullet("This software is provided 'as is' without warranties")
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.06))
            .cornerRadius(8)

            // Step 1
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 1: Sign in to Codex CLI")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("Install Node.js 18+, then install Codex CLI and sign in:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                codexCommandBlock("npm i -g @openai/codex")
                codexCommandBlock("codex login")

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
            }

            // Step 2
            VStack(alignment: .leading, spacing: 6) {
                Text("Step 2: Verify")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text("We automatically verify that Codex CLI is installed and that your auth tokens are present in ~/.codex/auth.json. You can also run a manual verify anytime.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

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
                } else if !codexAuth.isAuthenticated {
                    Label("Codex CLI installed, but not signed in", systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .task {
                await autoVerifyCodexSignInLoop()
            }

            if let error = codexAuth.authError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func disclaimerBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func codexCommandBlock(_ command: String) -> some View {
        HStack {
            Text(command)
                .font(.system(.caption, design: .monospaced))
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
            .help("Copy command")
        }
        .padding(8)
        .background(Color.black.opacity(0.05))
        .cornerRadius(6)
    }

    private var appleConfigSection: some View {
        SettingsCard(title: "Apple Models", icon: "apple.logo", color: .gray) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ModelSelectorRow(
                        provider: .appleFoundationModel,
                        model: viewModel.config.model,
                        onTap: { showModelPicker = true }
                    )
                    .modelSelectorTriggerBounds()
                }

                if !viewModel.isAppleModelAvailable {
                    Divider()
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On-device model unavailable")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(viewModel.appleModelStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    private var connectionSection: some View {
        SettingsCard(title: "Connection", icon: "network", color: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                if showsRequiresAPIKeyToggle {
                    Toggle(isOn: $viewModel.config.requiresAPIKey) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Requires API Key")
                                .font(.subheadline)
                            Text("Disable for local endpoints without auth")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    
                    Divider()
                }
                
                HStack(spacing: 12) {
                    Button(action: testConnection) {
                        HStack(spacing: 6) {
                            if isTestingConnection {
                                BouncingSpinner(size: 12, color: .primary)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingConnection || !viewModel.config.provider.isAvailable)
                    
                    if let status = testConnectionStatus {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                status.contains("Success") ? "Connected" : "Connection Failed",
                                systemImage: status.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill"
                            )
                            .foregroundColor(status.contains("Success") ? .green : .red)
                            
                            if !status.contains("Success") {
                                HStack(alignment: .top, spacing: 6) {
                                    Text(status.replacingOccurrences(of: "Error: ", with: ""))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.red)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                    
                                    Button {
                                        let pb = NSPasteboard.general
                                        pb.clearContents()
                                        pb.setString(status.replacingOccurrences(of: "Error: ", with: ""), forType: .string)
                                        HapticFeedbackManager.shared.tap()
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy error message")
                                }
                                
                                if let details = testConnectionDetails, !details.isEmpty {
                                    DisclosureGroup(isExpanded: $isDetailsExpanded) {
                                        Text(details)
                                            .font(.system(.caption, design: .monospaced))
                                            .padding(6)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(4)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    } label: {
                                        HStack {
                                            Text("Technical Details")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3)) {
                                                isDetailsExpanded.toggle()
                                            }
                                        }
                                    }
                                    .frame(maxWidth: 400)
                                }
                            }
                        }
                        .font(.subheadline)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
    }
    
    private func testConnection() {
        HapticFeedbackManager.shared.tap()
        isTestingConnection = true
        testConnectionStatus = nil
        testConnectionDetails = nil
        isDetailsExpanded = false

        Task {
            do {
                try await viewModel.testConnection()
                HapticFeedbackManager.shared.success()
                await MainActor.run {
                    appState.clearSetupRepairState()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        testConnectionStatus = "Success: Connection test passed"
                        testConnectionDetails = nil
                    }
                }
            } catch let decodingError as DecodingError {
                HapticFeedbackManager.shared.error()
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        testConnectionStatus = "Error: Invalid response format"
                        testConnectionDetails = "The API endpoint may be incorrect or the service returned unexpected data.\n\nDetails: \(context)"
                    }
                }
            } catch {
                HapticFeedbackManager.shared.error()
                await MainActor.run {
                    var details: String? = nil
                    if let aiError = error as? AIClientError {
                        details = aiError.failureReason
                    } else {
                        details = (error as NSError).localizedFailureReason ?? (error as NSError).localizedRecoverySuggestion
                    }
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        testConnectionStatus = "Error: \(error.localizedDescription)"
                        testConnectionDetails = details
                    }
                }
            }
            isTestingConnection = false
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
            viewModel.updateAvailableModels(force: true)
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
                viewModel.config.provider == .openAI
                    && viewModel.config.authMethod(for: .openAI) == .accountSignIn
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

    private func openShortcutsApp() {
        HapticFeedbackManager.shared.tap()
        if let shortcutsURL = URL(string: "shortcuts://") {
            NSWorkspace.shared.open(shortcutsURL)
        }
    }

    private var supportsSubscriptionAuthUI: Bool {
        FeatureFlags.subscriptionAuthEnabled && viewModel.config.provider.supportsSubscriptionAuth
    }

    private var selectedAuthMethod: Binding<ProviderAuthMethod> {
        Binding(
            get: { viewModel.config.authMethod(for: viewModel.config.provider) },
            set: { newMethod in
                setAuthMethod(newMethod)
            }
        )
    }

    private var showsRequiresAPIKeyToggle: Bool {
        guard viewModel.config.provider != .appleFoundationModel else {
            return false
        }
        if supportsSubscriptionAuthUI, viewModel.config.authMethod(for: viewModel.config.provider) != .apiKey {
            return false
        }
        return true
    }

    private func setAuthMethod(_ method: ProviderAuthMethod) {
        let provider = viewModel.config.provider
        var next = viewModel.config
        next.setAuthMethod(method, for: provider)
        if method == .apiKey {
            next.apiKey = KeychainManager.get(key: provider.keychainKey)
        } else {
            next.apiKey = nil
        }
        viewModel.config = next
        HapticFeedbackManager.shared.selection()
        viewModel.updateAvailableModels(force: true)
        openAIAuth.checkAuthenticationStatus()
    }
}

#Preview {
    let codexAuthManager = CodexCLIAuthManager()

    AIProviderSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(SubscriptionAuthManager(provider: .openAI, codexAuthManager: codexAuthManager))
        .environmentObject(codexAuthManager)
        .frame(width: 500, height: 600)
}

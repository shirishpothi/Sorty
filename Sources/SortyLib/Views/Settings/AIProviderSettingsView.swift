//
//  AIProviderSettingsView.swift
//  Sorty
//
//  AI Provider settings section
//

import SwiftUI

struct AIProviderSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
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
    @State private var isHoveringCodexTerminalButton = false
    @State private var isHoveringCodexVerifyButton = false
    @State private var codexTerminalButtonState: CodexActionVisualState = .idle
    @State private var codexVerifyButtonState: CodexActionVisualState = .idle
    @State private var codexTerminalResetTask: Task<Void, Never>?
    @State private var codexVerifyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            providerSelectionSection
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
        .onAppear {
            if viewModel.config.provider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
            }
            if viewModel.config.provider == .openAI {
                codexAuth.checkStatus()
                openAIAuth.checkAuthenticationStatus()
            }
        }
        .onChange(of: viewModel.config.provider) { _, newProvider in
            if newProvider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
            }
            if newProvider == .openAI {
                codexAuth.checkStatus()
                openAIAuth.checkAuthenticationStatus()
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
    }

    private var providerSelectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Select Provider", systemImage: "cpu")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)

            VStack(spacing: 2) {
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

                    if provider != AIProvider.userSelectableProviders.last {
                        Divider()
                            .padding(.leading, 54)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            Text(username)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .blur(radius: (FeatureFlags.privacyModeEnabled && !isHoveringUsername) ? 4 : 0)
                                .animation(.spring(), value: isHoveringUsername)
                                .onHover { hovering in
                                    isHoveringUsername = hovering
                                }
                        }
                    }

                    Spacer()

                    if !viewModel.availableModels.isEmpty {
                        ModelSelectorRow(
                            provider: .githubCopilot,
                            model: viewModel.config.model,
                            onTap: { showModelPicker = true }
                        )
                        .frame(width: 220)
                        .modelSelectorTriggerBounds()
                    } else if viewModel.isLoadingModels {
                        BouncingSpinner(size: 12, color: .secondary)
                    }

                    Button("Sign Out") {
                        copilotAuth.signOut()
                    }
                    .buttonStyle(.sortyBordered)
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
                            .buttonStyle(.sortyBordered)
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
                        Task { try? await copilotAuth.startDeviceFlow() }
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

                if viewModel.config.provider == .openAI {
                    openAIAuthenticationSection
                } else {
                    apiKeySection
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

    private var supportsSubscriptionAuthUI: Bool {
        FeatureFlags.subscriptionAuthEnabled && viewModel.config.provider.supportsSubscriptionAuth
    }

    private var selectedAuthMethod: Binding<ProviderAuthMethod> {
        Binding(
            get: { viewModel.config.authMethod(for: viewModel.config.provider) },
            set: { setAuthMethod($0) }
        )
    }

    private func setAuthMethod(_ method: ProviderAuthMethod) {
        var nextConfig = viewModel.config
        let provider = nextConfig.provider
        nextConfig.setAuthMethod(method, for: provider)
        nextConfig.apiKey = method == .apiKey ? KeychainManager.get(key: provider.keychainKey) : nil
        viewModel.config = nextConfig
        viewModel.updateAvailableModels(force: true)
        openAIAuth.checkAuthenticationStatus()
        HapticFeedbackManager.shared.selection()
    }

    @ViewBuilder
    private var openAIAuthenticationSection: some View {
        if supportsSubscriptionAuthUI {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Authentication", selection: selectedAuthMethod) {
                    ForEach(viewModel.config.provider.supportedAuthMethods, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch viewModel.config.authMethod(for: .openAI) {
                case .apiKey, .manualSessionToken:
                    apiKeySection
                case .accountSignIn:
                    codexSubscriptionSection
                }
            }
        } else {
            apiKeySection
        }
    }

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSecureField(
                title: "API Key",
                text: Binding(
                    get: { viewModel.config.apiKey ?? "" },
                    set: { viewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                ),
                isOptional: !viewModel.config.requiresAPIKey
            )

            if let url = viewModel.config.provider.apiKeyURL {
                HStack(spacing: 4) {
                    Text(viewModel.config.provider == .ollama ? "Find Ollama models at" : "Get your API key from")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Link(destination: url) {
                        Text(viewModel.config.provider.apiKeyLinkLabel)
                            .font(.caption)
                            .underline()
                    }
                }
            } else {
                Text(viewModel.config.provider.apiKeyHelpText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var codexSubscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if codexAuth.isAuthenticated {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codex subscription ready")
                            .font(.subheadline.weight(.semibold))
                        Text(codexAuth.accountEmail ?? "Signed in via Codex CLI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Sign Out") {
                        codexAuth.signOut()
                        openAIAuth.checkAuthenticationStatus()
                    }
                    .buttonStyle(.sortyBordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.green.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text("Use your OpenAI account through Codex CLI. Sorty reads the local Codex session after you sign in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    codexCommandBlock("npm i -g @openai/codex")
                    codexCommandBlock("codex login")
                }

                HStack(spacing: 8) {
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
                    .onHover { hovering in isHoveringCodexTerminalButton = hovering }

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
                    .onHover { hovering in isHoveringCodexVerifyButton = hovering }
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task {
            await autoVerifyCodexSignInLoop()
        }
    }

    private func codexCommandBlock(_ command: String) -> some View {
        HStack(spacing: 8) {
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
            .help("Copy command")
        }
        .padding(7)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                if viewModel.config.provider != .appleFoundationModel {
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

                VStack(spacing: 12) {
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
                    .buttonStyle(.sortyBordered)
                    .disabled(isTestingConnection || !viewModel.config.provider.isAvailable)

                    if let status = testConnectionStatus {
                        VStack(alignment: .center, spacing: 4) {
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
                                .frame(maxWidth: .infinity, alignment: .center)

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
                .frame(maxWidth: .infinity, alignment: .center)
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
    @discardableResult
    private func verifyCodexSignInStatus() -> Bool {
        let wasAuthenticated = codexAuth.isAuthenticated
        codexAuth.checkStatus()
        openAIAuth.checkAuthenticationStatus()
        if codexAuth.isAuthenticated && !wasAuthenticated {
            viewModel.updateAvailableModels(force: true)
            return true
        }
        return false
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

        if verifyCodexSignInStatus() || codexAuth.isAuthenticated {
            codexVerifyButtonState = .success
            HapticFeedbackManager.shared.success()
        } else {
            codexVerifyButtonState = .failure
            HapticFeedbackManager.shared.error()
            if !codexAuth.isCodexInstalled {
                codexAuth.authError = "Codex CLI not found. Install with: npm i -g @openai/codex"
            } else if codexAuth.authError == nil {
                codexAuth.authError = "Auth tokens not found. Run 'codex login' first."
            }
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
}

#Preview {
    let codexAuthManager = CodexCLIAuthManager()
    AIProviderSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(SubscriptionAuthManager(provider: .openAI, codexAuthManager: codexAuthManager))
        .environmentObject(codexAuthManager)
        .frame(width: 500, height: 600)
}

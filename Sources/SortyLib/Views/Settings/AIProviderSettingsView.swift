//
//  AIProviderSettingsView.swift
//  Sorty
//
//  AI Provider settings section
//

import SwiftUI

struct AIProviderSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var entitlementManager: EntitlementManager
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
    @State private var codexTerminalButtonState: CodexActionVisualState = .idle
    @State private var codexTerminalResetTask: Task<Void, Never>?
    @State private var codexDeviceAuthDismissTask: Task<Void, Never>?
    @State private var codexDeviceCodeCopiedID: UUID?
    @State private var isShowingCodexDeviceAuth = false

    private let providerColumns = Array(
        repeating: GridItem(.flexible(minimum: 160), spacing: 10),
        count: 3
    )

    private var lockedProviders: [AIProvider] {
        entitlementManager.visibleProviders.filter { !entitlementManager.isProviderSelectable($0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Provider Selection
            SettingsCard(title: "Select Provider", icon: "cpu", color: .purple) {
                LazyVGrid(
                    columns: providerColumns,
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(entitlementManager.visibleProviders, id: \.self) { provider in
                        AIProviderRow(
                            provider: provider,
                            isSelected: viewModel.config.provider == provider,
                            isLocked: !entitlementManager.isProviderSelectable(provider),
                            lockLabel: "Pro",
                            action: {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) {
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

                if !lockedProviders.isEmpty {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unlock more AI providers")
                                .font(.subheadline.weight(.semibold))
                            Text("Locked providers remain visible so you can compare the full lineup before upgrading.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)
                        OpenLicensingButton(title: "View Upgrade")
                    }
                    .padding(.top, 4)
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
        .sheet(isPresented: $isShowingCodexDeviceAuth) {
            CodexDeviceAuthSheet(
                session: codexAuth.deviceAuthSession,
                isCodexInstalled: codexAuth.isCodexInstalled,
                authError: codexAuth.authError,
                onStart: startCodexDeviceAuth,
                onCancel: {
                    codexDeviceAuthDismissTask?.cancel()
                    codexAuth.cancelDeviceAuth()
                    isShowingCodexDeviceAuth = false
                },
                onOpenSettings: openChatGPTSecuritySettings,
                onOpenDeviceAuthorization: openCodexDeviceAuthorization,
                onCopyCode: copyCodexDeviceCode,
                copiedID: codexDeviceCodeCopiedID
            )
            .frame(width: 610)
            .systemLiquidGlassBackground(cornerRadius: 28)
            .systemLiquidGlassPopover(cornerRadius: 28)
        }
        .onChange(of: codexAuth.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated, isShowingCodexDeviceAuth else { return }
            handleCodexDeviceAuthSuccess()
        }
        .onChange(of: codexAuth.deviceAuthSession?.status) { _, status in
            guard status == .authorized, isShowingCodexDeviceAuth else { return }
            handleCodexDeviceAuthSuccess()
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
                    ForEach(entitlementManager.supportedAuthMethods(for: viewModel.config.provider), id: \.self) { method in
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
                Text("Use your ChatGPT subscription for OpenAI inference through Codex CLI device authorization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    startCodexDeviceAuth()
                    isShowingCodexDeviceAuth = true
                } label: {
                    Label(codexDeviceAuthButtonTitle, systemImage: codexDeviceAuthButtonSymbol)
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.small)
                .accessibilityIdentifier("CodexDeviceAuthButton")
                .onHover { hovering in isHoveringCodexTerminalButton = hovering }

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

    private var codexDeviceAuthButtonTitle: String {
        switch codexTerminalButtonState {
        case .idle:
            return "Authenticate ChatGPT Subscription"
        case .activating:
            return "Starting Authorization..."
        case .success:
            return "Authorization Started"
        case .failure:
            return "Could Not Start Authorization"
        }
    }

    private var codexDeviceAuthButtonSymbol: String {
        switch codexTerminalButtonState {
        case .idle:
            return "person.crop.circle.badge.checkmark"
        case .activating:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
        }
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
                    HStack {
                        Spacer()
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
                        .fixedSize()
                        Spacer()
                    }

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
                    handleCodexDeviceAuthSuccess()
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
    private func startCodexDeviceAuth() {
        HapticFeedbackManager.shared.tap()
        codexTerminalButtonState = .activating
        codexAuth.startDeviceAuth()

        if codexAuth.authError == nil {
            codexTerminalButtonState = .success
        } else {
            codexTerminalButtonState = .failure
            HapticFeedbackManager.shared.error()
        }

        scheduleCodexTerminalButtonReset()
    }

    @MainActor
    private func openChatGPTSecuritySettings() {
        HapticFeedbackManager.shared.tap()
        let targetToggle = "Enable device code authorization for Codex"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(targetToggle, forType: .string)

        if let url = URL(string: "https://chatgpt.com/#settings/Security") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func openCodexDeviceAuthorization() {
        HapticFeedbackManager.shared.tap()
        let url = codexAuth.deviceAuthSession?.verificationURL
            ?? URL(string: "https://auth.openai.com/activate")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func copyCodexDeviceCode() {
        guard let code = codexAuth.deviceAuthSession?.userCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        HapticFeedbackManager.shared.tap()

        let copiedID = UUID()
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.72)) {
            codexDeviceCodeCopiedID = copiedID
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard codexDeviceCodeCopiedID == copiedID else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                codexDeviceCodeCopiedID = nil
            }
        }
    }

    @MainActor
    private func scheduleCodexTerminalButtonReset() {
        codexTerminalResetTask?.cancel()
        codexTerminalResetTask = Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                guard codexAuth.deviceAuthSession?.status != .authorized else { return }
                codexTerminalButtonState = .idle
            }
        }
    }

    @MainActor
    private func handleCodexDeviceAuthSuccess() {
        guard isShowingCodexDeviceAuth else { return }

        codexTerminalButtonState = .success
        viewModel.updateAvailableModels(force: true)
        openAIAuth.checkAuthenticationStatus()
        HapticFeedbackManager.shared.success()

        codexDeviceAuthDismissTask?.cancel()
        codexDeviceAuthDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard codexAuth.isAuthenticated || codexAuth.deviceAuthSession?.status == .authorized else { return }
            isShowingCodexDeviceAuth = false
        }
    }

    private func openShortcutsApp() {
        HapticFeedbackManager.shared.tap()
        if let shortcutsURL = URL(string: "shortcuts://") {
            NSWorkspace.shared.open(shortcutsURL)
        }
    }
}

private struct CodexDeviceAuthSheet: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: CodexDeviceAuthSession?
    let isCodexInstalled: Bool
    let authError: String?
    let onStart: () -> Void
    let onCancel: () -> Void
    let onOpenSettings: () -> Void
    let onOpenDeviceAuthorization: () -> Void
    let onCopyCode: () -> Void
    let copiedID: UUID?

    private var userCode: String {
        session?.userCode ?? "---- -----"
    }

    private var isWaiting: Bool {
        switch session?.status {
        case .starting, .waiting:
            return true
        default:
            return false
        }
    }

    private var isCodeCopied: Bool {
        copiedID != nil
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 14) {
                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reauthenticate ChatGPT Subscription")
                        .font(.title2.weight(.bold))
                    Text("Reauthenticate to keep using your ChatGPT subscription for OpenAI inference.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 12) {
                CodexDeviceAuthStep(number: 1, title: "Enable device code authorization for Codex.") {
                    Button(action: onOpenSettings) {
                        Label("Open ChatGPT Settings", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.sortyBordered)
                    .controlSize(.small)
                }

                CodexDeviceAuthStep(number: 2, title: "Open the OpenAI device authorization page.") {
                    Button(action: onOpenDeviceAuthorization) {
                        Label("Open device authorization", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.sortyBordered)
                    .controlSize(.small)
                }

                CodexDeviceAuthStep(number: 3, title: "Paste this device code when OpenAI asks for it:") {
                    Button(action: onCopyCode) {
                        HStack(spacing: 12) {
                            Text(userCode)
                                .font(.title2.monospaced().weight(.bold))
                                .tracking(3)
                                .frame(minWidth: 190, alignment: .leading)

                            Spacer(minLength: 10)

                            Label(isCodeCopied ? "Copied" : "Copy", systemImage: isCodeCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isCodeCopied ? .green : .secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isCodeCopied ? Color.green.opacity(0.10) : Color.clear)
                    }
                    .systemLiquidGlassBackground(cornerRadius: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isCodeCopied ? Color.green.opacity(0.42) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .scaleEffect(isCodeCopied && !reduceMotion ? 1.015 : 1)
                    .disabled(session?.userCode == nil)
                    .help("Copy device code")
                    .accessibilityLabel(isCodeCopied ? "Device code copied" : "Copy device code")
                }

                CodexDeviceAuthStep(number: 4, title: "Continue to finish approval.") {
                    CodexDeviceAuthStatusView(
                        session: session,
                        isCodexInstalled: isCodexInstalled,
                        authError: authError,
                        isWaiting: isWaiting,
                        onStart: onStart
                    )
                }
            }

            Text("Keep this dialog open while Sorty waits for approval.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.sortyBordered)
            }
        }
        .padding(28)
        .onAppear {
            if session == nil {
                onStart()
            }
        }
    }
}

private struct CodexDeviceAuthStep<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .systemLiquidGlassBackground(cornerRadius: 16)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .systemLiquidGlassBackground(cornerRadius: 14)
    }
}

private struct CodexDeviceAuthStatusView: View {
    let session: CodexDeviceAuthSession?
    let isCodexInstalled: Bool
    let authError: String?
    let isWaiting: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            switch session?.status {
            case .authorized:
                Label("Authorization complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                Button("Try Again", action: onStart)
                    .buttonStyle(.sortyBordered)
                    .controlSize(.small)
            default:
                HStack(spacing: 8) {
                    BouncingSpinner(size: 14, color: .primary)
                    Text(isWaiting ? "Waiting for authorization" : "Starting authorization")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Refreshing automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isCodexInstalled {
                Text("Codex CLI is required. Install with: npm i -g @openai/codex")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let authError {
                Text(authError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .systemLiquidGlassBackground(cornerRadius: 12)
    }
}

#Preview {
    let codexAuthManager = CodexCLIAuthManager()
    AIProviderSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AppState())
        .environmentObject(EntitlementManager())
        .environmentObject(SubscriptionAuthManager(provider: .openAI, codexAuthManager: codexAuthManager))
        .environmentObject(codexAuthManager)
        .frame(width: 500, height: 600)
}

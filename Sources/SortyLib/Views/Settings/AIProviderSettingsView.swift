//
//  AIProviderSettingsView.swift
//  Sorty
//
//  AI Provider settings section
//

import SwiftUI

struct AIProviderSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @ObservedObject var copilotAuth = GitHubCopilotAuthManager.shared
    
    @State private var testConnectionStatus: String?
    @State private var testConnectionDetails: String?
    @State private var isTestingConnection = false
    @State private var hasCopiedCode = false
    @State private var showModelPicker = false
    @State private var isHoveringUsername = false
    @State private var isDetailsExpanded = false
    
    var body: some View {
        VStack(spacing: 16) {
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
        .onAppear {
            if viewModel.config.provider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
            }
        }
        .onChange(of: viewModel.config.provider) { _, newProvider in
            if newProvider == .githubCopilot {
                copilotAuth.checkAuthenticationStatus()
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
                        Picker("", selection: $viewModel.config.model) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    } else if viewModel.isLoadingModels {
                        BouncingSpinner(size: 12, color: .secondary)
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
                        Text("Get your API key from")
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
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ModelSelectorRow(
                        provider: viewModel.config.provider,
                        model: viewModel.config.model,
                        onTap: { showModelPicker = true }
                    )
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelSelectionPopover(
                isPresented: $showModelPicker,
                currentProvider: viewModel.config.provider,
                currentModel: viewModel.config.model,
                onSelect: { provider, model in
                    viewModel.config.provider = provider
                    viewModel.config.model = model
                }
            )
        }
    }

    private var appleConfigSection: some View {
        let pccEnabled = FeatureFlags.applePrivateCloudComputeModelEnabled

        return SettingsCard(title: "Apple Models", icon: "apple.logo", color: .gray) {
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
                }

                if pccEnabled && viewModel.config.model == AIProvider.applePrivateCloudComputeModelName {
                    Divider()

                    HStack(spacing: 8) {
                        Image(systemName: ApplePrivateCloudComputeClient.isShortcutInstalled() ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ApplePrivateCloudComputeClient.isShortcutInstalled() ? .green : .orange)
                        Text(ApplePrivateCloudComputeClient.isShortcutInstalled() ? "Apple Intelligence shortcut ready" : "Apple Intelligence shortcut unavailable")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Text("No API key needed. Sorty automatically detects \"\(ApplePrivateCloudComputeClient.legacyShortcutName)\" or \"\(ApplePrivateCloudComputeClient.shortcutName)\" and uses whichever is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !ApplePrivateCloudComputeClient.isShortcutInstalled() {
                        Button("Open Shortcuts") {
                            openShortcutsApp()
                        }
                        .buttonStyle(.bordered)
                    }
                } else if !viewModel.isAppleModelAvailable {
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
                            if pccEnabled {
                                Button("Use Apple Private Cloud Compute") {
                                    viewModel.config.model = AIProvider.applePrivateCloudComputeModelName
                                }
                                .buttonStyle(.link)
                            } else {
                                Text("Apple Private Cloud Compute is disabled by feature flag.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelSelectionPopover(
                isPresented: $showModelPicker,
                currentProvider: .appleFoundationModel,
                currentModel: viewModel.config.model,
                onSelect: { provider, model in
                    viewModel.config.provider = provider
                    viewModel.config.model = model
                }
            )
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

    private func openShortcutsApp() {
        HapticFeedbackManager.shared.tap()
        if let shortcutsURL = URL(string: "shortcuts://") {
            NSWorkspace.shared.open(shortcutsURL)
        }
    }
}

#Preview {
    AIProviderSettingsView()
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 600)
}

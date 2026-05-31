//
//  AIProviderSettingsView.swift
//  Sorty
//
//  AI Provider settings section
//

import SwiftUI

struct AIProviderSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var copilotAuth = GitHubCopilotAuthManager.shared
    
    @State private var testConnectionStatus: String?
    @State private var testConnectionDetails: String?
    @State private var isTestingConnection = false
    @State private var hasCopiedCode = false
    @State private var showModelPicker = false
    @State private var isHoveringUsername = false
    @State private var isDetailsExpanded = false

    private let providerColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 280), spacing: 10, alignment: .top)
    ]
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                providerSelectionSection
                    .frame(minWidth: 420, maxWidth: .infinity, alignment: .top)
                    .animatedAppearance(delay: 0.05)

                configurationRail
                    .frame(width: 360)
                    .animatedAppearance(delay: 0.1)
            }

            VStack(spacing: 16) {
                providerSelectionSection
                    .animatedAppearance(delay: 0.05)
                configurationRail
                    .animatedAppearance(delay: 0.1)
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
        SettingsCard(title: "Select Provider", icon: "cpu", color: .purple) {
            VStack(alignment: .leading, spacing: 16) {
                selectedProviderHeadline

                ForEach(providerGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        LazyVGrid(columns: providerColumns, alignment: .leading, spacing: 10) {
                            ForEach(group.providers, id: \.self) { provider in
                                AIProviderRow(
                                    provider: provider,
                                    isSelected: viewModel.config.provider == provider,
                                    action: {
                                        selectProvider(provider)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectedProviderHeadline: some View {
        HStack(alignment: .center, spacing: 12) {
            ProviderLogoView(provider: viewModel.config.provider, size: 26)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(viewModel.config.provider.brandColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.config.provider.displayName)
                    .font(.headline)
                Text(viewModel.config.provider.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            ProviderSetupBadge(summary: setupSummary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.config.provider.displayName), \(setupSummary.title)")
    }

    private var configurationRail: some View {
        VStack(spacing: 16) {
            currentSetupSection
            providerConfigurationSection
            connectionSection
        }
    }

    @ViewBuilder
    private var providerConfigurationSection: some View {
        if viewModel.config.provider == .githubCopilot {
            copilotConfigSection
        } else if viewModel.config.provider == .appleFoundationModel {
            appleConfigSection
        } else if [.openAI, .groq, .openAICompatible, .openRouter, .anthropic, .ollama, .gemini].contains(viewModel.config.provider) {
            apiConfigSection
        }
    }

    private var currentSetupSection: some View {
        SettingsCard(title: "Current Setup", icon: setupSummary.icon, color: setupSummary.color) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: setupSummary.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(setupSummary.color)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(setupSummary.title)
                            .font(.subheadline.weight(.semibold))
                        Text(setupSummary.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                Divider()

                VStack(spacing: 9) {
                    SetupSummaryRow(icon: "cube", title: "Model", value: selectedModelDisplayName)

                    if let endpoint = selectedEndpointDisplayName {
                        SetupSummaryRow(icon: "network", title: "Endpoint", value: endpoint)
                    }

                    SetupSummaryRow(icon: "key", title: "Credential", value: credentialDisplayName)
                }
            }
        }
    }

    private var providerGroups: [AIProviderSettingsGroup] {
        let available = Set(AIProvider.userSelectableProviders)
        return [
            AIProviderSettingsGroup(
                title: "Best starting points",
                providers: [.openAI, .githubCopilot, .anthropic, .gemini].filter { available.contains($0) }
            ),
            AIProviderSettingsGroup(
                title: "Speed and breadth",
                providers: [.groq, .openRouter, .openAICompatible].filter { available.contains($0) }
            ),
            AIProviderSettingsGroup(
                title: "Local and on-device",
                providers: [.ollama, .appleFoundationModel].filter { available.contains($0) }
            )
        ]
        .filter { !$0.providers.isEmpty }
    }

    private var setupSummary: AIProviderSetupSummary {
        let provider = viewModel.config.provider

        if provider == .githubCopilot, !copilotAuth.isAuthenticated {
            return AIProviderSetupSummary(
                title: "Sign-in required",
                message: "Connect GitHub before Sorty can use Copilot models.",
                icon: "person.badge.key.fill",
                color: .orange,
                isReady: false
            )
        }

        if provider == .appleFoundationModel, !viewModel.isAppleModelAvailable {
            return AIProviderSetupSummary(
                title: "Unavailable",
                message: viewModel.appleModelStatus.isEmpty
                    ? "Apple Foundation Model is not available on this Mac."
                    : viewModel.appleModelStatus,
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                isReady: false
            )
        }

        if requiresEditableEndpoint(provider),
           (viewModel.config.apiURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AIProviderSetupSummary(
                title: "Endpoint required",
                message: "Add the API URL before testing this provider.",
                icon: "network.badge.shield.half.filled",
                color: .orange,
                isReady: false
            )
        }

        if !ProviderAuthResolver.hasRequiredCredential(for: provider, config: viewModel.config) {
            return AIProviderSetupSummary(
                title: "Credential required",
                message: "Add credentials before testing this provider.",
                icon: "key.fill",
                color: .orange,
                isReady: false
            )
        }

        return AIProviderSetupSummary(
            title: "Ready to test",
            message: "\(provider.displayName) has the required setup.",
            icon: "checkmark.shield.fill",
            color: .green,
            isReady: true
        )
    }

    private var selectedModelDisplayName: String {
        viewModel.config.model.isEmpty ? viewModel.config.provider.defaultModel : viewModel.config.model
    }

    private var selectedEndpointDisplayName: String? {
        guard requiresEditableEndpoint(viewModel.config.provider) else { return nil }
        return viewModel.config.apiURL ?? viewModel.config.provider.defaultAPIURL
    }

    private var credentialDisplayName: String {
        let provider = viewModel.config.provider
        let hasCredential = ProviderAuthResolver.hasRequiredCredential(for: provider, config: viewModel.config)

        if provider == .githubCopilot {
            return copilotAuth.isAuthenticated ? "GitHub signed in" : "Sign-in required"
        }

        if provider == .appleFoundationModel {
            return "Not required"
        }

        if provider == .ollama && !viewModel.config.requiresAPIKey {
            return "Not required"
        }

        if ProviderAuthResolver.effectiveAuthMethod(for: provider, config: viewModel.config) == .accountSignIn {
            return hasCredential ? "Codex CLI signed in" : "Codex CLI sign-in required"
        }

        if !viewModel.config.requiresAPIKey {
            return hasCredential ? "Optional key saved" : "Optional"
        }

        return hasCredential ? "API key saved" : "API key required"
    }

    private func requiresEditableEndpoint(_ provider: AIProvider) -> Bool {
        [.openAICompatible, .ollama].contains(provider)
    }

    private func selectProvider(_ provider: AIProvider) {
        let animation = reduceMotion ? nil : Animation.spring(response: 0.3, dampingFraction: 0.7)

        withAnimation(animation) {
            viewModel.config.provider = provider
            if let defaultURL = provider.defaultAPIURL {
                viewModel.config.apiURL = defaultURL
            }
            viewModel.config.requiresAPIKey = provider.typicallyRequiresAPIKey
            HapticFeedbackManager.shared.selection()
        }
    }
    
    private var copilotConfigSection: some View {
        SettingsCard(title: "GitHub Copilot", icon: "person.badge.key", color: .black) {
            if copilotAuth.isAuthenticated {
                // Signed in state
                VStack(alignment: .leading, spacing: 12) {
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
                                    .animation(reduceMotion ? nil : .spring(), value: isHoveringUsername)
                                    .onHover { hovering in
                                        isHoveringUsername = hovering
                                    }
                            }
                        }

                        Spacer()

                        Button("Sign Out") {
                            copilotAuth.signOut()
                        }
                        .buttonStyle(.sortyBordered)
                    }

                    if !viewModel.availableModels.isEmpty {
                        ModelSelectorRow(
                            provider: .githubCopilot,
                            model: viewModel.config.model,
                            onTap: { showModelPicker = true }
                        )
                        .modelSelectorTriggerBounds()
                    } else if viewModel.isLoadingModels {
                        HStack(spacing: 8) {
                            BouncingSpinner(size: 12, color: .secondary)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
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

    private func openShortcutsApp() {
        HapticFeedbackManager.shared.tap()
        if let shortcutsURL = URL(string: "shortcuts://") {
            NSWorkspace.shared.open(shortcutsURL)
        }
    }
}

private struct AIProviderSettingsGroup: Identifiable {
    let title: String
    let providers: [AIProvider]

    var id: String { title }
}

private struct AIProviderSetupSummary {
    let title: String
    let message: String
    let icon: String
    let color: Color
    let isReady: Bool
}

private struct ProviderSetupBadge: View {
    let summary: AIProviderSetupSummary

    var body: some View {
        Label(summary.isReady ? "Ready" : "Needs setup", systemImage: summary.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(summary.color)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(summary.color.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

private struct SetupSummaryRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
        .accessibilityElement(children: .combine)
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

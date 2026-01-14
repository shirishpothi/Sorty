//
//  AIProviderSettingsView.swift
//  Sorty
//
//  Improved AI Provider settings UI
//

import SwiftUI

struct AIProviderSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @ObservedObject var copilotAuth = GitHubCopilotAuthManager.shared
    
    // For connection testing
    @State private var testConnectionStatus: String?
    @State private var testConnectionDetails: String?
    @State private var isTestingConnection = false
    @State private var hasCopiedCode = false
    
    let providers = AIProvider.allCases
    
    var body: some View {
        VStack(spacing: 16) {
            // 1. Provider Selection
            SettingsCard(title: "AI Provider", icon: "cpu", color: .purple) {
                VStack(spacing: 4) {
                    ForEach(providers, id: \.self) { provider in
                        AIProviderRow(
                            provider: provider,
                            isSelected: viewModel.config.provider == provider,
                            action: { selectProvider(provider) }
                        )
                    }
                }
            }
            
            // 2. Configuration Area
            if viewModel.config.provider == .githubCopilot {
                SettingsCard(title: "GitHub Copilot", icon: "person.badge.key", color: .black) {
                    CopilotConfigView(
                        viewModel: viewModel,
                        copilotAuth: copilotAuth
                    )
                }
            } else if [.openAI, .groq, .openAICompatible, .openRouter, .anthropic, .ollama, .gemini].contains(viewModel.config.provider) {
                SettingsCard(title: "Configuration", icon: "slider.horizontal.3", color: .orange) {
                    StandardAPIConfigView(viewModel: viewModel)
                }
            }
            
            // 3. Connection Test
            if [.openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .anthropic, .ollama, .gemini, .appleFoundationModel].contains(viewModel.config.provider) {
                SettingsCard(title: "Connection", icon: "network", color: .blue) {
                    ConnectionTestView(
                        provider: viewModel.config.provider,
                        viewModel: viewModel,
                        isTesting: $isTestingConnection,
                        status: $testConnectionStatus,
                        details: $testConnectionDetails,
                        testAction: testConnection
                    )
                }
            }
        }
    }
    
    private func selectProvider(_ provider: AIProvider) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            viewModel.config.provider = provider
            if let defaultURL = provider.defaultAPIURL {
                viewModel.config.apiURL = defaultURL
            }
            viewModel.config.model = provider.defaultModel
            viewModel.config.requiresAPIKey = provider.typicallyRequiresAPIKey
            HapticFeedbackManager.shared.selection()
            
            // Clear test status on change
            testConnectionStatus = nil
        }
    }
    
    private func testConnection() {
        guard !isTestingConnection else { return }
        
        isTestingConnection = true
        testConnectionStatus = nil
        testConnectionDetails = nil
        HapticFeedbackManager.shared.tap()
        
        Task {
            do {
                if viewModel.config.provider == .githubCopilot {
                    // Specific Copilot check
                    if !GitHubCopilotAuthManager.shared.isAuthenticated {
                         throw NSError(domain: "Copilot", code: 401, userInfo: [NSLocalizedDescriptionKey: "Sign in required"])
                    }
                }
                
                let client = try AIClientFactory.createClient(config: viewModel.config)
                // Simple connectivity check
                _ = try await client.generateText(prompt: "Hello", systemPrompt: nil)
                
                await MainActor.run {
                    withAnimation {
                        testConnectionStatus = "Success! Connected to \(viewModel.config.provider.displayName)"
                        testConnectionDetails = nil
                        isTestingConnection = false
                        HapticFeedbackManager.shared.success()
                    }
                }
            } catch {
                await MainActor.run {
                    var details: String? = nil
                    if let aiError = error as? AIClientError {
                        details = aiError.failureReason
                    } else {
                        details = (error as NSError).localizedFailureReason ?? (error as NSError).localizedRecoverySuggestion
                    }
                    
                    withAnimation {
                        testConnectionStatus = "Error: \(error.localizedDescription)"
                        testConnectionDetails = details
                        isTestingConnection = false
                        HapticFeedbackManager.shared.error()
                    }
                }
            }
        }
    }
}

// MARK: - Subviews

struct AIProviderRow: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void
    
    /// Load provider logo from bundle's Images folder
    private var providerImage: Image {
        if provider.usesSystemImage {
            return Image(systemName: provider.logoImageName)
        }
        
        // Try to load from Images folder in bundle
        if let resourceURL = Bundle.module.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // Fallback to asset catalog (for Xcode builds)
        return Image(provider.logoImageName, bundle: .module)
    }
    
    var body: some View {
        Button(action: {
            if provider.isAvailable { action() }
        }) {
            HStack(spacing: 12) {
                // Provider logo
                providerImage
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                
                Text(provider.displayName)
                    .foregroundColor(provider.isAvailable ? .primary : .secondary)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Spacer()
                
                // Selection indicator
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
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .opacity(provider.isAvailable ? 1.0 : 0.6)
    }
}

struct CopilotConfigView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var copilotAuth: GitHubCopilotAuthManager
    @State private var hasCopiedCode = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("GitHub Copilot", systemImage: "person.badge.key")
                .font(.headline)
            
            Divider()
            
            if copilotAuth.isAuthenticated {
                // Signed in state
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in as \(copilotAuth.username ?? "User")")
                            .font(.subheadline)
                    }
                    
                    Spacer()
                    
                    Button("Sign Out") {
                        copilotAuth.signOut()
                    }
                    .buttonStyle(.bordered)
                }
                
                Group {
                    if !viewModel.availableModels.isEmpty {
                        Picker("Model", selection: $viewModel.config.model) {
                            ForEach(viewModel.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                    } else if viewModel.isLoadingModels {
                        HStack {
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            BouncingSpinner(size: 8, color: .secondary)
                        }
                    }
                }
                .onAppear {
                    viewModel.updateAvailableModels()
                }
                
            } else if let code = copilotAuth.deviceCodeResponse {
                // Device code flow
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("1. Open verification URL")
                                .font(.caption).bold()
                            Link(code.verificationUri, destination: URL(string: code.verificationUri)!)
                                .foregroundColor(.accentColor)
                        }
                        Spacer()
                    }
                    
                    HStack {
                        VStack(alignment: .leading) {
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
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    HStack {
                        BouncingSpinner(size: 8, color: .secondary)
                        Text("Waiting for authorization...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                
            } else {
                // Sign in prompt
                VStack(alignment: .leading, spacing: 12) {
                    Text("Access OpenAI models via your GitHub Copilot subscription.")
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Button {
                        Task { try? await copilotAuth.startDeviceFlow() }
                    } label: {
                        Text("Sign in with GitHub")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                    
                    if let error = copilotAuth.authError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
        }
    }
}

struct StandardAPIConfigView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Configuration", systemImage: "slider.horizontal.3")
                .font(.headline)
            
            Divider()
            
            if [.openAICompatible, .ollama].contains(viewModel.config.provider) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("API URL")
                        .font(.subheadline)
                    TextField(viewModel.config.provider == .ollama ? "http://localhost:11434/v1" : "https://api.openai.com", text: Binding(
                        get: { viewModel.config.apiURL ?? "" },
                        set: { viewModel.config.apiURL = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("API Key")
                        .font(.subheadline)
                    if !viewModel.config.requiresAPIKey {
                        Text("(Optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                SecureField("Enter API Key", text: Binding(
                    get: { viewModel.config.apiKey ?? "" },
                    set: { viewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                
                Text(viewModel.config.provider.apiKeyHelpText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Model Name")
                    .font(.subheadline)
                TextField(viewModel.config.provider.defaultModel, text: $viewModel.config.model)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

struct ConnectionTestView: View {
    let provider: AIProvider
    @ObservedObject var viewModel: SettingsViewModel
    @Binding var isTesting: Bool
    @Binding var status: String?
    @Binding var details: String?
    let testAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            
            if provider != .appleFoundationModel {
                Toggle("Requires Authentication", isOn: $viewModel.config.requiresAPIKey)
                    .toggleStyle(.switch)
                    .font(.subheadline)
            }
            
            HStack(alignment: .top) {
                Button(action: testAction) {
                    HStack {
                        if isTesting {
                            BouncingSpinner(size: 10, color: .primary)
                        } else {
                            Image(systemName: "network")
                        }
                        Text("Test Connection")
                    }
                    .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || !provider.isAvailable)
                
                if let status = status {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Image(systemName: status.contains("Success") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(status.contains("Success") ? .green : .red)
                                .padding(.top, 2)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text(status.replacingOccurrences(of: "Error: ", with: ""))
                                    .font(.callout)
                                    .fontWeight(status.contains("Success") ? .regular : .semibold)
                                    .foregroundColor(status.contains("Success") ? .primary : .red)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                if let details = details, !details.isEmpty {
                                    DisclosureGroup {
                                        Text(details)
                                            .font(.caption)
                                            .monospaced()
                                            .padding(8)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(6)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    } label: {
                                        Text("Technical Details")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity)
                }
                
                Spacer()
            }
        }
    }
}

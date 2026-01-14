//
//  SettingsView.swift
//  Sorty
//
//  Modern settings view with sidebar navigation and card-based sections
//

import SwiftUI

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable {
    case rules = "Organization Rules"
    case provider = "AI Provider"
    case strategy = "Organization Strategy"
    case tuning = "Parameter Tuning"
    case finder = "Finder Integration"
    case notifications = "Notifications"
    case advanced = "Advanced"
    case troubleshooting = "Troubleshooting"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .rules: return "folder.badge.gearshape"
        case .provider: return "cpu"
        case .strategy: return "wand.and.stars"
        case .tuning: return "slider.horizontal.3"
        case .finder: return "folder.badge.plus"
        case .notifications: return "bell"
        case .advanced: return "gearshape.2"
        case .troubleshooting: return "wrench.and.screwdriver"
        }
    }
    
    var color: Color {
        switch self {
        case .rules: return .blue
        case .provider: return .purple
        case .strategy: return .orange
        case .tuning: return .green
        case .finder: return .cyan
        case .notifications: return .pink
        case .advanced: return .gray
        case .troubleshooting: return .red
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var appState: AppState
    @StateObject private var healthManager = WorkspaceHealthManager()
    @StateObject private var notificationSettings = NotificationSettingsManager.shared
    @State private var showingHealthSettings = false
    @ObservedObject var copilotAuth = GitHubCopilotAuthManager.shared

    @State private var selectedCategory: SettingsCategory = .rules
    @State private var testConnectionStatus: String?
    @State private var testConnectionDetails: String?
    @State private var isTestingConnection = false
    @State private var showingAdvanced = false
    @State private var contentOpacity: Double = 0
    @State private var hasCopiedCode = false
    @State private var isQuickActionInstalled = ExtensionCommunication.isQuickActionInstalled()
    @State private var quickActionMessage: String?
    @State private var cacheSize: String = "Calculating..."
    @State private var showingResetConfirmation = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar - Fixed width to avoid HSplitView layout loops
            settingsSidebar
                .frame(width: 200)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    categoryHeader
                    
                    categoryContent
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .navigationTitle("Settings")
        .opacity(contentOpacity)
        .onAppear {
            // Async dispatch to avoid layout loop during view initialization
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    contentOpacity = 1.0
                }
            }
        }
        .sheet(isPresented: $showingHealthSettings) {
            WorkspaceHealthSettingsView(healthManager: healthManager)
        }
    }
    
    // MARK: - Sidebar
    
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsCategory.allCases) { category in
                SidebarButton(
                    title: category.rawValue,
                    icon: category.icon,
                    color: category.color,
                    isSelected: selectedCategory == category
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selectedCategory = category
                    }
                    HapticFeedbackManager.shared.selection()
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Category Header
    
    private var categoryHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedCategory.icon)
                .font(.title2)
                .foregroundStyle(selectedCategory.color)
                .frame(width: 32, height: 32)
                .background(selectedCategory.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(selectedCategory.rawValue)
                .font(.title2.bold())
            
            Spacer()
        }
        .padding(.bottom, 4)
    }
    
    // MARK: - Category Content
    
    @ViewBuilder
    private var categoryContent: some View {
        switch selectedCategory {
        case .rules:
            rulesSection
        case .provider:
            providerSection
        case .strategy:
            strategySection
        case .tuning:
            tuningSection
        case .finder:
            finderSection
        case .notifications:
            notificationsSection
        case .advanced:
            advancedSection
        case .troubleshooting:
            troubleshootingSection
        }
    }
    
    // MARK: - Rules Section
    
    private var rulesSection: some View {
        VStack(spacing: 16) {
            // Quick Navigation Cards
            SettingsNavigationCard(
                title: "Watched Folders",
                description: "Configure folders for automatic organization",
                icon: "eye",
                color: .blue
            ) {
                appState.currentView = .watchedFolders
            }
            .animatedAppearance(delay: 0.05)
            
            SettingsNavigationCard(
                title: "Exclusion Rules",
                description: "Define files and folders to skip during organization",
                icon: "eye.slash",
                color: .red
            ) {
                appState.currentView = .exclusions
            }
            .animatedAppearance(delay: 0.1)
            
            SettingsNavigationCard(
                title: "Storage Locations",
                description: "Add external destinations for files during organization",
                icon: "externaldrive",
                color: .purple
            ) {
                appState.currentView = .storageLocations
            }
            .animatedAppearance(delay: 0.15)
            
            SettingsNavigationCard(
                title: "Workspace Health Rules",
                description: "Set up health monitoring and cleanup policies",
                icon: "heart.text.square",
                color: .green
            ) {
                showingHealthSettings = true
            }
            .animatedAppearance(delay: 0.2)
            
            // Organization Style
            SettingsCard(title: "Organization Style", icon: "paintpalette", color: .purple) {
                PersonaPickerView()
            }
            .animatedAppearance(delay: 0.25)
        }
    }
    
    // MARK: - Provider Section
    
    private var providerSection: some View {
        VStack(spacing: 16) {
            // Provider Selection
            SettingsCard(title: "Select Provider", icon: "cpu", color: .purple) {
                VStack(spacing: 8) {
                    ForEach(Array(AIProvider.allCases), id: \.self) { provider in
                        AIProviderRow(
                            provider: provider,
                            isSelected: viewModel.config.provider == provider,
                            action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    viewModel.config.provider = provider
                                    if let defaultURL = provider.defaultAPIURL {
                                        viewModel.config.apiURL = defaultURL
                                    }
                                    viewModel.config.model = provider.defaultModel
                                    // Set default API key requirement based on provider. 
                                    // Note: Apple Foundation Model handles this via typicallyRequiresAPIKey (returning false).
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
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
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
                
                Text(viewModel.config.provider.apiKeyHelpText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                SettingsTextField(
                    title: "Model",
                    text: $viewModel.config.model,
                    placeholder: viewModel.config.provider.defaultModel
                )
            }
        }
    }
    
    private var connectionSection: some View {
        SettingsCard(title: "Connection", icon: "network", color: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                // Apple Foundation Model works strictly on-device and never requires an API key. 
                // Do not enable this for .appleFoundationModel to avoid confusing the user.
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
                                Text(status.replacingOccurrences(of: "Error: ", with: ""))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                if let details = testConnectionDetails, !details.isEmpty {
                                    DisclosureGroup {
                                        Text(details)
                                            .font(.system(.caption, design: .monospaced))
                                            .padding(6)
                                            .background(Color.secondary.opacity(0.1))
                                            .cornerRadius(4)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                    } label: {
                                        Text("Technical Details")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
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
    
    // MARK: - Strategy Section
    
    private var strategySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Folder Limits", icon: "folder.badge.questionmark", color: .purple) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Top-Level Folders")
                            .font(.subheadline)
                        Spacer()
                        Text("\(viewModel.config.maxTopLevelFolders)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .contentTransition(.numericText())
                    }
                    
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.config.maxTopLevelFolders) },
                            set: { viewModel.config.maxTopLevelFolders = Int($0) }
                        ),
                        in: 3...20,
                        step: 1
                    )
                    .onChange(of: viewModel.config.maxTopLevelFolders) { _, _ in
                        HapticFeedbackManager.shared.selection()
                    }
                    
                    HStack {
                        Text("Minimal (3)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Detailed (20)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Limits how many main folders the AI creates. Subfolders are not limited.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .animatedAppearance(delay: 0.05)
            
            SettingsCard(title: "Scanning Options", icon: "doc.text.magnifyingglass", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.enableDeepScan,
                        title: "Deep Scanning",
                        description: "Analyze file content (PDF text, EXIF data) for smarter organization"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $viewModel.config.detectDuplicates,
                        title: "Detect Duplicates",
                        description: "Find files with identical content using SHA-256 hashing"
                    )
                }
            }
            .animatedAppearance(delay: 0.1)
            
            SettingsCard(title: "File Tagging", icon: "tag", color: .orange) {
                SettingsToggle(
                    isOn: $viewModel.config.enableFileTagging,
                    title: "Enable File Tagging",
                    description: "Allow AI to suggest and apply Finder tags to files"
                )
            }
            .animatedAppearance(delay: 0.15)
        }
    }
    
    // MARK: - Tuning Section
    
    private var tuningSection: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "AI Temperature", icon: "thermometer.medium", color: .green) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .font(.subheadline)
                        Spacer()
                        Text("\(viewModel.config.temperature, specifier: "%.2f")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .contentTransition(.numericText())
                    }
                    
                    Slider(value: $viewModel.config.temperature, in: 0...1, step: 0.1)
                        .onChange(of: viewModel.config.temperature) { _, _ in
                            HapticFeedbackManager.shared.selection()
                        }
                    
                    HStack {
                        Text("Focused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Creative")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .animatedAppearance(delay: 0.05)
        }
    }
    
    // MARK: - Finder Integration Section
    
    private var finderSection: some View {
        VStack(spacing: 16) {
            // Quick Action
            SettingsCard(title: "Quick Action", icon: "cursorarrow.click.badge.clock", color: .cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: isQuickActionInstalled ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.title2)
                            .foregroundStyle(isQuickActionInstalled ? .green : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isQuickActionInstalled ? "Quick Action Installed" : "Quick Action Not Installed")
                                .font(.subheadline.weight(.medium))
                            Text("Right-click folders in Finder to organize with Sorty")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if isQuickActionInstalled {
                            Button("Uninstall") {
                                if ExtensionCommunication.uninstallQuickAction() {
                                    isQuickActionInstalled = false
                                    quickActionMessage = "Quick Action removed"
                                    HapticFeedbackManager.shared.success()
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Install") {
                                let result = ExtensionCommunication.installQuickAction()
                                isQuickActionInstalled = result.success
                                quickActionMessage = result.message
                                if result.success {
                                    HapticFeedbackManager.shared.success()
                                } else {
                                    HapticFeedbackManager.shared.error()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    if let message = quickActionMessage {
                        HStack(spacing: 6) {
                            Image(systemName: isQuickActionInstalled ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(isQuickActionInstalled ? .green : .orange)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animatedAppearance(delay: 0.05)
            
            // URL Scheme Info
            SettingsCard(title: "URL Scheme", icon: "link", color: .blue) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use URL schemes to trigger Sorty from scripts, Alfred, Raycast, or other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        URLSchemeRow(scheme: "sorty://organize?path=/path/to/folder", description: "Organize a folder")
                        URLSchemeRow(scheme: "sorty://duplicates?path=/path", description: "Find duplicates")
                        URLSchemeRow(scheme: "sorty://settings", description: "Open settings")
                    }
                }
            }
            .animatedAppearance(delay: 0.1)
            
            // Finder Extension (for signed builds)
            SettingsCard(title: "Finder Sync Extension", icon: "puzzlepiece.extension", color: .purple) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Requires code signing")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    
                    Text("The native Finder extension requires the app to be code-signed with an Apple Developer certificate. Use the Quick Action above for unsigned builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Extension Preferences") {
                        ExtensionCommunication.openFinderExtensionSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .animatedAppearance(delay: 0.15)
        }
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Streaming", icon: "waveform", color: .purple) {
                SettingsToggle(
                    isOn: $viewModel.config.enableStreaming,
                    title: "Enable Streaming",
                    description: "Stream AI responses for faster feedback"
                )
            }
            .animatedAppearance(delay: 0.05)
            
            SettingsCard(title: "Timeouts", icon: "clock", color: .orange) {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Request Timeout")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(viewModel.config.requestTimeout))s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.config.requestTimeout, in: 30...300, step: 10)
                        Text("Time to wait for initial response")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Resource Timeout")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(viewModel.config.resourceTimeout))s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.config.resourceTimeout, in: 60...1200, step: 60)
                        Text("Maximum total request duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .animatedAppearance(delay: 0.1)
            
            SettingsCard(title: "Token Limits", icon: "number", color: .blue) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Tokens")
                            .font(.subheadline)
                        Spacer()
                        TextField("Auto", value: $viewModel.config.maxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    Text("Leave empty for model default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .animatedAppearance(delay: 0.15)
            
            SettingsCard(title: "Developer", icon: "hammer", color: .gray) {
                VStack(spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.showStatsForNerds,
                        title: "Stats for Nerds",
                        description: "Show detailed generation metrics"
                    )
                    
                    Divider()
                    
                    Button {
                        if let logURL = LogManager.shared.exportLogs() {
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Debug Logs")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .animatedAppearance(delay: 0.2)
        }
    }
    
    // MARK: - Notifications Section
    
    private var notificationsSection: some View {
        VStack(spacing: 16) {
            // Permission Status
            NotificationPermissionCard()
                .animatedAppearance(delay: 0.0)
            
            // Delivery Method
            SettingsCard(title: "Delivery Method", icon: "bell.badge", color: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.inAppHUD,
                        title: "In-App HUD",
                        description: "Show notifications as subtle bottom-left overlays"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.systemNotifications,
                        title: "System Notifications",
                        description: "Show in macOS Notification Center"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.1)
            
            // Notification Types
            SettingsCard(title: "Notification Types", icon: "list.bullet", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.processingComplete,
                        title: "Processing Complete",
                        description: "When file processing finishes successfully"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.processingErrors,
                        title: "Processing Errors",
                        description: "When errors occur during processing"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.batchSummary,
                        title: "Batch Summary",
                        description: "Summary notification after processing multiple files"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.alwaysShowCriticalErrors,
                        title: "Always Show Critical Errors",
                        description: "Display critical errors even if notifications are off"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.15)
            
            // Sounds
            SettingsCard(title: "Sounds", icon: "speaker.wave.2", color: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.systemNotificationSounds,
                        title: "System Notification Sounds",
                        description: "Play sound with system notifications"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.hudSounds,
                        title: "HUD Sounds",
                        description: "Play sound with in-app HUD notifications"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.2)
            
            // Test Notifications
            SettingsCard(title: "Test", icon: "bell.and.waves.left.and.right", color: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send a test notification to verify your settings are working correctly.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button {
                            NotificationManager.shared.showInfo(title: "Test Notification", message: "Your notifications are working correctly!")
                            HapticFeedbackManager.shared.success()
                        } label: {
                            HStack {
                                Image(systemName: "bell")
                                Text("Send Test")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.25)
        }
    }
    
    // MARK: - Troubleshooting Section
    
    private var troubleshootingSection: some View {
        VStack(spacing: 16) {
            // Cache
            SettingsCard(title: "Cache", icon: "internaldrive", color: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Cache Size")
                            .font(.subheadline)
                        Spacer()
                        Text(cacheSize)
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        clearCache()
                        HapticFeedbackManager.shared.success()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
            .animatedAppearance(delay: 0.05)
            .onAppear {
                calculateCacheSize()
            }
            
            // Reset Settings
            SettingsCard(title: "Reset", icon: "arrow.counterclockwise", color: .red) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reset all preferences to default values. This cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Settings")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .animatedAppearance(delay: 0.1)
            .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetAllSettings()
                }
            } message: {
                Text("This will reset all preferences to their default values. This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func calculateCacheSize() {
        Task {
            let size = await getCacheSizeAsync()
            await MainActor.run {
                cacheSize = formatBytes(size)
            }
        }
    }
    
    private func getCacheSizeAsync() async -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        
        // App caches directory
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            totalSize += directorySize(at: cachesURL)
        }
        
        // App support directory for temporary files
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let sortyCache = appSupportURL.appendingPathComponent("Sorty/Cache")
            if fileManager.fileExists(atPath: sortyCache.path) {
                totalSize += directorySize(at: sortyCache)
            }
        }
        
        // Temporary directory
        let tempURL = fileManager.temporaryDirectory
        totalSize += directorySize(at: tempURL)
        
        return totalSize
    }
    
    private func directorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var size: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if resourceValues.isDirectory == false {
                    size += Int64(resourceValues.fileSize ?? 0)
                }
            } catch {
                // Skip files we can't access
            }
        }
        
        return size
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func clearCache() {
        let fileManager = FileManager.default
        
        // Clear caches directory
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: cachesURL)
            try? fileManager.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        }
        
        // Clear Sorty cache in app support
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let sortyCache = appSupportURL.appendingPathComponent("Sorty/Cache")
            try? fileManager.removeItem(at: sortyCache)
        }
        
        // Recalculate size
        calculateCacheSize()
    }
    
    private func resetAllSettings() {
        // Reset AI config
        viewModel.config = .default
        
        // Reset notification settings
        notificationSettings.reset()
        
        // Clear user defaults for other settings
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier ?? ""
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        
        // Reload settings
        HapticFeedbackManager.shared.success()
    }

    private func testConnection() {
        HapticFeedbackManager.shared.tap()
        isTestingConnection = true
        testConnectionStatus = nil
        testConnectionDetails = nil

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
}

// MARK: - Supporting Components

struct SidebarButton: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? color : .secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? color.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct SettingsNavigationCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.tap()
            action()
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                content
            }
        }
    }
}

struct SettingsTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsSecureField: View {
    let title: String
    @Binding var text: String
    var isOptional: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                if isOptional {
                    Text("Optional")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            SecureField("", text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct SettingsToggle: View {
    @Binding var isOn: Bool
    let title: String
    var description: String? = nil
    
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .toggleStyle(.switch)
        .onChange(of: isOn) { _, _ in
            HapticFeedbackManager.shared.selection()
        }
    }
}

// MARK: - URL Scheme Row

struct URLSchemeRow: View {
    let scheme: String
    let description: String
    @State private var copied = false
    
    var body: some View {
        HStack(spacing: 8) {
            Text(scheme)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
            
            Spacer()
            
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(scheme, forType: .string)
                HapticFeedbackManager.shared.tap()
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Animated Toggle (Legacy Support)

struct AnimatedToggle<Label: View>: View {
    @Binding var isOn: Bool
    var id: String? = nil
    let label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
        }
        .onChange(of: isOn) { _, _ in
            HapticFeedbackManager.shared.selection()
        }
        .applyIdentifier(id)
        .contentShape(Rectangle())
    }
}

extension View {
    @ViewBuilder
    func applyIdentifier(_ id: String?) -> some View {
        if let id = id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }
}

// MARK: - Notification Permission Card

struct NotificationPermissionCard: View {
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var isRequestingPermission = false
    
    private var statusInfo: (icon: String, color: Color, title: String, description: String) {
        switch notificationManager.notificationPermissionStatus {
        case .authorized:
            return ("checkmark.circle.fill", .green, "Authorized", "System notifications are enabled")
        case .denied:
            return ("xmark.circle.fill", .red, "Denied", "Open System Settings to enable notifications")
        case .provisional:
            return ("bell.badge.circle.fill", .orange, "Provisional", "Notifications delivered quietly")
        case .ephemeral:
            return ("clock.circle.fill", .blue, "Temporary", "App Clip temporary permission")
        case .notDetermined:
            return ("questionmark.circle.fill", .secondary, "Not Set", "Request permission to enable system notifications")
        @unknown default:
            return ("questionmark.circle.fill", .secondary, "Unknown", "Unable to determine permission status")
        }
    }
    
    var body: some View {
        SettingsCard(title: "System Notification Permission", icon: "bell.badge.circle", color: .cyan) {
            VStack(alignment: .leading, spacing: 12) {
                // Status indicator
                HStack(spacing: 12) {
                    Image(systemName: statusInfo.icon)
                        .font(.title2)
                        .foregroundStyle(statusInfo.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusInfo.title)
                            .font(.subheadline.weight(.medium))
                        Text(statusInfo.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Action button based on status
                    switch notificationManager.notificationPermissionStatus {
                    case .notDetermined:
                        Button {
                            requestPermission()
                        } label: {
                            HStack(spacing: 4) {
                                if isRequestingPermission {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "bell.badge")
                                }
                                Text("Enable")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRequestingPermission)
                        
                    case .denied:
                        Button {
                            openSystemSettings()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                        }
                        .buttonStyle(.bordered)
                        
                    case .authorized, .provisional:
                        Button {
                            Task {
                                await notificationManager.checkNotificationPermission()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Refresh permission status")
                        
                    default:
                        EmptyView()
                    }
                }
                
                // Note about HUD notifications
                if notificationManager.notificationPermissionStatus != .authorized {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("In-app HUD notifications work regardless of this setting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            Task {
                await notificationManager.checkNotificationPermission()
            }
        }
    }
    
    private func requestPermission() {
        isRequestingPermission = true
        Task {
            _ = await notificationManager.requestPermission()
            await MainActor.run {
                isRequestingPermission = false
                HapticFeedbackManager.shared.success()
            }
        }
    }
    
    private func openSystemSettings() {
        // Open System Settings > Notifications
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PersonaManager())
        .environmentObject(AppState())
        .frame(width: 700, height: 600)
}

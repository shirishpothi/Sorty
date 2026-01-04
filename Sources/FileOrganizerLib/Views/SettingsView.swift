//
//  SettingsView.swift
//  FileOrganizer
//
//  API configuration view with advanced settings
//  Enhanced with haptic feedback and micro-animations
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var personaManager: PersonaManager // Access persona manager
    @EnvironmentObject var appState: AppState
    @State private var healthManager = WorkspaceHealthManager()
    @State private var showingHealthSettings = false

    @State private var testConnectionStatus: String?
    @State private var isTestingConnection = false
    @State private var showingAdvanced = false
    @State private var contentOpacity: Double = 0
    @State private var sectionAppeared: [Int: Bool] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Main content
                    Form {
                        // Quick Navigation
                        Section {
                            Button {
                                appState.currentView = .watchedFolders
                            } label: {
                                Label {
                                    HStack {
                                        Text("Watched Folders")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "eye")
                                        .foregroundColor(.blue)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                appState.currentView = .exclusions
                            } label: {
                                Label {
                                    HStack {
                                        Text("Exclusion Rules")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "eye.slash")
                                        .foregroundColor(.red)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                showingHealthSettings = true
                            } label: {
                                Label {
                                    HStack {
                                        Text("Workspace Health Rules")
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "heart.text.square")
                                        .foregroundColor(.green)
                                }
                            }
                            .buttonStyle(.plain)
                        } header: {
                            Text("Organization Rules")
                        }
                        .animatedAppearance(delay: 0.05)

                        // Organization Style / Personas Section
                        Section {
                            PersonaPickerView()
                        } header: {
                            Text("Organization Style")
                        }
                        .animatedAppearance(delay: 0.1)

                        // AI Provider Section
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(AIProvider.allCases), id: \.self) { provider in
                                    HStack {
                                        // Radio Button Icon
                                        Image(systemName: viewModel.config.provider == provider ? "largecircle.fill.circle" : "circle")
                                            .foregroundColor(viewModel.config.provider == provider ? .accentColor : .secondary)
                                            .font(.system(size: 16))

                                        // Label
                                        Text(provider.displayName)
                                            .foregroundColor(.primary)

                                        Spacer()

                                        // Availability Badge
                                        if !provider.isAvailable {
                                            Label("Unavailable", systemImage: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        }
                                    }
                                    .contentShape(Rectangle()) // Make the whole row clickable
                                    .onTapGesture {
                                        if provider.isAvailable {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                viewModel.config.provider = provider
                                                HapticFeedbackManager.shared.selection()
                                            }
                                        }
                                    }
                                    .opacity(provider.isAvailable ? 1.0 : 0.6)
                                }
                            }
                            .padding(.vertical, 4)

                            if !viewModel.config.provider.isAvailable,
                               let reason = viewModel.config.provider.unavailabilityReason {
                                Label(reason, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .padding(.vertical, 4)
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        } header: {
                            Text("AI Provider")
                        }
                        .animatedAppearance(delay: 0.05)

                        // API Configuration (for OpenAI)
                        if viewModel.config.provider == .openAICompatible {
                            Section {
                                TextField("API URL", text: Binding(
                                    get: { viewModel.config.apiURL ?? "https://api.openai.com" },
                                    set: { viewModel.config.apiURL = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("API URL")
                                .accessibilityIdentifier("ApiUrlTextField")

                                HStack {
                                    SecureField("API Key", text: Binding(
                                        get: { viewModel.config.apiKey ?? "" },
                                        set: { viewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("API Key")
                                    .accessibilityIdentifier("ApiKeyTextField")

                                    if !viewModel.config.requiresAPIKey {
                                        Text("Optional")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                TextField("Model", text: $viewModel.config.model)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Model Name")
                                    .accessibilityIdentifier("ModelTextField")
                            } header: {
                                Text("API Configuration")
                            }
                            .transition(TransitionStyles.scaleAndFade)
                            .animatedAppearance(delay: 0.1)

                            // Separate Connection section for OpenAI Compatible
                            Section {
                                VStack(spacing: 12) {
                                    // Requires API Key toggle
                                    AnimatedToggle(isOn: $viewModel.config.requiresAPIKey) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Requires API Key")
                                            Text("Disable for local endpoints that don't require authentication")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .accessibilityLabel("API Key requirement")
                                    .padding(.vertical, 4)

                                    HStack(spacing: 12) {
                                        Button(action: testConnection) {
                                            HStack(spacing: 8) {
                                                if isTestingConnection {
                                                    BouncingSpinner(size: 14, color: .primary)
                                                } else {
                                                    Image(systemName: "network")
                                                        .font(.system(size: 14, weight: .semibold))
                                                }

                                                Text("Test Connection")
                                                    .font(.system(size: 14, weight: .medium))
                                            }
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(.ultraThinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(HapticBounceButtonStyle())
                                        .disabled(isTestingConnection || !viewModel.config.provider.isAvailable)
                                        .opacity(viewModel.config.provider.isAvailable ? 1.0 : 0.5)
                                        .accessibilityIdentifier("OpenAITestConnectionButton")

                                        if let status = testConnectionStatus {
                                            Label(
                                                status.contains("Success") ? "Connected" : "Failed",
                                                systemImage: status.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill"
                                            )
                                            .foregroundColor(status.contains("Success") ? .green : .red)
                                            .font(.caption)
                                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )

                                if let status = testConnectionStatus, !status.contains("Success") {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } header: {
                                Text("Connection")
                            }
                            .transition(TransitionStyles.scaleAndFade)
                            .animatedAppearance(delay: 0.15)
                            .animation(.easeInOut(duration: 0.2), value: testConnectionStatus)
                        }

                        // Ollama Configuration
                        if viewModel.config.provider == .ollama {
                            Section {
                                TextField("Server URL", text: Binding(
                                    get: { viewModel.config.apiURL ?? "http://localhost:11434" },
                                    set: { viewModel.config.apiURL = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Ollama Server URL")
                                
                                HStack {
                                    SecureField("API Key (Optional)", text: Binding(
                                        get: { viewModel.config.apiKey ?? "" },
                                        set: { viewModel.config.apiKey = $0.isEmpty ? nil : $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Ollama API Key")
                                    
                                    if !viewModel.config.requiresAPIKey {
                                        Text("Optional")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                TextField("Model", text: $viewModel.config.model)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Ollama Model Name")

                                Text("Ensure Ollama is running locally and the model is downloaded.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } header: {
                                Text("Ollama Local Configuration")
                            }
                            .transition(TransitionStyles.scaleAndFade)
                            .animatedAppearance(delay: 0.1)
                            .onAppear {
                                if viewModel.config.apiURL == nil {
                                    viewModel.config.apiURL = "http://localhost:11434"
                                }
                                if viewModel.config.model == "gpt-4" {
                                    viewModel.config.model = "llama3"
                                }
                            }
                            
                            // Separate Connection section for Ollama
                            Section {
                                VStack(spacing: 12) {
                                    AnimatedToggle(isOn: $viewModel.config.requiresAPIKey) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Requires API Key")
                                            Text("Enable if your Ollama instance requires authentication")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .accessibilityLabel("API Key requirement")
                                    .padding(.vertical, 4)
                                    
                                    HStack(spacing: 12) {
                                        Button(action: testConnection) {
                                            HStack(spacing: 8) {
                                                if isTestingConnection {
                                                    BouncingSpinner(size: 14, color: .primary)
                                                } else {
                                                    Image(systemName: "network")
                                                        .font(.system(size: 14, weight: .semibold))
                                                }
                                                
                                                Text("Test Connection")
                                                    .font(.system(size: 14, weight: .medium))
                                            }
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(.ultraThinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(HapticBounceButtonStyle())
                                        .disabled(isTestingConnection)
                                        .accessibilityIdentifier("OllamaTestConnectionButton")
                                        
                                        if let status = testConnectionStatus {
                                            Label(
                                                status.contains("Success") ? "Connected" : "Failed",
                                                systemImage: status.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill"
                                            )
                                            .foregroundColor(status.contains("Success") ? .green : .red)
                                            .font(.caption)
                                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                
                                if let status = testConnectionStatus, !status.contains("Success") {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } header: {
                                Text("Connection")
                            }
                            .transition(TransitionStyles.scaleAndFade)
                            .animatedAppearance(delay: 0.15)
                            .animation(.easeInOut(duration: 0.2), value: testConnectionStatus)
                        }
                        
                        // Apple Foundation Model Connection Test
                        if viewModel.config.provider == .appleFoundationModel {
                            Section {
                                VStack(spacing: 12) {
                                    if viewModel.config.provider.isAvailable {
                                        Text("Apple Intelligence is available on this device.")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Apple Intelligence requires macOS 26.0+ and compatible hardware.")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    HStack(spacing: 12) {
                                        Button(action: testConnection) {
                                            HStack(spacing: 8) {
                                                if isTestingConnection {
                                                    BouncingSpinner(size: 14, color: .primary)
                                                } else {
                                                    Image(systemName: "brain")
                                                        .font(.system(size: 14, weight: .semibold))
                                                }
                                                
                                                Text("Test Connection")
                                                    .font(.system(size: 14, weight: .medium))
                                            }
                                            .foregroundColor(.primary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(.ultraThinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(HapticBounceButtonStyle())
                                        .disabled(isTestingConnection || !viewModel.config.provider.isAvailable)
                                        .opacity(viewModel.config.provider.isAvailable ? 1.0 : 0.5)
                                        .accessibilityIdentifier("AppleFMTestConnectionButton")
                                        
                                        if let status = testConnectionStatus {
                                            Label(
                                                status.contains("Success") ? "Connected" : "Failed",
                                                systemImage: status.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill"
                                            )
                                            .foregroundColor(status.contains("Success") ? .green : .red)
                                            .font(.caption)
                                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                
                                if let status = testConnectionStatus, !status.contains("Success") {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } header: {
                                Text("Connection")
                            }
                            .transition(TransitionStyles.scaleAndFade)
                            .animatedAppearance(delay: 0.1)
                            .animation(.easeInOut(duration: 0.2), value: testConnectionStatus)
                        }

                        // Organization Strategy
                        Section {
                            AnimatedToggle(isOn: $viewModel.config.enableReasoning) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Include Reasoning")
                                    Text("AI will explain its organization choices. This will take significantly more time and tokens.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("ReasoningToggle")

                            AnimatedToggle(isOn: $viewModel.config.enableDeepScan) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Deep Scanning")
                                    Text("Analyze file content (PDF text, EXIF data for photos, etc.) for smarter organization.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("DeepScanToggle")

                            AnimatedToggle(isOn: $viewModel.config.detectDuplicates) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Detect Duplicates")
                                    Text("Find files with identical content using SHA-256 hashing. May slow down large scans.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("DuplicatesToggle")

                            AnimatedToggle(isOn: $viewModel.config.enableFileTagging) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Enable File Tagging")
                                    Text("Allow AI to suggest and apply Finder tags (e.g., 'Invoice', 'Personal') to files.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("FileTaggingToggle")
                        } header: {
                            Text("Organization Strategy")
                        }
                        .animatedAppearance(delay: 0.15)

                        // AI Settings
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Temperature")
                                    Spacer()
                                    Text("\(viewModel.config.temperature, specifier: "%.2f")")
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                }
                                Slider(value: $viewModel.config.temperature, in: 0...1, step: 0.1)
                                    .accessibilityLabel("Temperature")
                                    .accessibilityIdentifier("TemperatureSlider")
                                    .onChange(of: viewModel.config.temperature) { oldValue, newValue in
                                        HapticFeedbackManager.shared.selection()
                                    }
                                Text("Lower values = more focused, higher = more creative")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } header: {
                            Text("Parameter Tuning")
                        }
                        .animatedAppearance(delay: 0.2)



                        // Advanced Settings (Collapsible)
                        Section {
                            DisclosureGroup("Advanced Settings", isExpanded: $showingAdvanced) {
                                VStack(alignment: .leading, spacing: 16) {
                                    // Streaming toggle
                                    AnimatedToggle(isOn: $viewModel.config.enableStreaming) {
                                        Text("Enable Streaming")
                                    }
                                    .accessibilityLabel("Enable response streaming")



                                    // Timeout settings parameters...
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Request Timeout")
                                            Spacer()
                                            Text("\(Int(viewModel.config.requestTimeout))s")
                                                .foregroundColor(.secondary)
                                                .monospacedDigit()
                                                .contentTransition(.numericText())
                                        }
                                        Slider(value: $viewModel.config.requestTimeout, in: 30...300, step: 10)
                                            .onChange(of: viewModel.config.requestTimeout) { oldValue, newValue in
                                                HapticFeedbackManager.shared.selection()
                                            }
                                        Text("Time to wait for initial response")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Resource Timeout")
                                            Spacer()
                                            Text("\(Int(viewModel.config.resourceTimeout))s")
                                                .foregroundColor(.secondary)
                                                .monospacedDigit()
                                                .contentTransition(.numericText())
                                        }
                                        Slider(value: $viewModel.config.resourceTimeout, in: 60...1200, step: 60)
                                            .onChange(of: viewModel.config.resourceTimeout) { oldValue, newValue in
                                                HapticFeedbackManager.shared.selection()
                                            }
                                        Text("Maximum total request duration")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Divider()

                                    // Max tokens
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Max Tokens")
                                            Spacer()
                                            TextField("Auto", value: $viewModel.config.maxTokens, format: .number)
                                                .textFieldStyle(.roundedBorder)
                                                .frame(width: 100)
                                        }
                                        Text("Leave empty for model default")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Divider()

                                    AnimatedToggle(isOn: $viewModel.config.showStatsForNerds) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Stats for Nerds")
                                            Text("Show detailed generation metrics (tokens/sec, time to first token)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .onChange(of: showingAdvanced) { oldValue, newValue in
                                HapticFeedbackManager.shared.tap()
                            }
                        }
                        .animatedAppearance(delay: 0.3)
                        .animation(.easeInOut(duration: 0.25), value: showingAdvanced)

                    }
                    .formStyle(.grouped)
                }
                .padding()
            }
            .navigationTitle("Settings")
            .opacity(contentOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    contentOpacity = 1.0
                }
            }
        }
        .sheet(isPresented: $showingHealthSettings) {
            WorkspaceHealthSettingsView(healthManager: healthManager)
        }
    }

    private func testConnection() {
        HapticFeedbackManager.shared.tap()
        isTestingConnection = true
        testConnectionStatus = nil

        Task {
            do {
                try await viewModel.testConnection()
                HapticFeedbackManager.shared.success()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    testConnectionStatus = "Success: Connection test passed"
                }
            } catch {
                HapticFeedbackManager.shared.error()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    testConnectionStatus = "Error: \(error.localizedDescription)"
                }
            }
            isTestingConnection = false
        }
    }
}

// MARK: - Animated Toggle

struct AnimatedToggle<Label: View>: View {
    @Binding var isOn: Bool
    let label: () -> Label

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
        }
        .onChange(of: isOn) { oldValue, newValue in
            HapticFeedbackManager.shared.selection()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PersonaManager())
        .frame(width: 600, height: 800)
}

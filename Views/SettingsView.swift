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
                        // AI Provider Section
                        Section {
                            Picker("Provider", selection: $viewModel.config.provider) {
                                ForEach(Array(AIProvider.allCases), id: \.self) { provider in
                                    HStack {
                                        Text(provider.displayName)
                                        Spacer()
                                        if !provider.isAvailable {
                                            Label("Unavailable", systemImage: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        }
                                    }
                                    .tag(provider)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .accessibilityLabel("AI Provider Selection")
                            .onChange(of: viewModel.config.provider) { oldValue, newValue in
                                HapticFeedbackManager.shared.selection()
                            }

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
                                viewModel.config.requiresAPIKey = false
                            }
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
                            .accessibilityIdentifier("DuplicatesToggle")
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

                        // Test Connection
                        Section {
                            HStack(spacing: 12) {
                                Button(action: testConnection) {
                                    HStack {
                                        if isTestingConnection {
                                            BouncingSpinner(size: 16, color: .accentColor)
                                        }
                                        Text("Test Connection")
                                    }
                                }
                                .buttonStyle(.hapticBounce)
                                .disabled(isTestingConnection || !viewModel.config.provider.isAvailable)
                                .accessibilityIdentifier("TestConnectionButton")

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

                            if let status = testConnectionStatus, !status.contains("Success") {
                                Text(status)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animatedAppearance(delay: 0.25)
                        .animatedAppearance(delay: 0.25) // Keeping appearance animation but making it subtle in AnimatedModifier if needed
                        .animation(.easeInOut(duration: 0.2), value: testConnectionStatus)

                        // Advanced Settings (Collapsible)
                        Section {
                            DisclosureGroup("Advanced Settings", isExpanded: $showingAdvanced) {
                                VStack(alignment: .leading, spacing: 16) {
                                    Divider()

                                    // Persona Picker (Moved here)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Default Organization Persona")
                                            .font(.headline)
                                        CompactPersonaPicker()
                                    }
                                    .padding(.vertical, 4)
                                    .transition(.opacity.combined(with: .move(edge: .top)))

                                    Divider()

                                    // Streaming toggle
                                    AnimatedToggle(isOn: $viewModel.config.enableStreaming) {
                                        Text("Enable Streaming")
                                    }
                                    .accessibilityLabel("Enable response streaming")

                                    // API Key Required toggle
                                    AnimatedToggle(isOn: $viewModel.config.requiresAPIKey) {
                                        Text("Requires API Key")
                                    }
                                    .accessibilityLabel("API Key requirement")
                                    Text("Disable for local endpoints that don't require authentication")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Divider()

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

                                    // System prompt override (Per Persona)
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("Custom System Prompt")
                                            Spacer()

                                            if let _ = personaManager.customPrompts[personaManager.selectedPersona] {
                                                Button("Reset to Default") {
                                                    HapticFeedbackManager.shared.tap()
                                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                        personaManager.resetCustomPrompt(for: personaManager.selectedPersona)
                                                    }
                                                }
                                                .font(.caption)
                                                .buttonStyle(.borderless)
                                                .foregroundColor(.red)
                                                .bounceTap(scale: 0.95)
                                            }
                                        }

                                        Text(" customizing for: \(personaManager.selectedPersona.displayName)")
                                            .font(.caption)
                                            .foregroundColor(.purple)

                                        TextEditor(text: Binding(
                                            get: { personaManager.getPrompt(for: personaManager.selectedPersona) },
                                            set: { newValue in
                                                personaManager.saveCustomPrompt(for: personaManager.selectedPersona, prompt: newValue)
                                            }
                                        ))
                                        .font(.system(.body, design: .monospaced))
                                        .frame(height: 150)
                                        .border(Color.secondary.opacity(0.3), width: 1)

                                        Text("Customize how the AI behaves for the selected persona.")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .onChange(of: showingAdvanced) { oldValue, newValue in
                                HapticFeedbackManager.shared.tap()
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
                        .animatedAppearance(delay: 0.3)
                        .animation(.easeInOut(duration: 0.25), value: showingAdvanced)

                        // Watched Folders (Smart Automations)
                        Section {
                            NavigationLink {
                                WatchedFoldersView()
                            } label: {
                                HStack {
                                    Label("Watched Folders", systemImage: "eye")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .bounceTap(scale: 0.98)

                            Text("Automatically organize folders like Downloads when new files arrive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } header: {
                            Text("Smart Automations")
                        }
                        .animatedAppearance(delay: 0.35)

                        // Exclusion Rules
                        Section {
                            NavigationLink {
                                ExclusionRulesView()
                            } label: {
                                HStack {
                                    Label("Exclusion Rules", systemImage: "eye.slash")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .bounceTap(scale: 0.98)
                        }
                        .animatedAppearance(delay: 0.4)
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

    @State private var toggleScale: CGFloat = 1.0

    var body: some View {
        Toggle(isOn: $isOn) {
            label()
        }
        .scaleEffect(toggleScale)
        .onChange(of: isOn) { oldValue, newValue in
            HapticFeedbackManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.15)) {
                toggleScale = 1.05
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    toggleScale = 1.0
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(PersonaManager())
        .frame(width: 600, height: 800)
}

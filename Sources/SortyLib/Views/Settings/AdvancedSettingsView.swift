//
//  AdvancedSettingsView.swift
//  Sorty
//
//  Advanced settings section
//

import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var automationManager: AutomationManager
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("privacyModeEnabled") private var privacyModeEnabled = true
    @AppStorage(NetworkPrivacyPolicy.internetPrivacyModeKey) private var internetPrivacyModeEnabled = false
    @AppStorage("experimentalStreamingInsightsEnabled") private var experimentalStreamingInsightsEnabled = false
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Menu Bar", icon: "menubar.rectangle", color: .blue) {
                SettingsToggle(
                    isOn: $showMenuBarExtra,
                    title: "Show Menu Bar Icon",
                    description: "Display Sorty icon in the menu bar for quick access"
                )
            }
            .animatedAppearance(delay: 0.0)

            SettingsCard(title: "Finder Workflow", icon: "folder.badge.gearshape", color: .mint) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggle(
                        isOn: $automationManager.autoSelectOrganizedFolders,
                        title: "Automatically reveal organized folders",
                        description: "Open Finder and highlight newly organized folders after each completed run"
                    )
                    .accessibilityIdentifier("FinderAutoRevealToggle")

                    if !automationManager.autoSelectOrganizedFolders {
                        Text("Recommended for most users: keep this off and use \"View in Finder\" when needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .animatedAppearance(delay: 0.03)

            SettingsCard(title: "Privacy", icon: "lock.shield", color: .green) {
                VStack(spacing: 12) {
                    SettingsToggle(
                        isOn: $privacyModeEnabled,
                        title: "Privacy Mode",
                        description: "Mask usernames, paths, API keys, and raw AI details in the interface"
                    )
                    .accessibilityIdentifier("PrivacyModeToggle")

                    Divider()

                    SettingsToggle(
                        isOn: $internetPrivacyModeEnabled,
                        title: "Block Internet Connections",
                        description: "Allow only localhost requests for local models and offline workflows"
                    )
                    .accessibilityIdentifier("InternetPrivacyModeToggle")
                }
            }
            .animatedAppearance(delay: 0.04)
            
            if experimentalStreamingInsightsEnabled {
                SettingsCard(title: "Streaming", icon: "waveform", color: .purple) {
                    SettingsToggle(
                        isOn: $viewModel.config.enableStreaming,
                        title: "Enable Streaming",
                        description: "Stream AI responses for faster feedback"
                    )
                }
                .animatedAppearance(delay: 0.05)
            }
            
            SettingsCard(title: "Timeouts", icon: "clock", color: .orange) {
                VStack(spacing: 16) {
                    TimeoutSliderRow(
                        title: "Request Timeout",
                        description: "Time to wait for initial response",
                        value: $viewModel.config.requestTimeout,
                        sliderMin: 30,
                        defaultMax: 600,
                        step: 10
                    )
                    
                    Divider()
                    
                    TimeoutSliderRow(
                        title: "Resource Timeout",
                        description: "Maximum total request duration",
                        value: $viewModel.config.resourceTimeout,
                        sliderMin: 60,
                        defaultMax: 1800,
                        step: 60
                    )
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
                            Text("Show Error Logs")
                        }
                    }
                    .buttonStyle(.sortyBordered)
                }
            }
            .animatedAppearance(delay: 0.2)
        }
    }
}

// MARK: - Timeout Slider with Editable Maximum

private struct TimeoutSliderRow: View {
    let title: String
    let description: String
    @Binding var value: TimeInterval
    let sliderMin: Double
    let defaultMax: Double
    let step: Double
    
    @State private var editingMax = false
    @State private var maxText = ""
    @State private var customMax: Double?
    @FocusState private var maxFieldFocused: Bool
    
    private var effectiveMax: Double {
        if let customMax, customMax > sliderMin { return customMax }
        return max(defaultMax, value)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(value))s")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 8) {
                Slider(value: $value, in: sliderMin...effectiveMax, step: step)
                
                if editingMax {
                    TextField("Max", text: $maxText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .font(.subheadline.monospacedDigit())
                        .focused($maxFieldFocused)
                        .onSubmit { commitMax() }
                        .onAppear {
                            maxText = "\(Int(effectiveMax))"
                            maxFieldFocused = true
                        }
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            editingMax = true
                        }
                    } label: {
                        Text("\(Int(effectiveMax))s")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Click to set custom maximum")
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                            HapticFeedbackManager.shared.selection()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func commitMax() {
        if let parsed = Double(maxText), parsed >= sliderMin {
            let rounded = (parsed / step).rounded() * step
            withAnimation(.easeInOut(duration: 0.15)) {
                customMax = rounded
                if value > rounded { value = rounded }
            }
            HapticFeedbackManager.shared.success()
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            editingMax = false
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AutomationManager())
        .frame(width: 500, height: 500)
}

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
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Menu Bar", icon: "menubar.rectangle", color: .blue) {
                SettingsToggle(
                    isOn: $showMenuBarExtra,
                    title: "Show Menu Bar Icon",
                    description: "Display Sorty icon in the menu bar for quick access",
                    focusTarget: .advancedMenuBar
                )
            }
            .animatedAppearance(delay: 0.0)

            SettingsCard(title: "Finder Workflow", icon: "folder.badge.gearshape", color: .mint) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggle(
                        isOn: $automationManager.autoSelectOrganizedFolders,
                        title: "Automatically reveal organized folders",
                        description: "Open Finder and highlight newly organized folders after each completed run",
                        focusTarget: .advancedFinderWorkflow
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
                        description: "Mask usernames, paths, API keys, and raw AI details in the interface",
                        focusTarget: .advancedPrivacyMode
                    )
                    .accessibilityIdentifier("PrivacyModeToggle")

                    PrivacyTogglePreview(isEnabled: privacyModeEnabled)

                    Divider()

                    SettingsToggle(
                        isOn: $internetPrivacyModeEnabled,
                        title: "Block Internet Connections",
                        description: "Allow only localhost requests for local models and offline workflows",
                        focusTarget: .advancedInternetPrivacy
                    )
                    .accessibilityIdentifier("InternetPrivacyModeToggle")

                    InternetPrivacyPreview(isEnabled: internetPrivacyModeEnabled)
                }
            }
            .animatedAppearance(delay: 0.04)
            
            SettingsCard(title: "Timeouts", icon: "clock", color: .orange) {
                VStack(spacing: 16) {
                    TimeoutSliderRow(
                        title: "Request Timeout",
                        description: "Time to wait for initial response",
                        value: $viewModel.config.requestTimeout,
                        sliderMin: 30,
                        defaultMax: 600,
                        step: 10,
                        personaPreview: AnyView(
                            TimeoutPersonaPreview(value: viewModel.config.requestTimeout, isRequest: true)
                        )
                    )

                    Divider()

                    TimeoutSliderRow(
                        title: "Resource Timeout",
                        description: "Maximum total request duration",
                        value: $viewModel.config.resourceTimeout,
                        sliderMin: 60,
                        defaultMax: 1800,
                        step: 60,
                        personaPreview: AnyView(
                            TimeoutPersonaPreview(value: viewModel.config.resourceTimeout, isRequest: false)
                        )
                    )
                }
            }
            .settingsFocusable(.advancedTimeouts)
            .animatedAppearance(delay: 0.1)
            
            SettingsCard(title: "Developer", icon: "hammer", color: .gray) {
                VStack(spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.showStatsForNerds,
                        title: "Stats for Nerds",
                        description: "Show detailed generation metrics"
                    )
                    
                    Divider()
                    
                    Button {
                        HapticFeedbackManager.shared.tap()
                        if let logURL = LogManager.shared.exportLogs() {
                            HapticFeedbackManager.shared.success()
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        } else {
                            HapticFeedbackManager.shared.error()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "hammer")
                            Text("Show Error Logs")
                        }
                    }
                    .buttonStyle(.sortyProminent(intent: .destructive))
                    .accessibilityIdentifier("ShowErrorLogsButton")
                    .onHover { hovering in
                        if hovering {
                            HapticFeedbackManager.shared.selection()
                        }
                    }
                }
            }
            .settingsFocusable(.advancedDeveloper)
            .animatedAppearance(delay: 0.15)
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
    var personaPreview: AnyView? = nil

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
                    .contentTransition(.numericText(value: value))
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: value)
            }
            
            HStack(spacing: 8) {
                NoTickSlider(value: $value, in: sliderMin...effectiveMax, step: step)
                
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

            if let personaPreview {
                personaPreview
            }
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

//
//  AutomationSettingsView.swift
//  Sorty
//
//  Settings for automation and watched folder AI configuration
//

import SwiftUI

struct AutomationSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager

    @AppStorage("keepInBackground") private var keepInBackground = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    @State private var useSeparateModel = false
    @State private var selectedProvider: AIProvider = .openAI
    @State private var selectedModel: String = ""
    @State private var showModelPicker = false
    @State private var showBackgroundInfo = false
    
    var body: some View {
        VStack(spacing: 16) {
            globalModelSection
                .animatedAppearance(delay: 0.05)

            backgroundBehaviorSection
                .animatedAppearance(delay: 0.1)
        }
        .onAppear {
            loadAutomationSettings()
        }
    }
    
    private var globalModelSection: some View {
        SettingsCard(title: "Global Automation Model", icon: "cpu.fill", color: .green) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $useSeparateModel) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use separate model for automation")
                            .font(.subheadline)
                        Text("Run background tasks with a different AI model")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: useSeparateModel) { _, newValue in
                    if !newValue {
                        viewModel.config.automationProvider = nil
                        viewModel.config.automationModel = nil
                    } else {
                        if selectedModel.isEmpty {
                            selectedModel = selectedProvider.defaultModel
                        }
                        viewModel.config.automationProvider = selectedProvider
                        viewModel.config.automationModel = selectedModel
                    }
                }
                
                if useSeparateModel {
                    Divider()

                    automationOverrideNotice
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automation Model")
                                .font(.subheadline)
                            Text("Overrides the main organization model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        ModelSelectorCompactButton(
                            provider: selectedProvider,
                            label: selectedModelDisplay,
                            onTap: { showModelPicker = true }
                        )
                        .modelSelectorTriggerBounds()
                    }
                    
                    Divider()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("A lean automation model keeps watched folders responsive without changing the main Organize page.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .settingsFocusable(.automationGlobalModel)
        .modelSelectionOverlay(
            isPresented: $showModelPicker,
            currentProvider: selectedProvider,
            currentModel: selectedModel,
            contextMessage: "Choose the provider and model Sorty uses for watched-folder automation.",
            onSelect: { provider, model in
                selectedProvider = provider
                selectedModel = model
                viewModel.config.automationProvider = provider
                viewModel.config.automationModel = model
            }
        )
    }

    private var selectedModelDisplay: String {
        selectedModel.isEmpty ? selectedProvider.defaultModel : selectedModel
    }

    private var backgroundBehaviorSection: some View {
        SettingsCard(title: "Background Behavior", icon: "menubar.rectangle", color: .purple) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $launchAtLogin) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                                .font(.subheadline)
                            Text("Automatically start Sorty when you log in to macOS")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .settingsFocusableSetting(.automationLaunchAtLogin)

                    Toggle(isOn: $keepInBackground) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Keep in Background")
                                    .font(.subheadline)

                                Button {
                                    showBackgroundInfo.toggle()
                                } label: {
                                    Image(systemName: "info.circle")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Keep in Background information")
                                .popover(isPresented: $showBackgroundInfo, arrowEdge: .trailing) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(alignment: .firstTextBaseline) {
                                            Text("Background Activity")
                                                .font(.headline)
                                            Spacer()
                                            backgroundStatusBadge
                                        }

                                        Text("Enabling background features registers Sorty as a background activity app in System Settings, allowing it to perform tasks like folder watching reliably. It is recommended to keep this on.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(14)
                                    .frame(width: 280, alignment: .leading)
                                    .systemLiquidGlassPopover(cornerRadius: 12)
                                }
                            }

                            Text("Continue monitoring folders even when all windows are closed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .settingsFocusableSetting(.automationKeepInBackground)

                    @AppStorage("hideDockIcon") var hideDockIcon = false
                    Toggle(isOn: $hideDockIcon) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide Dock Icon")
                                .font(.subheadline)
                            Text("Run as a menu bar app without showing in the Dock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .settingsFocusableSetting(.automationHideDockIcon)
                }

            }
        }
    }

    private var automationOverrideNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Automation override is active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(automationOverrideMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var automationOverrideMessage: String {
        let overrideCount = watchedFoldersManager.folders.filter { $0.providerOverride != nil || $0.modelOverride != nil }.count
        let folderText = overrideCount == 1 ? "1 folder-level model choice" : "\(overrideCount) folder-level model choices"

        if overrideCount > 0 {
            return "Watched folders and background runs use \(automationModelName); \(folderText) are ignored while this is on. The main Organize page still uses its AI Provider model."
        }

        return "Watched folders and background runs use \(automationModelName). The main Organize page still uses its AI Provider model."
    }

    private var automationModelName: String {
        selectedModel.isEmpty ? selectedProvider.defaultModel : selectedModel
    }

    private var backgroundStatusBadge: some View {
        Label(backgroundStatusTitle, systemImage: loginItemManager.isBackgroundAgentEnabled ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.medium))
            .foregroundStyle(loginItemManager.isBackgroundAgentEnabled ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((loginItemManager.isBackgroundAgentEnabled ? Color.green : Color.secondary).opacity(0.08))
            .clipShape(Capsule())
            .accessibilityLabel("Background activity status is \(backgroundStatusTitle)")
    }

    private var backgroundStatusTitle: String {
        if loginItemManager.isBackgroundAgentEnabled {
            return "On"
        }

        if keepInBackground, !loginItemManager.agentStatus.isEmpty {
            return loginItemManager.agentStatus
        }

        return "Off"
    }
    
    private func loadAutomationSettings() {
        if let provider = viewModel.config.automationProvider {
            useSeparateModel = true
            selectedProvider = provider
            selectedModel = viewModel.config.automationModel ?? provider.defaultModel
        } else {
            useSeparateModel = false
            selectedProvider = viewModel.config.provider
            selectedModel = viewModel.config.model
        }
    }
}

#Preview {
    AutomationSettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(WatchedFoldersManager())
        .environmentObject(AppState())
        .frame(width: 500, height: 600)
}

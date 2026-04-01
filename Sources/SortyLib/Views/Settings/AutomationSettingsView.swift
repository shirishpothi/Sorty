//
//  AutomationSettingsView.swift
//  Sorty
//
//  Settings for automation and watched folder AI configuration
//

import SwiftUI

struct AutomationSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var loginItemManager: LoginItemManager
    @EnvironmentObject var notificationSettings: NotificationSettingsManager

    @AppStorage("keepInBackground") private var keepInBackground = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("confirmQuitWhileOrganizing") private var confirmQuitWhileOrganizing = true
    
    @State private var useSeparateModel = false
    @State private var selectedProvider: AIProvider = .openAI
    @State private var selectedModel: String = ""
    @State private var showModelPicker = false
    
    private var activeFoldersCount: Int {
        watchedFoldersManager.folders.filter { $0.isEnabled }.count
    }
    
    private var autoOrganizingCount: Int {
        watchedFoldersManager.folders.filter { $0.isEnabled && $0.autoOrganize }.count
    }
    
    var body: some View {
        VStack(spacing: 16) {
            globalModelSection
                .animatedAppearance(delay: 0.05)
            
            watchedFoldersSummarySection
                .animatedAppearance(delay: 0.1)
            
            backgroundBehaviorSection
                .animatedAppearance(delay: 0.15)
        }
        .onAppear {
            loadAutomationSettings()
        }
        .modelSelectionOverlay(
            isPresented: $showModelPicker,
            currentProvider: selectedProvider,
            currentModel: selectedModel,
            onSelect: { provider, model in
                selectedProvider = provider
                selectedModel = model
                viewModel.config.automationProvider = provider
                viewModel.config.automationModel = model
            }
        )
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
                        viewModel.config.automationProvider = selectedProvider
                        viewModel.config.automationModel = selectedModel
                    }
                }
                
                if useSeparateModel {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Provider & Model")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        ModelSelectorRow(
                            provider: selectedProvider,
                            model: selectedModel,
                            onTap: { showModelPicker = true }
                        )
                        .modelSelectorTriggerBounds()
                    }
                    
                    Divider()
                    
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("Use a faster, cheaper model for automation to reduce costs. Background tasks don't require the most advanced model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    
    private var watchedFoldersSummarySection: some View {
        SettingsCard(title: "Watched Folders Summary", icon: "folder.badge.gearshape", color: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    StatBadge(
                        value: "\(watchedFoldersManager.folders.count)",
                        label: "Total Folders",
                        color: .secondary
                    )
                    
                    StatBadge(
                        value: "\(activeFoldersCount)",
                        label: "Active",
                        color: .green
                    )
                    
                    StatBadge(
                        value: "\(autoOrganizingCount)",
                        label: "Auto-Organizing",
                        color: .blue
                    )
                    
                    Spacer()
                }
                
                if watchedFoldersManager.folders.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("No watched folders configured. Add folders to enable automatic organization.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                Divider()
                
                Button {
                    appState.navigatedFromSettings = true
                    appState.currentView = .watchedFolders
                } label: {
                    HStack {
                        Image(systemName: "folder.badge.plus")
                        Text("Manage Watched Folders")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
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

                    Toggle(isOn: $keepInBackground) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep in Background")
                                .font(.subheadline)
                            Text("Continue monitoring folders even when all windows are closed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

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

                    Toggle(isOn: $notificationSettings.settings.notifyOnAutoOrganize) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automation Notifications")
                                .font(.subheadline)
                            Text("Show a system notification when files are automatically organized")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    Toggle(isOn: $confirmQuitWhileOrganizing) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Warn Before Quitting During Organization")
                                .font(.subheadline)
                            Text("Show a confirmation before quitting while active organization is in progress")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                Divider()

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Background Activity")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Enabling background features registers Sorty as a background activity app in System Settings, allowing it to perform tasks like folder watching reliably.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if launchAtLogin || keepInBackground {
                    Button {
                        loginItemManager.openLoginItemsSettings()
                    } label: {
                        Label("System Settings > Background Items", systemImage: "arrow.up.forward.app")
                            .font(.caption)
                    }
                    .buttonStyle(.link)
                }
            }
        }
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

private struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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

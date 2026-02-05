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
                        Text("Provider")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Picker("", selection: $selectedProvider) {
                            ForEach(AIProvider.allCases.filter { $0.isAvailable }, id: \.self) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .onChange(of: selectedProvider) { _, newProvider in
                            selectedModel = newProvider.defaultModel
                            viewModel.config.automationProvider = newProvider
                            viewModel.config.automationModel = selectedModel
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        ModelSelectorRow(
                            provider: selectedProvider,
                            model: selectedModel,
                            onTap: { showModelPicker = true }
                        )
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
        .sheet(isPresented: $showModelPicker) {
            ModelSelectionPopover(
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "menubar.dock.rectangle")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menu Bar Presence")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Sorty runs in the menu bar to monitor watched folders and organize files automatically in the background.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trigger Behavior")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("When new files are detected in watched folders, organization runs after a short delay to batch multiple changes together.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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

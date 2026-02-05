//
//  OrganizationRulesSettingsView.swift
//  Sorty
//
//  Organization Rules settings section
//

import SwiftUI

struct OrganizationRulesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var healthManager: WorkspaceHealthManager
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var showingHealthSettings = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Quick Navigation Cards
            SettingsNavigationCard(
                title: "Watched Folders",
                description: "Configure folders for automatic organization",
                icon: "eye",
                color: .blue
            ) {
                appState.navigatedFromSettings = true
                appState.currentView = .watchedFolders
            }
            .animatedAppearance(delay: 0.05)
            
            SettingsNavigationCard(
                title: "Exclusion Rules",
                description: "Define files and folders to skip during organization",
                icon: "eye.slash",
                color: .red
            ) {
                appState.navigatedFromSettings = true
                appState.currentView = .exclusions
            }
            .animatedAppearance(delay: 0.1)
            
            SettingsNavigationCard(
                title: "Storage Locations",
                description: "Add external destinations for files during organization",
                icon: "externaldrive",
                color: .purple
            ) {
                appState.navigatedFromSettings = true
                appState.currentView = .storageLocations
            }
            .animatedAppearance(delay: 0.15)
            
            SettingsNavigationCard(
                title: "Workspace Health Rules",
                description: "Set up health monitoring and cleanup policies",
                icon: "heart.text.square",
                color: .green
            ) {
                appState.navigatedFromSettings = true
                showingHealthSettings = true
            }
            .animatedAppearance(delay: 0.2)
            
            SettingsCard(title: "Organization Limits", icon: "folder.badge.questionmark", color: .purple) {
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
            .animatedAppearance(delay: 0.25)
            
            SettingsCard(title: "Content Rules", icon: "checklist", color: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.detectDuplicates,
                        title: "Detect Duplicates",
                        description: "Find files with identical content using SHA-256 hashing"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $viewModel.config.enableFileTagging,
                        title: "Enable File Tagging",
                        description: "Allow AI to suggest and apply Finder tags to files"
                    )
                }
            }
            .animatedAppearance(delay: 0.3)
            
            // Organization Style
            SettingsCard(title: "Organization Style", icon: "paintpalette", color: .purple) {
                PersonaPickerView()
            }
            .animatedAppearance(delay: 0.35)
        }
        .sheet(isPresented: $showingHealthSettings) {
            WorkspaceHealthSettingsView(healthManager: healthManager)
        }
    }
}

#Preview {
    OrganizationRulesSettingsView()
        .environmentObject(AppState())
    .environmentObject(WorkspaceHealthManager())
    .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 400)
}

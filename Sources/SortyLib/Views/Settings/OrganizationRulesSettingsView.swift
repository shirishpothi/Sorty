//
//  OrganizationRulesSettingsView.swift
//  Sorty
//
//  Organization Rules settings section
//

import SwiftUI

struct OrganizationRulesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsNavigationCard(
                title: "Storage Locations",
                description: "Add external destinations for files during organization",
                icon: "externaldrive",
                color: .purple
            ) {
                appState.navigatedFromSettings = true
                appState.currentView = .storageLocations
            }
            .settingsFocusable(.rulesStorageLocations)
            .animatedAppearance(delay: 0.05)
            
            SettingsCard(title: "Organization Limits", icon: "folder.badge.questionmark", color: .purple) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Top-Level Folders")
                            .font(.subheadline)
                        Spacer()
                        Text("\(viewModel.config.maxTopLevelFolders)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .numericRoll(value: Double(viewModel.config.maxTopLevelFolders))
                    }

                    NoTickSlider(
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

                    Text("Limits how many main folders Sorty creates. Subfolders are not limited.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    MaxFoldersPreview(maxFolders: viewModel.config.maxTopLevelFolders)
                }
            }
            .settingsFocusable(.rulesOrganizationLimits)
            .animatedAppearance(delay: 0.1)
            
            SettingsCard(title: "Content Rules", icon: "checklist", color: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.enableFileTagging,
                        title: "Enable File Tagging",
                        description: "Allow Sorty to suggest and apply Finder tags to files"
                    )
                }
            }
            .settingsFocusable(.rulesContentRules)
            .animatedAppearance(delay: 0.15)

            SettingsCard(title: "AI Temperature", icon: "thermometer.medium", color: .green) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .font(.subheadline)
                        Spacer()
                        Text("\(viewModel.config.temperature, specifier: "%.2f")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .numericRoll(value: viewModel.config.temperature)
                    }

                    NoTickSlider(value: $viewModel.config.temperature, in: 0...1, step: 0.1)
                        .onChange(of: viewModel.config.temperature) { _, _ in
                            HapticFeedbackManager.shared.selection()
                        }
                        .accessibilityIdentifier("TemperatureSlider")

                    HStack {
                        Text("Focused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Creative")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    TemperaturePreview(temperature: viewModel.config.temperature)
                }
            }
            .animatedAppearance(delay: 0.2)

            // Organization Style
            SettingsCard(title: "Organization Style", icon: "paintpalette", color: .purple) {
                PersonaPickerView()
            }
            .settingsFocusable(.rulesOrganizationStyle)
            .animatedAppearance(delay: 0.25)
        }
    }
}

#Preview {
    OrganizationRulesSettingsView()
        .environmentObject(AppState())
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 400)
}

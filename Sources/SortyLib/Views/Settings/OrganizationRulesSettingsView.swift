//
//  OrganizationRulesSettingsView.swift
//  Sorty
//
//  Organization Rules settings section
//

import AppKit
import SwiftUI

struct OrganizationRulesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: SettingsViewModel

    private func openInMainWindow(_ destination: DeeplinkDestination) {
        guard let url = DeeplinkHandler.url(for: destination) else { return }
        if MainWindowRouter.shared.routeDeeplink(url) {
            return
        }
        NSWorkspace.shared.open(url)
    }

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
                openInMainWindow(.storage(action: nil, path: nil))
            }
            .settingsFocusable(.rulesStorageLocations)
            .animatedAppearance(delay: 0.05)
            .accessibilityIdentifier("SettingsRulesStorageLocationsCard")

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
            .settingsFocusable(.rulesOrganizationLimits)
            .animatedAppearance(delay: 0.1)

            SettingsCard(title: "Content Rules", icon: "checklist", color: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.enableFileTagging,
                        title: "Enable File Tagging",
                        description: "Allow AI to suggest and apply Finder tags to files"
                    )
                }
            }
            .settingsFocusable(.rulesContentRules)
            .animatedAppearance(delay: 0.15)

            SettingsNavigationCard(
                title: "Steering Prompts",
                description: "Manage reusable instructions from the organize workflow",
                icon: "text.bubble",
                color: .blue
            ) {
                openSteeringPromptsInMainWindow()
            }
            .settingsFocusable(.rulesSteeringPrompts)
            .animatedAppearance(delay: 0.18)
            .accessibilityIdentifier("SettingsRulesSteeringPromptsCard")

            // Organization Style
            SettingsCard(title: "Organization Style", icon: "paintpalette", color: .purple) {
                PersonaPickerView()
            }
            .settingsFocusable(.rulesOrganizationStyle)
            .animatedAppearance(delay: 0.22)
        }
    }

    private func openSteeringPromptsInMainWindow() {
        appState.navigatedFromSettings = true
        HapticFeedbackManager.shared.selection()

        if MainWindowRouter.shared.post(name: .presentSteeringPromptsInMainWindow) {
            MainWindowRouter.shared.activatePreferredWindow()
            return
        }

        appState.shouldPresentSteeringPrompts = true
        appState.currentView = .organize
        openInMainWindow(.organize(path: nil, persona: nil, mode: nil, autostart: false))
    }
}

#Preview {
    OrganizationRulesSettingsView()
        .environmentObject(AppState())
        .environmentObject(SettingsViewModel())
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .frame(width: 500, height: 400)
}

//
//  OrganizationRulesSettingsView.swift
//  Sorty
//
//  Organization Rules settings section
//

import SwiftUI

struct OrganizationRulesSettingsView: View {
    @SortyHotReload private var hotReload
    @EnvironmentObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Content Rules", icon: "checklist", color: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.enableFileTagging,
                        title: "Enable File Tagging",
                        description: "Allow Sorty to suggest and apply Finder tags to files",
                        focusTarget: .rulesFileTagging
                    )
                }
            }
            .settingsFocusable(.rulesContentRules)
            .animatedAppearance(delay: 0.05)

            SettingsCard(title: "AI Temperature", icon: "thermometer.medium", color: .green) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .font(.subheadline)
                        Spacer()
                        Text("\(viewModel.config.temperature, specifier: "%.2f")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .numericTextTransition(
                                animationValue: viewModel.config.temperature
                            )
                    }

                    NoTickSlider(value: $viewModel.config.temperature, in: 0...1, step: 0.1)
                        .onChange(of: viewModel.config.temperature) { _, _ in
                            HapticFeedbackManager.shared.selection()
                        }
                        .accessibilityIdentifier("TemperatureSlider")
                        .settingsFocusableSetting(.rulesTemperatureSlider)

                    HStack {
                        Text("Focused")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Creative")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .settingsFocusable(.rulesTemperature)
            .animatedAppearance(delay: 0.1)

            // Organization Style
            SettingsCard(title: "Organization Style", icon: "paintpalette", color: .purple) {
                PersonaPickerView()
            }
            .settingsFocusable(.rulesOrganizationStyle)
            .animatedAppearance(delay: 0.15)
        }
    }
}

#Preview {
    OrganizationRulesSettingsView()
        .environmentObject(AppState())
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 400)
}

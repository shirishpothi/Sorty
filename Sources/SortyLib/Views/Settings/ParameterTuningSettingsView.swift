//
//  ParameterTuningSettingsView.swift
//  Sorty
//
//  Parameter Tuning settings section
//

import SwiftUI

struct ParameterTuningSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "AI Temperature", icon: "thermometer.medium", color: .green) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperature")
                            .font(.subheadline)
                        Spacer()
                        Text("\(viewModel.config.temperature, specifier: "%.2f")")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .numericTextTransition(value: viewModel.config.temperature)
                    }
                    
                    NoTickSlider(value: $viewModel.config.temperature, in: 0...1, step: 0.1)
                        .onChange(of: viewModel.config.temperature) { _, _ in
                            HapticFeedbackManager.shared.selection()
                        }

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
            .animatedAppearance(delay: 0.05)
        }
    }
}

#Preview {
    ParameterTuningSettingsView()
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 200)
}

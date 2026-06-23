//
//  ParameterTuningSettingsView.swift
//  Sorty
//
//  Parameter Tuning settings section
//

import SwiftUI

struct ParameterTuningSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var temperatureEditing = false

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
                            .numericRoll(value: viewModel.config.temperature, isEditing: temperatureEditing)
                    }

                    NoTickSlider(value: $viewModel.config.temperature, in: 0...1, step: 0.1) { temperatureEditing = $0 }
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

                    TemperaturePreview(temperature: viewModel.config.temperature)
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

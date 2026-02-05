//
//  OrganizationStrategySettingsView.swift
//  Sorty
//
//  Organization Strategy settings section
//

import SwiftUI

struct OrganizationStrategySettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @StateObject private var namingGenerator = NamingInstructionsGenerator()
    @State private var namingPreferenceInput: String = ""
    @State private var showNamingInput: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Scanning Options", icon: "doc.text.magnifyingglass", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        SettingsToggle(
                            isOn: $viewModel.config.enableDeepScan,
                            title: "Deep Scanning",
                            description: "Analyze file content (PDF text, EXIF data) for smarter organization"
                        )
                        .disabled(!viewModel.config.provider.supportsDeepScan)
                        
                        if !viewModel.config.provider.supportsDeepScan {
                            Text("Not supported by \(viewModel.config.provider.displayName) due to context limits.")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.leading, 32)
                        }
                    }
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $viewModel.config.enableSmartRename,
                        title: "Smart Renaming",
                        description: "AI suggests more descriptive filenames based on content"
                    )
                    
                }
            }
            .animatedAppearance(delay: 0.05)
            
            // Vision AI Section
            SettingsCard(title: "AI Vision", icon: "eye", color: .teal) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.enableVision,
                        title: "Use AI Vision for Images",
                        description: "Send images to the AI for content-aware organization"
                    )
                    .disabled(!ModelCatalog.shared.supportsVision(modelId: viewModel.config.model, provider: viewModel.config.provider))
                    
                    if viewModel.config.enableVision {
                        Divider()
                        
                        HStack {
                            Text("Images per Batch")
                                .font(.subheadline)
                            Spacer()
                            Text("\(viewModel.config.visionBatchSize)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(viewModel.config.visionBatchSize) },
                                set: { viewModel.config.visionBatchSize = Int($0) }
                            ),
                            in: 1...10,
                            step: 1
                        )
                        
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("Vision uses more tokens and may incur higher API costs.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    }
                    
                    if !ModelCatalog.shared.supportsVision(modelId: viewModel.config.model, provider: viewModel.config.provider) {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            Text("Switch to a vision model (e.g., gpt-4o, claude-3-5-sonnet) to enable.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .animatedAppearance(delay: 0.1)
            
            // Naming Style Section
            SettingsCard(title: "Naming Style", icon: "textformat", color: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Naming Style", selection: $viewModel.config.namingStyle) {
                            ForEach(NamingStyle.allCases, id: \.self) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        
                        Text("Determines how the AI suggests file names when Smart Rename is enabled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if viewModel.config.enableSmartRename {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Custom Naming Instructions")
                                .font(.subheadline.weight(.medium))
                            
                            TextEditor(text: Binding(
                                get: { viewModel.config.customNamingInstructions ?? "" },
                                set: { viewModel.config.customNamingInstructions = $0.isEmpty ? nil : $0 }
                            ))
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 60)
                            .padding(4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            
                            if showNamingInput {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Describe your naming preference...", text: $namingPreferenceInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body))
                                    
                                    HStack {
                                        Button("Generate") {
                                            Task {
                                                do {
                                                    let instructions = try await namingGenerator.generateNamingInstructions(
                                                        from: namingPreferenceInput,
                                                        config: viewModel.config
                                                    )
                                                    viewModel.config.customNamingInstructions = instructions
                                                    showNamingInput = false
                                                    namingPreferenceInput = ""
                                                } catch {
                                                    // Error is handled by namingGenerator.error
                                                }
                                            }
                                        }
                                        .buttonStyle(.onboardingPill(size: .small))
                                        .disabled(namingPreferenceInput.isEmpty || namingGenerator.isGenerating)
                                        
                                        if namingGenerator.isGenerating {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                                .padding(.leading, 4)
                                        }
                                        
                                        Spacer()
                                        
                                        Button("Cancel") {
                                            showNamingInput = false
                                            namingPreferenceInput = ""
                                        }
                                        .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                                    }
                                    
                                    if let error = namingGenerator.error {
                                        Text(error.localizedDescription)
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.top, 4)
                            } else {
                                Button {
                                    showNamingInput = true
                                } label: {
                                    Label("Generate Instructions", systemImage: "wand.and.stars")
                                }
                                .buttonStyle(.onboardingPill(size: .small))
                                .padding(.top, 4)
                            }
                            
                            Text("Extra rules for the AI (e.g., 'Use camelCase for subjects')")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .animatedAppearance(delay: 0.15)
        }
    }
}

#Preview {
    OrganizationStrategySettingsView()
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 600)
}

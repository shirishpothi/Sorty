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
    @StateObject private var presetManager = NamingPresetManager.shared
    @State private var namingPreferenceInput: String = ""
    @State private var showNamingInput: Bool = false
    @State private var presetNameInput: String = ""
    @State private var showingSavePresetAlert: Bool = false
    @State private var pendingPresetInstructions: String = ""
    @State private var editingPreset: NamingPreset? = nil
    @State private var showEditSheet: Bool = false

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

            // Renaming Section
            SettingsCard(title: "Renaming", icon: "textformat", color: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Template", selection: Binding(
                            get: { viewModel.config.selectedNamingPresetId },
                            set: { newId in
                                viewModel.config.selectedNamingPresetId = newId
                                if let id = newId, let preset = presetManager.preset(for: id) {
                                    if preset.isBuiltIn {
                                        // Map built-in preset back to its NamingStyle
                                        if let style = presetManager.namingStyle(for: id) {
                                            viewModel.config.namingStyle = style
                                            viewModel.config.customNamingInstructions = nil
                                        }
                                    } else {
                                        // Custom preset
                                        viewModel.config.namingStyle = .custom
                                        viewModel.config.customNamingInstructions = preset.instructions
                                    }
                                }
                            }
                        )) {
                            Text("None").tag(nil as UUID?)

                            Section("Built-in") {
                                ForEach(presetManager.builtInPresets) { preset in
                                    Text(preset.name).tag(preset.id as UUID?)
                                }
                            }

                            if !presetManager.customPresets.isEmpty {
                                Section("Custom") {
                                    ForEach(presetManager.customPresets) { preset in
                                        Text(preset.name).tag(preset.id as UUID?)
                                    }
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()

                        Text("Controls how AI names files. Spaces are allowed and often preferred.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !viewModel.config.enableSmartRename {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text("Naming instructions will be applied when Smart Renaming is enabled during organization.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Picker("Separator", selection: $viewModel.config.renameNamingOptions.separator) {
                                ForEach(RenameSeparatorPreference.allCases, id: \.self) { separator in
                                    Text(separator.displayName).tag(separator)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Case", selection: $viewModel.config.renameNamingOptions.caseStyle) {
                                ForEach(RenameCaseStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack(spacing: 12) {
                            Picker("Dates", selection: $viewModel.config.renameNamingOptions.datePolicy) {
                                ForEach(RenameDatePolicy.allCases, id: \.self) { policy in
                                    Text(policy.displayName).tag(policy)
                                }
                            }
                            .pickerStyle(.menu)

                            TextField(
                                "Language",
                                text: Binding(
                                    get: { viewModel.config.renameNamingOptions.outputLanguage },
                                    set: { viewModel.config.renameNamingOptions.outputLanguage = $0.isEmpty ? "English" : $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            Text("Max Length")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.config.renameNamingOptions.maxFilenameLength) },
                                    set: { viewModel.config.renameNamingOptions.maxFilenameLength = Int($0) }
                                ),
                                in: 20...180,
                                step: 5
                            )
                            Text("\(viewModel.config.renameNamingOptions.maxFilenameLength)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundColor(.purple)
                            Text(viewModel.config.renameNamingOptions.exampleFilename)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }

                    // Preview of selected preset instructions
                    if let selectedId = viewModel.config.selectedNamingPresetId,
                       let selectedPreset = presetManager.preset(for: selectedId),
                       !selectedPreset.instructions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedPreset.instructions)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                        }
                    }

                    // Action buttons for custom presets
                    if let selectedId = viewModel.config.selectedNamingPresetId,
                       let selectedPreset = presetManager.preset(for: selectedId),
                       !selectedPreset.isBuiltIn {
                        HStack(spacing: 8) {
                            Button {
                                editingPreset = selectedPreset
                                showEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.onboardingPill(size: .small))

                            Button(role: .destructive) {
                                presetManager.deletePreset(id: selectedId)
                                // Reset to descriptive
                                viewModel.config.namingStyle = .descriptive
                                viewModel.config.customNamingInstructions = nil
                                viewModel.config.selectedNamingPresetId = presetManager.presetId(for: .descriptive)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .buttonStyle(.onboardingPill(isSecondary: true, size: .small))

                            Spacer()
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.config.namingStyle == .custom ? "Custom Naming Instructions" : "Additional Naming Instructions")
                            .font(.subheadline.weight(.medium))

                        TextEditor(text: Binding(
                            get: { viewModel.config.customNamingInstructions ?? "" },
                            set: {
                                viewModel.config.customNamingInstructions = $0.isEmpty ? nil : $0
                                if $0.isEmpty && viewModel.config.namingStyle == .custom {
                                    viewModel.config.namingStyle = .descriptive
                                    viewModel.config.selectedNamingPresetId = presetManager.presetId(for: .descriptive)
                                }
                            }
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
                                                pendingPresetInstructions = instructions
                                                showNamingInput = false
                                                namingPreferenceInput = ""
                                                presetNameInput = ""
                                                showingSavePresetAlert = true
                                            } catch {
                                                // Error is handled by namingGenerator.error
                                            }
                                        }
                                    }
                                    .buttonStyle(.onboardingPill(size: .small))
                                    .disabled(namingPreferenceInput.isEmpty || namingGenerator.isGenerating)

                                    if namingGenerator.isGenerating {
                                        SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
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
                                Label("Generate Naming Template", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.onboardingPill(size: .small))
                            .padding(.top, 4)
                        }

                        Text(viewModel.config.namingStyle == .custom
                             ? "These instructions define how files are named when using Custom style."
                             : "Extra rules for the AI (e.g., 'Use camelCase for subjects')")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .animatedAppearance(delay: 0.15)
            .alert("Save as Naming Preset", isPresented: $showingSavePresetAlert) {
                TextField("Preset name", text: $presetNameInput)
                Button("Save") {
                    let newPreset = NamingPreset(
                        name: presetNameInput.isEmpty ? "Custom Preset" : presetNameInput,
                        instructions: pendingPresetInstructions
                    )
                    presetManager.addPreset(newPreset)
                    viewModel.config.customNamingInstructions = newPreset.instructions
                    viewModel.config.namingStyle = .custom
                    viewModel.config.selectedNamingPresetId = newPreset.id
                    presetNameInput = ""
                    pendingPresetInstructions = ""
                }
                Button("Cancel", role: .cancel) {
                    // Still apply the instructions even if not saved as preset
                    viewModel.config.customNamingInstructions = pendingPresetInstructions
                    viewModel.config.namingStyle = .custom
                    pendingPresetInstructions = ""
                }
            } message: {
                Text("Enter a name for this naming preset so you can reuse it later.")
            }
            .sheet(isPresented: $showEditSheet) {
                if let preset = editingPreset {
                    EditPresetSheet(
                        preset: preset,
                        presetManager: presetManager,
                        viewModel: viewModel,
                        isPresented: $showEditSheet
                    )
                }
            }
        }
    }
}

// MARK: - Edit Preset Sheet

private struct EditPresetSheet: View {
    let preset: NamingPreset
    let presetManager: NamingPresetManager
    let viewModel: SettingsViewModel
    @Binding var isPresented: Bool

    @State private var editName: String
    @State private var editInstructions: String

    init(preset: NamingPreset, presetManager: NamingPresetManager, viewModel: SettingsViewModel, isPresented: Binding<Bool>) {
        self.preset = preset
        self.presetManager = presetManager
        self.viewModel = viewModel
        self._isPresented = isPresented
        self._editName = State(initialValue: preset.name)
        self._editInstructions = State(initialValue: preset.instructions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Naming Preset")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.subheadline.weight(.medium))
                TextField("Preset name", text: $editName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Instructions")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $editInstructions)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.onboardingPill(isSecondary: true, size: .small))

                Button("Save") {
                    var updated = preset
                    updated.name = editName
                    updated.instructions = editInstructions
                    presetManager.updatePreset(updated)
                    // Update the active config if this preset is currently selected
                    if viewModel.config.selectedNamingPresetId == preset.id {
                        viewModel.config.customNamingInstructions = editInstructions
                    }
                    isPresented = false
                }
                .buttonStyle(.onboardingPill(size: .small))
                .disabled(editName.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    OrganizationStrategySettingsView()
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 600)
}

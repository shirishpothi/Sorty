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
    @StateObject private var steeringManager = SteeringPromptManager.shared
    @State private var showingHealthSettings = false
    @State private var steeringPromptText = ""
    @State private var showSavePromptDialog = false
    @State private var savePromptName = ""
    @State private var isImprovingPrompt = false
    @State private var showSavedPromptsSheet = false
    
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

            SettingsCard(title: "Steering Prompts", icon: "wand.and.stars", color: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add optional default instructions to guide how the AI organizes your files.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("EXAMPLES")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        HStack(spacing: 8) {
                            ExamplePill(text: "Group by project") { steeringPromptText = "Group files by project or client name." }
                            ExamplePill(text: "Separate RAW photos") { steeringPromptText = "Move RAW photo files into a 'RAW' subfolder within each category." }
                            ExamplePill(text: "Keep documents by year") { steeringPromptText = "Organize all documents by the year they were created." }
                        }
                    }
                    .padding(.bottom, 4)

                    ZStack(alignment: .topLeading) {
                        if steeringPromptText.isEmpty {
                            Text("e.g. \"Group by project\", \"Separate RAW photos\", \"Keep documents by year\"...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }

                        if isImprovingPrompt {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Improving...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else {
                            TextEditor(text: $steeringPromptText)
                                .font(.body)
                                .frame(minHeight: 80, maxHeight: 120)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        if !steeringPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                Task { await improvePromptWithAI() }
                            } label: {
                                Label("Improve with AI", systemImage: "wand.and.stars")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.purple)
                            .disabled(isImprovingPrompt)
                            .help("Improve instructions with AI")

                            Button {
                                if let defaultPrompt = steeringManager.defaultPrompt {
                                    var updated = defaultPrompt
                                    updated.prompt = steeringPromptText
                                    steeringManager.updatePrompt(updated)
                                } else {
                                    let newDefault = SavedSteeringPrompt(name: "Default Instructions", prompt: steeringPromptText, isDefault: true)
                                    steeringManager.addPrompt(newDefault)
                                }
                                HapticFeedbackManager.shared.success()
                            } label: {
                                Label("Save as Default", systemImage: "star.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.orange)
                            .help("Save and set as the default steering prompt for all organization sessions")

                            Button {
                                savePromptName = ""
                                showSavePromptDialog.toggle()
                            } label: {
                                Label("Save as New", systemImage: "bookmark")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .popover(isPresented: $showSavePromptDialog) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Save Prompt")
                                        .font(.headline)

                                    TextField("Prompt name", text: $savePromptName)
                                        .textFieldStyle(.roundedBorder)

                                    HStack {
                                        Button("Cancel") {
                                            showSavePromptDialog = false
                                        }
                                        .buttonStyle(.bordered)

                                        Spacer()

                                        Button("Save") {
                                            let prompt = SavedSteeringPrompt(
                                                name: savePromptName.isEmpty ? "Untitled" : savePromptName,
                                                prompt: steeringPromptText
                                            )
                                            steeringManager.addPrompt(prompt)
                                            showSavePromptDialog = false
                                            HapticFeedbackManager.shared.success()
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .disabled(savePromptName.trimmingCharacters(in: .whitespaces).isEmpty)
                                    }
                                }
                                .padding(16)
                                .frame(width: 280)
                            }
                        }

                        Spacer()

                        Button {
                            showSavedPromptsSheet.toggle()
                        } label: {
                            Label(
                                steeringManager.prompts.isEmpty ? "Saved Prompts" : "Saved Prompts (\(steeringManager.prompts.count))",
                                systemImage: "list.bullet"
                            )
                            .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .animatedAppearance(delay: 0.32)

            // Organization Style
            SettingsCard(title: "Organization Style", icon: "paintpalette", color: .purple) {
                PersonaPickerView()
            }
            .animatedAppearance(delay: 0.35)
        }
        .sheet(isPresented: $showingHealthSettings) {
            WorkspaceHealthSettingsView(healthManager: healthManager)
        }
        .sheet(isPresented: $showSavedPromptsSheet) {
            SavedPromptsSheet(
                steeringManager: steeringManager,
                settingsConfig: viewModel.config,
                onApplyPrompt: { prompt in
                    steeringPromptText = prompt
                    showSavedPromptsSheet = false
                    HapticFeedbackManager.shared.tap()
                }
            )
        }
        .onAppear {
            if steeringPromptText.isEmpty, let defaultPrompt = steeringManager.defaultPrompt {
                steeringPromptText = defaultPrompt.prompt
            }
        }
    }

    private func improvePromptWithAI() async {
        let original = steeringPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        isImprovingPrompt = true
        defer { isImprovingPrompt = false }

        do {
            let client = try AIClientFactory.createClient(config: viewModel.config)
            let improved = try await client.generateText(
                prompt: "Improve the following file organization instructions to be clearer, more specific, and more actionable for an AI file organizer. Keep the same intent but make it more precise. Return only the improved instructions text, nothing else.\n\nOriginal instructions: \"\(original)\"",
                systemPrompt: "You are a file organization expert. You help users write better instructions for organizing their files and folders. Be concise and practical."
            )
            let trimmed = improved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                steeringPromptText = trimmed
                HapticFeedbackManager.shared.success()
            }
        } catch {
            HapticFeedbackManager.shared.error()
        }
    }
}

// MARK: - Helper Components

struct SavedPromptRow: View {
    let prompt: SavedSteeringPrompt
    @StateObject private var steeringManager = SteeringPromptManager.shared
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(prompt.name)
                        .font(.subheadline.weight(.medium))
                    if prompt.isDefault {
                        Text("Default")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }
                Text(prompt.prompt)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !prompt.isDefault {
                Button {
                    steeringManager.setDefault(id: prompt.id)
                    HapticFeedbackManager.shared.success()
                } label: {
                    Image(systemName: "star")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Set as default")
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    OrganizationRulesSettingsView()
        .environmentObject(AppState())
    .environmentObject(WorkspaceHealthManager())
    .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 400)
}

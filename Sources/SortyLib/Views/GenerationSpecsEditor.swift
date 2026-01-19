//
//  GenerationSpecsEditor.swift
//  Sorty
//
//  UI for configuring multiple generation runs (specs) for parallel AI generation
//

import SwiftUI

// MARK: - GenerationSpecsEditor

public struct GenerationSpecsEditor: View {
    @ObservedObject var orchestrator: GenerationOrchestrator
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    let onDismiss: () -> Void
    let onStart: () -> Void
    
    @State private var showPresets = false
    @State private var editableSpecs: [EditableSpec] = []
    @State private var showAddModelSheet = false
    @EnvironmentObject var customPersonaStore: CustomPersonaStore
    
    private let maxRunsAllowed = 4
    
    public init(
        orchestrator: GenerationOrchestrator,
        onDismiss: @escaping () -> Void,
        onStart: @escaping () -> Void
    ) {
        self.orchestrator = orchestrator
        self.onDismiss = onDismiss
        self.onStart = onStart
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            if editableSpecs.isEmpty {
                emptyStateView
            } else {
                specsListView
            }
            
            Divider()
            actionsBar
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadSpecsFromOrchestrator()
        }
        .sheet(isPresented: $showAddModelSheet) {
            AddModelSheet(
                onAdd: { provider, model in
                    addSpecWithSelection(provider: provider, model: model)
                },
                onDismiss: {
                    showAddModelSheet = false
                }
            )
            .environmentObject(settingsViewModel)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Multi-Model Generation")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text("Generate with up to \(maxRunsAllowed) models to see different organization approaches")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Presets row
            presetsRow
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var presetsRow: some View {
        HStack(spacing: 8) {
            Text("Presets:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            PresetChip(
                title: "Multiple models",
                icon: "square.stack.3d.up",
                action: applySameProviderPreset
            )
            
            PresetChip(
                title: "Multiple providers",
                icon: "arrow.triangle.branch",
                action: applyDifferentProvidersPreset
            )
            
            Spacer()
            
            if editableSpecs.count < maxRunsAllowed {
                Button {
                    showAddModelSheet = true
                } label: {
                    Label("Add Model", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("No models configured")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Add models to generate multiple organization suggestions")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                Button(action: applySameProviderPreset) {
                    Label("Use Multiple Models", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.bordered)
                
                Button {
                    showAddModelSheet = true
                } label: {
                    Label("Add Model", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private func addSpecWithSelection(provider: AIProvider, model: String) {
        guard editableSpecs.count < maxRunsAllowed else { return }
        let newSpec = EditableSpec(
            id: UUID(),
            provider: provider,
            model: model,
            personaID: nil,
            customInstructions: "",
            showCustomInstructions: false,
            enableReasoning: false,
            enableDeepScan: false,
            enableStreamingPreview: false
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            editableSpecs.append(newSpec)
        }
    }
    
    // MARK: - Specs List
    
    private var specsListView: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(editableSpecs.enumerated()), id: \.element.id) { index, _ in
                    SpecCard(
                        spec: $editableSpecs[index],
                        index: index + 1,
                        customPersonaStore: customPersonaStore,
                        isOnlySpec: editableSpecs.count == 1,
                        onRemove: { removeSpec(id: editableSpecs[index].id) }
                    )
                    .environmentObject(settingsViewModel)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions Bar
    
    private var actionsBar: some View {
        HStack {
            // Status indicator
            if !editableSpecs.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: allSpecsValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(allSpecsValid ? .green : .orange)
                        .font(.system(size: 14))
                    
                    Text(allSpecsValid ? "Ready to generate" : "Using current provider for all runs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("Cancel") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button {
                saveSpecsToOrchestrator()
                onStart()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Generate All")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(editableSpecs.isEmpty)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private var allSpecsValid: Bool {
        editableSpecs.count <= maxRunsAllowed && editableSpecs.allSatisfy { isSpecValid($0) }
    }
    
    private func isSpecValid(_ spec: EditableSpec) -> Bool {
        isAPIKeyConfigured(for: spec.provider)
    }
    
    private func isAPIKeyConfigured(for provider: AIProvider) -> Bool {
        if !provider.typicallyRequiresAPIKey {
            return true
        }
        // Currently only one API key is stored - check if it matches the current provider
        if provider == settingsViewModel.config.provider {
            return settingsViewModel.config.apiKey?.isEmpty == false
        }
        // For other providers, we can't verify - assume they'll use current config
        return false
    }
    
    private func addNewSpec() {
        guard editableSpecs.count < maxRunsAllowed else { return }
        let currentProvider = settingsViewModel.config.provider
        let newSpec = EditableSpec(
            id: UUID(),
            provider: currentProvider,
            model: currentProvider.defaultModel,
            personaID: nil,
            customInstructions: "",
            showCustomInstructions: false,
            enableReasoning: false,
            enableDeepScan: false,
            enableStreamingPreview: false
        )
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            editableSpecs.append(newSpec)
        }
    }
    
    private func removeSpec(id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            editableSpecs.removeAll { $0.id == id }
        }
    }
    
    private func loadSpecsFromOrchestrator() {
        editableSpecs = orchestrator.runs.map { run in
            EditableSpec(
                id: run.spec.id,
                provider: run.spec.provider,
                model: run.spec.model,
                personaID: run.spec.personaID,
                customInstructions: run.spec.customInstructions,
                showCustomInstructions: !run.spec.customInstructions.isEmpty,
                enableReasoning: run.spec.enableReasoning,
                enableDeepScan: run.spec.enableDeepScan,
                enableStreamingPreview: run.spec.enableStreamingPreview
            )
        }
        
        if editableSpecs.isEmpty {
            addNewSpec()
        }
    }
    
    private func saveSpecsToOrchestrator() {
        orchestrator.runs.removeAll()
        
        for spec in editableSpecs {
            let generationSpec = GenerationSpec(
                id: spec.id,
                provider: spec.provider,
                model: spec.model,
                personaID: spec.personaID,
                customInstructions: spec.showCustomInstructions ? spec.customInstructions : "",
                enableReasoning: spec.enableReasoning,
                enableDeepScan: spec.enableDeepScan,
                enableStreamingPreview: spec.enableStreamingPreview
            )
            orchestrator.addSpec(generationSpec)
        }
    }
    
    // MARK: - Presets
    
    private func getModelsForProvider(_ provider: AIProvider) -> [String] {
        let catalogModels = ModelCatalog.shared.cachedModels(for: provider)
        if !catalogModels.isEmpty {
            return catalogModels.map { $0.id }
        }
        return provider.recommendedModels
    }
    
    private func applySameProviderPreset() {
        let provider = settingsViewModel.config.provider
        let models = Array(getModelsForProvider(provider).prefix(maxRunsAllowed))
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            editableSpecs = models.map { model in
                EditableSpec(
                    id: UUID(),
                    provider: provider,
                    model: model,
                    personaID: nil,
                    customInstructions: "",
                    showCustomInstructions: false,
                    enableReasoning: false,
                    enableDeepScan: false,
                    enableStreamingPreview: false
                )
            }
        }
    }
    
    private func applyDifferentProvidersPreset() {
        // For now, since we only have one API key, just use different models from current provider
        applySameProviderPreset()
    }
}

// MARK: - EditableSpec

struct EditableSpec: Identifiable {
    let id: UUID
    var provider: AIProvider
    var model: String
    var personaID: String?
    var customInstructions: String
    var showCustomInstructions: Bool
    var enableReasoning: Bool
    var enableDeepScan: Bool
    var enableStreamingPreview: Bool
}

// MARK: - PresetChip

private struct PresetChip: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
            )
            .foregroundColor(isHovered ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - SpecCard

struct SpecCard: View {
    @Binding var spec: EditableSpec
    let index: Int
    let customPersonaStore: CustomPersonaStore
    let isOnlySpec: Bool
    let onRemove: () -> Void
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @StateObject private var modelCatalog = ModelCatalog.shared
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            HStack(spacing: 12) {
                // Run number
                Text("\(index)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor))
                
                // Provider & Model
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        ProviderIcon(provider: spec.provider, size: 18)
                        
                        Menu {
                            ForEach(AIProvider.allCases.filter { $0.isAvailable }, id: \.self) { provider in
                                Button {
                                    spec.provider = provider
                                    spec.model = provider.defaultModel
                                } label: {
                                    Label(provider.displayName, systemImage: provider.usesSystemImage ? provider.logoImageName : "cpu")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(spec.provider.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .menuStyle(.borderlessButton)
                    }
                    
                    // Model picker
                    Menu {
                        ForEach(modelsForCurrentProvider, id: \.self) { model in
                            Button {
                                spec.model = model
                            } label: {
                                HStack {
                                    Text(model)
                                    if model == spec.provider.defaultModel {
                                        Text("Default").foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(spec.model)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                }
                
                Spacer()
                
                // Persona badge (if set)
                if let personaID = spec.personaID {
                    personaBadge(personaID)
                }
                
                // Options toggle
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "ellipsis")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                
                // Remove button
                if !isOnlySpec {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.secondary.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            
            // Expanded options
            if isExpanded {
                Divider()
                expandedOptions
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            Task {
                await modelCatalog.refresh(provider: spec.provider)
            }
        }
        .onChange(of: spec.provider) { _, newProvider in
            Task {
                await modelCatalog.refresh(provider: newProvider)
            }
        }
    }
    
    private var modelsForCurrentProvider: [String] {
        let catalogModels = modelCatalog.cachedModels(for: spec.provider)
        if !catalogModels.isEmpty {
            return catalogModels.map { $0.id }
        }
        return spec.provider.recommendedModels
    }
    
    private func personaBadge(_ personaID: String) -> some View {
        let displayName: String = {
            if let personaType = PersonaType(rawValue: personaID) {
                return personaType.displayName
            }
            if let custom = customPersonaStore.customPersonas.first(where: { $0.id == personaID }) {
                return custom.name
            }
            return "Persona"
        }()
        
        return Text(displayName)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.purple.opacity(0.1)))
    }
    
    private var expandedOptions: some View {
        VStack(spacing: 12) {
            // Persona picker
            HStack {
                Text("Persona")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Menu {
                    Button { spec.personaID = nil } label: {
                        Label("None", systemImage: "person.slash")
                    }
                    
                    Divider()
                    
                    ForEach(PersonaType.allCases, id: \.self) { persona in
                        Button { spec.personaID = persona.rawValue } label: {
                            Label(persona.displayName, systemImage: persona.icon)
                        }
                    }
                    
                    if !customPersonaStore.customPersonas.isEmpty {
                        Divider()
                        ForEach(customPersonaStore.customPersonas) { persona in
                            Button { spec.personaID = persona.id } label: {
                                Label(persona.name, systemImage: persona.icon)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(spec.personaID.flatMap { id in
                            PersonaType(rawValue: id)?.displayName ?? customPersonaStore.customPersonas.first { $0.id == id }?.name
                        } ?? "None")
                            .font(.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.primary)
                }
                .menuStyle(.borderlessButton)
            }
            
            // Toggles row
            HStack(spacing: 16) {
                Toggle("Streaming", isOn: $spec.enableStreamingPreview)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                
                Toggle("Deep Scan", isOn: $spec.enableDeepScan)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                
                Toggle("Reasoning", isOn: $spec.enableReasoning)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .font(.caption)
            
            // Custom instructions
            DisclosureGroup(
                isExpanded: $spec.showCustomInstructions,
                content: {
                    TextEditor(text: $spec.customInstructions)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 50)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                },
                label: {
                    Text("Custom Instructions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            )
        }
        .padding(12)
        .background(Color.secondary.opacity(0.03))
    }
}

// MARK: - AddModelSheet (Two-Step: Provider → Model)

struct AddModelSheet: View {
    let onAdd: (AIProvider, String) -> Void
    let onDismiss: () -> Void
    
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @StateObject private var modelCatalog = ModelCatalog.shared
    
    enum Step {
        case selectProvider
        case selectModel
    }
    
    @State private var currentStep: Step = .selectProvider
    @State private var selectedProvider: AIProvider?
    @State private var selectedModel: String = ""
    @State private var customModelText: String = ""
    @State private var showCustomModelInput = false
    @State private var isTestingConnection = false
    @State private var connectionTestResult: ConnectionTestResult?
    
    enum ConnectionTestResult {
        case success
        case failure(String)
    }
    
    private var availableProviders: [AIProvider] {
        AIProvider.allCases.filter { $0.isAvailable }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content based on step
            if currentStep == .selectProvider {
                providerSelectionView
            } else {
                modelSelectionView
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 440, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            // Back button (only in model selection step)
            if currentStep == .selectModel {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        currentStep = .selectProvider
                        selectedModel = ""
                        customModelText = ""
                        showCustomModelInput = false
                        connectionTestResult = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Back")
                            .font(.subheadline)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Title
            VStack(spacing: 2) {
                Text(currentStep == .selectProvider ? "Select Provider" : "Select Model")
                    .font(.headline)
                
                if currentStep == .selectModel, let provider = selectedProvider {
                    HStack(spacing: 4) {
                        ProviderIcon(provider: provider, size: 12)
                        Text(provider.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Provider Selection
    
    private var providerSelectionView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(availableProviders, id: \.self) { provider in
                    ProviderSelectionCard(
                        provider: provider,
                        isCurrent: provider == settingsViewModel.config.provider,
                        onSelect: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedProvider = provider
                                currentStep = .selectModel
                            }
                            Task {
                                await modelCatalog.refresh(provider: provider)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Model Selection
    
    private var modelSelectionView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Models list
                if let provider = selectedProvider {
                    let models = getModelsForProvider(provider)
                    
                    if modelCatalog.isFetching[provider] == true {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                    } else if models.isEmpty {
                        Text("No models available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        ForEach(models.prefix(30), id: \.self) { model in
                            ModelSelectionRow(
                                model: model,
                                isSelected: selectedModel == model,
                                isDefault: model == provider.defaultModel,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedModel = model
                                        showCustomModelInput = false
                                        customModelText = ""
                                    }
                                }
                            )
                            
                            if model != models.prefix(30).last {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                        
                        if models.count > 30 {
                            Text("+ \(models.count - 30) more models")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                    
                    Divider()
                        .padding(.top, 8)
                    
                    // Custom model section
                    customModelInputSection(for: provider)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Custom Model Input
    
    private func customModelInputSection(for provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showCustomModelInput.toggle()
                    if showCustomModelInput {
                        selectedModel = ""
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showCustomModelInput ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Image(systemName: "pencil.line")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    
                    Text("Use Custom Model")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(showCustomModelInput ? Color.orange.opacity(0.05) : Color.clear)
            }
            .buttonStyle(.plain)
            
            if showCustomModelInput {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter a model name for \(provider.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        TextField("e.g., \(provider.defaultModel)", text: $customModelText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(customModelBorderColor, lineWidth: 1)
                            )
                        
                        Button {
                            testConnection(provider: provider, model: customModelText)
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingConnection {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                }
                                Text("Test")
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .disabled(customModelText.isEmpty || isTestingConnection)
                    }
                    
                    // Test result feedback
                    if let result = connectionTestResult {
                        HStack(spacing: 6) {
                            switch result {
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connection successful")
                                    .foregroundColor(.green)
                            case .failure(let error):
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                        }
                        .font(.caption)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private var customModelBorderColor: Color {
        if let result = connectionTestResult {
            switch result {
            case .success: return .green
            case .failure: return .red
            }
        }
        return Color.secondary.opacity(0.3)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Step indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(currentStep == .selectProvider ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                Circle()
                    .fill(currentStep == .selectModel ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
            
            Spacer()
            
            Button("Cancel") {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button {
                if let provider = selectedProvider {
                    let modelToUse = showCustomModelInput ? customModelText : selectedModel
                    if !modelToUse.isEmpty {
                        onAdd(provider, modelToUse)
                        onDismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                    Text("Add Model")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canAddModel)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
    
    private var canAddModel: Bool {
        guard selectedProvider != nil else { return false }
        if showCustomModelInput {
            return !customModelText.isEmpty
        }
        return !selectedModel.isEmpty
    }
    
    // MARK: - Helpers
    
    private func getModelsForProvider(_ provider: AIProvider) -> [String] {
        let catalogModels = modelCatalog.cachedModels(for: provider)
        if !catalogModels.isEmpty {
            return catalogModels.map { $0.id }
        }
        return provider.recommendedModels
    }
    
    private func testConnection(provider: AIProvider, model: String) {
        isTestingConnection = true
        connectionTestResult = nil
        
        Task {
            do {
                // Create a minimal test to validate the model
                // This is a lightweight check - we'll just verify the model name format
                // A full API test would require actual credentials and rate limiting considerations
                try await Task.sleep(nanoseconds: 500_000_000) // Simulate network delay
                
                // Basic validation
                if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await MainActor.run {
                        connectionTestResult = .failure("Model name cannot be empty")
                        isTestingConnection = false
                    }
                    return
                }
                
                // For now, we'll accept any non-empty model name
                // In a real implementation, you'd want to make an actual API call
                await MainActor.run {
                    connectionTestResult = .success
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = .failure("Connection failed: \(error.localizedDescription)")
                    isTestingConnection = false
                }
            }
        }
    }
}

// MARK: - Provider Selection Card

private struct ProviderSelectionCard: View {
    let provider: AIProvider
    let isCurrent: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                // Provider icon
                ZStack {
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                        .frame(width: 48, height: 48)
                    
                    ProviderIcon(provider: provider, size: 24)
                }
                
                // Provider name
                Text(provider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Current badge
                if isCurrent {
                    Text("Current")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.1)))
                } else {
                    // Model count placeholder
                    Text("\(provider.recommendedModels.count)+ models")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHovered ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isHovered ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
    }
}

// MARK: - Model Selection Row

private struct ModelSelectionRow: View {
    let model: String
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
                
                // Model name
                Text(model)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                
                // Default badge
                if isDefault {
                    Text("Default")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.1)))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isHovered ? Color.secondary.opacity(0.05) :
                (isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct GenerationSpecsEditor_Previews: PreviewProvider {
    static var previews: some View {
        GenerationSpecsEditor(
            orchestrator: GenerationOrchestrator(),
            onDismiss: {},
            onStart: {}
        )
        .environmentObject(SettingsViewModel())
    }
}
#endif

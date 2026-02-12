//
//  ModelSelector.swift
//  Sorty
//
//  Unified model selection component for consistent UX across the app
//

import SwiftUI

// MARK: - Model Selector Row (Compact Display + Trigger)

struct ModelSelectorRow: View {
    let provider: AIProvider
    let model: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ProviderLogoView(provider: provider, size: 16)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(model.isEmpty ? provider.defaultModel : model)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Text("Change")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model Selection Popover (Two-Column Layout)

struct ModelSelectionPopover: View {
    @Binding var isPresented: Bool
    let currentProvider: AIProvider
    let currentModel: String
    let onSelect: (AIProvider, String) -> Void
    
    @StateObject private var modelCatalog = ModelCatalog.shared
    
    @State private var selectedProvider: AIProvider = .openAI
    @State private var selectedModel: String = ""
    @State private var searchText: String = ""
    @State private var showAllModels: Bool = false
    @State private var customModelText: String = ""
    @State private var showCustomInput: Bool = false
    @State private var showFreeOnly: Bool = false
    
    private var availableProviders: [AIProvider] {
        AIProvider.allCases.filter { $0.isAvailable }
    }
    
    private var filteredProviders: [AIProvider] {
        if searchText.isEmpty {
            return availableProviders
        }
        return availableProviders.filter { provider in
            provider.displayName.localizedCaseInsensitiveContains(searchText) ||
            getModelsForProvider(provider).contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private var modelsForSelectedProvider: [String] {
        var models = getModelsForProvider(selectedProvider)

        // Filter free models for OpenRouter if toggled
        if showFreeOnly && selectedProvider == .openRouter {
            let catalogModels = modelCatalog.cachedModels(for: selectedProvider)
            let freeIds = Set(catalogModels.filter { $0.isFree }.map { $0.id })
            models = models.filter { freeIds.contains($0) }
        }

        if !searchText.isEmpty {
            models = models.filter { $0.localizedCaseInsensitiveContains(searchText) }
        }
        return showAllModels || !searchText.isEmpty ? models : Array(models.prefix(10))
    }

    /// Returns whether a model ID is free (for badge display)
    private func isModelFree(_ modelId: String) -> Bool {
        let catalogModels = modelCatalog.cachedModels(for: selectedProvider)
        return catalogModels.first(where: { $0.id == modelId })?.isFree ?? false
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            twoColumnContent
            Divider()
            footer
        }
        .frame(width: 500, height: 420)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            selectedProvider = currentProvider
            selectedModel = currentModel
            Task {
                await modelCatalog.refresh(provider: currentProvider)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
            
            TextField("Search providers or models...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Two Column Content
    
    private var twoColumnContent: some View {
        HStack(spacing: 0) {
            providerList
            
            Divider()
            
            modelList
        }
    }
    
    private var providerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROVIDER")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredProviders, id: \.self) { provider in
                        providerRow(provider)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 160)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
    
    private func providerRow(_ provider: AIProvider) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedProvider = provider
                showCustomInput = false
            }
            Task {
                await modelCatalog.refresh(provider: provider)
            }
        } label: {
            HStack(spacing: 8) {
                ProviderLogoView(provider: provider, size: 12)
                    .foregroundColor(selectedProvider == provider ? .white : .accentColor)
                    .frame(width: 16)
                
                Text(provider.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(selectedProvider == provider ? .white : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                if provider == currentProvider {
                    Circle()
                        .fill(selectedProvider == provider ? Color.white.opacity(0.8) : Color.green)
                        .frame(width: 6, height: 6)
                }
                
                if modelCatalog.isFetching[provider] ?? false {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedProvider == provider ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var modelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("MODEL")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if selectedProvider == .openRouter {
                    HStack(spacing: 4) {
                        Text("Free")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Toggle("", isOn: $showFreeOnly)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    .fixedSize()
                    .help("Show only free models")
                }

                Button {
                    Task {
                        await modelCatalog.refresh(provider: selectedProvider, force: true)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                        Text("Refresh")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(modelCatalog.isFetching[selectedProvider] ?? false)
                .help("Refresh model list from provider")
                
                if getModelsForProvider(selectedProvider).count > 10 {
                    Button {
                        showAllModels.toggle()
                    } label: {
                        Text(showAllModels ? "Show Less" : "Show All")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    if let error = modelCatalog.lastError[selectedProvider] as? Error {
                        errorView(error)
                    }
                    
                    if modelCatalog.usingFallback[selectedProvider] ?? false {
                        fallbackWarningView
                    }
                    
                    ForEach(modelsForSelectedProvider, id: \.self) { model in
                        modelRow(model)
                    }
                    
                    if !showCustomInput {
                        customModelButton
                    } else {
                        customModelInput
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func modelRow(_ model: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.1)) {
                selectedModel = model
                showCustomInput = false
            }
        } label: {
            HStack(spacing: 8) {
                Text(model)
                    .font(.system(size: 12))
                    .foregroundColor(selectedModel == model ? .white : .primary)
                    .lineLimit(1)

                if selectedProvider == .openRouter && isModelFree(model) {
                    Text("Free")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(selectedModel == model ? .white : .green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(selectedModel == model ? Color.white.opacity(0.2) : Color.green.opacity(0.15))
                        )
                }

                Spacer()

                if model == selectedProvider.defaultModel {
                    Text("Default")
                        .font(.system(size: 9))
                        .foregroundColor(selectedModel == model ? .white.opacity(0.8) : .secondary)
                }

                if model == currentModel && selectedProvider == currentProvider {
                    Text("Current")
                        .font(.system(size: 9))
                        .foregroundColor(selectedModel == model ? .white.opacity(0.8) : .green)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedModel == model ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func errorView(_ error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 12))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Fetch Failed")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                Text(error.localizedDescription)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .cornerRadius(6)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    private var fallbackWarningView: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))
            
            Text("Using offline model list")
                .font(.system(size: 11))
                .foregroundColor(.orange)
            
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    private var customModelButton: some View {
        Button {
            showCustomInput = true
            customModelText = ""
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("Use custom model ID...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var customModelInput: some View {
        HStack(spacing: 6) {
            TextField("model-id", text: $customModelText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(4)
            
            Button("Use") {
                if !customModelText.isEmpty {
                    selectedModel = customModelText
                    showCustomInput = false
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(customModelText.isEmpty)
            
            Button {
                showCustomInput = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            if !selectedModel.isEmpty {
                HStack(spacing: 6) {
                    ProviderLogoView(provider: selectedProvider, size: 12)
                    Text("\(selectedProvider.displayName) / \(selectedModel)")
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            } else {
                Text("Select a model")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.escape, modifiers: [])
            
            Button("Select") {
                onSelect(selectedProvider, selectedModel)
                isPresented = false
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
            .disabled(selectedModel.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - Helpers
    
    private func getModelsForProvider(_ provider: AIProvider) -> [String] {
        let catalogModels = modelCatalog.cachedModels(for: provider)
        if !catalogModels.isEmpty {
            return catalogModels.map { $0.id }
        }
        return provider.recommendedModels
    }
}

// MARK: - Preview

#Preview {
    ModelSelectionPopover(
        isPresented: .constant(true),
        currentProvider: .openAI,
        currentModel: "gpt-4o",
        onSelect: { _, _ in }
    )
}

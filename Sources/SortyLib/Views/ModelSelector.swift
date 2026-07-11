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

private struct ModelSelectionTriggerBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

extension View {
    func modelSelectorTriggerBounds() -> some View {
        anchorPreference(key: ModelSelectionTriggerBoundsPreferenceKey.self, value: .bounds) { $0 }
    }

    func modelSelectionOverlay(
        isPresented: Binding<Bool>,
        currentProvider: AIProvider,
        currentModel: String,
        contextMessage: String? = nil,
        selectionActionTitle: String = "Select",
        isSelectionActionProminent: Bool = true,
        onSelect: @escaping (AIProvider, String) -> Void
    ) -> some View {
        modifier(
            ModelSelectionOverlayModifier(
                isPresented: isPresented,
                currentProvider: currentProvider,
                currentModel: currentModel,
                contextMessage: contextMessage,
                selectionActionTitle: selectionActionTitle,
                isSelectionActionProminent: isSelectionActionProminent,
                onSelect: onSelect
            )
        )
    }
}

// MARK: - Model Selection Popover (Two-Column Layout)

struct ModelSelectionPopover: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPresented: Bool
    let currentProvider: AIProvider
    let currentModel: String
    let contextMessage: String?
    let selectionActionTitle: String
    let isSelectionActionProminent: Bool
    let popoverSize: CGSize
    let onSelect: (AIProvider, String) -> Void

    private let cornerRadius: CGFloat = 12
    
    @StateObject private var modelCatalog = ModelCatalog.shared
    
    @State private var selectedProvider: AIProvider = .openAI
    @State private var selectedModel: String = ""
    @State private var searchText: String = ""
    @State private var showAllModels: Bool = false
    @State private var customModelText: String = ""
    @State private var showCustomInput: Bool = false
    @State private var showFreeOnly: Bool = false
    @State private var showCodexOnly: Bool = false

    init(
        isPresented: Binding<Bool>,
        currentProvider: AIProvider,
        currentModel: String,
        contextMessage: String? = nil,
        selectionActionTitle: String = "Select",
        isSelectionActionProminent: Bool = true,
        popoverSize: CGSize = CGSize(width: 500, height: 420),
        onSelect: @escaping (AIProvider, String) -> Void
    ) {
        self._isPresented = isPresented
        self.currentProvider = currentProvider
        self.currentModel = currentModel
        self.contextMessage = contextMessage
        self.selectionActionTitle = selectionActionTitle
        self.isSelectionActionProminent = isSelectionActionProminent
        self.popoverSize = popoverSize
        self.onSelect = onSelect
    }
    
    private var availableProviders: [AIProvider] {
        AIProvider.userSelectableProviders.filter { $0.isAvailable }
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

        // Filter Codex (subscription) models for OpenAI if toggled
        if showCodexOnly && selectedProvider == .openAI {
            models = models.filter { isCodexModel($0) }
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

    /// Returns whether a model ID belongs to OpenAI's Codex (subscription) line
    private func isCodexModel(_ modelId: String) -> Bool {
        modelId.localizedCaseInsensitiveContains("codex")
    }

    /// Returns whether a model supports vision (for badge display)
    private func isVisionModel(_ modelId: String) -> Bool {
        modelCatalog.supportsVision(modelId: modelId, provider: selectedProvider)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let contextMessage, !contextMessage.isEmpty {
                contextMessageView(message: contextMessage)
                Divider()
            }
            twoColumnContent
            Divider()
            footer
        }
        .frame(width: popoverSize.width, height: popoverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .modifier(ModelSelectionPopoverGlassModifier(cornerRadius: cornerRadius))
        .onAppear {
            selectedProvider = currentProvider
            selectedModel = currentModel
            Task {
                await modelCatalog.refresh(provider: currentProvider)
            }
        }
    }

    private func contextMessageView(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.accentColor)
                .font(.system(size: 12))

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SortyDesignSystem.Colors.resolvedAccent.opacity(0.05))
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
        .background(chromeBackground)
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
        .background(sidebarBackground)
    }
    
    private func providerRow(_ provider: AIProvider) -> some View {
        Button {
            HapticFeedbackManager.shared.selection()
            withAnimation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.35, dampingFraction: 0.5)
            ) {
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
                    SortyGradientCircularLoader(size: 9, lineWidth: 1.8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedProvider == provider ? SortyDesignSystem.Colors.resolvedAccent : Color.clear)
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

                if selectedProvider == .openAI {
                    HStack(spacing: 4) {
                        Text("Codex")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Toggle("", isOn: $showCodexOnly)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                    }
                    .fixedSize()
                    .help("Show only Codex (ChatGPT subscription) models")
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
                            .transition(modelRowTransition)
                    }
                    
                    if !showCustomInput {
                        customModelButton
                    } else {
                        customModelInput
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .animation(modelListAnimation, value: modelsForSelectedProvider)
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

                if isVisionModel(model) {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Vision")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(selectedModel == model ? .white : .teal)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(selectedModel == model ? Color.white.opacity(0.2) : Color.teal.opacity(0.15))
                    )
                }

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

                if selectedProvider == .openAI && isCodexModel(model) {
                    Text("Codex")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(selectedModel == model ? .white : .purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(selectedModel == model ? Color.white.opacity(0.2) : Color.purple.opacity(0.15))
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
                    .fill(selectedModel == model ? SortyDesignSystem.Colors.resolvedAccent : Color.clear)
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
                .background(customFieldBackground)
            
            Button("Use") {
                if !customModelText.isEmpty {
                    selectedModel = customModelText
                    showCustomInput = false
                }
            }
            .buttonStyle(.sortyBordered)
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
            
            Button(selectionActionTitle) {
                onSelect(selectedProvider, selectedModel)
                isPresented = false
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(selectionActionButtonStyle)
            .disabled(selectedModel.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(chromeBackground)
    }

    private var selectionActionButtonStyle: SortyStandardButtonStyle {
        isSelectionActionProminent ? .sortyProminent : .sortyBordered(intent: .primary)
    }

    @ViewBuilder
    private var chromeBackground: some View {
        if #available(macOS 26.0, *) {
            Color.white.opacity(0.02)
        } else {
            LinearGradient(
                colors: [
                    Color.primary.opacity(0.05),
                    Color.primary.opacity(0.015)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if #available(macOS 26.0, *) {
            Color.white.opacity(0.015)
        } else {
            LinearGradient(
                colors: [
                    SortyDesignSystem.Colors.resolvedAccent.opacity(0.08),
                    Color.primary.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var customFieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
    
    // MARK: - Helpers
    
    private func getModelsForProvider(_ provider: AIProvider) -> [String] {
        let catalogModels = modelCatalog.cachedModels(for: provider)
        if !catalogModels.isEmpty {
            return catalogModels.map { $0.id }
        }
        return provider.recommendedModels
    }

    private var modelListAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.35, dampingFraction: 0.5)
    }

    private var modelRowTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.96, anchor: .top))
                .combined(with: .offset(y: 5)),
            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
        )
    }
}

private struct ModelSelectionPopoverGlassModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fallbackSurfaceFill)
            }
            .systemLiquidGlassBackground(cornerRadius: cornerRadius)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.1), radius: 14, y: 8)
            .presentationCornerRadius(cornerRadius)
    }

    private var fallbackSurfaceFill: AnyShapeStyle {
        if #available(macOS 26.0, *) {
            return AnyShapeStyle(Color.clear)
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color(nsColor: .controlBackgroundColor)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

private struct ModelSelectionOverlayModifier: ViewModifier {
    @Binding var isPresented: Bool
    let currentProvider: AIProvider
    let currentModel: String
    let contextMessage: String?
    let selectionActionTitle: String
    let isSelectionActionProminent: Bool
    let onSelect: (AIProvider, String) -> Void

    private let contentPadding: CGFloat = 12
    private let verticalSpacing: CGFloat = 12
    private let idealPopoverSize = CGSize(width: 500, height: 420)
    private let minimumUsableHostSize = CGSize(width: 420, height: 320)

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(ModelSelectionTriggerBoundsPreferenceKey.self) { anchor in
                GeometryReader { proxy in
                    if isPresented {
                        let frame = anchor.map { proxy[$0] }
                        let popoverSize = resolvedPopoverSize(in: proxy.size)

                        ZStack(alignment: .topLeading) {
                            Color.black
                                .opacity(0.05)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isPresented = false
                                }

                            ModelSelectionPopover(
                                isPresented: $isPresented,
                                currentProvider: currentProvider,
                                currentModel: currentModel,
                                contextMessage: contextMessage,
                                selectionActionTitle: selectionActionTitle,
                                isSelectionActionProminent: isSelectionActionProminent,
                                popoverSize: popoverSize,
                                onSelect: onSelect
                            )
                            .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
                            .offset(x: resolvedX(for: frame, popoverSize: popoverSize, in: proxy.size), y: resolvedY(for: frame, popoverSize: popoverSize, in: proxy.size))
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                        }
                        .zIndex(1000)
                    }
                }
            }
    }

    private func resolvedPopoverSize(in containerSize: CGSize) -> CGSize {
        let hostAvailableWidth = max(0, containerSize.width - (contentPadding * 2))
        let hostAvailableHeight = max(0, containerSize.height - (contentPadding * 2))

        let hostCanFitPopoverComfortably = hostAvailableWidth >= minimumUsableHostSize.width && hostAvailableHeight >= minimumUsableHostSize.height

        if hostCanFitPopoverComfortably {
            return CGSize(
                width: min(idealPopoverSize.width, hostAvailableWidth),
                height: min(idealPopoverSize.height, hostAvailableHeight)
            )
        }

        // Fallback to screen bounds so compact hosts (like history cards) don't collapse the selector UI.
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let screenAvailableWidth = max(0, screenFrame.width - (contentPadding * 2))
        let screenAvailableHeight = max(0, screenFrame.height - (contentPadding * 2))

        return CGSize(
            width: min(idealPopoverSize.width, screenAvailableWidth > 0 ? screenAvailableWidth : hostAvailableWidth),
            height: min(idealPopoverSize.height, screenAvailableHeight > 0 ? screenAvailableHeight : hostAvailableHeight)
        )
    }

    private func resolvedX(for frame: CGRect?, popoverSize: CGSize, in containerSize: CGSize) -> CGFloat {
        guard let frame else {
            return max(contentPadding, (containerSize.width - popoverSize.width) / 2)
        }

        let preferredX = frame.maxX - popoverSize.width
        let maxX = max(contentPadding, containerSize.width - popoverSize.width - contentPadding)
        return min(max(preferredX, contentPadding), maxX)
    }

    private func resolvedY(for frame: CGRect?, popoverSize: CGSize, in containerSize: CGSize) -> CGFloat {
        guard let frame else {
            return max(contentPadding, (containerSize.height - popoverSize.height) / 2)
        }

        let belowY = frame.maxY + verticalSpacing
        let maxY = containerSize.height - popoverSize.height - contentPadding

        if belowY <= maxY {
            return belowY
        }

        return max(frame.minY - popoverSize.height - verticalSpacing, contentPadding)
    }

}

// MARK: - Preview

#Preview {
    ModelSelectionPopover(
        isPresented: .constant(true),
        currentProvider: .openAI,
        currentModel: "gpt-4o",
        contextMessage: nil,
        selectionActionTitle: "Select",
        onSelect: { _, _ in }
    )
}

//
//  OrganizeView.swift
//  Sorty
//
//  Main organization workflow view with improved layout
//  Enhanced with micro-animations, haptic feedback, and state transitions
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OrganizeView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var customPersonaStore: CustomPersonaStore

    @State private var previousState: OrganizationState?

    var body: some View {
        VStack(spacing: 0) {
            // Header with selected directory
            if let directory = appState.selectedDirectory {
                DirectoryHeader(
                    url: directory,
                    onBack: {
                        HapticFeedbackManager.shared.tap()
                        withAnimation(.pageTransition) {
                            if organizer.state == .ready {
                                organizer.cancel()
                            } else {
                                appState.selectedDirectory = nil
                                organizer.reset()
                            }
                        }
                    },
                    onClear: {
                        HapticFeedbackManager.shared.tap()
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.message = "Select a directory to organize"
                        panel.prompt = "Select"
                        if panel.runModal() == .OK, let url = panel.url {
                            withAnimation(.pageTransition) {
                                organizer.reset()
                                appState.selectedDirectory = url
                            }
                            HapticFeedbackManager.shared.success()
                        }
                    }
                )
                .transition(TransitionStyles.slideFromBottom)
            }

            // Main content area with animated transitions
            ZStack {
                if appState.selectedDirectory == nil {
                    DirectorySelectionView(selectedDirectory: $appState.selectedDirectory)
                        .transition(TransitionStyles.scaleAndFade)
                } else {
                    stateContent
                        .id(stateIdentifier)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .scale(scale: 1.02).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stateIdentifier)
        }
        .navigationTitle("Organize Files")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if organizer.state == .ready {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        Task {
                            try? await organizer.regeneratePreview()
                        }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .help("Regenerate organization plan with current settings")
                    .accessibilityLabel("Regenerate organization plan")
                    .accessibilityHint("Use when you want different AI suggestions")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Organization workflow")
        .accessibilityHint("Select a folder and configure options")
        .onAppear {
            configureOrganizer()
        }
        .onChange(of: settingsViewModel.config.provider) { oldValue, newValue in
            configureOrganizer()
        }
        .onChange(of: organizer.state) { oldValue, newValue in
            handleStateChange(to: newValue)
        }
        .onChange(of: appState.selectedDirectory) { oldValue, newValue in
            // Prewarm AI connection when user selects a folder
            if newValue != nil {
                Task {
                    await prewarmAIConnection()
                }
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        stateContentInner
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }
    
    @ViewBuilder
    private var stateContentInner: some View {
        switch organizer.state {
        case .idle:
            ReadyToOrganizeView(onStart: startOrganization)
        case .scanning:
            AnalysisView()
        case .organizing:
            AnalysisView()
        case .ready:
            if let plan = organizer.currentPlan {
                PreviewView(plan: plan, baseURL: appState.selectedDirectory!)
            } else {
                SortyGradientLoadingBar(width: 180, height: 10)
            }
        case .applying:
            AnalysisView()
        case .completed:
            if let plan = organizer.currentPlan {
                OrganizationCompleteView(
                    stats: plan.generationStats,
                    totalFiles: plan.suggestions.reduce(0) { $0 + $1.totalFileCount },
                    totalFolders: plan.suggestions.count,
                    directoryURL: appState.selectedDirectory!
                )
            } else {
                OrganizationCompleteView(
                    stats: nil,
                    totalFiles: 0,
                    totalFolders: 0,
                    directoryURL: appState.selectedDirectory ?? URL(fileURLWithPath: "/")
                )
            }
        case .error(let error):
            ErrorView(error: error) {
                HapticFeedbackManager.shared.tap()
                withAnimation(.pageTransition) {
                    organizer.reset()
                }
            }
        }
    }

    private var stateIdentifier: String {
        // Group states that show the same view to avoid unnecessary subtree rebuilds
        switch organizer.state {
        case .idle: return "idle"
        case .scanning, .organizing, .applying: return "active"
        case .ready: return "ready"
        case .completed: return "completed"
        case .error: return "error"
        }
    }

    private func handleStateChange(to newState: OrganizationState) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch newState {
            case .completed:
                HapticFeedbackManager.shared.success()
            case .error:
                HapticFeedbackManager.shared.error()
            case .ready:
                HapticFeedbackManager.shared.success()
            case .scanning, .organizing:
                HapticFeedbackManager.shared.selection()
            default:
                break
            }
        }
    }

    private func configureOrganizer() {
        Task {
            do {
                try await organizer.configure(with: settingsViewModel.config)
            } catch {
                organizer.state = .error(error)
            }
        }
    }

    private func startOrganization() {
        guard let directory = appState.selectedDirectory else { return }

        HapticFeedbackManager.shared.tap()

        // Apply default steering prompt if no custom instructions provided
        if organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultPrompt = SteeringPromptManager.shared.defaultPrompt {
            organizer.customInstructions = defaultPrompt.prompt
        }

        Task {
            do {
                try await organizer.organize(directory: directory)
            } catch {
                organizer.state = .error(error)
            }
        }
    }
    
    private func prewarmAIConnection() async {
        let provider = settingsViewModel.config.provider
        let config = settingsViewModel.config
        await AISessionManager.shared.prewarm(provider: provider, config: config)
    }
}

// MARK: - Directory Header

struct DirectoryHeader: View {
    let url: URL
    let onBack: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GlassyBackButton(action: onBack)
                .padding(.trailing, 4)

            FolderThumbnailView(url: url, size: CGSize(width: 32, height: 32))

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.headline)
                PrivacySensitivePathText(path: url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            CompactPersonaPicker()
                .padding(.trailing, 8)

            Button("Change Folder", action: onClear)
                .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Ready to Organize View

struct ReadyToOrganizeView: View {
    let onStart: () -> Void
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var automationManager: AutomationManager
    @StateObject private var sessionManager = AISessionManager.shared
    @StateObject private var steeringManager = SteeringPromptManager.shared
    @State private var hasAppeared = false
    @State private var isTextFieldFocused = false
    @State private var showStorageLocations = false
    @State private var showingFolderPicker = false
    @State private var suggestedLocationName: String? = nil
    @State private var addStorageLocationErrorMessage: String?
    @State private var showSavePromptDialog = false
    @State private var savePromptName = ""
    @State private var isImprovingPrompt = false
    @State private var showSavedPromptsSheet = false
    @FocusState private var textFieldFocus: Bool
    
    private var isConnecting: Bool {
        sessionManager.prewarmingProvider != nil
    }

    var body: some View {
        WorkflowContainer(currentStep: .configure) {
            // Compact header
            VStack(spacing: 16) {
                iconSection
                VStack(spacing: 6) {
                    Text("Ready to Organize")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("AI will analyze your files and suggest an organized folder structure")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
            
            // Instructions card
            WorkflowCard(title: "Instructions", icon: "text.bubble") {
                instructionsContent
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
            
            // Storage locations card
            WorkflowCard(title: "Storage Locations", icon: "externaldrive") {
                storageLocationsContent
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
            
            // Start button - full width
            Button {
                HapticFeedbackManager.shared.tap()
                onStart()
            } label: {
                HStack(spacing: 8) {
                    if isConnecting {
                        SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                            .frame(width: 12, height: 12)
                        Text("Connecting...")
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                        Text("Start Organization")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(isConnecting)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
            .help(isConnecting ? "Connecting to AI provider. Start is enabled when connection is ready." : "Start organizing files using your current settings")
            .accessibilityIdentifier("StartOrganizationButton")
            .accessibilityLabel(isConnecting ? "Connecting to provider" : "Start organization")
            .accessibilityHint(isConnecting ? "Please wait until connection completes" : "Press Enter to start")
            .accessibilityValue(isConnecting ? "Connecting" : "Ready")
            .accessibilityAddTraits(.isButton)

            // Keyboard shortcut hint
            HStack(spacing: 4) {
                Text("⏎")
                    .font(.caption2)
                    .fontWeight(.medium)
                Text(isConnecting ? "Waiting..." : "Start")
                    .font(.caption2)
            }
            .foregroundStyle(.quaternary)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.45), value: hasAppeared)
            
            // Connection status indicator
            connectionStatusView
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: hasAppeared)

        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    HapticFeedbackManager.shared.success()
                    do {
                        try storageLocationsManager.addLocation(url: url, customName: suggestedLocationName)
                    } catch {
                        HapticFeedbackManager.shared.error()
                        addStorageLocationErrorMessage = error.localizedDescription
                    }
                }
            case .failure(let error):
                HapticFeedbackManager.shared.error()
                addStorageLocationErrorMessage = error.localizedDescription
            }
            suggestedLocationName = nil
        }
        .alert(
            "Couldn't Add Storage Location",
            isPresented: Binding(
                get: { addStorageLocationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        addStorageLocationErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                addStorageLocationErrorMessage = nil
            }
        } message: {
            Text(addStorageLocationErrorMessage ?? "Please try selecting the folder again.")
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
        }
    }
    
    private var storageLocationsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Collapsible toggle header
            Button {
                HapticFeedbackManager.shared.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showStorageLocations.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if !storageLocationsManager.enabledLocations.isEmpty {
                        Text("\(storageLocationsManager.enabledLocations.count) active")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                    } else {
                        Text("No locations configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: showStorageLocations ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showStorageLocations ? "Hide storage destination locations" : "Show storage destination locations")
            .accessibilityHint("Expand to manage folders files can move into")
            
            if showStorageLocations {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Files can be moved to these destination folders during organization")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if !storageLocationsManager.locations.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(storageLocationsManager.locations.prefix(3)) { location in
                                CompactStorageLocationRow(location: location)
                            }
                            
                            if storageLocationsManager.locations.count > 3 {
                                Text("+ \(storageLocationsManager.locations.count - 3) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    
                    // Quick add suggestions
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quick add:")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        
                        HStack(spacing: 8) {
                            StorageSuggestionPill(name: "Archives", icon: "archivebox") {
                                suggestedLocationName = "Archives"
                                showingFolderPicker = true
                            }
                            StorageSuggestionPill(name: "Projects", icon: "folder.badge.gearshape") {
                                suggestedLocationName = "Projects"
                                showingFolderPicker = true
                            }
                            StorageSuggestionPill(name: "Backups", icon: "externaldrive") {
                                suggestedLocationName = "Backups"
                                showingFolderPicker = true
                            }
                        }
                    }
                    
                    HStack {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            suggestedLocationName = nil
                            showingFolderPicker = true
                        } label: {
                            Label("Add Custom Location", systemImage: "plus")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Add a folder that Sorty can use as a destination")
                        .accessibilityHint("Opens folder picker to add a destination location")
                        
                        Spacer()
                        
                        Text("More in Settings")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
    }
    
    private var iconSection: some View {
        ZStack {
            Circle()
                .fill(Color.teal.opacity(0.12))
                .frame(width: 80, height: 80)
            
            if let mascotHead = SortyResources.image(named: "SortyMascotHead") {
                Image(nsImage: mascotHead)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            } else {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.teal)
            }
        }
    }
    
    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 6) {
            if sessionManager.prewarmingProvider != nil {
                SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    .frame(width: 12, height: 12)
                Text("Connecting to \(settingsViewModel.config.provider.displayName)...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if sessionManager.isPrewarmed {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text("Connected to \(settingsViewModel.config.provider.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let error = sessionManager.prewarmError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Connection warning: \(error.prefix(40))...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 16)
        .help("Current AI connection state")
        .accessibilityLabel("Connection status")
        .accessibilityHint("Shows whether Sorty can reach the selected AI provider")
    }
    
    private var instructionsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if organizer.customInstructions.isEmpty {
                    Text("e.g. \"Group by project\", \"Separate RAW photos\", \"Keep documents by year\"...")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }

                if isImprovingPrompt {
                    HStack {
                        Spacer()
                        SortyGradientCircularLoader(size: 13, lineWidth: 2.4)
                        Text("Improving...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    SubmittableTextEditor(text: $organizer.customInstructions) {
                        onStart()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 60, maxHeight: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .accessibilityIdentifier("CustomInstructionsTextField")
            .accessibilityLabel("Additional instructions for organization")
            .accessibilityHint("Press Command+Enter to start organization, Enter for new line")

            HStack(spacing: 8) {
                // Improve with AI button
                if !organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await improvePromptWithAI() }
                    } label: {
                        Label("Improve", systemImage: "wand.and.stars")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.teal)
                    .disabled(isImprovingPrompt)
                    .help("Improve instructions with AI")
                    .accessibilityHint("Rewrites your prompt to be clearer and more specific")
                }

                // Save prompt button
                if !organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        savePromptName = ""
                        showSavePromptDialog.toggle()
                    } label: {
                        Label("Save", systemImage: "bookmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .help("Save current instructions for reuse")
                    .accessibilityHint("Stores this prompt in your saved prompts list")
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
                                        prompt: organizer.customInstructions
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

                // Manage saved prompts button
                Button {
                    showSavedPromptsSheet.toggle()
                } label: {
                    Label(
                        steeringManager.prompts.isEmpty ? "Saved Prompts" : "Saved Prompts (\(steeringManager.prompts.count))",
                        systemImage: "text.alignleft"
                    )
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("Open your saved instruction prompts")
                .accessibilityHint("View, edit, and apply saved prompts")
            }
            .font(.caption2)
            .foregroundStyle(.quaternary)
        }
        .sheet(isPresented: $showSavedPromptsSheet) {
            SavedPromptsSheet(
                steeringManager: steeringManager,
                settingsConfig: settingsViewModel.config,
                onApplyPrompt: { prompt in
                    organizer.customInstructions = prompt
                    showSavedPromptsSheet = false
                    HapticFeedbackManager.shared.tap()
                }
            )
        }
    }

    private func improvePromptWithAI() async {
        let original = organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        isImprovingPrompt = true
        defer { isImprovingPrompt = false }

        do {
            let client = try AIClientFactory.createClient(config: settingsViewModel.config)
            let improved = try await client.generateText(
                prompt: "Improve the following file organization instructions to be clearer, more specific, and more actionable for an AI file organizer. Keep the same intent but make it more precise. Return only the improved instructions text, nothing else.\n\nOriginal instructions: \"\(original)\"",
                systemPrompt: "You are a file organization expert. You help users write better instructions for organizing their files and folders. Be concise and practical."
            )
            let trimmed = improved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                organizer.customInstructions = trimmed
                HapticFeedbackManager.shared.success()
            }
        } catch {
            HapticFeedbackManager.shared.error()
        }
    }
}

// MARK: - Saved Prompts Sheet

struct SavedPromptsSheet: View {
    @ObservedObject var steeringManager: SteeringPromptManager
    let settingsConfig: AIConfig
    let onApplyPrompt: (String) -> Void

    @State private var editingPromptId: UUID? = nil
    @State private var editName = ""
    @State private var editText = ""
    @State private var improvingPromptId: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Saved Prompts")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            if steeringManager.prompts.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No saved prompts yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Save your instructions from the organize view to reuse them.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(steeringManager.prompts) { prompt in
                            savedPromptCard(prompt)
                        }
                    }
                    .padding(20)
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Add New Prompt") {
                    let newPrompt = SavedSteeringPrompt(name: "New Prompt", prompt: "")
                    steeringManager.addPrompt(newPrompt)
                    editingPromptId = newPrompt.id
                    editName = newPrompt.name
                    editText = newPrompt.prompt
                    HapticFeedbackManager.shared.tap()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
        }
        .frame(width: 520, height: 500)
    }

    @ViewBuilder
    private func savedPromptCard(_ prompt: SavedSteeringPrompt) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if editingPromptId == prompt.id {
                // Editing mode
                TextField("Prompt name", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline.weight(.medium))

                TextEditor(text: $editText)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )

                HStack(spacing: 8) {
                    // Improve with AI button
                    Button {
                        Task { await improveEditingPrompt(prompt) }
                    } label: {
                        if improvingPromptId == prompt.id {
                            SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                        } else {
                            Label("Improve with AI", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(editText.trimmingCharacters(in: .whitespaces).isEmpty || improvingPromptId == prompt.id)

                    Spacer()

                    Button("Cancel") {
                        editingPromptId = nil
                    }
                    .controlSize(.small)

                    Button("Save") {
                        var updated = prompt
                        updated.name = editName.isEmpty ? "Untitled" : editName
                        updated.prompt = editText
                        steeringManager.updatePrompt(updated)
                        editingPromptId = nil
                        HapticFeedbackManager.shared.success()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                // Display mode
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(prompt.name)
                                .font(.subheadline.weight(.semibold))
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
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Use") {
                        onApplyPrompt(prompt.prompt)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Edit") {
                        editingPromptId = prompt.id
                        editName = prompt.name
                        editText = prompt.prompt
                    }
                    .controlSize(.small)

                    Button(prompt.isDefault ? "Unset Default" : "Set Default") {
                        if prompt.isDefault {
                            steeringManager.clearDefault()
                        } else {
                            steeringManager.setDefault(id: prompt.id)
                        }
                        HapticFeedbackManager.shared.selection()
                    }
                    .controlSize(.small)

                    Spacer()

                    Button(role: .destructive) {
                        steeringManager.deletePrompt(id: prompt.id)
                        HapticFeedbackManager.shared.tap()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }

    private func improveEditingPrompt(_ prompt: SavedSteeringPrompt) async {
        let original = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }
        improvingPromptId = prompt.id
        defer { improvingPromptId = nil }

        do {
            let client = try AIClientFactory.createClient(config: settingsConfig)
            let improved = try await client.generateText(
                prompt: "Improve the following file organization instructions to be clearer, more specific, and more actionable for an AI file organizer. Keep the same intent but make it more precise. Return only the improved instructions text, nothing else.\n\nOriginal instructions: \"\(original)\"",
                systemPrompt: "You are a file organization expert. You help users write better instructions for organizing their files and folders. Be concise and practical."
            )
            let trimmed = improved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                editText = trimmed
                HapticFeedbackManager.shared.success()
            }
        } catch {
            HapticFeedbackManager.shared.error()
        }
    }
}

// MARK: - Compact Storage Location Row

struct CompactStorageLocationRow: View {
    let location: StorageLocation
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 14))
                .foregroundStyle(location.isEnabled ? .teal : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(location.isEnabled ? .primary : .secondary)
                
                PrivacySensitivePathText(path: location.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { location.isEnabled },
                set: { _ in
                    HapticFeedbackManager.shared.selection()
                    storageLocationsManager.toggleEnabled(for: location)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    let onRetry: () -> Void
    
    @EnvironmentObject private var appState: AppState
    
    private enum ErrorCategory {
        case apiKey
        case network
        case permissions
        case generic
    }
    
    private var category: ErrorCategory {
        let description = error.localizedDescription.lowercased()
        if description.contains("api key") || description.contains("unauthorized") || description.contains("authentication") {
            return .apiKey
        }
        if description.contains("network") || description.contains("internet") || description.contains("offline") || description.contains("timeout") {
            return .network
        }
        if description.contains("permission") || description.contains("access") || description.contains("sandbox") {
            return .permissions
        }
        return .generic
    }
    
    private var errorIcon: String {
        switch category {
        case .apiKey:
            return "key.fill"
        case .network:
            return "wifi.exclamationmark"
        case .permissions:
            return "lock.trianglebadge.exclamationmark"
        case .generic:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var errorTitle: String {
        switch category {
        case .apiKey:
            return "AI Credentials Required"
        case .network:
            return "Connection Problem"
        case .permissions:
            return "Permission Required"
        case .generic:
            return "Something Went Wrong"
        }
    }
    
    private var recoveryText: String {
        switch category {
        case .apiKey:
            return "Check your provider and API key in Settings, then retry."
        case .network:
            return "Check your internet connection and provider availability, then retry."
        case .permissions:
            return "Grant file access for this folder and try again."
        case .generic:
            return "Try again. If this keeps happening, open Help & Support with the copied error details."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: errorIcon)
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text(errorTitle)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                
                Text(recoveryText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            HStack(spacing: 10) {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
                    .help("Retry the organization workflow")
                    .accessibilityHint("Attempts the last operation again")
                
                if category == .apiKey || category == .permissions {
                    Button("Open Settings") {
                        appState.selectedSettingsSection = category == .apiKey ? .provider : .troubleshooting
                        appState.navigatedFromSettings = true
                        appState.currentView = .settings
                    }
                    .buttonStyle(.bordered)
                    .help("Open Settings to resolve this issue")
                    .accessibilityHint("Navigates to relevant settings section")
                }
                
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error.localizedDescription, forType: .string)
                    HapticFeedbackManager.shared.selection()
                }
                .buttonStyle(.bordered)
                .help("Copy error details for support")
                .accessibilityHint("Copies this error message to clipboard")
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Custom Text Editor with Enter to Submit

/// A TextEditor that treats Cmd+Enter as submit and Enter as new line
struct SubmittableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak textView] event in
            guard let tv = textView, tv.window?.firstResponder === tv else { return event }
            
            let isReturn = event.keyCode == 36
            let hasCommand = event.modifierFlags.contains(.command)
            
            if isReturn && hasCommand {
                context.coordinator.onSubmit()
                return nil
            }
            
            return event
        }
        context.coordinator.eventMonitor = monitor
        
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
        
        context.coordinator.onSubmit = onSubmit
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var eventMonitor: Any?
        
        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }
        
        deinit {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

// MARK: - Previews

@MainActor
private enum OrganizePreviewObjects {
    static var idleOrganizer: FolderOrganizer {
        let organizer = FolderOrganizer()
        organizer.state = .idle
        return organizer
    }
    
    static var scanningOrganizer: FolderOrganizer {
        let organizer = FolderOrganizer()
        organizer.state = .scanning
        organizer.progress = 0.35
        organizer.organizationStage = "Scanning files..."
        return organizer
    }
    
    static var readyOrganizer: FolderOrganizer {
        let organizer = FolderOrganizer()
        organizer.state = .ready
        organizer.currentPlan = PreviewMocks.makeOrganizationPlan()
        return organizer
    }
    
    static var errorOrganizer: FolderOrganizer {
        let organizer = FolderOrganizer()
        organizer.state = .error(NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection failed. Please check your API key."]))
        return organizer
    }
    
    static var readyAppState: AppState {
        let state = AppState()
        state.hasCompletedOnboarding = true
        state.selectedDirectory = URL(fileURLWithPath: "/Users/user/Downloads")
        return state
    }
}

#Preview("Organize View - Idle") {
    OrganizeView()
        .environmentObject(OrganizePreviewObjects.idleOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(AppState.preview)
        .environmentObject(CustomPersonaStore.preview)
        .frame(width: 900, height: 600)
}

#Preview("Organize View - Scanning") {
    OrganizeView()
        .environmentObject(OrganizePreviewObjects.scanningOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(AppState.preview)
        .environmentObject(CustomPersonaStore.preview)
        .frame(width: 900, height: 600)
}

#Preview("Organize View - Ready") {
    OrganizeView()
        .environmentObject(OrganizePreviewObjects.readyOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(OrganizePreviewObjects.readyAppState)
        .environmentObject(CustomPersonaStore.preview)
        .environmentObject(LearningsManager.preview)
        .frame(width: 900, height: 700)
}

#Preview("Organize View - Error") {
    OrganizeView()
        .environmentObject(OrganizePreviewObjects.errorOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(AppState.preview)
        .environmentObject(CustomPersonaStore.preview)
        .frame(width: 900, height: 600)
}

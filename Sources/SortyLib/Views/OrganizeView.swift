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
                DirectoryHeader(url: directory) {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.pageTransition) {
                        appState.selectedDirectory = nil
                        organizer.reset()
                    }
                }
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
                        .transition(TransitionStyles.scaleAndFade)
                }
            }
            .animation(.pageTransition, value: stateIdentifier)
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
                ProgressView()
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
        switch organizer.state {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .organizing: return "organizing"
        case .ready: return "ready"
        case .applying: return "applying"
        case .completed: return "completed"
        case .error: return "error"
        }
    }

    private func handleStateChange(to newState: OrganizationState) {
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
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FolderThumbnailView(url: url, size: CGSize(width: 32, height: 32))

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.headline)
                Text(url.deletingLastPathComponent().path)
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
    @StateObject private var sessionManager = AISessionManager.shared
    @State private var hasAppeared = false
    @State private var isTextFieldFocused = false
    @State private var showStorageLocations = false
    @State private var showingFolderPicker = false
    @State private var suggestedLocationName: String? = nil
    @FocusState private var textFieldFocus: Bool

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
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("Start Organization")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
            .accessibilityIdentifier("StartOrganizationButton")
            .accessibilityLabel("Start organization")
            .accessibilityHint("Press Enter to start")
            .accessibilityAddTraits(.isButton)
            
            // Keyboard shortcut hint
            HStack(spacing: 4) {
                Text("⏎")
                    .font(.caption2)
                    .fontWeight(.medium)
                Text("Start")
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
                    }
                }
            case .failure:
                HapticFeedbackManager.shared.error()
            }
            suggestedLocationName = nil
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
                .fill(Color.purple.opacity(0.1))
                .frame(width: 80, height: 80)
            
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.purple)
        }
    }
    
    @ViewBuilder
    private var connectionStatusView: some View {
        HStack(spacing: 6) {
            if sessionManager.prewarmingProvider != nil {
                ProgressView()
                    .scaleEffect(0.6)
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
    }
    
    private var instructionsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if organizer.customInstructions.isEmpty {
                    Text("e.g. \"Group by project\", \"Separate RAW photos\", \"Keep documents by year\"...")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                
                SubmittableTextEditor(text: $organizer.customInstructions) {
                    onStart()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
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
            .accessibilityHint("Press Enter to start organization, Command+Enter for new line")
            
            HStack(spacing: 8) {
                Text("⏎ Send")
                Text("⌘⏎ New Line")
            }
            .font(.caption2)
            .foregroundStyle(.quaternary)
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
                .foregroundStyle(location.isEnabled ? .purple : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(location.isEnabled ? .primary : .secondary)
                
                Text(location.path)
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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Custom Text Editor with Enter to Submit

/// A TextEditor that treats Enter as submit and Cmd+Enter as new line
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
        
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // Only update if text changed externally
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
        
        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Handle Enter key (insertNewline:)
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Check if Command key is held using the current event
                let commandKeyPressed = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
                
                if commandKeyPressed {
                    // Cmd+Enter: Insert actual newline
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                } else {
                    // Enter without modifiers: Submit
                    onSubmit()
                    return true
                }
            }
            return false
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

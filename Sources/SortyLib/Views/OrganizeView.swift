//
//  OrganizeView.swift
//  Sorty
//
//  Main organization workflow view with improved layout
//  Enhanced with micro-animations, haptic feedback, and state transitions
//

import SwiftUI
import AppKit

struct OrganizeView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState

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
        .onAppear {
            configureOrganizer()
        }
        .onChange(of: settingsViewModel.config.provider) { oldValue, newValue in
            configureOrganizer()
        }
        .onChange(of: organizer.state) { oldValue, newValue in
            handleStateChange(to: newValue)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        Group {
            if case .idle = organizer.state {
                ReadyToOrganizeView(onStart: startOrganization)
            } else if case .scanning = organizer.state {
                AnalysisView()
            } else if case .organizing = organizer.state {
                AnalysisView()
            } else if case .ready = organizer.state, let plan = organizer.currentPlan {
                PreviewView(plan: plan, baseURL: appState.selectedDirectory!)
            } else if case .completed = organizer.state {
                OrganizationResultView()
            } else if case .error(let error) = organizer.state {
                ErrorView(error: error) {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.pageTransition) {
                        organizer.reset()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
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
}

// MARK: - Directory Header

struct DirectoryHeader: View {
    let url: URL
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)

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
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    @State private var hasAppeared = false
    @State private var isTextFieldFocused = false
    @State private var showStorageLocations = false
    @State private var showingFolderPicker = false
    @State private var suggestedLocationName: String? = nil
    @FocusState private var textFieldFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                iconSection
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                VStack(spacing: 8) {
                    Text("Ready to Organize")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("AI will analyze your files and suggest an organized folder structure")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 450)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                
                instructionsField
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                
                // Storage Locations Section
                storageLocationsSection
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: hasAppeared)

                Button {
                    HapticFeedbackManager.shared.tap()
                    onStart()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                        Text("Start Organization")
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
                .accessibilityIdentifier("StartOrganizationButton")
            }
            
            Spacer()
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
    
    private var storageLocationsSection: some View {
        VStack(spacing: 12) {
            // Toggle header
            Button {
                HapticFeedbackManager.shared.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showStorageLocations.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.plus")
                        .font(.system(size: 14))
                        .foregroundStyle(.purple)
                    
                    Text("Storage Locations")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if !storageLocationsManager.enabledLocations.isEmpty {
                        Text("\(storageLocationsManager.enabledLocations.count) active")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    Image(systemName: showStorageLocations ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: 450)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.05))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if showStorageLocations {
                VStack(spacing: 10) {
                    // Description
                    Text("Files can be moved to these destination folders during organization")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    
                    // Active locations preview
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
                        .frame(width: 400)
                    }
                    
                    // Quick add suggestions
                    VStack(spacing: 6) {
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
                    
                    // Add custom button
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
                    
                    // Link to settings
                    Text("Configure all locations in Settings → Storage Locations")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(width: 450)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
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
                .frame(width: 100, height: 100)
            
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.purple)
        }
    }
    
    private var instructionsField: some View {
        VStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Additional Instructions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .center, spacing: 6) {
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
                        // On Enter: Start organization
                        onStart()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .frame(minHeight: 60, maxHeight: 80)
                .frame(width: 450)
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
                
                VStack(spacing: 4) {
                    Text("These instructions will guide the AI in organizing your files")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "return")
                                .font(.system(size: 9, weight: .medium))
                            Text("Send")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                        )
                        
                        HStack(spacing: 4) {
                            Image(systemName: "command")
                                .font(.system(size: 9, weight: .medium))
                            Image(systemName: "return")
                                .font(.system(size: 9, weight: .medium))
                            Text("New Line")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
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

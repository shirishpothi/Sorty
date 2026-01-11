//
//  WatchedFoldersView.swift
//  Sorty
//
//  Modern watched folders management with rich folder cards and status indicators
//

import SwiftUI
import UniformTypeIdentifiers

struct WatchedFoldersView: View {
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var organizer: FolderOrganizer
    @State private var showingFolderPicker = false
    @State private var selectedFolderForEdit: WatchedFolder?
    @State private var contentOpacity: Double = 0
    
    // Check if AI is available
    private var isAIConfigured: Bool {
        organizer.aiClient != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()

            // Folder Grid/List
            ZStack {
                if watchedFoldersManager.folders.isEmpty {
                    EmptyWatchedFoldersView(onAddFolder: {
                        HapticFeedbackManager.shared.tap()
                        showingFolderPicker = true
                    })
                    .transition(TransitionStyles.scaleAndFade)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(watchedFoldersManager.folders.enumerated()), id: \.element.id) { index, folder in
                                WatchedFolderCard(folder: folder)
                                    .animatedAppearance(delay: Double(index) * 0.05)
                            }
                        }
                        .padding(20)
                    }
                    .transition(TransitionStyles.slideFromRight)
                }
            }
            .animation(.pageTransition, value: watchedFoldersManager.folders.isEmpty)
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
                    
                    // Create security-scoped bookmark
                    let bookmarkData = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    
                    if bookmarkData == nil {
                        DebugLogger.log("Failed to create security-scoped bookmark for \(url.path)")
                    }
                    
                    let folder = WatchedFolder(
                        path: url.path,
                        bookmarkData: bookmarkData
                    )
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        watchedFoldersManager.addFolder(folder)
                    }
                }
            case .failure(let error):
                HapticFeedbackManager.shared.error()
                DebugLogger.log("Failed to select folder: \(error)")
            }
        }
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Watched Folders")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack(spacing: 8) {
                    let activeCount = watchedFoldersManager.folders.filter { $0.isEnabled }.count
                    let autoCount = watchedFoldersManager.folders.filter { $0.isEnabled && $0.autoOrganize }.count
                    
                    Text("\(activeCount) active")
                        .foregroundStyle(activeCount > 0 ? .green : .secondary)
                    
                    if autoCount > 0 {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(autoCount) auto-organizing")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
            }
            .animatedAppearance(delay: 0.05)

            Spacer()

            Button {
                HapticFeedbackManager.shared.tap()
                showingFolderPicker = true
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("AddWatchedFolderButton")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Empty State View

struct EmptyWatchedFoldersView: View {
    let onAddFolder: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Watched Folders")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Add folders like Downloads or Desktop to automatically organize new files as they arrive")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            
            // Suggestion cards
            VStack(spacing: 8) {
                Text("Popular choices:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    FolderSuggestionPill(name: "Downloads", icon: "arrow.down.circle")
                    FolderSuggestionPill(name: "Desktop", icon: "menubar.dock.rectangle")
                    FolderSuggestionPill(name: "Documents", icon: "doc.text")
                }
            }

            Button {
                onAddFolder()
            } label: {
                Label("Add Folder", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FolderSuggestionPill: View {
    let name: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(name)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Watched Folder Card

struct WatchedFolderCard: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var organizer: FolderOrganizer
    @State private var showingConfig = false
    @State private var isHovered = false
    
    private var isOrganizing: Bool {
        guard let currentDir = organizer.currentDirectory else { return false }
        return currentDir.path == folder.path && 
               organizer.state != .idle && 
               organizer.state != .completed && 
               !isErrorState
    }
    
    private var isErrorState: Bool {
        if case .error = organizer.state { return true }
        return false
    }
    
    // Check if AI is available
    private var isAIConfigured: Bool {
        organizer.aiClient != nil
    }
    
    private var statusColor: Color {
        if !folder.exists { return .red }
        if folder.accessStatus == .lost { return .orange }
        if !folder.isEnabled { return .secondary }
        if isOrganizing { return .blue }
        if folder.autoOrganize { return .green }
        return .blue
    }
    
    private var statusIcon: String {
        if !folder.exists { return "exclamationmark.triangle.fill" }
        if folder.accessStatus == .lost { return "lock.slash.fill" }
        if !folder.isEnabled { return "pause.circle.fill" }
        if isOrganizing { return "arrow.triangle.2.circlepath" }
        if folder.autoOrganize { return "bolt.circle.fill" }
        return "eye.circle.fill"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Folder Icon with Status
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(folder.isEnabled ? .blue : .secondary)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(statusColor)
                    .background(
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 18, height: 18)
                    )
                    .offset(x: 4, y: 4)
            }
            .frame(width: 48, height: 48)

            // Folder Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(folder.name)
                        .font(.headline)
                        .foregroundColor(folder.isEnabled ? .primary : .secondary)
                    
                    if isOrganizing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                            Text("Organizing...")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    // Show warning if enabled but AI not configured
                    if folder.isEnabled && folder.autoOrganize && !isAIConfigured {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                            Text("AI Missing")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                        .help("Auto-organization requires an AI provider configured in Settings")
                    }
                }

                Text(folder.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                // Stats row
                HStack(spacing: 12) {
                    if let lastTriggered = folder.lastTriggered {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(lastTriggered, style: .relative)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    if folder.autoOrganize {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                            Text("Auto")
                                .font(.caption2)
                        }
                        .foregroundStyle(.green)
                    }
                    
                    if !folder.exists {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Folder not found")
                                .font(.caption2)
                        }
                        .foregroundStyle(.red)
                    } else if folder.accessStatus == .lost {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.slash.fill")
                                .font(.caption2)
                            Text("Access Lost")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                        .help("App Sandbox access to this folder was lost. Try removing and re-adding it.")
                    }
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 12) {
                if isHovered {
                    // Quick Actions
                    HStack(spacing: 8) {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                        } label: {
                            Image(systemName: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reveal in Finder")
                        
                        Button {
                            HapticFeedbackManager.shared.tap()
                            showingConfig = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Configure")
                        
                        Button {
                            HapticFeedbackManager.shared.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                watchedFoldersManager.removeFolder(folder)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Remove")
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Auto-organize toggle
                VStack(alignment: .trailing, spacing: 4) {
                    Toggle("", isOn: Binding(
                        get: { folder.isEnabled },
                        set: { _ in
                            HapticFeedbackManager.shared.selection()
                            watchedFoldersManager.toggleEnabled(for: folder)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    
                    if folder.isEnabled {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            // Only allow toggling auto if AI is configured
                            if isAIConfigured {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    watchedFoldersManager.toggleAutoOrganize(for: folder)
                                }
                            } else {
                                // Provide feedback that it's disabled
                                HapticFeedbackManager.shared.error()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: folder.autoOrganize ? "bolt.fill" : "bolt")
                                    .font(.caption2)
                                Text(folder.autoOrganize ? "Auto" : "Manual")
                                    .font(.caption2)
                            }
                            .foregroundColor(folder.autoOrganize ? .green : .secondary)
                            .opacity(isAIConfigured ? 1.0 : 0.5)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isAIConfigured)
                        .transition(.scale.combined(with: .opacity))
                        .help(!isAIConfigured ? "AI Provider required" : "")
                    }
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: folder.isEnabled)
        }
        .padding(16)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(folder.exists ? Color.white.opacity(0.1) : Color.red.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        .opacity(folder.exists ? 1.0 : 0.8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            }
            Button("Configure...") {
                showingConfig = true
            }
            Divider()
            Button("Remove", role: .destructive) {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    watchedFoldersManager.removeFolder(folder)
                }
            }
        }
        .sheet(isPresented: $showingConfig) {
            WatchedFolderConfigView(folder: folder)
                .modalBounce()
        }
    }
}

// MARK: - Watched Folder Config View

struct WatchedFolderConfigView: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var customPrompt: String
    @State private var temperature: Double
    @State private var autoOrganize: Bool
    
    // Check if AI is available
    private var isAIConfigured: Bool {
        organizer.aiClient != nil
    }

    init(folder: WatchedFolder) {
        self.folder = folder
        _customPrompt = State(initialValue: folder.customPrompt ?? "")
        _temperature = State(initialValue: folder.temperature ?? 0.7)
        _autoOrganize = State(initialValue: folder.autoOrganize)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.headline)
                        Text(folder.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button("Done") {
                    HapticFeedbackManager.shared.success()
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Automation Section
                    ConfigSection(title: "Automation", icon: "bolt", color: .green) {
                        VStack(spacing: 12) {
                            if !isAIConfigured {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text("AI Provider Not Configured")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                    Spacer()
                                }
                                
                                Text("To enable automatic organization, please configure an AI provider in Settings first.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                Button("Open Settings") {
                                    appState.currentView = .settings
                                    dismiss()
                                }
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            Toggle(isOn: $autoOrganize) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-Organize")
                                        .font(.subheadline)
                                    Text("Automatically organize new files as they appear")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .disabled(!isAIConfigured)
                            
                            if autoOrganize {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.blue)
                                    Text("Files will be organized into existing folders based on content and type.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color.blue.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    
                    // Actions Section
                    ConfigSection(title: "Actions", icon: "play", color: .blue) {
                        Button {
                            appState.calibrateAction?(folder)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "wand.and.stars")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Run Full Organization")
                                        .foregroundStyle(.primary)
                                    Text("Analyze and organize all files now")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Custom Instructions Section
                    ConfigSection(title: "Custom Instructions", icon: "text.bubble", color: .purple) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $customPrompt)
                                .font(.system(.body, design: .default))
                                .frame(height: 80)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            
                            Text("e.g., \"Group by project name\" or \"Keep invoices separate\"")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // AI Creativity Section
                    ConfigSection(title: "AI Creativity", icon: "sparkles", color: .orange) {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Temperature")
                                    .font(.subheadline)
                                Spacer()
                                Text(creativityLabel)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(creativityColor.opacity(0.1))
                                    .foregroundStyle(creativityColor)
                                    .clipShape(Capsule())
                            }
                            
                            Slider(value: $temperature, in: 0...1, step: 0.1)
                                .tint(creativityColor)
                            
                            HStack {
                                Text("Strict")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Creative")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // Folder Info
                    if let lastTriggered = folder.lastTriggered {
                        ConfigSection(title: "Statistics", icon: "chart.bar", color: .gray) {
                            HStack {
                                Text("Last organized")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(lastTriggered, style: .relative)
                                    .font(.subheadline)
                                Text("ago")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 450, height: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var creativityLabel: String {
        if temperature < 0.3 { return "Strict" }
        if temperature < 0.6 { return "Balanced" }
        return "Creative"
    }
    
    private var creativityColor: Color {
        if temperature < 0.3 { return .blue }
        if temperature < 0.6 { return .green }
        return .orange
    }

    private func save() {
        var updated = folder
        updated.customPrompt = customPrompt.isEmpty ? nil : customPrompt
        updated.temperature = temperature
        updated.autoOrganize = autoOrganize
        
        withAnimation {
            watchedFoldersManager.updateFolder(updated)
        }
        dismiss()
    }
}

// MARK: - Config Section

struct ConfigSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    WatchedFoldersView()
        .environmentObject(WatchedFoldersManager())
        .environmentObject(FolderOrganizer())
        .frame(width: 600, height: 500)
}

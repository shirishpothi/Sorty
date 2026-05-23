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
    @EnvironmentObject var appState: AppState
    @State private var showingFolderPicker = false
    @State private var selectedFolderForEdit: WatchedFolder?
    @State private var contentOpacity: Double = 0
    @State private var isDropTargeted = false
    
    // Check if AI is available
    private var isAIConfigured: Bool {
        organizer.aiClient != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if watchedFoldersManager.folders.isEmpty {
                ZStack(alignment: .topLeading) {
                    EmptyWatchedFoldersView(onAddFolder: {
                        HapticFeedbackManager.shared.tap()
                        showingFolderPicker = true
                    })
                    .transition(TransitionStyles.scaleAndFade)
                    .animatedAppearance(delay: 0.08)

                    emptyHeaderView
                        .padding(.horizontal, 32)
                        .animatedAppearance(delay: 0.03)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                // Header
                headerView
                    .animatedAppearance(delay: 0.03)

                Divider()

                // Folder Grid/List
                ZStack {
                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(Array(watchedFoldersManager.folders.enumerated()), id: \.element.id) { index, folder in
                                    WatchedFolderCard(folder: folder)
                                        .id(folder.id)
                                        .animatedAppearance(delay: Double(index) * 0.05)
                                }
                            }
                            .padding(20)
                        }
                        .onChange(of: appState.highlightedWatchedFolderID) { _, highlightedID in
                            guard let highlightedID else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                scrollProxy.scrollTo(highlightedID, anchor: .center)
                            }
                        }
                    }
                    .transition(TransitionStyles.slideFromRight)
                }
                .animation(.pageTransition, value: watchedFoldersManager.folders.isEmpty)
            }
        }
        .animation(.pageTransition, value: watchedFoldersManager.folders.isEmpty)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    addWatchedFolder(from: url)
                }
            case .failure(let error):
                HapticFeedbackManager.shared.error()
                DebugLogger.log("Failed to select folder: \(error)")
            }
        }
        .siriDropZone(cornerRadius: 12, isTargeted: $isDropTargeted) { providers in
            handleFolderDrop(providers: providers)
        }
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
        .navigationTitle("Watched Folders")
    }

    private func addWatchedFolder(from url: URL) {
        HapticFeedbackManager.shared.success()

        // Start accessing the security-scoped resource before creating the bookmark.
        // fileImporter URLs are security-scoped but the resource must be explicitly
        // started to ensure bookmark creation captures the scope.
        let didStart = url.startAccessingSecurityScopedResource()

        let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        if didStart {
            url.stopAccessingSecurityScopedResource()
        }

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
    
    private func handleFolderDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.hasDirectoryPath {
                Task { @MainActor in
                    HapticFeedbackManager.shared.success()
                    let bookmarkData = try? url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    let folder = WatchedFolder(
                        path: url.path,
                        bookmarkData: bookmarkData
                    )
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        watchedFoldersManager.addFolder(folder)
                    }
                }
            }
        }
        return true
    }
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 12) {
                if appState.navigatedFromSettings {
                    GlassyBackButton {
                        HapticFeedbackManager.shared.tap()
                        appState.navigatedFromSettings = false
                        appState.openSettingsWindow(section: .rules)
                    }
                }
                
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
            }
            .animatedAppearance(delay: 0.05)

            Spacer()

            Button {
                HapticFeedbackManager.shared.tap()
                showingFolderPicker = true
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.onboardingPill)
            .onboardingBeamBorder(variant: .success)
            .accessibilityIdentifier("AddWatchedFolderButton")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Watched Folders")
                    .font(.largeTitle.bold())

                Text("Monitor folders and automatically organize new files as they arrive")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Empty State View

struct EmptyWatchedFoldersView: View {
    let onAddFolder: () -> Void
    @State private var hasAppeared = false
    @State private var beamHasAppeared = false
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: hasAppeared)

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
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)

            Button {
                onAddFolder()
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.onboardingPill)
            .onboardingBeamBorder(variant: .featured, active: beamHasAppeared)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 15)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                beamHasAppeared = true
            }
        }
    }
}

struct FolderSuggestionPill: View {
    let name: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(isHovered ? 0.16 : 0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.03 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            if hovering && !isHovered {
                HapticFeedbackManager.shared.selection()
            }
            isHovered = hovering
        }
        .accessibilityLabel("Add \(name) to watched folders")
    }
}

// MARK: - Watched Folder Card

struct WatchedFolderCard: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @State private var showingConfig = false
    @State private var isHovered = false
    @State private var highlightPulse = false

    
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
    
    private var isHighlighted: Bool {
        appState.highlightedWatchedFolderID == folder.id
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

    private var cardBackgroundColor: Color {
        if isHighlighted {
            return SortyDesignSystem.Colors.resolvedAccent.opacity(highlightPulse ? 0.14 : 0.08)
        }
        return isHovered ? Color.primary.opacity(0.03) : Color.clear
    }

    private var cardBorderColor: Color {
        if isHighlighted {
            return SortyDesignSystem.Colors.resolvedAccent.opacity(highlightPulse ? 0.9 : 0.45)
        }
        return folder.exists ? Color.white.opacity(0.1) : Color.red.opacity(0.3)
    }

    private var cardShadowColor: Color {
        if isHighlighted {
            return SortyDesignSystem.Colors.resolvedAccent.opacity(highlightPulse ? 0.35 : 0.16)
        }
        return .black.opacity(0.03)
    }

    private var cardShadowRadius: CGFloat {
        isHighlighted ? 10 : 3
    }

    private var folderIconView: some View {
        ZStack(alignment: .bottomTrailing) {
            FolderThumbnailView(url: URL(fileURLWithPath: folder.path), size: CGSize(width: 40, height: 40))
                .opacity(folder.isEnabled ? 1.0 : 0.6)

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
    }

    private var organizingBadge: some View {
        HStack(spacing: 4) {
            SortyGradientCircularLoader(size: 10, lineWidth: 2)
            Text("Organizing...")
                .font(.caption2)
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }

    private var aiMissingBadge: some View {
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

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(folder.name)
                .font(.headline)
                .foregroundColor(folder.isEnabled ? .primary : .secondary)

            if isOrganizing {
                organizingBadge
            }

            if folder.isEnabled && folder.autoOrganize && !isAIConfigured {
                aiMissingBadge
            }
        }
    }

    private var lastTriggeredStat: some View {
        Group {
            if let lastTriggered = folder.lastTriggered {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(lastTriggered, style: .relative)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var autoStat: some View {
        Group {
            if folder.autoOrganize {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text("Auto")
                        .font(.caption2)
                }
                .foregroundStyle(.green)
            }
        }
    }

    private var modelOverrideStat: some View {
        Group {
            if let modelOverride = folder.modelOverride {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                    Text(modelOverride)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.purple)
            }
        }
    }

    private var missingFolderStatus: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
            Text("Folder not found")
                .font(.caption2)
        }
        .foregroundStyle(.red)
    }

    private var lostAccessLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.slash.fill")
                .font(.caption2)
            Text("Access Lost")
                .font(.caption2)
        }
        .foregroundStyle(.orange)
        .help("App Sandbox access to this folder was lost. Try removing and re-adding it.")
    }

    private var grantAccessButton: some View {
        Button("Grant Access") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Re-select \"\(folder.name)\" to restore access"
            panel.prompt = "Grant Access"
            panel.directoryURL = URL(fileURLWithPath: folder.path).deletingLastPathComponent()

            if panel.runModal() == .OK, let url = panel.url {
                watchedFoldersManager.reauthorizeFolder(folder, with: url)
                HapticFeedbackManager.shared.success()
            }
        }
        .font(.caption2)
        .buttonStyle(.sortyBordered)
        .controlSize(.mini)
    }

    @ViewBuilder
    private var healthStatusView: some View {
        if !folder.exists {
            missingFolderStatus
        } else if folder.accessStatus == .lost {
            HStack(spacing: 6) {
                lostAccessLabel
                grantAccessButton
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            lastTriggeredStat
            autoStat
            modelOverrideStat
            healthStatusView
        }
    }

    private var folderInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleRow

            PrivacySensitivePathText(path: folder.path)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            statsRow
        }
    }

    private var quickActionsView: some View {
        HStack(spacing: 8) {
            Button {
                HapticFeedbackManager.shared.tap()
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
            } label: {
                Image(systemName: "folder")
                    .font(.caption)
            }
            .buttonStyle(.sortyBordered)
            .controlSize(.small)
            .help("Reveal in Finder")

            Button {
                HapticFeedbackManager.shared.tap()
                showingConfig = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
            }
            .buttonStyle(.sortyBordered)
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
            .buttonStyle(.sortyBordered)
            .controlSize(.small)
            .help("Remove")
        }
    }

    private var autoOrganizeControlView: some View {
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
                    if isAIConfigured {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            watchedFoldersManager.toggleAutoOrganize(for: folder)
                        }
                    } else {
                        HapticFeedbackManager.shared.error()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: folder.autoOrganize ? "bolt.fill" : "bolt")
                            .font(.caption2)
                        Text(folder.autoOrganize ? "Auto" : "Manual")
                            .font(.caption2)
                    }
                    .contentShape(Rectangle())
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

    private var controlsView: some View {
        HStack(spacing: 12) {
            if isHovered {
                quickActionsView
                    .transition(.scale.combined(with: .opacity))
            }

            autoOrganizeControlView
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: folder.isEnabled)
    }

    var body: some View {
        HStack(spacing: 16) {
            folderIconView
            folderInfoView

            Spacer()

            controlsView
        }
        .padding(16)
        .contentShape(Rectangle())
        .background(cardBackgroundColor)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(cardBorderColor, lineWidth: isHighlighted ? 1.6 : 1)
        )
        .shadow(color: cardShadowColor, radius: cardShadowRadius, x: 0, y: 1)
        .opacity(folder.exists ? 1.0 : 0.8)
        .scaleEffect(isHighlighted && highlightPulse ? 1.008 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onAppear {
            updateHighlightAnimation(isHighlighted)
        }
        .onChange(of: isHighlighted) { _, newValue in
            updateHighlightAnimation(newValue)
        }
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

    private func updateHighlightAnimation(_ isActive: Bool) {
        if isActive {
            highlightPulse = false
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                highlightPulse = true
            }
        } else {
            highlightPulse = false
        }
    }
}

// MARK: - Watched Folder Config View

struct WatchedFolderConfigView: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @Environment(\.dismiss) var dismiss
    
    @State private var customPrompt: String
    @State private var temperature: Double
    @State private var autoOrganize: Bool
    @State private var useCustomModel: Bool
    @State private var selectedProvider: AIProvider
    @State private var selectedModel: String
    @State private var showModelPicker = false
    
    // Check if AI is available
    private var isAIConfigured: Bool {
        organizer.aiClient != nil
    }

    init(folder: WatchedFolder) {
        self.folder = folder
        _customPrompt = State(initialValue: folder.customPrompt ?? "")
        _temperature = State(initialValue: folder.temperature ?? 0.7)
        _autoOrganize = State(initialValue: folder.autoOrganize)
        _useCustomModel = State(initialValue: folder.modelOverride != nil)
        _selectedProvider = State(initialValue: folder.providerOverride ?? .openAI)
        _selectedModel = State(initialValue: folder.modelOverride ?? AIProvider.openAI.defaultModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    FolderThumbnailView(
                        url: URL(fileURLWithPath: folder.path),
                        size: CGSize(width: 32, height: 32)
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.name)
                            .font(.headline)
                        PrivacySensitivePathText(path: folder.path)
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
                .buttonStyle(.sortyProminent)
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
                                    appState.openSettingsWindow(section: .provider)
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
                                Text("\(temperature, specifier: "%.2f")")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.numericText())
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
                                Text("Strict (0.0)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Creative (1.0)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    // AI Model Section
                    ConfigSection(title: "AI Model", icon: "cpu", color: .purple) {
                        VStack(spacing: 12) {
                            Toggle(isOn: $useCustomModel) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use Custom Model")
                                        .font(.subheadline)
                                    Text("Override the global automation model for this folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)

                            if useCustomModel {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Model")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    ModelSelectorRow(
                                        provider: selectedProvider,
                                        model: selectedModel,
                                        onTap: { showModelPicker = true }
                                    )
                                    .modelSelectorTriggerBounds()
                                }
                            
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                    Text("Tip: Use cheaper models like gpt-4o-mini, claude-3-haiku, or local Ollama for cost-effective background automation.")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                                .padding(10)
                                .background(Color.purple.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: useCustomModel)
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
        .frame(minWidth: 520, idealWidth: 560, minHeight: 650, idealHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            primeModelSelectionFromGlobalDefaultsIfNeeded()
        }
        .onChange(of: useCustomModel) { _, useOverride in
            if useOverride && selectedModel.isEmpty {
                let defaults = globalAutomationSelection
                selectedProvider = defaults.provider
                selectedModel = defaults.model
            }
        }
        .modelSelectionOverlay(
            isPresented: $showModelPicker,
            currentProvider: selectedProvider,
            currentModel: selectedModel,
            onSelect: { provider, model in
                selectedProvider = provider
                selectedModel = model
            }
        )
    }

    private var globalAutomationSelection: (provider: AIProvider, model: String) {
        let provider = settingsViewModel.config.automationProvider ?? settingsViewModel.config.provider
        let configuredModel = settingsViewModel.config.automationProvider == nil
            ? settingsViewModel.config.model
            : (settingsViewModel.config.automationModel ?? "")
        let model = configuredModel.isEmpty ? provider.defaultModel : configuredModel
        return (provider, model)
    }

    private func primeModelSelectionFromGlobalDefaultsIfNeeded() {
        guard folder.modelOverride == nil || folder.providerOverride == nil else {
            return
        }

        let defaults = globalAutomationSelection
        selectedProvider = defaults.provider
        selectedModel = defaults.model
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
        
        if useCustomModel {
            updated.providerOverride = selectedProvider
            updated.modelOverride = selectedModel
        } else {
            updated.providerOverride = nil
            updated.modelOverride = nil
        }
        
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

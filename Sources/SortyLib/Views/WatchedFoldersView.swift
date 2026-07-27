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
    @EnvironmentObject var appState: AppState
    @State private var showingFolderPicker = false
    @State private var selectedFolderForEdit: WatchedFolder?
    @State private var contentOpacity: Double = 0
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if watchedFoldersManager.folders.isEmpty {
                ZStack(alignment: .topLeading) {
                    EmptyWatchedFoldersView(onAddFolder: {
                        HapticFeedbackManager.shared.tap()
                        showingFolderPicker = true
                    }, onAddSuggestedFolder: { url in
                        addWatchedFolder(from: url)
                    })
                    .transition(TransitionStyles.scaleAndFade)
                    .animatedAppearance(delay: 0.08)

                    emptyHeaderView
                        .padding(.horizontal, 32)
                        .animatedAppearance(delay: 0.03)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                ForEach(watchedFoldersManager.folders) { folder in
                                    WatchedFolderCard(folder: folder)
                                        .id(folder.id)
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
        .emptyStateWorkflowGradient(isVisible: watchedFoldersManager.folders.isEmpty)
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
                url.hasDirectoryPath
            {
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
                        let activeCount = watchedFoldersManager.activeFolderCount

                        Text("\(activeCount) active")
                            .foregroundStyle(activeCount > 0 ? .green : .secondary)
                            .numericTextTransition(animationValue: activeCount)
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
    let onAddSuggestedFolder: (URL) -> Void
    @State private var hasAppeared = false
    @State private var beamHasAppeared = false

    var body: some View {
        VStack(spacing: 24) {
            EmptyStateHeroIcon(systemName: "folder.badge.plus")
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.8)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: hasAppeared)

            VStack(spacing: 8) {
                Text("No Watched Folders")
                    .font(.title3)
                    .fontWeight(.semibold)

                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text("Add folders like")

                        FolderSuggestionPill(
                            name: "Downloads",
                            url: FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent("Downloads"),
                            action: onAddSuggestedFolder
                        )

                        Text("or")

                        FolderSuggestionPill(
                            name: "Desktop",
                            url: FileManager.default.homeDirectoryForCurrentUser
                                .appendingPathComponent("Desktop"),
                            action: onAddSuggestedFolder
                        )
                    }

                    Text("to automatically organize new files as they arrive")
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
    let url: URL
    let action: (URL) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            action(url)
        } label: {
            HStack(spacing: 4) {
                FolderThumbnailView(
                    url: url,
                    size: CGSize(width: 16, height: 16)
                )

                Text(name)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(isHovered ? 0.14 : 0.07))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .scaleEffect(isHovered ? 1.02 : 1)
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
        return currentDir.path == folder.path && organizer.state != .idle
            && organizer.state != .completed && !isErrorState
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
        return .green
    }

    private var statusIcon: String {
        if !folder.exists { return "exclamationmark.triangle.fill" }
        if folder.accessStatus == .lost { return "lock.slash.fill" }
        if !folder.isEnabled { return "pause.circle.fill" }
        if isOrganizing { return "arrow.triangle.2.circlepath" }
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
            FolderThumbnailView(
                url: URL(fileURLWithPath: folder.path), size: CGSize(width: 40, height: 40)
            )
            .opacity(folder.isEnabled ? 1.0 : 0.6)

            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundStyle(statusColor)
                .symbolReplaceTransition(animationValue: statusIcon)
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
            Text("Running...")
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
            Text("Provider Missing")
                .font(.caption2)
        }
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
        .help("Watching requires a provider configured in Settings")
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text(folder.name)
                .font(.headline)
                .foregroundColor(folder.isEnabled ? .primary : .secondary)

            if isOrganizing {
                organizingBadge
            }

            if folder.isEnabled && !isAIConfigured {
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
                        .contentTransition(.symbolEffect(.replace))
                    Text(lastTriggered, style: .relative)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var modelOverrideStat: some View {
        Group {
            if let modelOverride = folder.modelOverride {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .contentTransition(.symbolEffect(.replace))
                    Text(modelOverride)
                        .font(.caption2)
                        .lineLimit(1)
                        .numericTextTransition(animationValue: modelOverride)
                }
                .foregroundStyle(.purple)
            }
        }
    }

    private var organizationModeStat: some View {
        HStack(spacing: 4) {
            Image(systemName: folder.effectiveOrganizationMode.iconName)
                .font(.caption2)
                .symbolReplaceTransition(
                    animationValue: folder.effectiveOrganizationMode
                )
            Text(folder.effectiveOrganizationMode.displayName)
                .font(.caption2)
                .numericTextTransition(
                    animationValue: folder.effectiveOrganizationMode
                )
        }
        .foregroundStyle(.blue)
    }

    private var missingFolderStatus: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .contentTransition(.symbolEffect(.replace))
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
            organizationModeStat
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
            .accessibilityLabel("Reveal \(folder.name) in Finder")

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
            .accessibilityLabel("Configure \(folder.name)")

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
            .accessibilityLabel("Remove \(folder.name)")
        }
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { folder.isEnabled },
            set: { _ in
                HapticFeedbackManager.shared.selection()
                watchedFoldersManager.toggleEnabled(for: folder)
            }
        )
    }

    private var watchToggle: some View {
        Toggle("Watch \(folder.name)", isOn: isEnabledBinding)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityHint(
                "When enabled, Sorty organizes new files into this folder's preferred structure.")
    }

    private var controlsView: some View {
        HStack(spacing: 12) {
            if isHovered {
                quickActionsView
                    .transition(.scale.combined(with: .opacity))
            }

            watchToggle
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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var customPersonaStore: CustomPersonaStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var steeringManager = SteeringPromptManager.shared

    @State private var customPrompt: String
    @State private var useCustomModel: Bool
    @State private var selectedProvider: AIProvider
    @State private var selectedModel: String
    @State private var selectedMode: OrganizationMode
    @State private var showModelPicker = false
    @State private var showFolderModelInfo = false
    @State private var showSavedPromptsSheet = false
    @State private var showSavePromptDialog = false
    @State private var savePromptName = ""
    @State private var isImprovingPrompt = false
    @State private var showImprovePromptRequest = false
    @State private var improvePromptRequestMessage = ""
    @State private var isPromptFocused = false
    @State private var instructionSuggestionIndex = 0
    @State private var instructionSelection = NSRange(location: 0, length: 0)

    init(folder: WatchedFolder) {
        self.folder = folder
        _customPrompt = State(initialValue: folder.customPrompt ?? "")
        _useCustomModel = State(initialValue: folder.modelOverride != nil)
        _selectedProvider = State(initialValue: folder.providerOverride ?? .openAI)
        _selectedModel = State(initialValue: folder.modelOverride ?? AIProvider.openAI.defaultModel)
        _selectedMode = State(initialValue: folder.effectiveOrganizationMode)
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
                    ConfigSection(title: "Action", icon: "slider.horizontal.3", color: .blue) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 4) {
                                ForEach(OrganizationMode.allCases, id: \.self) { mode in
                                    OrganizationModeSegment(
                                        mode: mode,
                                        isSelected: selectedMode == mode
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedMode = mode
                                        }
                                        HapticFeedbackManager.shared.selection()
                                    }
                                }
                            }
                            .padding(4)
                            .systemLiquidGlassBackground(cornerRadius: 999)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Watched folder action")

                            Text(LocalizedStringKey(selectedMode.description))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .numericTextTransition(animationValue: selectedMode)
                        }
                    }

                    // Actions Section
                    ConfigSection(title: "Actions", icon: "play", color: .blue) {
                        Button(action: openFullOrganization) {
                            HStack {
                                Image(systemName: selectedMode.iconName)
                                    .foregroundStyle(.blue)
                                    .symbolReplaceTransition(animationValue: selectedMode)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(selectedModeManualAction.title))
                                        .foregroundStyle(.primary)
                                        .numericTextTransition(animationValue: selectedMode)
                                    Text(LocalizedStringKey(selectedModeManualAction.description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .numericTextTransition(animationValue: selectedMode)
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
                    ConfigSection(title: "Custom Instructions", icon: "text.bubble", color: .purple)
                    {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                SubmittableTextEditor(
                                    text: $customPrompt,
                                    isFocused: $isPromptFocused,
                                    selectedRange: $instructionSelection,
                                    onAcceptSuggestion: acceptCurrentInstructionSuggestion,
                                    onSubmit: {}
                                )
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)

                                if customPrompt.isEmpty {
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(currentInstructionSuggestion)
                                            .font(.body)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(2)
                                            .numericTextTransition(
                                                animationValue: instructionSuggestionIndex
                                            )

                                        Spacer(minLength: 0)

                                        Text("Tab")
                                            .font(
                                                .system(
                                                    size: 10,
                                                    weight: .semibold,
                                                    design: .rounded
                                                )
                                            )
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(
                                                Color.secondary.opacity(0.10),
                                                in: RoundedRectangle(cornerRadius: 5)
                                            )
                                            .accessibilityHidden(true)
                                    }
                                    .padding(.leading, 18)
                                    .padding(.trailing, 10)
                                    .padding(.vertical, 9)
                                    .allowsHitTesting(false)
                                    .task(id: instructionSuggestions) {
                                        instructionSuggestionIndex = 0

                                        while !Task.isCancelled {
                                            try? await Task.sleep(for: .seconds(3.5))
                                            guard !Task.isCancelled else { return }
                                            instructionSuggestionIndex =
                                                (instructionSuggestionIndex + 1)
                                                % instructionSuggestions.count
                                        }
                                    }
                                }
                            }
                            .frame(height: 80)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(NSColor.textBackgroundColor))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)

                                FocusedInstructionBeamBorder(active: isPromptFocused)
                            }
                            .accessibilityIdentifier("WatchedFolderCustomInstructionsTextField")
                            .accessibilityLabel("Custom instructions for this watched folder")
                            .accessibilityHint(
                                customPrompt.isEmpty
                                    ? "Press Tab to use the suggested instruction"
                                    : "Enter adds a new line"
                            )

                            instructionActions
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
                            .frame(maxWidth: .infinity, alignment: .leading)

                            if useCustomModel {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text("Folder Model")
                                                .font(.subheadline)

                                            Button {
                                                HapticFeedbackManager.shared.tap()
                                                showFolderModelInfo.toggle()
                                            } label: {
                                                Image(systemName: "info.circle")
                                                    .font(.caption)
                                            }
                                            .buttonStyle(.plain)
                                            .foregroundStyle(.secondary)
                                            .help("About using a separate watched folder model")
                                            .accessibilityLabel(
                                                "Separate watched folder model information"
                                            )
                                            .onHover { showFolderModelInfo = $0 }
                                            .popover(
                                                isPresented: $showFolderModelInfo,
                                                arrowEdge: .trailing
                                            ) {
                                                VStack(alignment: .leading, spacing: 8) {
                                                    Text("Separate Watched Folder Model")
                                                        .font(.headline)

                                                    Text(
                                                        "The main Organize page keeps using the model selected under AI Provider. For faster, more responsive automation, try a smaller model such as GPT-5.6 Luna."
                                                    )
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(
                                                        horizontal: false,
                                                        vertical: true
                                                    )
                                                }
                                                .padding(14)
                                                .frame(width: 300, alignment: .leading)
                                                .systemLiquidGlassPopover(cornerRadius: 12)
                                            }
                                        }

                                        Text("Used only for this watched folder")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    ModelSelectorCompactButton(
                                        provider: selectedProvider,
                                        label: selectedModel.isEmpty
                                            ? selectedProvider.defaultModel
                                            : selectedModel,
                                        onTap: { showModelPicker = true }
                                    )
                                    .modelSelectorTriggerBounds()
                                }
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : AnyTransition(.blurReplace)
                                )
                            }
                        }
                        .animation(
                            reduceMotion
                                ? .easeOut(duration: 0.15)
                                : .easeInOut(duration: 0.25),
                            value: useCustomModel
                        )
                    }

                    // Folder Info
                    if let lastTriggered = folder.lastTriggered {
                        ConfigSection(title: "Statistics", icon: "chart.bar", color: .gray) {
                            HStack {
                                Text("Last run")
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
        .frame(minWidth: 520, idealWidth: 560)
        .fixedSize(horizontal: false, vertical: true)
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
            contextMessage: "Choose the provider and model used only for this watched folder.",
            onSelect: { provider, model in
                selectedProvider = provider
                selectedModel = model
            }
        )
        .sheet(isPresented: $showSavedPromptsSheet) {
            SavedPromptsSheet(
                steeringManager: steeringManager,
                settingsConfig: settingsViewModel.config,
                onApplyPrompt: { prompt in
                    customPrompt = prompt
                    showSavedPromptsSheet = false
                    HapticFeedbackManager.shared.tap()
                }
            )
        }
    }

    private var instructionActions: some View {
        HStack(alignment: .center, spacing: 0) {
            if !trimmedCustomPrompt.isEmpty {
                Button {
                    Task { await improvePromptWithAI() }
                } label: {
                    Label("Improve", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.teal)
                .disabled(isImprovingPrompt)
                .help("Improve instructions with Sorty")
                .accessibilityHint("Rewrites this watched folder's prompt to be clearer and more specific")
                .alert("Sorty needs more detail", isPresented: $showImprovePromptRequest) {
                    Button("Edit Instructions") {
                        isPromptFocused = true
                    }
                } message: {
                    Text("\(improvePromptRequestMessage)\n\nEdit the instructions above, then click Improve again.")
                }

                Button {
                    savePromptName = ""
                    showSavePromptDialog.toggle()
                } label: {
                    Label("Save", systemImage: "bookmark")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("Save current instructions for reuse")
                .accessibilityHint("Stores this prompt in your saved prompts list")
                .popover(isPresented: $showSavePromptDialog) {
                    savePromptPopover
                }
            }

            Button {
                showSavedPromptsSheet.toggle()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                        .frame(width: 18)
                        .accessibilityHidden(true)

                    Text(
                        steeringManager.prompts.isEmpty
                            ? "Saved Prompts"
                            : "Saved Prompts (\(steeringManager.prompts.count))"
                    )
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .systemLiquidGlassBackground(cornerRadius: 12)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            SortyDesignSystem.Colors.resolvedAccent.opacity(0.18),
                            lineWidth: 1
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Open your saved instruction prompts")
            .accessibilityHint("View, edit, and apply saved prompts")

            Spacer()

            CompactPersonaPicker()
        }
        .font(.caption2)
        .foregroundStyle(.quaternary)
    }

    private var savePromptPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Prompt")
                .font(.headline)

            TextField("Prompt name", text: $savePromptName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showSavePromptDialog = false
                }
                .buttonStyle(.sortyBordered)

                Spacer()

                Button("Save") {
                    steeringManager.addPrompt(
                        SavedSteeringPrompt(name: savePromptName, prompt: customPrompt)
                    )
                    showSavePromptDialog = false
                    HapticFeedbackManager.shared.success()
                }
                .buttonStyle(.sortyProminent)
                .disabled(savePromptName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 280)
        .foregroundStyle(.primary)
        .systemLiquidGlassPopover(cornerRadius: 12)
    }

    private var trimmedCustomPrompt: String {
        customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var instructionSuggestions: [String] {
        InstructionSuggestionCatalog.suggestions(
            for: selectedMode,
            personaManager: personaManager,
            customPersonaStore: customPersonaStore
        )
    }

    private var currentInstructionSuggestion: String {
        instructionSuggestions[instructionSuggestionIndex % instructionSuggestions.count]
    }

    private var selectedModeManualAction: (title: String, description: String) {
        switch selectedMode {
        case .organize:
            return (
                "Run Organization",
                "Organize the files already in this folder without changing their names."
            )
        case .organizeAndRename:
            return (
                "Run Organization & Rename",
                "Organize the files already in this folder and improve their names."
            )
        case .renameOnly:
            return (
                "Run Rename",
                "Improve the names of files already in this folder without moving them."
            )
        }
    }

    private func acceptCurrentInstructionSuggestion() -> Bool {
        guard customPrompt.isEmpty else { return false }

        customPrompt = currentInstructionSuggestion
        instructionSelection = NSRange(
            location: (currentInstructionSuggestion as NSString).length,
            length: 0
        )
        HapticFeedbackManager.shared.selection()
        return true
    }

    private func improvePromptWithAI() async {
        guard !trimmedCustomPrompt.isEmpty else { return }
        isImprovingPrompt = true
        defer { isImprovingPrompt = false }

        do {
            let client = try AIClientFactory.createClient(config: settingsViewModel.config)
            let outcome = try await ImproveInstructionsTool.run(
                client: client,
                originalInstructions: trimmedCustomPrompt,
                workflow: selectedMode.gerund
            )

            switch outcome {
            case .replacement(let improved):
                customPrompt = improved
                showImprovePromptRequest = false
                HapticFeedbackManager.shared.success()
            case .needsUserInput(let message):
                improvePromptRequestMessage = message
                showImprovePromptRequest = true
                HapticFeedbackManager.shared.selection()
            }
        } catch {
            HapticFeedbackManager.shared.error()
        }
    }

    private var globalAutomationSelection: (provider: AIProvider, model: String) {
        let provider =
            settingsViewModel.config.automationProvider ?? settingsViewModel.config.provider
        let configuredModel =
            settingsViewModel.config.automationProvider == nil
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

    private var currentFolderConfiguration: WatchedFolder {
        var updated = folder
        updated.organizationMode = selectedMode
        updated.customPrompt =
            customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : customPrompt

        if useCustomModel {
            updated.providerOverride = selectedProvider
            updated.modelOverride = selectedModel
        } else {
            updated.providerOverride = nil
            updated.modelOverride = nil
        }

        return updated
    }

    private func openFullOrganization() {
        HapticFeedbackManager.shared.tap()

        let updatedFolder = currentFolderConfiguration
        withAnimation {
            watchedFoldersManager.updateFolder(updatedFolder)
        }

        var config = settingsViewModel.config
        config.enableSmartRename = true
        config.mode = updatedFolder.effectiveOrganizationMode
        settingsViewModel.config = config

        appState.organizer?.reset()
        appState.organizer?.customInstructions = updatedFolder.customPrompt ?? ""
        withAnimation(.pageTransition) {
            appState.selectedDirectory = updatedFolder.url
            appState.currentView = .organize
        }
        dismiss()
    }

    private func save() {
        withAnimation {
            watchedFoldersManager.updateFolder(currentFolderConfiguration)
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
                Text(LocalizedStringKey(title))
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

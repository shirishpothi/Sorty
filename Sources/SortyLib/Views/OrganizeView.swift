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
    @EnvironmentObject var codexAuth: CodexCLIAuthManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var copilotAuth = GitHubCopilotAuthManager.shared
    @StateObject private var steeringManager = SteeringPromptManager.shared

    @State private var previousState: OrganizationState?
    @State private var showSmarterRetryModelPicker = false
    @State private var showSavedPromptsSheet = false
    @State private var isReturningToStart = false
    @State private var isShowingReturnToStartContent = false
    @State private var returnsToDirectorySelection = false
    @State private var keepsReadyContentVisibleAfterReturn = false
    @State private var showsCompletionContent = false
    @State private var liveOrganizationStartedAt: Date?
    @State private var keepsLiveOrganizationVisible = false
    @State private var readyPreviewHandoffTask: Task<Void, Never>?

    private let minimumLiveOrganizationPresentation: TimeInterval = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Header with selected directory
            if let directory = appState.selectedDirectory {
                DirectoryHeader(
                    url: directory,
                    mode: settingsViewModel.config.mode,
                    onBack: {
                        HapticFeedbackManager.shared.tap()
                        switch organizer.state {
                        case .scanning, .organizing, .ready, .applying, .completed:
                            returnToStartAfterCancellation()
                        default:
                            returnToDirectorySelection()
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
                .id(settingsViewModel.config.mode)
                .transition(directoryHeaderTransition)
                .animation(directoryHeaderModeAnimation, value: settingsViewModel.config.mode)
            }

            // Main content area with animated transitions.
            ZStack {
                WorkflowGradientBackground()
                    .opacity(persistentWorkflowGradientOpacity)
                    .animation(persistentWorkflowGradientAnimation, value: persistentWorkflowGradientOpacity)
                    .allowsHitTesting(false)

                if appState.selectedDirectory == nil {
                    DirectorySelectionView(
                        selectedDirectory: $appState.selectedDirectory,
                        startsVisible: isShowingReturnToStartContent
                    )
                        .transition(TransitionStyles.scaleAndFade)
                } else {
                    stateContent
                        .environment(\.workflowGradientHidden, true)
                        .opacity(stateContentOpacity)
                        .scaleEffect(stateContentScale)
                        .blur(radius: stateContentBlur)
                        .offset(y: stateContentOffset)

                    if isShowingReturnToStartContent {
                        returnToStartContent
                            .environment(\.workflowGradientHidden, true)
                            .opacity(returnToStartContentOpacity)
                            .scaleEffect(returnToStartContentScale)
                            .offset(y: returnToStartContentOffset)
                            .transition(.identity)
                    }
                }
            }
        }
        .navigationTitle(settingsViewModel.config.mode.workflowTitle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Organization workflow")
        .accessibilityHint("Select a folder and configure options")
        .onAppear {
            configureOrganizer()
            presentSteeringPromptsIfRequested()
        }
        .onChange(of: appState.shouldPresentSteeringPrompts) { _, _ in
            presentSteeringPromptsIfRequested()
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
        .modelSelectionOverlay(
            isPresented: $showSmarterRetryModelPicker,
            currentProvider: settingsViewModel.config.provider,
            currentModel: settingsViewModel.config.model,
            contextMessage: "Select a stronger model to retry this failed organization attempt. Your selection also becomes the active model for future runs.",
            selectionActionTitle: "Retry with Model",
            onSelect: retryWithSelectedModel
        )
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
        .onAppear {
            updateSetupRepairHUD()
        }
        .onChange(of: activeSetupRepairMessage) {
            updateSetupRepairHUD()
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        stateContentInner
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
    }

    private var persistentWorkflowGradientOpacity: Double {
        guard appState.selectedDirectory != nil else { return 0 }
        return 1
    }

    private var persistentWorkflowGradientAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.52)
    }

    private var directoryHeaderTransition: AnyTransition {
        reduceMotion ? .opacity : .headerBlurReplace
    }

    private var directoryHeaderModeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.4, dampingFraction: 0.85)
    }

    private var stateContentOpacity: Double {
        if isReturningToStart { return 0 }
        return 1
    }

    private var stateContentScale: CGFloat {
        1
    }

    private var stateContentBlur: CGFloat {
        // Blur during transitions is expensive on macOS and was producing a
        // visible "reload" wobble when returning from a cancelled run.
        0
    }

    private var stateContentOffset: CGFloat {
        0
    }

    private var returnToStartContentOpacity: Double {
        isReturningToStart ? 1 : 0
    }

    private var returnToStartContentScale: CGFloat {
        1
    }

    private var returnToStartContentOffset: CGFloat {
        0
    }

    private var returnToStartContent: some View {
        Group {
            if returnsToDirectorySelection {
                DirectorySelectionView(
                    selectedDirectory: $appState.selectedDirectory,
                    startsVisible: true
                )
            } else {
                ReadyToOrganizeView(onStart: startOrganization, startsVisible: true)
            }
        }
    }

    @ViewBuilder
    private var stateContentInner: some View {
        if shouldShowCompletionView {
            completionHandoffContent
        } else {
            stateContentSwitch
        }
    }

    @ViewBuilder
    private var completionHandoffContent: some View {
        ZStack {
            if let plan = organizer.currentPlan {
                PreviewView(
                    plan: plan,
                    baseURL: appState.selectedDirectory ?? URL(fileURLWithPath: "/"),
                    onReturnToStart: returnToStartAfterCancellation
                )
                .opacity(isCompletionContentVisible ? 0 : 1)
                .blur(radius: completionPreviewBlur)
                .scaleEffect(isCompletionContentVisible && !reduceMotion ? 0.992 : 1)
                .allowsHitTesting(!isCompletionContentVisible)

                OrganizationCompleteView(
                    stats: plan.generationStats,
                    totalFiles: plan.suggestions.reduce(0) { $0 + $1.totalFileCount },
                    totalFolders: plan.suggestions.count,
                    renameCount: plan.suggestions.reduce(0) { $0 + $1.allFileRenameMappings.filter { $0.hasRename }.count },
                    mode: settingsViewModel.config.mode,
                    directoryURL: appState.selectedDirectory ?? URL(fileURLWithPath: "/"),
                    onReturnToStart: returnToStartAfterCancellation
                )
                .opacity(isCompletionContentVisible ? 1 : 0)
                .scaleEffect(isCompletionContentVisible || reduceMotion ? 1 : 0.985)
                .offset(y: isCompletionContentVisible || reduceMotion ? 0 : 10)
                .allowsHitTesting(isCompletionContentVisible)
            } else {
                OrganizationCompleteView(
                    stats: nil,
                    totalFiles: 0,
                    totalFolders: 0,
                    renameCount: 0,
                    mode: settingsViewModel.config.mode,
                    directoryURL: appState.selectedDirectory ?? URL(fileURLWithPath: "/"),
                    onReturnToStart: returnToStartAfterCancellation
                )
            }
        }
        .animation(completionHandoffAnimation, value: showsCompletionContent)
    }

    private var completionPreviewBlur: CGFloat {
        isCompletionContentVisible && !reduceMotion ? 2 : 0
    }

    private var completionHandoffAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.42)
    }

    private var shouldShowCompletionView: Bool {
        if case .completed = organizer.state { return true }
        return organizer.pinsCompletionView
    }

    private var isCompletionContentVisible: Bool {
        if case .completed = organizer.state { return true }
        return showsCompletionContent
    }

    @ViewBuilder
    private var stateContentSwitch: some View {
        switch organizer.state {
        case .idle:
            if needsSetupRepair {
                SetupRepairGateView(
                    message: activeSetupRepairMessage ?? "Finish setting up your provider before organizing files.",
                    onOpenSettings: {
                        HapticFeedbackManager.shared.selection()
                        appState.startSetupRepair(
                            message: activeSetupRepairMessage ?? "Finish setting up your provider before organizing files.",
                            navigateToSettings: true
                        )
                    }
                )
            } else {
                ReadyToOrganizeView(
                    onStart: startOrganization,
                    startsVisible: isShowingReturnToStartContent
                        || keepsReadyContentVisibleAfterReturn
                        || appState.hasPresentedReadyToOrganize
                )
            }
        case .scanning, .organizing, .applying:
            AnalysisView(
                onReturnToStart: returnToStartAfterCancellation,
                onLiveOrganizationStarted: noteLiveOrganizationStarted
            )
        case .ready:
            if keepsLiveOrganizationVisible {
                AnalysisView(
                    onReturnToStart: returnToStartAfterCancellation,
                    onLiveOrganizationStarted: noteLiveOrganizationStarted
                )
            } else if let plan = organizer.currentPlan {
                PreviewView(
                    plan: plan,
                    baseURL: appState.selectedDirectory!,
                    onReturnToStart: returnToStartAfterCancellation
                )
            } else {
                PreviewHandoffView(mode: settingsViewModel.config.mode)
            }
        case .completed:
            completionHandoffContent
        case .error(let error):
            ErrorView(
                error: error,
                onRetry: {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.pageTransition) {
                        organizer.reset()
                    }
                },
                onRetryWithSmarterModel: {
                    showSmarterRetryModelPicker = true
                }
            )
        }
    }

    private var returnToStartExitAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.08 : 0.14)
    }

    private func returnToStartAfterCancellation() {
        guard !isReturningToStart else { return }

        let stateAtReturnStart = organizer.state
        let isReturningFromCompletion: Bool
        if case .completed = stateAtReturnStart {
            isReturningFromCompletion = true
        } else {
            isReturningFromCompletion = false
        }
        returnsToDirectorySelection = isReturningFromCompletion
        isShowingReturnToStartContent = true
        if !isReturningFromCompletion {
            organizer.prepareForReturnToStartTransition()
        }

        withAnimation(returnToStartExitAnimation, completionCriteria: .logicallyComplete) {
            isReturningToStart = true
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if isReturningFromCompletion {
                    organizer.pinsCompletionView = false
                    organizer.reset()
                    appState.selectedDirectory = nil
                } else {
                    organizer.cancel()
                }
                showsCompletionContent = false
                keepsReadyContentVisibleAfterReturn = !isReturningFromCompletion
                isShowingReturnToStartContent = false
                returnsToDirectorySelection = false
                isReturningToStart = false
            }
        }
    }

    private func returnToDirectorySelection() {
        guard !isReturningToStart else { return }

        returnsToDirectorySelection = true
        isShowingReturnToStartContent = true
        withAnimation(returnToStartExitAnimation, completionCriteria: .logicallyComplete) {
            isReturningToStart = true
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                organizer.reset()
                appState.selectedDirectory = nil
                showsCompletionContent = false
                keepsReadyContentVisibleAfterReturn = false
                isShowingReturnToStartContent = false
                returnsToDirectorySelection = false
                isReturningToStart = false
            }
        }
    }

    private func handleStateChange(to newState: OrganizationState) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            switch newState {
            case .completed:
                HapticFeedbackManager.shared.success()
                beginCompletionHandoff()
            case .error:
                showsCompletionContent = false
                HapticFeedbackManager.shared.error()
            case .ready:
                showsCompletionContent = false
                HapticFeedbackManager.shared.success()
            case .scanning, .organizing:
                showsCompletionContent = false
                HapticFeedbackManager.shared.selection()
            default:
                break
            }
        }

        switch newState {
        case .ready:
            scheduleReadyPreviewHandoff()
        case .completed, .error, .idle:
            resetLiveOrganizationPresentation()
        default:
            break
        }

        previousState = newState
    }

    private func noteLiveOrganizationStarted() {
        guard !reduceMotion, liveOrganizationStartedAt == nil else { return }
        liveOrganizationStartedAt = Date()
        keepsLiveOrganizationVisible = true

        // The throttled stream update can arrive after the organizer reaches
        // ready, so schedule the handoff here as well as in handleStateChange.
        if organizer.state == .ready {
            scheduleReadyPreviewHandoff()
        }
    }

    private func scheduleReadyPreviewHandoff() {
        guard !reduceMotion,
              keepsLiveOrganizationVisible,
              let liveOrganizationStartedAt else {
            resetLiveOrganizationPresentation()
            return
        }

        let elapsed = Date().timeIntervalSince(liveOrganizationStartedAt)
        let remaining = minimumLiveOrganizationPresentation - elapsed
        guard remaining > 0 else {
            finishLiveOrganizationPresentation()
            return
        }

        readyPreviewHandoffTask?.cancel()
        readyPreviewHandoffTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, organizer.state == .ready else { return }
            finishLiveOrganizationPresentation()
        }
    }

    private func finishLiveOrganizationPresentation() {
        readyPreviewHandoffTask?.cancel()
        readyPreviewHandoffTask = nil
        liveOrganizationStartedAt = nil
        withAnimation(.smooth(duration: 0.34)) {
            keepsLiveOrganizationVisible = false
        }
    }

    private func resetLiveOrganizationPresentation() {
        readyPreviewHandoffTask?.cancel()
        readyPreviewHandoffTask = nil
        liveOrganizationStartedAt = nil
        keepsLiveOrganizationVisible = false
    }

    private func beginCompletionHandoff() {
        guard !showsCompletionContent else { return }

        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.42)) {
            showsCompletionContent = true
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
        guard !needsSetupRepair else {
            HapticFeedbackManager.shared.error()
            appState.startSetupRepair(
                message: activeSetupRepairMessage ?? "Finish setting up your provider before organizing files."
            )
            return
        }

        HapticFeedbackManager.shared.tap()
        resetLiveOrganizationPresentation()
        keepsReadyContentVisibleAfterReturn = false

        // Apply default steering prompt if no custom instructions provided
        if organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultPrompt = SteeringPromptManager.shared.defaultPrompt {
            organizer.customInstructions = defaultPrompt.prompt
        }

        Task {
            do {
                await appState.prepareForManualOrganization(at: directory)
                try await organizer.organize(directory: directory)
            } catch {
                organizer.state = .error(error)
            }
        }
    }

    private func retryWithSelectedModel(provider: AIProvider, model: String) {
        Task {
            do {
                settingsViewModel.config.provider = provider
                settingsViewModel.config.model = model
                try await organizer.configure(with: settingsViewModel.config)
                try await organizer.regenerateWithModel(provider: provider, model: model)
            } catch {
                await MainActor.run {
                    organizer.state = .error(error)
                }
            }
        }
    }
    
    private func prewarmAIConnection() async {
        let provider = settingsViewModel.config.provider
        let config = settingsViewModel.config
        await AISessionManager.shared.prewarm(provider: provider, config: config)
    }

    private func presentSteeringPromptsIfRequested() {
        guard appState.shouldPresentSteeringPrompts else { return }
        showSavedPromptsSheet = true
        appState.shouldPresentSteeringPrompts = false
    }

    private var providerSetupStatus: ProviderSetupStatus {
        OnboardingSetupValidator.providerStatus(
            context: ProviderSetupContext(
                config: settingsViewModel.config,
                isGitHubCopilotAuthenticated: copilotAuth.isAuthenticated,
                isCodexAuthenticated: codexAuth.isAuthenticated,
                isCodexInstalled: codexAuth.isCodexInstalled,
                isAppleFoundationModelAvailable: settingsViewModel.isAppleModelAvailable,
                appleFoundationModelStatus: settingsViewModel.appleModelStatus
            )
        )
    }

    private var needsSetupRepair: Bool {
        appState.requiresSetupRepair || !providerSetupStatus.isReady
    }

    private var activeSetupRepairMessage: String? {
        if appState.requiresSetupRepair {
            return appState.setupRepairMessage ?? providerSetupStatus.message
        }
        if !providerSetupStatus.isReady {
            return providerSetupStatus.message
        }
        return nil
    }

    private func updateSetupRepairHUD() {
        guard let message = activeSetupRepairMessage else {
            NotificationManager.shared.dismissHUD(identifier: "setup-repair")
            return
        }

        appState.presentSetupRepairHUD(message: message)
    }

}

// MARK: - Directory Header

struct DirectoryHeader: View {
    let url: URL
    let mode: OrganizationMode
    let onBack: () -> Void
    let onClear: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHoveringPath = false

    var body: some View {
        HStack(spacing: 12) {
            GlassyBackButton(action: onBack)
                .padding(.trailing, 4)

            Button(action: revealSelectedDirectory) {
                FolderThumbnailView(url: url, size: CGSize(width: 32, height: 32))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reveal \(url.lastPathComponent) in Finder")
            .accessibilityLabel("Reveal \(url.lastPathComponent) in Finder") // [VERIFY] confirm label matches intent

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                        .accessibilityHidden(true)

                    Text(mode.workflowTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button(action: revealSelectedDirectory) {
                    HStack(spacing: 5) {
                        PrivacySensitivePathText(path: url.deletingLastPathComponent().path)
                            .lineLimit(1)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 10)
                            .opacity(isHoveringPath ? 1 : 0)
                            .offset(
                                x: reduceMotion || isHoveringPath ? 0 : -3,
                                y: reduceMotion || isHoveringPath ? 0 : 3
                            )
                            .scaleEffect(reduceMotion || isHoveringPath ? 1 : 0.75)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Reveal \(url.lastPathComponent) in Finder")
                .accessibilityLabel("Reveal \(url.lastPathComponent) in Finder") // [VERIFY] confirm label matches intent
                .animation(
                    reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
                    value: isHoveringPath
                )
                .onHover { hovering in
                    isHoveringPath = hovering
                }
            }

            Spacer()

            Button {
                onClear()
            } label: {
                Label("Change Folder", systemImage: "folder.badge.gearshape")
            }
            .buttonStyle(.sortyBordered(size: .small))
            .accessibilityIdentifier("ChangeFolderButton")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private func revealSelectedDirectory() {
        HapticFeedbackManager.shared.tap()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}

private struct HeaderBlurReplaceModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var headerBlurReplace: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: HeaderBlurReplaceModifier(radius: 7, opacity: 0),
                identity: HeaderBlurReplaceModifier(radius: 0, opacity: 1)
            ),
            removal: .modifier(
                active: HeaderBlurReplaceModifier(radius: 5, opacity: 0),
                identity: HeaderBlurReplaceModifier(radius: 0, opacity: 1)
            )
        )
    }
}

private struct SetupRepairGateView: View {
    let message: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Finish Provider Setup")
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("Open Provider Settings", action: onOpenSettings)
                .buttonStyle(.sortyProminent)
                .accessibilityIdentifier("OpenProviderSettingsForRepairButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

// MARK: - Ready to Organize View

struct ReadyToOrganizeView: View {
    let onStart: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var showImprovePromptRequest = false
    @State private var improvePromptRequestMessage = ""
    @State private var showSavedPromptsSheet = false
    @State private var showStorageLocationsInfo = false
    @State private var referenceableFiles: [InstructionFileReference] = []
    @State private var instructionSelection: NSRange = NSRange(location: 0, length: 0)
    @State private var referenceRefreshTask: Task<Void, Never>?
    @State private var startCTACompression: CGFloat = 0

    init(onStart: @escaping () -> Void, startsVisible: Bool = false) {
        self.onStart = onStart
        _hasAppeared = State(initialValue: startsVisible)
    }

    private var mode: OrganizationMode {
        settingsViewModel.config.mode
    }
    
    private var isConnecting: Bool {
        sessionManager.prewarmingProvider != nil
    }

    private var selectedStorageLocationCount: Int {
        storageLocationsManager.locations.filter(\.isEnabled).count
    }

    private var unavailableSelectedStorageLocationCount: Int {
        max(0, selectedStorageLocationCount - storageLocationsManager.enabledLocations.count)
    }

    private var storageLocationSummaryID: String {
        if selectedStorageLocationCount > 0 {
            return unavailableSelectedStorageLocationCount > 0
                ? "selected-unavailable"
                : "selected-available"
        }

        return storageLocationsManager.locations.isEmpty ? "unconfigured" : "inactive"
    }

    private var storageLocationSummaryTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.94, anchor: .leading))
    }

    private var storageLocationTitle: String {
        selectedStorageLocationCount == 1 ? "Storage Location" : "Storage Locations"
    }

    private var storageLocationSelectionTint: Color {
        unavailableSelectedStorageLocationCount > 0 ? .orange : .green
    }

    private var storageLocationsVerticalPadding: CGFloat {
        if showStorageLocations {
            return 10
        }

        return storageLocationsManager.locations.isEmpty ? 4 : 6
    }

    private var storageLocationListIDs: [StorageLocation.ID] {
        storageLocationsManager.locations.map(\.id)
    }

    private var storageLocationInsertionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.32, dampingFraction: 0.84)
    }

    private var storageLocationRowTransition: AnyTransition {
        .opacity
    }

    private var addStorageLocationErrorIsPresented: Binding<Bool> {
        Binding(
            get: { addStorageLocationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    addStorageLocationErrorMessage = nil
                }
            }
        )
    }

    var body: some View {
        WorkflowContainer(currentStep: .configure) {
            // Compact header
            VStack(spacing: 16) {
                iconSection
                ReadyToOrganizeTitle(mode: mode)
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.96)
            .offset(y: hasAppeared ? 0 : 8)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.04), value: hasAppeared)

            // Instructions card
            WorkflowCard(title: "Instructions", icon: "text.bubble") {
                instructionsContent
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.10), value: hasAppeared)

            if mode != .renameOnly {
                WorkflowCard(verticalPadding: storageLocationsVerticalPadding) {
                    storageLocationsContent
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.16), value: hasAppeared)
            }

            ReadyToOrganizeStartButton(
                mode: mode,
                isConnecting: isConnecting,
                hasAppeared: hasAppeared,
                reduceMotion: reduceMotion,
                compression: startCTACompression,
                onStart: runStartCTAAnimation
            )

            ReadyToOrganizeKeyboardHint(
                actionVerb: mode.actionVerb,
                isConnecting: isConnecting,
                hasAppeared: hasAppeared,
                reduceMotion: reduceMotion
            )

            // Connection status indicator
            connectionStatusView
                .opacity(hasAppeared ? 1 : 0)
                .animation(reduceMotion ? nil : .smooth(duration: 0.45).delay(0.32), value: hasAppeared)
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFolderImport(result)
        }
        .alert(
            "Couldn't Add Storage Location",
            isPresented: addStorageLocationErrorIsPresented
        ) {
            Button("OK", role: .cancel) {
                addStorageLocationErrorMessage = nil
            }
        } message: {
            Text(addStorageLocationErrorMessage ?? "Please try selecting the folder again.")
        }
        .onAppear(perform: prepareForDisplay)
        .onChange(of: appState.selectedDirectory) { _, _ in
            scheduleReferenceableFilesRefresh()
        }
        .onDisappear(perform: stopReferenceRefresh)
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                HapticFeedbackManager.shared.success()
                do {
                    try withAnimation(storageLocationInsertionAnimation) {
                        try storageLocationsManager.addLocation(
                            url: url,
                            customName: suggestedLocationName
                        )
                    }
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

    private func prepareForDisplay() {
        scheduleReferenceableFilesRefresh()
        storageLocationsManager.refreshAccessStatus()

        guard !hasAppeared else { return }
        guard !appState.hasPresentedReadyToOrganize else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasAppeared = true
            }
            return
        }

        appState.hasPresentedReadyToOrganize = true
        hasAppeared = true
    }

    private func stopReferenceRefresh() {
        referenceRefreshTask?.cancel()
        referenceRefreshTask = nil
    }

    private func runStartCTAAnimation() {
        HapticFeedbackManager.shared.tap()
        guard !reduceMotion else {
            onStart()
            return
        }

        withAnimation(.spring(response: 0.18, dampingFraction: 0.56)) {
            startCTACompression = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(70))
            onStart()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                startCTACompression = 0
            }
        }
    }

    private var storageLocationsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        showStorageLocations.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedStorageLocationCount > 0 ? "externaldrive.fill" : "externaldrive")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                selectedStorageLocationCount > 0
                                    ? SortyDesignSystem.Colors.resolvedAccent
                                    : Color.secondary
                            )
                            .frame(width: 22, height: 22)
                            .background {
                                Circle()
                                    .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.32))
                                    .frame(width: 18, height: 18)
                                    .blur(radius: 5)
                                    .opacity(selectedStorageLocationCount > 0 ? 1 : 0)
                            }

                        Text(storageLocationTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .numericTextTransition(
                                animationValue: storageLocationTitle,
                                animation: .easeInOut(duration: 0.28)
                            )

                        Spacer(minLength: 8)

                        storageLocationSelectionSummary

                        Image(systemName: showStorageLocations ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 16)
                            .offset(x: 16)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(showStorageLocations ? "Hide organization locations" : "Show organization locations")
                .accessibilityLabel(showStorageLocations ? "Hide storage locations" : "Show storage locations")
                .accessibilityHint("Expand to manage local, cloud, and external organization locations")
                .accessibilityValue(showStorageLocations ? "Expanded" : "Collapsed")

                Button {
                    HapticFeedbackManager.shared.tap()
                    showStorageLocationsInfo.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showStorageLocationsInfo, arrowEdge: .bottom) {
                    StorageLocationsInfoPopover()
                        .systemLiquidGlassPopover(cornerRadius: 12)
                }
                .help("How storage locations work")
                .accessibilityLabel("About storage locations")
                .accessibilityIdentifier("StorageLocationsInfoButton")
            }
            
            if showStorageLocations {
                VStack(alignment: .leading, spacing: 10) {
                    if !storageLocationsManager.locations.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(storageLocationsManager.locations) { location in
                                CompactStorageLocationRow(location: location)
                                    .transition(storageLocationRowTransition)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .animation(storageLocationInsertionAnimation, value: storageLocationListIDs)
                    }
                    
                    HStack(alignment: .center, spacing: 14) {
                        if storageLocationsManager.locations.isEmpty {
                            Spacer()
                        }

                        Button {
                            HapticFeedbackManager.shared.tap()
                            suggestedLocationName = nil
                            showingFolderPicker = true
                        } label: {
                            Label {
                                Text("Add Custom Location")
                            } icon: {
                                Image(systemName: "plus")
                                    .rotationEffect(.degrees(showingFolderPicker ? 45 : 0))
                                    .animation(
                                        reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72),
                                        value: showingFolderPicker
                                    )
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.sortyBordered)
                        .controlSize(.small)
                        .help("Add a folder that Sorty can organize with")
                        .accessibilityHint("Opens the folder picker to add an organization location")

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(
                        storageLocationInsertionAnimation,
                        value: storageLocationsManager.locations.isEmpty
                    )
                    .padding(.top, 2)
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var storageLocationSelectionSummary: some View {
        ZStack(alignment: .trailing) {
            Group {
                if selectedStorageLocationCount > 0 {
                    HStack(spacing: 8) {
                        Text("\(selectedStorageLocationCount) selected")
                            .font(.caption)
                            .foregroundStyle(storageLocationSelectionTint)
                            .numericTextTransition(animationValue: selectedStorageLocationCount)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .systemLiquidGlassBackground(cornerRadius: 999)

                        if unavailableSelectedStorageLocationCount > 0 {
                            Text("\(unavailableSelectedStorageLocationCount) unavailable")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .numericTextTransition(
                                    animationValue: unavailableSelectedStorageLocationCount
                                )
                        }
                    }
                } else if !storageLocationsManager.locations.isEmpty {
                    Text("No active locations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No locations configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .id(storageLocationSummaryID)
            .transition(storageLocationSummaryTransition)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.26, dampingFraction: 0.86),
            value: storageLocationSummaryID
        )
        .accessibilityElement(children: .combine)
    }
    
    @ViewBuilder
    private var iconSection: some View {
        if let image = SortyResources.image(named: "ReadyToOrganizeIcon") {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .clipShape(Circle())
                .accessibilityLabel("Sorty is ready to \(mode.actionVerb.lowercased())")
        } else {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 104, height: 104)
                .accessibilityLabel("Sorty is ready to \(mode.actionVerb.lowercased())")
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
            let mention = activeFileMention

            ZStack(alignment: .topLeading) {
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
                    SubmittableTextEditor(
                        text: $organizer.customInstructions,
                        isFocused: $isTextFieldFocused,
                        selectedRange: $instructionSelection
                    ) {
                        onStart()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                if organizer.customInstructions.isEmpty {
                    Text(mode.instructionPlaceholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 18)
                        .padding(.trailing, 10)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 60, maxHeight: 80)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)

                FocusedInstructionBeamBorder(active: isTextFieldFocused)
            }
            .accessibilityIdentifier("CustomInstructionsTextField")
            .accessibilityLabel("Additional instructions for \(mode.gerund)")
            .accessibilityHint("Press Command+Enter to start \(mode.gerund), Enter for new line")
            .overlay(alignment: .bottomLeading) {
                if let mention, shouldShowReferencePicker(for: mention) {
                    InstructionFileReferencePicker(
                        matches: referenceMatches(for: mention.query),
                        query: mention.query,
                        onSelect: { reference in
                            insertReference(reference, replacing: mention)
                        }
                    )
                    .offset(y: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                    .zIndex(4)
                }
            }
            .animation(.easeInOut(duration: 0.16), value: mention?.query)

            HStack(alignment: .center, spacing: 0) {
                // Improve with AI button
                if !organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    .accessibilityHint("Rewrites your prompt to be clearer and more specific")
                    .alert("Sorty needs more detail", isPresented: $showImprovePromptRequest) {
                        Button("Edit Instructions") {
                            isTextFieldFocused = true
                        }
                    } message: {
                        Text("\(improvePromptRequestMessage)\n\nEdit the instructions above, then click Improve again.")
                    }
                }

                // Save prompt button
                if !organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                                    let prompt = SavedSteeringPrompt(
                                        name: savePromptName.isEmpty ? "Untitled" : savePromptName,
                                        prompt: organizer.customInstructions
                                    )
                                    steeringManager.addPrompt(prompt)
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
                }

                // Manage saved prompts button
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
            let outcome = try await ImproveInstructionsTool.run(
                client: client,
                originalInstructions: original,
                workflow: mode.gerund
            )

            switch outcome {
            case .replacement(let improved):
                organizer.customInstructions = improved
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

    private var activeFileMention: InstructionMentionQuery? {
        InstructionMentionQuery.active(in: organizer.customInstructions, selectedRange: instructionSelection)
    }

    private func shouldShowReferencePicker(for mention: InstructionMentionQuery) -> Bool {
        isTextFieldFocused && !mention.query.isEmpty && !referenceMatches(for: mention.query).isEmpty
    }

    private func referenceMatches(for query: String) -> [InstructionFileReference] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let matches: [InstructionFileReference]

        if normalizedQuery.isEmpty {
            matches = Array(referenceableFiles.prefix(8))
        } else {
            let prefixMatches = referenceableFiles.filter {
                $0.name.localizedLowercase.hasPrefix(normalizedQuery)
            }
            let containedMatches = referenceableFiles.filter {
                !$0.name.localizedLowercase.hasPrefix(normalizedQuery) &&
                $0.name.localizedLowercase.localizedStandardContains(normalizedQuery)
            }
            matches = Array((prefixMatches + containedMatches).prefix(8))
        }

        return matches
    }

    private func insertReference(_ reference: InstructionFileReference, replacing mention: InstructionMentionQuery) {
        var instructions = organizer.customInstructions

        let replacement = "@\(reference.displayToken)"
        instructions.replaceSubrange(mention.range, with: replacement)
        organizer.customInstructions = instructions
        instructionSelection = NSRange(location: mention.nsRange.location + (replacement as NSString).length, length: 0)
        HapticFeedbackManager.shared.selection()
    }

    private func scheduleReferenceableFilesRefresh() {
        referenceRefreshTask?.cancel()

        guard let directory = appState.selectedDirectory else {
            referenceableFiles = []
            return
        }

        referenceRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }

            let files = await Self.loadReferenceableFiles(in: directory)
            guard !Task.isCancelled else { return }
            referenceableFiles = files
            referenceRefreshTask = nil
        }
    }

    private nonisolated static func loadReferenceableFiles(in directory: URL) async -> [InstructionFileReference] {
        await Task.detached(priority: .utility) {
            referenceableFiles(in: directory)
        }.value
    }

    private nonisolated static func referenceableFiles(in directory: URL) -> [InstructionFileReference] {
        guard !Task.isCancelled else { return [] }

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            return []
        }

        var files: [InstructionFileReference] = []
        for case let url as URL in enumerator {
            guard !Task.isCancelled else { return [] }
            guard files.count < 400 else { break }
            guard let values = try? url.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else { continue }

            files.append(
                InstructionFileReference(
                    url: url,
                    baseDirectory: directory,
                    fileSize: values.fileSize
                )
            )
        }

        return files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private struct InstructionMentionQuery: Equatable {
    let range: Range<String.Index>
    let nsRange: NSRange
    let query: String

    static func active(in text: String, selectedRange: NSRange) -> InstructionMentionQuery? {
        guard selectedRange.length == 0 else { return nil }
        guard selectedRange.location <= (text as NSString).length else { return nil }
        let cursor = String.Index(utf16Offset: selectedRange.location, in: text)
        let prefix = text[..<cursor]
        guard let atIndex = prefix.lastIndex(of: "@") else { return nil }
        let afterAt = text.index(after: atIndex)
        let query = String(text[afterAt..<cursor])

        guard !query.contains(where: \.isNewline) else { return nil }
        guard query.rangeOfCharacter(from: CharacterSet(charactersIn: ",;()[]{}")) == nil else { return nil }
        guard query.count <= 80 else { return nil }
        if let characterBeforeAt = text[..<atIndex].last,
           !characterBeforeAt.isWhitespace,
           !",;([{".contains(characterBeforeAt) {
            return nil
        }

        let range = atIndex..<cursor
        return InstructionMentionQuery(
            range: range,
            nsRange: NSRange(range, in: text),
            query: query
        )
    }
}

private struct InstructionFileReference: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let name: String
    let relativePath: String
    let fileSize: Int?

    init(url: URL, baseDirectory: URL, fileSize: Int?) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.fileSize = fileSize

        let basePath = baseDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(basePath + "/") {
            self.relativePath = String(path.dropFirst(basePath.count + 1))
        } else {
            self.relativePath = url.lastPathComponent
        }
    }

    var displayToken: String {
        let token = relativePath
        return token.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;()[]{}"))) == nil ? token : "\"\(token)\""
    }

    var subtitle: String {
        let folder = URL(fileURLWithPath: relativePath).deletingLastPathComponent().path
        if folder == "." || folder == "/" || folder.isEmpty {
            return formattedSize
        }
        return "\(folder) • \(formattedSize)"
    }

    private var formattedSize: String {
        guard let fileSize else { return "File" }
        return ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }
}

private struct InstructionFileReferencePicker: View {
    let matches: [InstructionFileReference]
    let query: String
    let onSelect: (InstructionFileReference) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "at")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
                Text("Reference a file")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↩ to insert")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            ForEach(matches) { reference in
                Button {
                    onSelect(reference)
                } label: {
                    HStack(spacing: 10) {
                        FileThumbnailView(url: reference.url, size: CGSize(width: 24, height: 24))
                            .frame(width: 24, height: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            highlightedName(reference.name)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)

                            Text(reference.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if !reference.url.pathExtension.isEmpty {
                            Text(".\(reference.url.pathExtension)")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.teal.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reference \(reference.name)")
                .accessibilityHint("Adds this file reference to the instructions")
            }
        }
        .padding(6)
        .frame(width: 360)
        .systemLiquidGlassPopover(cornerRadius: 12)
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 10)
    }

    private func highlightedName(_ name: String) -> Text {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              let range = name.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(name)
        }

        let prefix = String(name[..<range.lowerBound])
        let match = String(name[range])
        let suffix = String(name[range.upperBound...])
        return Text(prefix) + Text(match).foregroundStyle(.teal) + Text(suffix)
    }
}

private struct PreviewHandoffView: View {
    let mode: OrganizationMode
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 48, height: 48)

                Image(systemName: mode == .renameOnly ? "text.badge.checkmark" : "checkmark.circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .scaleEffect(appeared ? 1 : 0.88)
            }

            Text(mode == .renameOnly ? "Preparing name preview" : "Preparing preview")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.32))
                        .frame(width: 5, height: 5)
                        .modifier(PreviewHandoffDot(delay: Double(index) * 0.14))
                }
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .animation(.smooth(duration: 0.28), value: appeared)
        .onAppear { appeared = true }
    }
}

private struct PreviewHandoffDot: ViewModifier {
    let delay: Double
    @State private var isOn = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isOn ? 1.22 : 0.78)
            .opacity(isOn ? 0.88 : 0.35)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.58).repeatForever().delay(delay)) {
                    isOn = true
                }
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
    @State private var showImprovePromptRequest = false
    @State private var improvePromptRequestMessage = ""
    @FocusState private var isEditTextFocused: Bool
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
                .buttonStyle(.sortyBordered)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.sortyProminent)
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
                    .focused($isEditTextFocused)
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
                            Label("Improve with Sorty", systemImage: "wand.and.stars")
                        }
                    }
                    .buttonStyle(.sortyBordered)
                    .controlSize(.small)
                    .disabled(editText.trimmingCharacters(in: .whitespaces).isEmpty || improvingPromptId == prompt.id)
                    .alert("Sorty needs more detail", isPresented: $showImprovePromptRequest) {
                        Button("Edit Instructions") {
                            isEditTextFocused = true
                        }
                    } message: {
                        Text(
                            "\(improvePromptRequestMessage)\n\nEdit the instructions above, then click Improve again."
                        )
                    }

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
                    .buttonStyle(.sortyProminent)
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
                    .buttonStyle(.sortyProminent)
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
            let outcome = try await ImproveInstructionsTool.run(
                client: client,
                originalInstructions: original,
                workflow: "organization"
            )

            switch outcome {
            case .replacement(let replacement):
                editText = replacement
                showImprovePromptRequest = false
                HapticFeedbackManager.shared.success()
            case .needsUserInput(let message):
                improvePromptRequestMessage = message
                showImprovePromptRequest = true
                HapticFeedbackManager.shared.tap()
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingConfig = false
    @State private var showReauthorizePicker = false
    @State private var isHoveringPath = false

    private var needsAttention: Bool {
        !location.exists || location.accessStatus == .lost
    }

    private var statusHelp: String? {
        if !location.exists { return "Folder not found" }
        if location.accessStatus == .lost { return "Access to this folder was lost. Grant access again." }
        if location.accessStatus == .stale { return "Access is being refreshed automatically" }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: location.isEnabled ? "externaldrive.fill" : "externaldrive")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.blue)

                if needsAttention {
                    Image(systemName: !location.exists ? "exclamationmark.triangle.fill" : "lock.slash.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(!location.exists ? .red : .orange)
                        .offset(x: 5, y: 4)
                        .accessibilityHidden(true)
                }
            }
            .help(statusHelp ?? "")

            VStack(alignment: .leading, spacing: 2) {
                Text(location.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(location.isEnabled ? .primary : .secondary)
                
                Button {
                    HapticFeedbackManager.shared.tap()
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
                } label: {
                    HStack(spacing: 5) {
                        PrivacySensitivePathText(path: location.path, revealOnClick: false)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 10)
                            .opacity(isHoveringPath ? 1 : 0)
                            .offset(
                                x: reduceMotion || isHoveringPath ? 0 : -3,
                                y: reduceMotion || isHoveringPath ? 0 : 3
                            )
                            .scaleEffect(reduceMotion || isHoveringPath ? 1 : 0.75)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .help("Reveal \(location.name) in Finder")
                .accessibilityLabel("Reveal \(location.name) in Finder")
                .animation(
                    reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
                    value: isHoveringPath
                )
                .onHover { hovering in
                    isHoveringPath = hovering
                }
            }
            
            Spacer()

            if location.accessStatus == .lost {
                Button("Grant Access") {
                    HapticFeedbackManager.shared.tap()
                    showReauthorizePicker = true
                }
                .font(.caption2)
                .buttonStyle(.sortyBordered)
                .controlSize(.mini)
                .help("Re-select this folder to restore access")
                .accessibilityLabel("Grant access to \(location.name)")
            }

            HStack(spacing: 6) {
                Button {
                    HapticFeedbackManager.shared.tap()
                    showingConfig = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.mini)
                .help("Customize \(location.name)")
                .accessibilityLabel("Customize \(location.name)")

                Button(role: .destructive) {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        storageLocationsManager.removeLocation(location)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.mini)
                .help("Remove \(location.name)")
                .accessibilityLabel("Remove \(location.name)")
            }

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
            .accessibilityLabel("Enable \(location.name)")
            .accessibilityValue(location.isEnabled ? "On" : "Off")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
            }
            Button("Customize...") {
                showingConfig = true
            }
            Divider()
            Button("Remove", role: .destructive) {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    storageLocationsManager.removeLocation(location)
                }
            }
        }
        .sheet(isPresented: $showingConfig) {
            StorageLocationConfigView(location: location)
                .modalBounce()
        }
        .fileImporter(
            isPresented: $showReauthorizePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                storageLocationsManager.reauthorizeLocation(location, with: url)
            }
        }
    }
}

// MARK: - Storage Locations Info Popover

struct StorageLocationsInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("How Storage Locations Work", systemImage: "externaldrive")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 10) {
                InfoRow(icon: "arrow.right.circle", text: "Files can be moved TO enabled locations during organization")
                InfoRow(icon: "xmark.circle", text: "Files already inside a location will NOT be reorganized")
                InfoRow(icon: "brain", text: "Sorty matches files using each location's description — customize it to steer results")
                InfoRow(icon: "externaldrive.fill.badge.icloud", text: "Local, cloud, and external drive folders are all supported")
                InfoRow(icon: "checkmark.shield", text: "Folder access is checked automatically; Sorty asks only if it needs you to re-grant access")
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    let onRetry: () -> Void
    let onRetryWithSmarterModel: () -> Void

    private enum ErrorActionFeedback {
        case cancel
        case retry
        case settings
        case copy
    }

    @State private var showRetryOptions = false
    @State private var showCopiedFeedback = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var activeActionFeedback: ErrorActionFeedback?
    @State private var actionFeedbackResetTask: Task<Void, Never>?
    
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var organizer: FolderOrganizer
    
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
            return "Try again, or retry with a smarter model. If this keeps happening, open Help & Support with the copied error details."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: errorIcon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 8) {
                Text(errorTitle)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                Text(recoveryText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            HStack(spacing: 12) {
                Button {
                    HapticFeedbackManager.shared.tap()
                    animateActionFeedback(.cancel)
                    organizer.reset()
                    appState.selectedDirectory = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .symbolEffect(.bounce, value: activeActionFeedback == .cancel)
                        Text("Cancel")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.tintedPill(.red, size: .small))
                .scaleEffect(activeActionFeedback == .cancel ? 1.04 : 1.0)
                .help("Return to folder selection")
                .accessibilityIdentifier("ErrorBackToFolderPickerButton")

                Button {
                    HapticFeedbackManager.shared.tap()
                    animateActionFeedback(.retry)
                    showRetryOptions = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .symbolEffect(.bounce, value: activeActionFeedback == .retry)
                        Text("Retry")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.onboardingPill(size: .small))
                .scaleEffect(activeActionFeedback == .retry ? 1.04 : 1.0)
                .help("Choose how to retry this organization")
                .accessibilityIdentifier("ErrorTryAgainButton")
                .modelSelectorTriggerBounds()

                if category == .apiKey || category == .permissions {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        animateActionFeedback(.settings)
                        appState.openSettingsWindow(
                            section: category == .apiKey ? .provider : .troubleshooting
                        )
                        appState.navigatedFromSettings = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 10, weight: .semibold))
                                .symbolEffect(.bounce, value: activeActionFeedback == .settings)
                            Text("Settings")
                                .font(.caption.bold())
                        }
                    }
                    .buttonStyle(.tintedPill(.indigo, size: .small))
                    .scaleEffect(activeActionFeedback == .settings ? 1.04 : 1.0)
                    .help("Open Settings to resolve this issue")
                    .accessibilityIdentifier("ErrorOpenSettingsButton")
                }

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error.localizedDescription, forType: .string)
                    HapticFeedbackManager.shared.selection()
                    animateActionFeedback(.copy)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        showCopiedFeedback = true
                    }
                    copyResetTask?.cancel()
                    copyResetTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                            showCopiedFeedback = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopiedFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: activeActionFeedback == .copy)
                        Text(showCopiedFeedback ? "Copied" : "Copy")
                            .font(.caption.bold())
                            .contentTransition(.opacity)
                    }
                }
                .buttonStyle(.tintedPill(.orange, size: .small))
                .scaleEffect(showCopiedFeedback || activeActionFeedback == .copy ? 1.04 : 1.0)
                .help("Copy error details for support")
                .accessibilityIdentifier("ErrorCopyDetailsButton")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .confirmationDialog(
            "Retry Options",
            isPresented: $showRetryOptions,
            titleVisibility: .visible
        ) {
            Button("Retry with Current Model") {
                HapticFeedbackManager.shared.tap()
                onRetry()
            }

            Button("Choose Smarter Model") {
                HapticFeedbackManager.shared.tap()
                onRetryWithSmarterModel()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Retry using your current model, or choose a smarter model first.")
        }
    }

    private func animateActionFeedback(_ action: ErrorActionFeedback) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            activeActionFeedback = action
        }

        actionFeedbackResetTask?.cancel()
        actionFeedbackResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                activeActionFeedback = nil
            }
        }
    }
}

private struct FocusedInstructionBeamBorder: View {
    let active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.TimelineView(.animation(paused: reduceMotion || !active)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate / 1.96

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: 0.08),
                            .init(color: Color(red: 0.08, green: 0.80, blue: 1.0).opacity(0.36), location: 0.16),
                            .init(color: Color(red: 0.92, green: 0.16, blue: 0.58).opacity(0.62), location: 0.25),
                            .init(color: .white.opacity(0.88), location: 0.32),
                            .init(color: Color(red: 1.0, green: 0.34, blue: 0.18).opacity(0.54), location: 0.39),
                            .init(color: Color(red: 0.40, green: 0.20, blue: 1.0).opacity(0.36), location: 0.48),
                            .init(color: .clear, location: 0.58),
                            .init(color: .clear, location: 1.00),
                        ],
                        center: .center,
                        angle: .degrees((phase.truncatingRemainder(dividingBy: 1)) * 360)
                    ),
                    lineWidth: 1.2
                )
                .opacity(active ? 0.95 : 0)
                .animation(.easeOut(duration: 0.2), value: active)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Custom Text Editor with Enter to Submit

/// A TextEditor that treats Cmd+Enter as submit and Enter as new line
struct SubmittableTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Binding<Bool>?
    var selectedRange: Binding<NSRange>?
    var onSubmit: () -> Void

    init(
        text: Binding<String>,
        isFocused: Binding<Bool>? = nil,
        selectedRange: Binding<NSRange>? = nil,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.isFocused = isFocused
        self.selectedRange = selectedRange
        self.onSubmit = onSubmit
    }
    
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
        textView.textContainerInset = NSSize(width: 10, height: 7)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false

        context.coordinator.selectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification,
            object: textView,
            queue: .main
        ) { [weak textView, weak coordinator = context.coordinator] _ in
            guard let textView, let coordinator else { return }
            coordinator.updateFocusState(for: textView)
            coordinator.updateSelectedRange(from: textView)
        }
        
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak textView, weak coordinator = context.coordinator] event in
            guard let tv = textView else { return event }

            DispatchQueue.main.async {
                coordinator?.updateFocusState(for: tv)
            }

            guard event.type == .keyDown else { return event }
            guard tv.window?.firstResponder === tv else { return event }
            
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
            let selectedRanges = selectedRange.map { [NSValue(range: $0.wrappedValue)] } ?? textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        } else if let selectedRange,
                  textView.selectedRange() != selectedRange.wrappedValue,
                  selectedRange.wrappedValue.location + selectedRange.wrappedValue.length <= (textView.string as NSString).length {
            textView.setSelectedRange(selectedRange.wrappedValue)
        }
        
        context.coordinator.onSubmit = onSubmit
        context.coordinator.isFocused = isFocused
        context.coordinator.selectedRange = selectedRange

        context.coordinator.updateFocusState(for: textView)
        context.coordinator.updateSelectedRange(from: textView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, selectedRange: selectedRange, onSubmit: onSubmit)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>?
        var selectedRange: Binding<NSRange>?
        var onSubmit: () -> Void
        var eventMonitor: Any?
        var selectionObserver: NSObjectProtocol?
        
        init(
            text: Binding<String>,
            isFocused: Binding<Bool>?,
            selectedRange: Binding<NSRange>?,
            onSubmit: @escaping () -> Void
        ) {
            self.text = text
            self.isFocused = isFocused
            self.selectedRange = selectedRange
            self.onSubmit = onSubmit
        }
        
        deinit {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let selectionObserver {
                NotificationCenter.default.removeObserver(selectionObserver)
            }
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            updateSelectedRange(from: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            isFocused?.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isFocused?.wrappedValue = false
        }

        func updateFocusState(for textView: NSTextView) {
            guard let isFocused else { return }
            let currentlyFocused = textView.window?.firstResponder === textView
            if isFocused.wrappedValue != currentlyFocused {
                isFocused.wrappedValue = currentlyFocused
            }
        }

        func updateSelectedRange(from textView: NSTextView) {
            guard let selectedRange else { return }
            let currentRange = textView.selectedRange()
            if selectedRange.wrappedValue != currentRange {
                selectedRange.wrappedValue = currentRange
            }
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
    let codexAuthManager = CodexCLIAuthManager()

    OrganizeView()
        .environmentObject(OrganizePreviewObjects.idleOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(AppState.preview)
        .environmentObject(CustomPersonaStore.preview)
        .environmentObject(LearningsManager.preview)
        .environmentObject(codexAuthManager)
        .frame(width: 900, height: 600)
}

#Preview("Organize View - Scanning") {
    let codexAuthManager = CodexCLIAuthManager()

    OrganizeView()
        .environmentObject(OrganizePreviewObjects.scanningOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(AppState.preview)
        .environmentObject(CustomPersonaStore.preview)
        .environmentObject(LearningsManager.preview)
        .environmentObject(codexAuthManager)
        .frame(width: 900, height: 600)
}

#Preview("Organize View - Ready") {
    let codexAuthManager = CodexCLIAuthManager()

    OrganizeView()
        .environmentObject(OrganizePreviewObjects.readyOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(OrganizePreviewObjects.readyAppState)
        .environmentObject(CustomPersonaStore.preview)
        .environmentObject(LearningsManager.preview)
        .environmentObject(codexAuthManager)
        .frame(width: 900, height: 700)
}

#Preview("Organize View - Error") {
    let codexAuthManager = CodexCLIAuthManager()

    OrganizeView()
        .environmentObject(OrganizePreviewObjects.errorOrganizer)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(AppState.preview)
        .environmentObject(CustomPersonaStore.preview)
        .environmentObject(LearningsManager.preview)
        .environmentObject(codexAuthManager)
        .frame(width: 900, height: 600)
}

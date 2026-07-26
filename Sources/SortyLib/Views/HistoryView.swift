//
//  HistoryView.swift
//  Sorty
//
//  Advanced History view with 6 stats, card-based layout matching DuplicatesView style
//  Enhanced with haptic feedback, micro-animations, and full ARIA accessibility
//

import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var learningsManager: LearningsManager
    @State private var selectedEntry: OrganizationHistoryEntry?
    @State private var isProcessing = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var selectedFilter: HistoryFilter = .all
    @State private var searchText: String = ""
    @State private var contentOpacity: Double = 0
    @State private var showingDetail = false
    @State private var showWatchedAutomations = true
    @State private var showRedoModelPicker = false
    @State private var redoModelEntry: OrganizationHistoryEntry?
    @State private var activeNotificationRedoRequestID: UUID?

    // Partial result state for inline undo
    @State private var showPartialResultSheet = false
    @State private var partialUndoResult: PartialUndoResult?

    // Lazy loading state
    @State private var displayedEntryCount: Int = 50
    @State private var isLoadingMore: Bool = false
    private let pageSize: Int = 50
    private let loadMoreThreshold: Int = 10 // Load more when within 10 items of end

    private var allFilteredEntries: [OrganizationHistoryEntry] {
        let statusFiltered: [OrganizationHistoryEntry]
        switch selectedFilter {
        case .all:
            statusFiltered = organizer.history.entries
        case .success:
            statusFiltered = organizer.history.entries.filter { $0.status == .completed }
        case .failed:
            statusFiltered = organizer.history.entries.filter { $0.status == .failed }
        case .skipped:
            statusFiltered = organizer.history.entries.filter { $0.status == .skipped || $0.status == .cancelled }
        case .manual:
            statusFiltered = organizer.history.entries.filter { $0.source == .manual }
        case .watched:
            statusFiltered = organizer.history.entries.filter { $0.source == .watchedFolder }
        }

        guard !searchText.isEmpty else { return statusFiltered }
        let query = searchText.lowercased()
        return statusFiltered.filter { entry in
            entry.directoryPath.lowercased().contains(query) ||
            URL(fileURLWithPath: entry.directoryPath).lastPathComponent.lowercased().contains(query)
        }
    }

    private var manualEntries: [OrganizationHistoryEntry] {
        Array(allFilteredEntries.filter { $0.source == .manual }.prefix(displayedEntryCount))
    }

    private var watchedEntries: [OrganizationHistoryEntry] {
        Array(allFilteredEntries.filter { $0.source == .watchedFolder }.prefix(displayedEntryCount))
    }

    private var totalManualFilteredCount: Int {
        allFilteredEntries.filter { $0.source == .manual }.count
    }

    private var totalWatchedFilteredCount: Int {
        allFilteredEntries.filter { $0.source == .watchedFolder }.count
    }

    private var hasMoreEntries: Bool {
        switch selectedFilter {
        case .manual:
            return manualEntries.count < totalManualFilteredCount
        case .watched:
            return watchedEntries.count < totalWatchedFilteredCount
        case .all, .success, .failed, .skipped:
            return manualEntries.count < totalManualFilteredCount ||
                watchedEntries.count < totalWatchedFilteredCount
        }
    }

    private var canProvideSessionFeedback: Bool {
        learningsManager.summary.canProvideFeedback
    }

    enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case success = "Success"
        case failed = "Failed"
        case skipped = "Skipped"
        case manual = "Manual"
        case watched = "Watched"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if organizer.history.entries.count > 1 {
                content
                    .searchable(text: $searchText, prompt: "Search folders")
            } else {
                content
            }
        }
        .onChange(of: organizer.history.entries.count) { _, count in
            if count <= 1 {
                searchText = ""
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if organizer.history.entries.isEmpty {
                ZStack(alignment: .topLeading) {
                    HistoryEmptyStateView()
                        .transition(TransitionStyles.scaleAndFade)

                    HistoryHeader(
                        manager: organizer,
                        selectedFilter: $selectedFilter,
                        showsControls: false,
                        onClearHistory: {
                            appState.clearHistoryWithConfirmation()
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(contentOpacity)
            } else {
                // Header - matches DuplicatesView style
                HistoryHeader(
                    manager: organizer,
                    selectedFilter: $selectedFilter,
                    showsControls: true,
                    onClearHistory: {
                        appState.clearHistoryWithConfirmation()
                    }
                )

                Divider()

                ZStack {
                    if !searchText.isEmpty && allFilteredEntries.isEmpty {
                        HistorySearchEmptyStateView(searchText: searchText, onClear: { searchText = "" })
                            .transition(TransitionStyles.scaleAndFade)
                    } else {
                        historyEntriesScroll
                        .background(Color(NSColor.windowBackgroundColor))
                        .transition(TransitionStyles.slideFromRight)
                    }
                }
                .animation(.pageTransition, value: selectedFilter)
                .opacity(contentOpacity)
            }
        }
        .emptyStateWorkflowGradient(isVisible: organizer.history.entries.isEmpty)
        .animation(.pageTransition, value: organizer.history.entries.isEmpty)
        .navigationTitle("History")
        .disabled(isProcessing)
        .overlay {
            if isProcessing {
                ProcessingOverlay(stage: organizer.organizationStage)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isProcessing)
        .alert("History Action", isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                HapticFeedbackManager.shared.tap()
            }
        } message: {
            if let msg = alertMessage {
                Text(msg)
            }
        }
        .sheet(isPresented: $showingDetail) {
            if let entry = selectedEntry {
                HistoryDetailSheet(
                    entry: entry,
                    isProcessing: $isProcessing,
                    onAction: { msg in
                        alertMessage = msg
                        showAlert = true
                    },
                    onDismiss: {
                        showingDetail = false
                        selectedEntry = nil
                    }
                )
                .environmentObject(organizer)
            }
        }
        .modelSelectionOverlay(
            isPresented: $showRedoModelPicker,
            currentProvider: settingsViewModel.config.provider,
            currentModel: settingsViewModel.config.model,
            onSelect: { provider, model in
                guard let entry = redoModelEntry else { return }
                showRedoModelPicker = false
                handleRedoWithModel(entry, provider: provider, model: model)
            }
        )
        .sheet(isPresented: $showPartialResultSheet) {
            if let result = partialUndoResult {
                PartialUndoResultSheet(result: result) {
                    showPartialResultSheet = false
                    partialUndoResult = nil
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
            consumePendingNotificationActionIfNeeded()
        }
        .onChange(of: selectedFilter) { _, _ in
            // Reset pagination when filter changes
            displayedEntryCount = pageSize
            if selectedFilter == .watched {
                showWatchedAutomations = true
            }
        }
        .onChange(of: searchText) { _, _ in
            displayedEntryCount = pageSize
        }
        .onChange(of: appState.pendingNotificationActionRequest?.id) { _, _ in
            consumePendingNotificationActionIfNeeded()
        }
        .onChange(of: showRedoModelPicker) { oldValue, newValue in
            guard oldValue, !newValue, activeNotificationRedoRequestID != nil else { return }
            NotificationManager.shared.recordActionLifecycle("redo_with_model", stage: "cancelled", detail: "history picker")
            activeNotificationRedoRequestID = nil
        }
    }

    private var historyEntriesScroll: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HistorySummaryCard(history: organizer.history)
                    .padding(.top, 16)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("History Summary")

                manualSessionsSection
                watchedAutomationsSection

                if hasMoreEntries {
                    LoadMoreButton(isLoading: isLoadingMore) {
                        loadMoreEntries()
                    }
                    .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private var manualSessionsSection: some View {
        if !manualEntries.isEmpty {
            HStack {
                Label("Manual Sessions", systemImage: "person.fill")
                    .font(.headline)
                Spacer()
                Text("\(totalManualFilteredCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .numericTextTransition(animationValue: totalManualFilteredCount)
            }

            ForEach(Array(manualEntries.enumerated()), id: \.element.id) { index, entry in
                HistorySessionCard(
                    entry: entry,
                    isSelected: selectedEntry == entry,
                    isProcessing: isProcessing,
                    isModelPickerAnchorActive: showRedoModelPicker && redoModelEntry?.id == entry.id,
                    onSelect: {
                        HapticFeedbackManager.shared.selection()
                        selectEntry(entry)
                    },
                    onUndo: { handleUndo(entry) },
                    onRedo: { handleRedo(entry) },
                    onOpenModelPicker: {
                        redoModelEntry = entry
                        showRedoModelPicker = true
                    },
                    canProvideFeedback: canProvideSessionFeedback,
                    onFeedback: { outcome in
                        handleFeedback(entry, outcome: outcome)
                    }
                )
                .animatedAppearance(delay: Double(index) * 0.03)
                .onAppear {
                    if index >= manualEntries.count - loadMoreThreshold && hasMoreEntries && !isLoadingMore {
                        loadMoreEntries()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var watchedAutomationsSection: some View {
        if !watchedEntries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showWatchedAutomations.toggle()
                    }
                } label: {
                    HStack {
                        Label("Watched Folder Automations", systemImage: "bolt.horizontal.circle")
                            .font(.headline)
                        Spacer()
                        Text("\(totalWatchedFilteredCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .numericTextTransition(animationValue: totalWatchedFilteredCount)
                        Image(systemName: showWatchedAutomations ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showWatchedAutomations {
                    ForEach(Array(watchedEntries.enumerated()), id: \.element.id) { index, entry in
                        WatchedAutomationRow(entry: entry) {
                            HapticFeedbackManager.shared.selection()
                            selectEntry(entry)
                        }
                        .animatedAppearance(delay: Double(index) * 0.02)
                        .onAppear {
                            if index >= watchedEntries.count - loadMoreThreshold && hasMoreEntries && !isLoadingMore {
                                loadMoreEntries()
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func loadMoreEntries() {
        guard !isLoadingMore && hasMoreEntries else { return }

        isLoadingMore = true

        // Simulate a small delay for better UX (shows loading state)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s

            displayedEntryCount += pageSize
            isLoadingMore = false
        }
    }

    private func selectEntry(_ entry: OrganizationHistoryEntry) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedEntry = entry
            showingDetail = true
        }
    }

    private func handleUndo(_ entry: OrganizationHistoryEntry) {
        isProcessing = true
        Task { @MainActor in
            do {
                let result = try await organizer.undoHistoryEntry(entry)
                if result.hasIssues {
                    HapticFeedbackManager.shared.tap()
                    // Show detailed partial result sheet instead of generic alert
                    partialUndoResult = PartialUndoResult(
                        successCount: result.successfulOperations,
                        missingFiles: result.missingFiles,
                        failedOperationCount: result.retryableFailedOperationIDs.count,
                        directoryPath: entry.directoryPath
                    )
                    isProcessing = false
                    showPartialResultSheet = true
                } else {
                    HapticFeedbackManager.shared.success()
                    alertMessage = "All \(result.successfulOperations) operations reversed successfully."
                    showAlert = true
                }
            } catch {
                HapticFeedbackManager.shared.error()
                alertMessage = friendlyUndoErrorMessage(for: error)
                showAlert = true
            }
            isProcessing = false
        }
    }

    private func friendlyUndoErrorMessage(for error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError:
                return "Some files were moved or deleted since this organization. Open the session details to undo individual operations."
            case NSFileWriteNoPermissionError:
                return "Permission denied. Check that Sorty has access to this folder in System Settings > Privacy & Security."
            case NSFileWriteOutOfSpaceError:
                return "Not enough disk space available. Free up some space and try again."
            default:
                break
            }
        }

        return "Could not undo: \(error.localizedDescription)"
    }

    private func handleRedo(_ entry: OrganizationHistoryEntry) {
        isProcessing = true
        Task { @MainActor in
            do {
                try await organizer.redoOrganization(from: entry)
                HapticFeedbackManager.shared.success()
                alertMessage = "Organization re-applied."
                showAlert = true
            } catch {
                HapticFeedbackManager.shared.error()
                alertMessage = "Error: \(error.localizedDescription)"
                showAlert = true
            }
            isProcessing = false
        }
    }

    private func handleRedoWithModel(_ entry: OrganizationHistoryEntry, provider: AIProvider, model: String) {
        isProcessing = true
        if activeNotificationRedoRequestID != nil {
            NotificationManager.shared.recordActionLifecycle("redo_with_model", stage: "confirmed", detail: "\(provider.displayName):\(model)")
            NotificationManager.shared.recordActionLifecycle("redo_with_model", stage: "executing", detail: entry.directoryPath)
        }
        Task { @MainActor in
            do {
                // First set up the folder context from history entry
                let directoryURL = URL(fileURLWithPath: entry.directoryPath)
                organizer.currentDirectory = directoryURL

                // Generate new plan with specified provider/model
                try await organizer.regenerateWithModel(provider: provider, model: model)
                HapticFeedbackManager.shared.success()
                alertMessage = "New organization generated with \(provider.displayName) (\(model))."
                showAlert = true
                if activeNotificationRedoRequestID != nil {
                    NotificationManager.shared.recordActionLifecycle("redo_with_model", stage: "completed", detail: entry.directoryPath)
                    activeNotificationRedoRequestID = nil
                }
            } catch {
                HapticFeedbackManager.shared.error()
                alertMessage = "Error: \(error.localizedDescription)"
                showAlert = true
                if activeNotificationRedoRequestID != nil {
                    NotificationManager.shared.recordActionLifecycle("redo_with_model", stage: "failed", failed: true, detail: error.localizedDescription)
                    activeNotificationRedoRequestID = nil
                }
            }
            isProcessing = false
        }
    }

    private func handleFeedback(_ entry: OrganizationHistoryEntry, outcome: LearningsManager.SessionOutcome) {
        learningsManager.recordSessionOutcomeFeedback(
            sessionId: entry.id.uuidString,
            outcome: outcome,
            folderPath: entry.directoryPath
        )

        DebugLogger.log(
            "Session feedback recorded: \(outcome.rawValue) for session \(entry.id.uuidString)"
        )
    }

    private func consumePendingNotificationActionIfNeeded() {
        guard let request = appState.pendingNotificationActionRequest else { return }
        guard request.kind == .redoWithModelConfirmation else { return }
        guard request.notificationType != "previewReady" else { return }
        guard let targetEntry = notificationRedoTargetEntry(for: request.folderPath) else { return }

        redoModelEntry = targetEntry
        activeNotificationRedoRequestID = request.id
        NotificationManager.shared.recordActionLifecycle("redo_with_model", stage: "confirmation_shown", detail: targetEntry.directoryPath)
        showRedoModelPicker = true
        appState.clearNotificationActionRequest(id: request.id)
    }

    private func notificationRedoTargetEntry(for folderPath: String?) -> OrganizationHistoryEntry? {
        if let folderPath {
            let normalizedPath = URL(fileURLWithPath: folderPath).standardizedFileURL.path
            if let matchingEntry = organizer.history.entries.first(where: {
                URL(fileURLWithPath: $0.directoryPath).standardizedFileURL.path == normalizedPath
            }) {
                return matchingEntry
            }
        }

        return organizer.history.entries.first
    }
}

// MARK: - History Header

struct HistoryHeader: View {
    @ObservedObject var manager: FolderOrganizer
    @Binding var selectedFilter: HistoryView.HistoryFilter
    var showsControls: Bool = true
    let onClearHistory: () -> Void
    private let controlsHeight: CGFloat = 31

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsControls {
                titleRow
            } else {
                emptyStateTitleRow
            }

            if showsControls {
                HStack(spacing: 12) {
                    filterPicker
                        .frame(maxWidth: .infinity)
                        .frame(height: controlsHeight)

                    clearHistoryButton
                }
            }
        }
        .padding(.horizontal, showsControls ? 28 : 32)
        .padding(.top, showsControls ? 10 : 0)
        .padding(.bottom, showsControls ? 10 : 0)
        .background {
            if showsControls {
                Rectangle().fill(.bar)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History controls")
    }

    private var titleRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.blue.gradient)
                Text("History")
                    .font(.title3.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("History")

            Text("\(manager.history.totalSessions) runs")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .numericTextTransition(animationValue: manager.history.totalSessions)
                .accessibilityLabel("\(manager.history.totalSessions) runs recorded")

            Spacer()
        }
    }

    private var emptyStateTitleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("History")
                    .font(.largeTitle.bold())

                Text("Review past runs, undo changes, and reapply plans when needed")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var filterPicker: some View {
        Picker("Filter history sessions", selection: $selectedFilter) {
            ForEach(HistoryView.HistoryFilter.allCases) { filter in
                Text(LocalizedStringKey(filter.rawValue))
                    .tag(filter)
            }
        }
        .pickerStyle(.palette)
        .labelsHidden()
        .frame(height: controlsHeight)
        .accessibilityLabel("Filter history sessions")
        .accessibilityIdentifier("HistoryFilterPicker")
    }

    private var clearHistoryButton: some View {
        Button {
            onClearHistory()
        } label: {
            Label("Clear", systemImage: "trash")
        }
        .buttonStyle(.tintedPill(.red, size: .small))
        .controlSize(.small)
        .disabled(manager.history.entries.isEmpty)
        .accessibilityLabel("Clear all history")
        .accessibilityIdentifier("ClearHistoryButton")
    }
}

// MARK: - History Summary Card (Dashboard Impact Stats)

struct HistorySummaryCard: View {
    let history: OrganizationHistory

    private var filesOrganizedValue: String {
        "\(history.totalFilesOrganized)"
    }

    private var timeSavedValue: String {
        let seconds = history.totalTimeSaved
        if seconds < 3600 {
            let minutes = seconds / 60.0
            return String(format: "%.1f", minutes)
        } else {
            let hours = seconds / 3600.0
            return String(format: "%.1f", hours)
        }
    }

    private var timeSavedLabel: String {
        history.totalTimeSaved < 3600 ? "Minutes Saved" : "Hours Saved"
    }

    private var foldersCreatedValue: String {
        "\(history.totalFoldersCreated)"
    }

    private var totalSessionsValue: String {
        "\(history.totalSessions)"
    }

    private var successRateValue: String {
        history.totalSessions > 0
            ? "\(Int(history.successRate * 100))%"
            : "—"
    }

    private var successRateLabel: String {
        history.totalSessions > 0
            ? "\(Int(history.successRate * 100)) percent"
            : "not available"
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 132), spacing: 10), count: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Impact", systemImage: "chart.bar.xaxis.ascending")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                HistoryStatItem(
                    title: "Files Organized",
                    value: filesOrganizedValue,
                    icon: "doc.on.doc.fill",
                    color: .blue
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Files organized: \(filesOrganizedValue)")

                HistoryStatItem(
                    title: timeSavedLabel,
                    value: timeSavedValue,
                    icon: "clock.arrow.circlepath",
                    color: .orange
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(timeSavedLabel): \(timeSavedValue)")

                HistoryStatItem(
                    title: "Folders Created",
                    value: foldersCreatedValue,
                    icon: "folder.fill.badge.plus",
                    color: .green
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Folders created: \(foldersCreatedValue)")

                HistoryStatItem(
                    title: "Total Sessions",
                    value: totalSessionsValue,
                    icon: "list.bullet.rectangle.fill",
                    color: .accentColor
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total sessions: \(totalSessionsValue)")

                HistoryStatItem(
                    title: "Success Rate",
                    value: successRateValue,
                    icon: "chart.line.uptrend.xyaxis.circle.fill",
                    color: .teal
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Success rate: \(successRateLabel)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .systemLiquidGlassBackground(cornerRadius: 18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct HistoryStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.gradient)
                .accessibilityHidden(true)

            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .numericTextTransition(animationValue: value)

            Text(LocalizedStringKey(title))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 88)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - History Session Card

private enum HistoryCardActionState: Equatable {
    case idle
    case undoing
    case redoing

    var isUndoing: Bool { self == .undoing }
    var isRedoing: Bool { self == .redoing }
    var isBusy: Bool { self != .idle }
}

private struct HistorySessionCardHeader: View {
    let entry: OrganizationHistoryEntry
    let modelBadgeText: String?
    let statusColor: Color
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            FolderThumbnailView(url: URL(fileURLWithPath: entry.directoryPath), size: CGSize(width: 32, height: 32))
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: entry.directoryPath).lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)

                HistorySessionSummary(entry: entry, statusColor: statusColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let modelBadgeText {
                    Text(modelBadgeText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                        .accessibilityLabel("Model: \(modelBadgeText)")
                }

                Text(entry.timestamp.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct HistorySessionSummary: View {
    let entry: OrganizationHistoryEntry
    let statusColor: Color

    var body: some View {
        HStack(spacing: 12) {
            if entry.status == .completed {
                Label("\(entry.filesOrganized) files", systemImage: "doc")
                Label("\(entry.foldersCreated) folders", systemImage: "folder")
            } else if entry.status == .duplicatesCleanup {
                Label("\(entry.duplicatesDeleted ?? 0) deleted", systemImage: "trash")
                if let recovered = entry.recoveredSpace {
                    Label(ByteCountFormatter.string(fromByteCount: recovered, countStyle: .file), systemImage: "externaldrive")
                }
            } else if entry.status == .partiallyUndone {
                Text("Partially Undone")
                    .foregroundStyle(statusColor)
            } else {
                Text(entry.status.rawValue.capitalized)
                    .foregroundStyle(statusColor)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct HistorySessionExpandedContent: View {
    let entry: OrganizationHistoryEntry
    let hasStorageMoves: Bool
    let operationsBreakdown: (moves: Int, renames: Int, folderCreates: Int)
    let hasOperationsData: Bool
    let isProcessing: Bool
    let actionState: HistoryCardActionState
    let isModelPickerAnchorActive: Bool
    let canProvideFeedback: Bool
    @Binding var feedbackGiven: LearningsManager.SessionOutcome?
    @Binding var showFeedbackConfirmation: Bool
    let onSelect: () -> Void
    let onApplyPlan: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onOpenModelPicker: () -> Void
    let onFeedback: ((LearningsManager.SessionOutcome) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                PrivacySensitivePathText(path: entry.directoryPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Path: \(PrivacyPathMasker.redactedPath(entry.directoryPath))")

            if hasStorageMoves {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .foregroundStyle(.orange)
                    Text("Includes moves to storage locations")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("This organization included moves to external storage locations")
            }

            if hasOperationsData && entry.status == .completed {
                OperationsBreakdownBar(
                    moves: operationsBreakdown.moves,
                    renames: operationsBreakdown.renames,
                    folderCreates: operationsBreakdown.folderCreates
                )
            }

            HistorySessionActions(
                entry: entry,
                isProcessing: isProcessing,
                actionState: actionState,
                isModelPickerAnchorActive: isModelPickerAnchorActive,
                canProvideFeedback: canProvideFeedback,
                feedbackGiven: $feedbackGiven,
                showFeedbackConfirmation: $showFeedbackConfirmation,
                onSelect: onSelect,
                onApplyPlan: onApplyPlan,
                onUndo: onUndo,
                onRedo: onRedo,
                onOpenModelPicker: onOpenModelPicker,
                onFeedback: onFeedback
            )
        }
        .padding(16)
        .background(Color.black.opacity(0.02))
    }
}

private struct HistorySessionActions: View {
    let entry: OrganizationHistoryEntry
    let isProcessing: Bool
    let actionState: HistoryCardActionState
    let isModelPickerAnchorActive: Bool
    let canProvideFeedback: Bool
    @Binding var feedbackGiven: LearningsManager.SessionOutcome?
    @Binding var showFeedbackConfirmation: Bool
    let onSelect: () -> Void
    let onApplyPlan: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onOpenModelPicker: () -> Void
    let onFeedback: ((LearningsManager.SessionOutcome) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                Label("View Details", systemImage: "info.circle")
            }
            .buttonStyle(.sortyBordered)
            .controlSize(.small)
            .accessibilityLabel("View session details")
            .accessibilityIdentifier("ViewDetailsButton-\(entry.id.uuidString)")

            if entry.hasApplicablePlan {
                Button(action: onApplyPlan) {
                    Label("Apply Plan", systemImage: "checkmark.circle")
                }
                .buttonStyle(.sortyProminent)
                .controlSize(.small)
                .accessibilityLabel("Apply this generated organization plan")
                .accessibilityIdentifier("ApplyPlanButton-\(entry.id.uuidString)")
            } else if entry.success && entry.status != .duplicatesCleanup {
                undoOrRedoButton

                Button {
                    HapticFeedbackManager.shared.tap()
                    onOpenModelPicker()
                } label: {
                    Label("Try Different Model", systemImage: "wand.and.stars")
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.small)
                .accessibilityLabel("Try organization with a different AI model")
                .accessibilityIdentifier("TryModelButton-\(entry.id.uuidString)")
                .background {
                    if isModelPickerAnchorActive {
                        Color.clear.modelSelectorTriggerBounds()
                    }
                }
            }

            Spacer()

            if canProvideFeedback && entry.status == .completed && !entry.isUndone, let onFeedback {
                QuickFeedbackButtons(
                    feedbackGiven: $feedbackGiven,
                    showConfirmation: $showFeedbackConfirmation,
                    onFeedback: onFeedback
                )
            }
        }
    }

    @ViewBuilder
    private var undoOrRedoButton: some View {
        Group {
            if entry.isUndone {
                Button(action: onRedo) {
                    Label(
                        actionState.isRedoing ? "Redoing…" : "Redo",
                        systemImage: actionState.isRedoing ? "arrow.triangle.2.circlepath" : "arrow.uturn.forward"
                    )
                }
                .buttonStyle(.onboardingPill)
                .accessibilityLabel("Redo organization")
                .accessibilityIdentifier("RedoButton-\(entry.id.uuidString)")
            } else {
                Button(action: onUndo) {
                    Label(
                        actionState.isUndoing ? "Undoing…" : "Undo",
                        systemImage: actionState.isUndoing ? "arrow.triangle.2.circlepath" : "arrow.uturn.backward"
                    )
                }
                .buttonStyle(.sortyBordered)
                .accessibilityLabel("Undo organization")
                .accessibilityIdentifier("UndoButton-\(entry.id.uuidString)")
            }
        }
        .controlSize(.small)
        .contentTransition(.symbolEffect(.replace))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
        .disabled(isProcessing || actionState.isBusy)
    }
}

struct HistorySessionCard: View {
    let entry: OrganizationHistoryEntry
    let isSelected: Bool
    let isProcessing: Bool
    let isModelPickerAnchorActive: Bool
    let onSelect: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onOpenModelPicker: () -> Void
    let canProvideFeedback: Bool
    var onFeedback: ((LearningsManager.SessionOutcome) -> Void)?

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var feedbackGiven: LearningsManager.SessionOutcome?
    @State private var showFeedbackConfirmation = false
    @State private var actionState: HistoryCardActionState = .idle
    @State private var swipeOffset: CGFloat = 0
    @State private var hasCrossedSwipeThreshold = false

    // MARK: - Operations Breakdown

    private var operationsBreakdown: (moves: Int, renames: Int, folderCreates: Int) {
        guard let operations = entry.operations else {
            return (0, 0, 0)
        }
        let moves = operations.filter { $0.type == .moveFile }.count
        let renames = operations.filter { $0.type == .renameFile || $0.metadata?.newFilename != nil }.count
        let folderCreates = operations.filter { $0.type == .createFolder }.count
        return (moves, renames, folderCreates)
    }

    private var hasOperationsData: Bool {
        let breakdown = operationsBreakdown
        return breakdown.moves > 0 || breakdown.renames > 0 || breakdown.folderCreates > 0
    }

    private var modelBadgeText: String? {
        guard let stats = entry.plan?.generationStats else { return nil }
        let modelName = stats.compactModelName
        if stats.hasBillableCost {
            return "\(modelName) · \(GenerationStats.formatCost(stats.computedCost))"
        }
        return modelName
    }

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .skipped: return .secondary
        case .undo: return .orange
        case .partiallyUndone: return .yellow
        case .duplicatesCleanup: return .accentColor
        }
    }

    private var hasStorageMoves: Bool {
        guard let plan = entry.plan else { return false }
        return plan.suggestions.contains { $0.folderName.hasPrefix("/") }
    }

    private var statusIcon: String {
        switch entry.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .skipped: return "arrow.right.circle.fill"
        case .undo: return "arrow.uturn.backward.circle.fill"
        case .partiallyUndone: return "exclamationmark.triangle.fill"
        case .duplicatesCleanup: return "trash.circle.fill"
        }
    }

    private var canSwipeToRevert: Bool {
        entry.success &&
            !entry.isUndone &&
            entry.status != .duplicatesCleanup &&
            !isProcessing &&
            !actionState.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticFeedbackManager.shared.tap()
            } label: {
                HistorySessionCardHeader(
                    entry: entry,
                    modelBadgeText: modelBadgeText,
                    statusColor: statusColor,
                    isExpanded: isExpanded
                )
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(URL(fileURLWithPath: entry.directoryPath).lastPathComponent), \(entry.status.rawValue), \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("HistorySessionCard-\(entry.id.uuidString)")

            // Expanded Content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                HistorySessionExpandedContent(
                    entry: entry,
                    hasStorageMoves: hasStorageMoves,
                    operationsBreakdown: operationsBreakdown,
                    hasOperationsData: hasOperationsData,
                    isProcessing: isProcessing,
                    actionState: actionState,
                    isModelPickerAnchorActive: isModelPickerAnchorActive,
                    canProvideFeedback: canProvideFeedback,
                    feedbackGiven: $feedbackGiven,
                    showFeedbackConfirmation: $showFeedbackConfirmation,
                    onSelect: onSelect,
                    onApplyPlan: onRedo,
                    onUndo: beginUndo,
                    onRedo: beginRedo,
                    onOpenModelPicker: onOpenModelPicker,
                    onFeedback: onFeedback
                )
            }
        }
        .background(swipeActionBackground)
        .offset(x: swipeOffset)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.5) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: actionState)
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: swipeOffset)
        .onChange(of: isProcessing) { _, newValue in
            guard !newValue else { return }
            resetActionState()
            resetSwipe()
        }
        .onChange(of: entry.isUndone) { _, _ in
            resetActionState()
            resetSwipe()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(swipeToRevertGesture)
    }

    @ViewBuilder
    private var swipeActionBackground: some View {
        if canSwipeToRevert || swipeOffset < 0 {
            HStack {
                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolEffect(.bounce, value: hasCrossedSwipeThreshold)

                    Text("Revert")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.orange.gradient)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var swipeToRevertGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .onChanged { value in
                guard canSwipeToRevert, abs(value.translation.width) > abs(value.translation.height) else { return }
                let proposedOffset = min(0, value.translation.width)
                swipeOffset = max(proposedOffset, -132)

                let crossed = abs(swipeOffset) >= 96
                if crossed && !hasCrossedSwipeThreshold {
                    HapticFeedbackManager.shared.selection()
                }
                hasCrossedSwipeThreshold = crossed
            }
            .onEnded { _ in
                guard canSwipeToRevert else {
                    resetSwipe()
                    return
                }

                if abs(swipeOffset) >= 96 {
                    HapticFeedbackManager.shared.tap()
                    beginUndo()
                }
                resetSwipe()
            }
    }

    private func beginUndo() {
        guard !isProcessing, !actionState.isBusy else { return }
        HapticFeedbackManager.shared.tap()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            actionState = .undoing
        }
        onUndo()
    }

    private func beginRedo() {
        guard !isProcessing, !actionState.isBusy else { return }
        HapticFeedbackManager.shared.tap()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            actionState = .redoing
        }
        onRedo()
    }

    private func resetActionState() {
        guard actionState != .idle else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            actionState = .idle
        }
    }

    private func resetSwipe() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            swipeOffset = 0
            hasCrossedSwipeThreshold = false
        }
    }
}

// MARK: - Quick Feedback Buttons

/// Compact feedback buttons for session outcome (useful / not useful)
private struct QuickFeedbackButtons: View {
    @Binding var feedbackGiven: LearningsManager.SessionOutcome?
    @Binding var showConfirmation: Bool
    let onFeedback: (LearningsManager.SessionOutcome) -> Void

    @State private var usefulHovered = false
    @State private var notUsefulHovered = false

    var body: some View {
        HStack(spacing: 6) {
            if feedbackGiven == nil {
                Text("Helpful?")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Thumbs up
                Button {
                    HapticFeedbackManager.shared.success()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        feedbackGiven = .useful
                        showConfirmation = true
                    }
                    onFeedback(.useful)

                    // Auto-hide confirmation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showConfirmation = false
                        }
                    }
                } label: {
                    Image(systemName: "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(usefulHovered ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .scaleEffect(usefulHovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: usefulHovered)
                .onHover { hovering in
                    usefulHovered = hovering
                    if hovering { HapticFeedbackManager.shared.selection() }
                }
                .accessibilityLabel("Mark as helpful")
                .accessibilityIdentifier("FeedbackUsefulButton")

                // Thumbs down
                Button {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        feedbackGiven = .notUseful
                        showConfirmation = true
                    }
                    onFeedback(.notUseful)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showConfirmation = false
                        }
                    }
                } label: {
                    Image(systemName: "hand.thumbsdown")
                        .font(.caption)
                        .foregroundStyle(notUsefulHovered ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .scaleEffect(notUsefulHovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: notUsefulHovered)
                .onHover { hovering in
                    notUsefulHovered = hovering
                    if hovering { HapticFeedbackManager.shared.selection() }
                }
                .accessibilityLabel("Mark as not helpful")
                .accessibilityIdentifier("FeedbackNotUsefulButton")
            } else {
                // Feedback confirmation
                HStack(spacing: 4) {
                    Image(systemName: feedbackGiven == .useful ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(feedbackGiven == .useful ? .green : .orange)

                    Text(feedbackGiven == .useful ? "Thanks!" : "Noted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(feedbackGiven == nil ? "Rate this organization" : "Feedback recorded")
    }
}

// MARK: - Operations Breakdown Bar

/// A compact horizontal bar showing the breakdown of file operations (moves, renames, folder creates)
/// with colored segments proportional to each operation type.
private struct OperationsBreakdownBar: View {
    let moves: Int
    let renames: Int
    let folderCreates: Int

    @State private var isHovered = false

    private var total: Int {
        moves + renames + folderCreates
    }

    private var moveFraction: CGFloat {
        total > 0 ? CGFloat(moves) / CGFloat(total) : 0
    }

    private var renameFraction: CGFloat {
        total > 0 ? CGFloat(renames) / CGFloat(total) : 0
    }

    private var folderFraction: CGFloat {
        total > 0 ? CGFloat(folderCreates) / CGFloat(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Segmented Bar
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    if moves > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.blue.gradient)
                            .frame(width: max(geometry.size.width * moveFraction - 1, 4))
                    }
                    if renames > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(SortyDesignSystem.Colors.resolvedAccent.gradient)
                            .frame(width: max(geometry.size.width * renameFraction - 1, 4))
                    }
                    if folderCreates > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green.gradient)
                            .frame(width: max(geometry.size.width * folderFraction - 1, 4))
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.1))
            )

            // Legend (inline, compact)
            HStack(spacing: 12) {
                if moves > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                        Text("\(moves) moved")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if renames > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(SortyDesignSystem.Colors.resolvedAccent)
                            .frame(width: 6, height: 6)
                        Text("\(renames) renamed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if folderCreates > 0 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("\(folderCreates) folders")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Operations breakdown: \(moves) files moved, \(renames) files renamed, \(folderCreates) folders created")
    }
}

struct WatchedAutomationRow: View {
    let entry: OrganizationHistoryEntry
    let onSelect: () -> Void

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .skipped: return .secondary
        case .undo: return .orange
        case .partiallyUndone: return .yellow
        case .duplicatesCleanup: return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: entry.directoryPath).lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(entry.filesOrganized)", systemImage: "doc")
                    Label("\(entry.foldersCreated)", systemImage: "folder")
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.status.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.15))
                .foregroundStyle(statusColor)
                .clipShape(Capsule())

            Button("Details") {
                onSelect()
            }
            .buttonStyle(.sortyBordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Watched automation for \(URL(fileURLWithPath: entry.directoryPath).lastPathComponent), \(entry.status.rawValue)")
        .accessibilityIdentifier("WatchedAutomationRow-\(entry.id.uuidString)")
    }
}

// MARK: - History Search Empty State

struct HistorySearchEmptyStateView: View {
    let searchText: String
    let onClear: () -> Void

    @State private var hasAppeared = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.8)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: hasAppeared)

            VStack(spacing: 8) {
                Text("No Results Found")
                    .font(.title3.bold())

                Text("No history entries match \"\(searchText)\"")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.1), value: hasAppeared)

            Button {
                HapticFeedbackManager.shared.tap()
                onClear()
            } label: {
                Label("Clear Search", systemImage: "xmark.circle")
            }
            .buttonStyle(.sortyBordered)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    HapticFeedbackManager.shared.selection()
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
            .accessibilityIdentifier("ClearSearchButton")

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            hasAppeared = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No search results for \(searchText)")
    }
}

// MARK: - History Empty State

struct HistoryEmptyStateView: View {
    @EnvironmentObject var appState: AppState
    @State private var isHovered = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Hero section
            VStack(spacing: 16) {
                EmptyStateHeroIcon(systemName: "clock.arrow.circlepath")
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("No History Yet")
                        .font(.title2.bold())

                    Text("Organize a folder to start tracking sessions, results, and actions you can revisit later.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
            }

            // CTA button
            Button {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    appState.currentView = .organize
                }
            } label: {
                Text("Start Organizing")
            }
            .buttonStyle(.onboardingPill)
            .onboardingBeamBorder(
                variant: .featured,
                active: hasAppeared,
                isIntensified: isHovered,
                includesInteriorGlow: isHovered
            )
            .controlSize(.large)
            .contentShape(Capsule())
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: isHovered)
            .onHover { hovering in
                if hovering && !isHovered {
                    HapticFeedbackManager.shared.selection()
                }
                isHovered = hovering
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 15)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
            .accessibilityLabel("Start organizing a folder")
            .accessibilityHint("Navigate to the organize view to begin")
            .accessibilityIdentifier("HistoryEmptyStateCTA")

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("No history yet. Organize a folder to start tracking your sessions.")
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
        }
    }
}

private struct HistoryFeaturePreviewCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.gradient)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(LocalizedStringKey(description))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

// MARK: - History Detail Sheet

struct HistoryDetailSheet: View {
    let entry: OrganizationHistoryEntry
    @Binding var isProcessing: Bool
    let onAction: (String) -> Void
    let onDismiss: () -> Void

    @State private var showRawAIResponse = false
    @State private var showRedoModelPicker = false
    @State private var undoneOperationIDs: Set<UUID> = []
    @State private var failedOperationIDs: Set<UUID> = []
    @State private var undoingOperationID: UUID?
    @State private var highlightedFileID: UUID? = nil

    // Pre-flight validation state
    @State private var showUndoConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showRedoConfirmation = false
    @State private var preflightResult: PreflightValidationResult?
    @State private var showPartialResultSheet = false
    @State private var partialUndoResult: PartialUndoResult?

    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var learningsManager: LearningsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentEntry: OrganizationHistoryEntry {
        organizer.history.entries.first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    HistoryDetailHeaderSection(entry: entry)

                    Divider()

                    HistorySessionStatisticsSection(
                        entry: entry,
                        showsDetailedStats: settingsViewModel.config.showStatsForNerds
                    )

                    HistoryDetailErrorSection(entry: entry)

                    HistoryDetailActionsSection(
                        entry: entry,
                        onRestoreDuplicates: handleRestoreDuplicates,
                        onApplyOrRedo: handleRedo,
                        onRestore: handleRestore,
                        onUndo: handleUndo,
                        onTryDifferentModel: showDifferentModelPicker
                    )

                    // Timeline Section
                    if entry.success {
                        CompactTimelineView(
                            entries: organizer.history.entries,
                            directoryPath: entry.directoryPath
                        )
                    }

                    // Learnings Applied
                    if let plan = entry.plan {
                        HistoryLiquidGlassLearningsCard(plan: plan)
                    }

                    // AI Reasoning
                    if let plan = entry.plan, !plan.notes.isEmpty {
                        HistoryLiquidGlassReasoningCard(notes: plan.notes)
                    }

                    // Duplicate Files
                    if let plan = entry.plan {
                        HistoryLiquidGlassDuplicateCard(
                            plan: plan,
                            handoffDirectory: URL(fileURLWithPath: entry.directoryPath),
                            highlightedFileID: $highlightedFileID
                        )
                    }

                    HistoryPlanDetailsSection(
                        entry: entry,
                        highlightedFileID: $highlightedFileID
                    )

                    HistoryFileOperationsSection(
                        entry: currentEntry,
                        undoneOperationIDs: undoneOperationIDs,
                        failedOperationIDs: failedOperationIDs,
                        undoingOperationID: undoingOperationID,
                        onUndo: handleUndoSingleOperation
                    )

                    HistoryRestorableItemsSection(entry: entry)

                    // Raw AI Response (Stats for Nerds)
                    if settingsViewModel.config.showStatsForNerds,
                       let raw = currentEntry.rawAIResponse,
                       !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        rawAIResponseSection(raw)
                    }
                    }
                    .padding(24)
                }
                .onChange(of: highlightedFileID) { _, highlightedFileID in
                    guard let highlightedFileID else { return }
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                        scrollProxy.scrollTo(highlightedFileID, anchor: .center)
                    }
                    DispatchQueue.main.async {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                            scrollProxy.scrollTo(highlightedFileID, anchor: .center)
                        }
                    }
                }
                .navigationTitle("Session Details")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            onDismiss()
                        }
                        .accessibilityLabel("Close details")
                        .accessibilityIdentifier("DismissDetailsButton")
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .modelSelectionOverlay(
            isPresented: $showRedoModelPicker,
            currentProvider: settingsViewModel.config.provider,
            currentModel: settingsViewModel.config.model,
            onSelect: { provider, model in
                handleRedoWithModel(provider: provider, model: model)
            }
        )
        .confirmationDialog(
            "Undo Organization?",
            isPresented: $showUndoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Undo \(preflightResult?.availableCount ?? 0) Operations", role: .destructive) {
                executeUndo()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let result = preflightResult {
                Text(undoConfirmationMessage(result))
            }
        }
        .confirmationDialog(
            "Restore to This State?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                executeRestore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will undo all organization sessions after this point for this folder. Some files may have been modified or moved since.")
        }
        .confirmationDialog(
            "Re-Apply Organization?",
            isPresented: $showRedoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Re-Apply") {
                executeRedo()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let result = preflightResult {
                Text(redoConfirmationMessage(result))
            }
        }
        .sheet(isPresented: $showPartialResultSheet) {
            if let result = partialUndoResult {
                PartialUndoResultSheet(result: result) {
                    showPartialResultSheet = false
                    partialUndoResult = nil
                }
            }
        }
    }

    private func undoConfirmationMessage(_ result: PreflightValidationResult) -> String {
        var message = "This will move \(result.availableCount) file(s) back to their original locations."
        if !result.missingFiles.isEmpty {
            message += "\n\n⚠️ \(result.missingFiles.count) file(s) cannot be restored because they were moved or deleted."
        }
        if !result.directoryIssues.isEmpty {
            message += "\n\n⚠️ \(result.directoryIssues.count) original folder(s) no longer exist and will be recreated."
        }
        return message
    }

    private func redoConfirmationMessage(_ result: PreflightValidationResult) -> String {
        var message = "This will reorganize \(result.availableCount) file(s) according to the original plan."
        if !result.missingFiles.isEmpty {
            message += "\n\n⚠️ \(result.missingFiles.count) file(s) are no longer available."
        }
        return message
    }

    @ViewBuilder
    private func rawAIResponseSection(_ raw: String) -> some View {
        let displayRaw = FeatureFlags.privacyModeEnabled ? PrivacyPathMasker.redactedText(raw) : raw
        let copyRaw = FeatureFlags.privacyModeEnabled ? displayRaw : raw
        let responseLines = displayRaw.components(separatedBy: .newlines)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleRawAIResponse()
                HapticFeedbackManager.shared.tap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showRawAIResponse ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Raw AI Response")
                        .font(.headline)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("RawAIResponseDisclosure")
            .accessibilityHint(showRawAIResponse ? "Tap to collapse" : "Tap to expand")

            if showRawAIResponse {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        CopyButtonWithAnimation(
                            content: copyRaw,
                            label: FeatureFlags.privacyModeEnabled ? "Copy Redacted JSON" : "Copy Raw JSON"
                        )
                        .accessibilityIdentifier("CopyRawJSONButton")
                    }

                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(responseLines.enumerated()), id: \.offset) { _, line in
                                Text(line.isEmpty ? " " : line)
                                    .scrollTransition(
                                        topLeading: .identity,
                                        bottomTrailing: reduceMotion
                                            ? .identity
                                            : .interactive(timingCurve: .easeInOut)
                                                .threshold(.visible(0.18)),
                                        axis: .vertical
                                    ) { content, phase in
                                        content
                                            .opacity(phase == .bottomTrailing ? 0 : 1)
                                            .blur(radius: phase == .bottomTrailing ? 1.5 : 0)
                                            .offset(y: phase == .bottomTrailing ? 6 : 0)
                                    }
                            }
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .defaultScrollAnchor(.topLeading)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 500, alignment: .leading)
                    .padding()
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
                    .accessibilityLabel(FeatureFlags.privacyModeEnabled ? "Raw AI response hidden in Privacy Mode" : "Raw AI response data")
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
                )
            }
        }
    }

    private func toggleRawAIResponse() {
        if showRawAIResponse {
            withAnimation(rawAIResponseDisclosureAnimation) {
                showRawAIResponse = false
            }
            return
        }

        withAnimation(rawAIResponseDisclosureAnimation) {
            showRawAIResponse = true
        }
    }

    private var rawAIResponseDisclosureAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.12)
            : .spring(response: 0.52, dampingFraction: 0.86)
    }

    private func handleUndo() {
        HapticFeedbackManager.shared.tap()
        // Perform pre-flight validation before showing confirmation
        Task { @MainActor in
            let result = performPreflightValidation(for: .undo)
            preflightResult = result
            showUndoConfirmation = true
        }
    }

    private func executeUndo() {
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            do {
                let result = try await organizer.undoHistoryEntry(entry)
                if result.hasIssues {
                    HapticFeedbackManager.shared.tap()
                    // Show detailed partial result sheet
                    partialUndoResult = PartialUndoResult(
                        successCount: result.successfulOperations,
                        missingFiles: result.missingFiles,
                        failedOperationCount: result.retryableFailedOperationIDs.count,
                        directoryPath: entry.directoryPath
                    )
                    isProcessing = false
                    showPartialResultSheet = true
                } else {
                    HapticFeedbackManager.shared.success()
                    onAction("All \(result.successfulOperations) operations reversed successfully.")
                    onDismiss()
                }
            } catch {
                HapticFeedbackManager.shared.error()
                onAction(friendlyErrorMessage(for: error, operation: "undo"))
            }
            isProcessing = false
        }
    }

    private func handleRestore() {
        HapticFeedbackManager.shared.tap()
        showRestoreConfirmation = true
    }

    private func showDifferentModelPicker() {
        HapticFeedbackManager.shared.tap()
        showRedoModelPicker = true
    }

    private func executeRestore() {
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            do {
                let result = try await organizer.restoreToState(targetEntry: entry)
                if result.hasIssues {
                    HapticFeedbackManager.shared.tap()
                    partialUndoResult = PartialUndoResult(
                        successCount: result.successfulOperations,
                        missingFiles: result.missingFiles,
                        failedOperationCount: result.retryableFailedOperationIDs.count,
                        directoryPath: entry.directoryPath
                    )
                    isProcessing = false
                    showPartialResultSheet = true
                } else {
                    HapticFeedbackManager.shared.success()
                    onAction("Folder state restored successfully.")
                    onDismiss()
                }
            } catch {
                HapticFeedbackManager.shared.error()
                onAction(friendlyErrorMessage(for: error, operation: "restore"))
            }
            isProcessing = false
        }
    }

    private func handleRedo() {
        HapticFeedbackManager.shared.tap()
        // Perform pre-flight validation before showing confirmation
        Task { @MainActor in
            let result = performPreflightValidation(for: .redo)
            preflightResult = result
            showRedoConfirmation = true
        }
    }

    private func executeRedo() {
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            do {
                try await organizer.redoOrganization(from: entry)
                HapticFeedbackManager.shared.success()
                onAction("Organization re-applied successfully.")
                onDismiss()
            } catch {
                HapticFeedbackManager.shared.error()
                onAction(friendlyErrorMessage(for: error, operation: "redo"))
            }
            isProcessing = false
        }
    }

    private enum PreflightOperation {
        case undo
        case redo
    }

    private func performPreflightValidation(for operation: PreflightOperation) -> PreflightValidationResult {
        var missingFiles: [String] = []
        var directoryIssues: [String] = []
        var availableCount = 0

        let fileManager = FileManager.default

        switch operation {
        case .undo:
            // Check if files at destination paths still exist (for undo, we move from destination back to source)
            guard let operations = entry.operations else {
                return PreflightValidationResult(availableCount: 0, missingFiles: [], directoryIssues: [])
            }

            for op in operations where op.type == .moveFile || op.type == .renameFile {
                if let destPath = op.destinationPath {
                    if fileManager.fileExists(atPath: destPath) {
                        availableCount += 1
                        // Check if source directory still exists
                        let sourceDir = URL(fileURLWithPath: op.sourcePath).deletingLastPathComponent().path
                        if !fileManager.fileExists(atPath: sourceDir) && !directoryIssues.contains(sourceDir) {
                            directoryIssues.append(sourceDir)
                        }
                    } else {
                        let fileName = URL(fileURLWithPath: destPath).lastPathComponent
                        missingFiles.append(fileName)
                    }
                }
            }

        case .redo:
            // For redo, check if source files exist at their original locations
            guard let operations = entry.operations else {
                return PreflightValidationResult(availableCount: 0, missingFiles: [], directoryIssues: [])
            }

            for op in operations where op.type == .moveFile || op.type == .renameFile {
                if fileManager.fileExists(atPath: op.sourcePath) {
                    availableCount += 1
                } else {
                    let fileName = URL(fileURLWithPath: op.sourcePath).lastPathComponent
                    missingFiles.append(fileName)
                }
            }
        }

        return PreflightValidationResult(
            availableCount: availableCount,
            missingFiles: missingFiles,
            directoryIssues: directoryIssues
        )
    }

    private func friendlyErrorMessage(for error: Error, operation: String) -> String {
        let nsError = error as NSError

        // Handle common file system errors with actionable guidance
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileNoSuchFileError:
                return "Some files were moved or deleted since this organization. Try using 'Undo' on individual operations instead."
            case NSFileWriteNoPermissionError:
                return "Permission denied. Check that Sorty has access to this folder in System Settings > Privacy & Security > Files and Folders."
            case NSFileWriteOutOfSpaceError:
                return "Not enough disk space. Free up some space and try again."
            case NSFileWriteVolumeReadOnlyError:
                return "This volume is read-only. Check that the disk is not locked or in read-only mode."
            default:
                break
            }
        }

        // Default to the localized description with operation context
        return "Could not \(operation): \(error.localizedDescription)"
    }

    private func handleRestoreDuplicates() {
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            guard let restorables = entry.restorableItems else {
                isProcessing = false
                return
            }
            var restoredCount = 0
            var failedCount = 0
            for item in restorables {
                guard DuplicateRestorationManager.shared.canRestore(item: item) else {
                    failedCount += 1
                    continue
                }
                do {
                    try DuplicateRestorationManager.shared.restore(item: item)
                    restoredCount += 1
                } catch {
                    failedCount += 1
                }
            }
            if restoredCount > 0 {
                HapticFeedbackManager.shared.success()
            } else {
                HapticFeedbackManager.shared.error()
            }
            let failureSuffix = failedCount == 0 ? "" : " \(failedCount) could not be restored because they were removed from Trash or their destination is occupied."
            onAction("Restored \(restoredCount) files.\(failureSuffix)")
            isProcessing = false
            onDismiss()
        }
    }

    private func handleUndoSingleOperation(_ operation: FileSystemManager.FileOperation) {
        HapticFeedbackManager.shared.tap()
        undoingOperationID = operation.id
        Task {
            do {
                let result = try await organizer.undoSingleOperation(from: currentEntry, operation: operation)
                if result.hasIssues {
                    HapticFeedbackManager.shared.error()
                    failedOperationIDs.insert(operation.id)
                } else {
                    HapticFeedbackManager.shared.success()
                    undoneOperationIDs.insert(operation.id)
                }
            } catch {
                HapticFeedbackManager.shared.error()
                failedOperationIDs.insert(operation.id)
            }
            undoingOperationID = nil
        }
    }

    private func handleRedoWithModel(provider: AIProvider, model: String) {
        showRedoModelPicker = false
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            do {
                // Set up folder context from history entry
                let directoryURL = URL(fileURLWithPath: entry.directoryPath)
                organizer.currentDirectory = directoryURL

                // Generate new plan with specified provider/model
                try await organizer.regenerateWithModel(provider: provider, model: model)
                HapticFeedbackManager.shared.success()
                onAction("New organization generated with \(provider.displayName) (\(model)).")
                onDismiss()
            } catch {
                HapticFeedbackManager.shared.error()
                onAction("Error: \(error.localizedDescription)")
            }
            isProcessing = false
        }
    }

}

// MARK: - Operation Row View

struct OperationRowView: View {
    let operation: FileSystemManager.FileOperation
    let isUndone: Bool
    let isFailed: Bool
    let isUndoing: Bool
    let isEntryUndone: Bool
    let onUndo: () -> Void

    @State private var isHovered = false

    private var fileName: String {
        if let dest = operation.destinationPath {
            return URL(fileURLWithPath: dest).lastPathComponent
        }
        return URL(fileURLWithPath: operation.sourcePath).lastPathComponent
    }

    private var operationIcon: String {
        switch operation.type {
        case .moveFile: return "arrow.right.doc"
        case .renameFile: return "pencil.line"
        case .tagFile: return "tag"
        case .createFolder: return "folder.badge.plus"
        case .deleteFile: return "trash"
        case .copyFile: return "doc.on.doc"
        }
    }

    private var operationLabel: String {
        switch operation.type {
        case .moveFile: return operation.metadata?.newFilename == nil ? "Moved" : "Moved & Renamed"
        case .renameFile: return "Renamed"
        case .tagFile: return "Tagged"
        case .createFolder: return "Created"
        case .deleteFile: return "Deleted"
        case .copyFile: return "Copied"
        }
    }

    private var destinationFolder: String? {
        guard let dest = operation.destinationPath else { return nil }
        return URL(fileURLWithPath: dest).deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            if isUndone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else if isFailed {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                Image(systemName: operationIcon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(fileName)
                    .font(.caption)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(operationLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let folder = destinationFolder {
                        Text("→ \(folder)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if isUndoing {
                CometLoader(size: 16, lineWidth: 2, color: .secondary)
                    .frame(width: 16, height: 16)
            } else if !isUndone && !isEntryUndone {
                Button {
                    onUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.mini)
                .disabled(isFailed)
                .accessibilityLabel("Undo \(fileName)")
                .accessibilityIdentifier("UndoOperation-\(operation.id.uuidString)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isUndone ? Color.green.opacity(0.05) : isFailed ? Color.red.opacity(0.05) : Color.secondary.opacity(0.05))
        )
        .opacity(isUndone ? 0.7 : 1.0)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(operationLabel) \(fileName)\(isUndone ? ", undone" : "")\(isFailed ? ", failed" : "")")
    }
}

// MARK: - Processing Overlay

struct ProcessingOverlay: View {
    let stage: String
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.1)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                BouncingSpinner(size: 24, color: .accentColor)

                Text(stage)
                    .font(.body)
                    .foregroundColor(.primary)
            }
            .padding(24)
            .background(.regularMaterial)
            .cornerRadius(12)
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Processing: \(stage)")
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - Detail Stat View

struct DetailStatView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(value)
                    .font(.headline)
                    .numericTextTransition(animationValue: value)
            }
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(minWidth: 120, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: OrganizationStatus

    private var color: Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .skipped: return .secondary
        case .undo: return .orange
        case .partiallyUndone: return .yellow
        case .duplicatesCleanup: return .accentColor
        }
    }

    var body: some View {
        Text(status.rawValue.uppercased())
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
            .accessibilityLabel("Status: \(status.rawValue)")
    }
}

// MARK: - Section View

struct SectionView<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(color)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

// MARK: - Folder History Detail Row

struct FolderHistoryDetailRow: View {
    let suggestion: FolderSuggestion
    var rootDirectory: URL? = nil
    @Binding var highlightedFileID: UUID?
    @EnvironmentObject var learningsManager: LearningsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var showStoragePopover = false
    @State private var visibleFileCount: Int = 60
    private let filePageSize: Int = 60

    private func fileTags(for file: FileItem) -> [String]? {
        let tags = suggestion.tags(for: file)
        return tags.isEmpty ? nil : tags
    }

    private func fileComment(for file: FileItem) -> String? {
        suggestion.comment(for: file)
    }

    private var allSiblingFiles: [FileItem] {
        suggestion.files
    }

    private var isStorageDestination: Bool {
        suggestion.folderName.hasPrefix("/")
    }

    private var storageLocationURL: URL? {
        StorageLocationPathResolver.absoluteURL(from: suggestion.folderName)
    }

    private var storageLocationPath: String {
        storageLocationURL?.path ?? suggestion.folderName
    }

    private var storageLocationDisplayName: String {
        storageLocationURL?.lastPathComponent ?? "Storage"
    }

    private func fileDuplicateInfo(for file: FileItem) -> DuplicateInfo? {
        guard let hash = file.sha256Hash, !hash.isEmpty else { return nil }
        let duplicates = allSiblingFiles.filter { $0.id != file.id && $0.sha256Hash == hash }
        guard !duplicates.isEmpty else { return nil }
        return DuplicateInfo(file: file, duplicates: duplicates, isExactMatch: true, similarity: 1.0)
    }

    private func subtreeContainsFile(_ fileID: UUID, in folder: FolderSuggestion) -> Bool {
        if folder.files.contains(where: { $0.id == fileID }) {
            return true
        }
        for subfolder in folder.subfolders {
            if subtreeContainsFile(fileID, in: subfolder) {
                return true
            }
        }
        return false
    }

    private func expandForHighlightedFileIfNeeded(_ fileID: UUID?) {
        guard let fileID, !isExpanded else { return }
        guard subtreeContainsFile(fileID, in: suggestion) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded = true
        }
    }

    private func toggleExpanded() {
        HapticFeedbackManager.shared.tap()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
            isExpanded.toggle()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)

                    CompactFolderThumbnail(
                        url: nil,
                        folderName: suggestion.folderName,
                        size: 18
                    )
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(reduceMotion ? nil : .subtleBounce, value: isHovered)
                    .accessibilityHidden(true)

                    PrivacySensitivePathText(path: suggestion.folderName)
                        .fontWeight(.semibold)

                    Text("(\(suggestion.totalFileCount) files)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if isStorageDestination {
                        storageLocationDropdown
                    }

                    if !suggestion.tags.isEmpty {
                        TagDotsView(tags: suggestion.tags)
                    }

                    if let comment = suggestion.comment, !comment.isEmpty {
                        CommentBubbleButton(comment: comment)
                    }

                    Spacer()

                    LiquidGlassReasoningButton(suggestion: suggestion)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(suggestion.folderName), \(suggestion.totalFileCount) files")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    let shouldAnimate = suggestion.files.count <= 40
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(suggestion.files.prefix(visibleFileCount).enumerated()), id: \.element.id) { index, fileItem in
                            FolderHistoryFileRow(
                                file: fileItem,
                                suggestion: suggestion,
                                tags: fileTags(for: fileItem),
                                comment: fileComment(for: fileItem),
                                duplicateInfo: fileDuplicateInfo(for: fileItem),
                                rootDirectory: rootDirectory,
                                learningsManager: learningsManager,
                                highlightedFileID: $highlightedFileID,
                                isExpanded: isExpanded,
                                animationDelay: shouldAnimate && !reduceMotion
                                    ? Double(index) * 0.02
                                    : nil
                            )
                        }

                        if suggestion.files.count > visibleFileCount {
                            Button {
                                HapticFeedbackManager.shared.tap()
                                visibleFileCount = min(visibleFileCount + filePageSize, suggestion.files.count)
                            } label: {
                                Label("Show more files", systemImage: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(suggestion.subfolders) { subfolder in
                        FolderHistoryDetailRow(
                            suggestion: subfolder,
                            rootDirectory: rootDirectory,
                            highlightedFileID: $highlightedFileID
                        )
                        .padding(.leading, 12)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                )
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(8)
        .onAppear {
            expandForHighlightedFileIfNeeded(highlightedFileID)
        }
        .onChange(of: highlightedFileID) { _, newValue in
            expandForHighlightedFileIfNeeded(newValue)
        }
    }

    @ViewBuilder
    private var storageLocationDropdown: some View {
        Button {
            showStoragePopover.toggle()
        } label: {
            Image(systemName: "externaldrive")
                .font(.caption)
                .foregroundStyle(showStoragePopover ? .primary : .secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .help("Storage location options")
        .accessibilityIdentifier("HistoryStorageLocationMenuButton-\(suggestion.id.uuidString)")
        .popover(isPresented: $showStoragePopover, arrowEdge: .bottom) {
            StorageLocationPopoverContent(
                displayName: storageLocationDisplayName,
                path: storageLocationPath,
                onShowInFinder: {
                    showStoragePopover = false
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: storageLocationPath)
                },
                onCopyPath: {
                    showStoragePopover = false
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(storageLocationPath, forType: .string)
                }
            )
            .systemLiquidGlassPopover(cornerRadius: 12)
        }
    }
}

private struct FolderHistoryFileRow: View {
    let file: FileItem
    let suggestion: FolderSuggestion
    let tags: [String]?
    let comment: String?
    let duplicateInfo: DuplicateInfo?
    let rootDirectory: URL?
    let learningsManager: LearningsManager
    @Binding var highlightedFileID: UUID?
    let isExpanded: Bool
    let animationDelay: Double?

    var body: some View {
        HStack(spacing: 8) {
            FileThumbnailView(
                url: URL(fileURLWithPath: file.path),
                size: CGSize(width: 20, height: 20)
            )
            Text(file.displayName)

            if let tags, !tags.isEmpty {
                TagDotsView(tags: tags)
            }

            if let comment, !comment.isEmpty {
                CommentBubbleButton(comment: comment)
            }

            LiquidGlassLearningsButton(
                file: file,
                suggestion: suggestion,
                learningsManager: learningsManager
            )

            if let duplicateInfo {
                LiquidGlassDuplicateButton(
                    duplicateInfo: duplicateInfo,
                    handoffDirectory: rootDirectory,
                    highlightedFileID: $highlightedFileID
                )
            }

            Spacer()
            Text(file.formattedSize)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    highlightedFileID == file.id
                        ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.12)
                        : Color.clear
                )
        )
        .opacity(isExpanded ? 1 : 0)
        .offset(y: isExpanded ? 0 : -5)
        .animation(
            animationDelay.map {
                Animation.spring(response: 0.3, dampingFraction: 0.7).delay($0)
            },
            value: isExpanded
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(file.displayName), \(file.formattedSize)")
    }
}

// MARK: - Load More Button

struct LoadMoreButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    CometLoader(size: 16, lineWidth: 2)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 16))
                }

                Text(isLoading ? "Loading..." : "Load More History")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SortyDesignSystem.Colors.resolvedAccent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Loading more history entries" : "Load more history entries")
        .accessibilityIdentifier("LoadMoreHistoryButton")
    }
}

// MARK: - Liquid Glass AI Reasoning Card (History)

private struct HistoryLearningsFileContext: Identifiable {
    let file: FileItem
    let suggestion: FolderSuggestion

    var id: UUID { file.id }
}

struct HistoryLiquidGlassLearningsCard: View {
    let plan: OrganizationPlan

    @EnvironmentObject var learningsManager: LearningsManager
    @State private var showPopover = false
    @State private var hoveredFileID: UUID?

    private var ruledSuggestions: [FolderSuggestion] {
        flattenSuggestions(plan.suggestions).filter(hasRuleContext(_:))
    }

    private var fileContexts: [HistoryLearningsFileContext] {
        var contexts: [HistoryLearningsFileContext] = []
        var seenIDs: Set<UUID> = []

        for suggestion in ruledSuggestions {
            for file in suggestion.files where seenIDs.insert(file.id).inserted {
                contexts.append(HistoryLearningsFileContext(file: file, suggestion: suggestion))
            }
        }

        return contexts
    }

    var body: some View {
        if !fileContexts.isEmpty {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(.teal)
                    Text("Learnings Applied")
                        .font(.headline)
                    Text("\(fileContexts.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.teal))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .systemLiquidGlassBackground(cornerRadius: 999)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Learnings applied to \(fileContexts.count) files")
            .accessibilityHint("Tap to view file-specific learnings")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                learningsPopover
                    .systemLiquidGlassPopover(cornerRadius: 12)
            }
        }
    }

    private var learningsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.teal)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Learnings Applied")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("\(fileContexts.count) file\(fileContexts.count == 1 ? "" : "s") with learnings context")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.bottom, 10)

            Divider()
                .opacity(0.4)
                .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fileContexts) { context in
                        learningsFileRow(context)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .padding(14)
        .frame(minWidth: 320, maxWidth: 430)
    }

    private func learningsFileRow(_ context: HistoryLearningsFileContext) -> some View {
        HStack(spacing: 10) {
            FileThumbnailView(url: URL(fileURLWithPath: context.file.path), size: CGSize(width: 24, height: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(context.file.displayName)
                    .font(.callout)
                    .lineLimit(1)

                PrivacySensitivePathText(path: context.suggestion.folderName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            LiquidGlassLearningsButton(
                file: context.file,
                suggestion: context.suggestion,
                learningsManager: learningsManager
            )
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredFileID == context.file.id ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .onHover { isHovering in
            hoveredFileID = isHovering ? context.file.id : nil
        }
    }

    private func flattenSuggestions(_ suggestions: [FolderSuggestion]) -> [FolderSuggestion] {
        suggestions.flatMap { suggestion in
            [suggestion] + flattenSuggestions(suggestion.subfolders)
        }
    }

    private func hasRuleContext(_ suggestion: FolderSuggestion) -> Bool {
        if let ruleID = suggestion.ruleId?.trimmingCharacters(in: .whitespacesAndNewlines), !ruleID.isEmpty {
            return true
        }

        return suggestion.semanticTags.contains { tag in
            tag.lowercased().hasPrefix("rule:")
        }
    }
}

struct HistoryLiquidGlassReasoningCard: View {
    let notes: String
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                Text("AI Reasoning")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .systemLiquidGlassBackground(cornerRadius: 999)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI Reasoning")
        .accessibilityHint("Tap to view AI reasoning details")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.12))
                            .frame(width: 28, height: 28)

                        Image(systemName: "brain")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                    }

                    Text("AI Reasoning")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.bottom, 10)

                Divider()
                    .opacity(0.4)
                    .padding(.bottom, 10)

                FormattedReasoningText(
                    text: notes,
                    font: .callout,
                    secondaryFont: .caption,
                    foregroundStyle: .primary
                )
            }
            .padding(14)
            .frame(minWidth: 280, maxWidth: 400)
            .systemLiquidGlassPopover(cornerRadius: 12)
        }
    }
}

// MARK: - Liquid Glass Duplicate Summary Card (History)

struct HistoryLiquidGlassDuplicateCard: View {
    let plan: OrganizationPlan
    var handoffDirectory: URL? = nil
    @Binding var highlightedFileID: UUID?
    @State private var showPopover = false
    @EnvironmentObject var appState: AppState

    private var duplicateGroups: [DuplicateInfo] {
        var allFiles: [FileItem] = []
        func collectFiles(from folder: FolderSuggestion) {
            allFiles.append(contentsOf: folder.files)
            for subfolder in folder.subfolders { collectFiles(from: subfolder) }
        }
        for suggestion in plan.suggestions { collectFiles(from: suggestion) }
        allFiles.append(contentsOf: plan.unorganizedFiles)

        // Ignore repeated references to the same physical file in a historical plan.
        var uniqueFiles: [FileItem] = []
        var seenPaths: Set<String> = []
        for file in allFiles {
            let normalizedPath = URL(fileURLWithPath: file.path).standardizedFileURL.path
            if seenPaths.insert(normalizedPath).inserted {
                uniqueFiles.append(file)
            }
        }

        var hashGroups: [String: [FileItem]] = [:]
        for file in uniqueFiles {
            guard let hash = file.sha256Hash, !hash.isEmpty else { continue }
            hashGroups[hash, default: []].append(file)
        }

        var infos: [DuplicateInfo] = []
        var seenHashes: Set<String> = []
        for (hash, files) in hashGroups where files.count > 1 {
            guard !seenHashes.contains(hash) else { continue }
            seenHashes.insert(hash)
            if let first = files.first {
                let others = Array(files.dropFirst())
                infos.append(DuplicateInfo(file: first, duplicates: others, isExactMatch: true, similarity: 1.0))
            }
        }
        return infos.sorted { $0.duplicateCount > $1.duplicateCount }
    }

    private var totalDuplicateCount: Int {
        duplicateGroups.reduce(0) { $0 + $1.duplicateCount }
    }

    var body: some View {
        if !duplicateGroups.isEmpty {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.red)
                    Text("Duplicates")
                        .font(.headline)
                    Text("\(totalDuplicateCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .systemLiquidGlassBackground(cornerRadius: 999)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Duplicates found: \(totalDuplicateCount)")
            .accessibilityHint("Tap to view duplicate file groups")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                historyDuplicatePopover
                    .systemLiquidGlassPopover(cornerRadius: 12)
            }
        }
    }

    private var historyDuplicatePopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Duplicate Files")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text("\(duplicateGroups.count) group\(duplicateGroups.count == 1 ? "" : "s"), \(totalDuplicateCount) duplicate\(totalDuplicateCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.bottom, 10)

            Divider()
                .opacity(0.4)
                .padding(.bottom, 10)

            Button {
                handoffToDuplicates()
            } label: {
                Label("Handle in Duplicates", systemImage: "arrowshape.turn.up.right.circle.fill")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(duplicateGroups) { group in
                        HistoryDuplicateGroupRow(
                            group: group,
                            handoffDirectory: handoffDirectory,
                            highlightedFileID: $highlightedFileID
                        )
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(14)
        .frame(minWidth: 300, maxWidth: 400)
    }

    private func handoffToDuplicates() {
        let filePaths = duplicateGroups.flatMap { group in
            [group.file.path] + group.duplicates.map(\.path)
        }
        appState.handoffToDuplicates(
            forFilePaths: filePaths,
            preferredDirectory: handoffDirectory,
            autoStart: true
        )
        showPopover = false
        HapticFeedbackManager.shared.selection()
    }
}

// MARK: - History Helper Views

struct HistoryDuplicateGroupRow: View {
    let group: DuplicateInfo
    var handoffDirectory: URL? = nil
    @Binding var highlightedFileID: UUID?
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    highlightedFileID = group.file.id
                }
            } label: {
                HStack(spacing: 6) {
                    FileThumbnailView(url: URL(fileURLWithPath: group.file.path), size: CGSize(width: 20, height: 20))
                    Text(group.file.displayName)
                        .font(.callout)
                        .fontWeight(highlightedFileID == group.file.id ? .semibold : .medium)
                        .foregroundStyle(highlightedFileID == group.file.id ? .primary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(group.duplicateCount + 1) copies")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.red))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(highlightedFileID == group.file.id ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.12) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .contextMenu {
                contextMenu(for: group.file.path)
            }

            ForEach(group.duplicates) { dup in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        highlightedFileID = dup.id
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(dup.displayName)
                            .font(.caption)
                            .fontWeight(highlightedFileID == dup.id ? .semibold : .regular)
                            .foregroundStyle(highlightedFileID == dup.id ? .primary : .secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(dup.formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(highlightedFileID == dup.id ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.12) : Color.clear)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .contextMenu {
                    contextMenu(for: dup.path)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func contextMenu(for path: String) -> some View {
        let groupPaths = [group.file.path] + group.duplicates.map(\.path)

        Button {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        Button {
            appState.handoffToDuplicates(
                forFilePaths: groupPaths,
                preferredDirectory: handoffDirectory,
                autoStart: true
            )
        } label: {
            Label("Handle in Duplicates", systemImage: "arrowshape.turn.up.right.circle")
        }
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } label: {
            Label("Quick Look", systemImage: "eye")
        }
        Button {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                NotificationManager.shared.show(.info(title: "Success", message: "Moved duplicate to Trash"))
            } catch {
                NotificationManager.shared.showError(message: "Could not move to Trash: \(error.localizedDescription)")
            }
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }
}

// MARK: - Pre-flight Validation Models

/// Result of pre-flight validation before undo/redo operations
struct PreflightValidationResult {
    let availableCount: Int
    let missingFiles: [String]
    let directoryIssues: [String]

    var hasIssues: Bool { !missingFiles.isEmpty || !directoryIssues.isEmpty }
}

/// Result shown when an undo operation partially succeeds
struct PartialUndoResult {
    let successCount: Int
    let missingFiles: [String]
    let failedOperationCount: Int
    let directoryPath: String

    var folderName: String {
        URL(fileURLWithPath: directoryPath).lastPathComponent
    }
}

// MARK: - Partial Undo Result Sheet

struct PartialUndoResultSheet: View {
    let result: PartialUndoResult
    let onDismiss: () -> Void

    @State private var isHoveredOpenFolder = false
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange.gradient)
                    .accessibilityHidden(true)

                Text("Partial Undo Complete")
                    .font(.title2.bold())

                Text("Some files could not be restored")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            // Stats
            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(result.successCount)")
                        .font(.title.bold())
                        .foregroundStyle(.green)
                    Text("Restored")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 40)

                VStack(spacing: 4) {
                    Text("\(result.missingFiles.count)")
                        .font(.title.bold())
                        .foregroundStyle(.orange)
                    Text("Missing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if result.failedOperationCount > 0 {
                    Divider()
                        .frame(height: 40)

                    VStack(spacing: 4) {
                        Text("\(result.failedOperationCount)")
                            .font(.title.bold())
                            .foregroundStyle(.red)
                        Text("Failed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 16)

            Divider()

            // Missing files list
            if !result.missingFiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Files Not Found", systemImage: "questionmark.folder")
                            .font(.headline)
                        Spacer()
                        Text("\(result.missingFiles.count) file\(result.missingFiles.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("These files may have been moved, renamed, or deleted:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(result.missingFiles, id: \.self) { fileName in
                                let displayName = FeatureFlags.privacyModeEnabled
                                    ? PrivacyPathMasker.redactedText(fileName)
                                    : fileName
                                HStack(spacing: 8) {
                                    Image(systemName: "doc.questionmark")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    Text(displayName)
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.08))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
                .padding(16)
            }

            Spacer(minLength: 0)

            // Actions
            VStack(spacing: 12) {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: result.directoryPath)
                } label: {
                    Label("Open Folder in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.sortyBordered)
                .scaleEffect(isHoveredOpenFolder ? 1.02 : 1.0)
                .animation(.subtleBounce, value: isHoveredOpenFolder)
                .onHover { isHoveredOpenFolder = $0 }
                .accessibilityIdentifier("OpenFolderButton")

                Button("Done") {
                    HapticFeedbackManager.shared.tap()
                    onDismiss()
                }
                .buttonStyle(.sortyProminent)
                .controlSize(.large)
                .accessibilityIdentifier("DismissPartialResultButton")
            }
            .padding(20)
        }
        .frame(minWidth: 400, idealWidth: 400, maxWidth: 400, minHeight: 450)
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Partial undo complete. \(result.successCount) files restored, \(result.missingFiles.count) files not found.")
    }
}

#Preview {
    HistoryView()
        .environmentObject(AppState())
        .environmentObject(FolderOrganizer())
        .environmentObject(SettingsViewModel())
        .frame(width: 900, height: 700)
}

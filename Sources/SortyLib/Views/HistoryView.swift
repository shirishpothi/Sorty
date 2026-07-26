//
//  HistoryView.swift
//  Sorty
//
//  Advanced History view with 6 stats, card-based layout matching DuplicatesView style
//  Enhanced with haptic feedback, micro-animations, and full ARIA accessibility
//

import SwiftUI

private struct HistoryImpactSummary: Equatable {
    var filesOrganized = 0
    var foldersCreated = 0
    var totalSessions = 0
    var completedSessions = 0
    var totalTimeSaved: TimeInterval = 0

    init(entries: [OrganizationHistoryEntry] = []) {
        totalSessions = entries.count

        for entry in entries where entry.status == .completed {
            filesOrganized += entry.filesOrganized
            foldersCreated += entry.foldersCreated
            completedSessions += 1
            totalTimeSaved += entry.plan?.generationStats?.estimatedTimeSaved ?? 0
        }
    }

    var successRate: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }
}

private struct HistorySessionRow: Identifiable, Equatable {
    let id: UUID
    let folderName: String
    let timestamp: Date
    let status: OrganizationStatus
    let filesOrganized: Int
    let foldersCreated: Int
    let duplicatesDeleted: Int?
    let recoveredSpace: Int64?
    let generationMetadata: String?

    init(entry: OrganizationHistoryEntry) {
        id = entry.id
        folderName = URL(fileURLWithPath: entry.directoryPath).lastPathComponent
        timestamp = entry.timestamp
        status = entry.status
        filesOrganized = entry.filesOrganized
        foldersCreated = entry.foldersCreated
        duplicatesDeleted = entry.duplicatesDeleted
        recoveredSpace = entry.recoveredSpace

        if let stats = entry.plan?.generationStats {
            let modelName = stats.compactModelName
            generationMetadata = stats.hasBillableCost
                ? "\(modelName) · \(GenerationStats.formatCost(stats.computedCost))"
                : modelName
        } else {
            generationMetadata = nil
        }
    }
}

private struct HistorySessionRecord: Equatable {
    let row: HistorySessionRow
    let directoryPath: String
    let source: OrganizationEntrySource
    let isUndone: Bool
    let hasOperations: Bool

    init(entry: OrganizationHistoryEntry) {
        row = HistorySessionRow(entry: entry)
        directoryPath = entry.directoryPath
        source = entry.source
        isUndone = entry.isUndone
        hasOperations = !(entry.operations?.isEmpty ?? true)
    }
}

struct HistoryView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @State private var selectedEntry: OrganizationHistoryEntry?
    @State private var isProcessing = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var selectedFilter: HistoryFilter = .all
    @State private var searchText: String = ""
    @State private var contentOpacity: Double = 0
    @State private var showingDetail = false
    @State private var showRedoModelPicker = false
    @State private var redoModelEntry: OrganizationHistoryEntry?
    @State private var activeNotificationRedoRequestID: UUID?
    @State private var cachedEntries: [OrganizationHistoryEntry] = []
    @State private var cachedSessionRecords: [HistorySessionRecord] = []
    @State private var filteredManualEntries: [HistorySessionRow] = []
    @State private var filteredWatchedEntries: [HistorySessionRow] = []
    @State private var impactSummary = HistoryImpactSummary()
    @State private var displayedEntryCount = 50
    private let pageSize = 50

    private var hasFilteredEntries: Bool {
        !filteredManualEntries.isEmpty || !filteredWatchedEntries.isEmpty
    }

    private var manualEntries: ArraySlice<HistorySessionRow> {
        filteredManualEntries.prefix(displayedEntryCount)
    }

    private var watchedEntries: ArraySlice<HistorySessionRow> {
        filteredWatchedEntries.prefix(displayedEntryCount)
    }

    private var hasMoreEntries: Bool {
        manualEntries.count < filteredManualEntries.count ||
            watchedEntries.count < filteredWatchedEntries.count
    }

    private enum HistorySectionKind: Equatable {
        case manual
        case watched

        var title: String {
            switch self {
            case .manual: "Manual Sessions"
            case .watched: "Watched Folder Automations"
            }
        }

        var systemImage: String {
            switch self {
            case .manual: "person.fill"
            case .watched: "bolt.horizontal.circle"
            }
        }
    }

    private var primarySectionKind: HistorySectionKind {
        selectedFilter == .watched || manualEntries.isEmpty ? .watched : .manual
    }

    private var showsSecondaryWatchedSection: Bool {
        primarySectionKind == .manual && !watchedEntries.isEmpty
    }

    enum HistoryFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case undoable = "Undoable"
        case failed = "Failed"
        case skipped = "Skipped"
        case cancelled = "Cancelled"
        case manual = "Manual"
        case watched = "Watched"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .all: "tray.full"
            case .undoable: "arrow.uturn.backward.circle"
            case .failed: "exclamationmark.triangle"
            case .skipped: "forward"
            case .cancelled: "xmark.circle"
            case .manual: "hand.tap"
            case .watched: "eye"
            }
        }

        func includes(
            status: OrganizationStatus,
            source: OrganizationEntrySource,
            isUndone: Bool = false,
            hasOperations: Bool = false
        ) -> Bool {
            switch self {
            case .all: true
            case .undoable:
                !isUndone &&
                    hasOperations &&
                    (status == .completed || status == .partiallyUndone)
            case .failed: status == .failed
            case .skipped: status == .skipped
            case .cancelled: status == .cancelled
            case .manual: source == .manual
            case .watched: source == .watchedFolder
            }
        }
    }

    var body: some View {
        Group {
            if cachedEntries.count > 1 {
                content
                    .searchable(text: $searchText, prompt: "Search folders")
            } else {
                content
            }
        }
        .onReceive(organizer.history.$entries) { entries in
            refreshHistorySnapshot(entries)
            if entries.count <= 1 {
                searchText = ""
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if cachedEntries.isEmpty {
                ZStack(alignment: .topLeading) {
                    HistoryEmptyStateView()
                        .transition(TransitionStyles.scaleAndFade)

                    HistoryHeader(
                        totalSessions: impactSummary.totalSessions,
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
                    totalSessions: impactSummary.totalSessions,
                    selectedFilter: $selectedFilter,
                    showsControls: true,
                    onClearHistory: {
                        appState.clearHistoryWithConfirmation()
                    }
                )

                Divider()

                ZStack {
                    if !searchText.isEmpty && !hasFilteredEntries {
                        HistorySearchEmptyStateView(searchText: searchText, onClear: { searchText = "" })
                            .transition(TransitionStyles.scaleAndFade)
                    } else {
                        historyEntriesScroll
                        .background(Color(NSColor.windowBackgroundColor))
                        .transition(TransitionStyles.slideFromRight)
                    }
                }
                .opacity(contentOpacity)
            }
        }
        .emptyStateWorkflowGradient(isVisible: cachedEntries.isEmpty)
        .animation(.pageTransition, value: cachedEntries.isEmpty)
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
            consumePendingNotificationActionIfNeeded()
        }
        .onChange(of: selectedFilter) { _, _ in
            displayedEntryCount = pageSize
            refreshFilteredEntries()
        }
        .onChange(of: searchText) { _, _ in
            displayedEntryCount = pageSize
            refreshFilteredEntries()
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
        List {
            HistorySummaryCard(summary: impactSummary)
                .padding(.top, 10)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("History Summary")
                .listRowInsets(EdgeInsets(top: 6, leading: 28, bottom: 12, trailing: 28))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            historySessionsSection(primarySectionKind)

            if showsSecondaryWatchedSection {
                historySessionsSection(.watched)
            }

            if hasMoreEntries {
                LoadMoreHistoryRow {
                    displayedEntryCount += pageSize
                }
                .task(id: displayedEntryCount) {
                    await Task.yield()
                    guard hasMoreEntries else { return }
                    displayedEntryCount += pageSize
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 28, bottom: 16, trailing: 28))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func historySessionsSection(_ kind: HistorySectionKind) -> some View {
        let entries = kind == .manual ? manualEntries : watchedEntries
        let totalCount = kind == .manual ? filteredManualEntries.count : filteredWatchedEntries.count

        if !entries.isEmpty {
            HStack {
                Label(kind.title, systemImage: kind.systemImage)
                    .font(.headline)
                Spacer()
                Text("\(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .numericTextTransition(animationValue: totalCount)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 28, bottom: 4, trailing: 28))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            ForEach(entries) { entry in
                HistorySessionCard(
                    entry: entry,
                    isSelected: selectedEntry?.id == entry.id,
                    onSelect: {
                        HapticFeedbackManager.shared.selection()
                        selectEntry(id: entry.id)
                    },
                    onTryAgain: {
                        prepareTryAgain(id: entry.id)
                    }
                )
                .listRowInsets(EdgeInsets(top: 6, leading: 28, bottom: 6, trailing: 28))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if kind == .manual && showsSecondaryWatchedSection {
                Color.clear
                    .frame(height: 4)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func refreshHistorySnapshot(_ entries: [OrganizationHistoryEntry]) {
        let records = entries.map(HistorySessionRecord.init)
        cachedEntries = entries
        cachedSessionRecords = records
        impactSummary = HistoryImpactSummary(entries: entries)
        refreshFilteredEntries(in: records)
    }

    private func refreshFilteredEntries() {
        refreshFilteredEntries(in: cachedSessionRecords)
    }

    private func refreshFilteredEntries(in records: [HistorySessionRecord]) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var manual: [HistorySessionRow] = []
        var watched: [HistorySessionRow] = []
        manual.reserveCapacity(records.count)
        watched.reserveCapacity(records.count / 4)

        for record in records {
            guard selectedFilter.includes(
                status: record.row.status,
                source: record.source,
                isUndone: record.isUndone,
                hasOperations: record.hasOperations
            ) else {
                continue
            }
            guard query.isEmpty || record.directoryPath.localizedCaseInsensitiveContains(query) else {
                continue
            }

            switch record.source {
            case .manual:
                manual.append(record.row)
            case .watchedFolder:
                watched.append(record.row)
            }
        }

        filteredManualEntries = manual
        filteredWatchedEntries = watched
    }

    private func selectEntry(id: UUID) {
        guard let entry = cachedEntries.first(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedEntry = entry
            showingDetail = true
        }
    }

    private func prepareTryAgain(id: UUID) {
        guard let entry = cachedEntries.first(where: { $0.id == id }) else { return }
        redoModelEntry = entry
        showRedoModelPicker = true
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
    let totalSessions: Int
    @Binding var selectedFilter: HistoryView.HistoryFilter
    var showsControls: Bool = true
    let onClearHistory: () -> Void

    var body: some View {
        Group {
            if showsControls {
                populatedHeader
            } else {
                emptyStateTitleRow
            }
        }
        .padding(.horizontal, showsControls ? 28 : 32)
        .padding(.vertical, showsControls ? 12 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History controls")
    }

    private var populatedHeader: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.blue.gradient)
                Text("History")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .lineLimit(1)

                Text("\(totalSessions) runs")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .numericTextTransition(animationValue: totalSessions)
                    .accessibilityLabel("\(totalSessions) runs recorded")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("History, \(totalSessions) runs")

            Spacer(minLength: 12)

            HistoryNavigatorPicker(selection: $selectedFilter)

            Spacer(minLength: 12)

            clearHistoryButton
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

    private var clearHistoryButton: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            onClearHistory()
        } label: {
            Label("Clear", systemImage: "trash")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .systemLiquidGlassBackground(cornerRadius: 999)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(totalSessions == 0)
        .accessibilityLabel("Clear all history")
        .accessibilityIdentifier("ClearHistoryButton")
    }
}

private struct HistoryNavigatorPicker: View {
    @Binding var selection: HistoryView.HistoryFilter

    private var animatedSelection: Binding<HistoryView.HistoryFilter> {
        Binding(
            get: { selection },
            set: { newSelection in
                guard newSelection != selection else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    selection = newSelection
                }
                HapticFeedbackManager.shared.selection()
            }
        )
    }

    var body: some View {
        Picker("Filter history sessions", selection: animatedSelection) {
            ForEach(HistoryView.HistoryFilter.allCases) { filter in
                Label(filter.rawValue, systemImage: filter.systemImage)
                    .labelStyle(.iconOnly)
                    .tag(filter)
                    .accessibilityLabel(filter.rawValue)
                    .help(filter.rawValue)
            }
        }
        .pickerStyle(.palette)
        .buttonStyle(.accessoryBar)
        .labelsHidden()
        .controlSize(.large)
        .fixedSize()
        .accessibilityIdentifier("HistoryFilterPicker")
    }
}

// MARK: - History Summary Card (Dashboard Impact Stats)

private struct HistorySummaryCard: View {
    let summary: HistoryImpactSummary

    private var filesOrganizedValue: String {
        "\(summary.filesOrganized)"
    }

    private var timeSavedValue: String {
        let seconds = summary.totalTimeSaved
        if seconds < 3600 {
            let minutes = seconds / 60.0
            return String(format: "%.1f", minutes)
        } else {
            let hours = seconds / 3600.0
            return String(format: "%.1f", hours)
        }
    }

    private var timeSavedLabel: String {
        summary.totalTimeSaved < 3600 ? "Minutes Saved" : "Hours Saved"
    }

    private var foldersCreatedValue: String {
        "\(summary.foldersCreated)"
    }

    private var totalSessionsValue: String {
        "\(summary.totalSessions)"
    }

    private var successRateValue: String {
        summary.totalSessions > 0
            ? "\(Int(summary.successRate * 100))%"
            : "—"
    }

    private var successRateLabel: String {
        summary.totalSessions > 0
            ? "\(Int(summary.successRate * 100)) percent"
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

private struct HistorySessionCardHeader: View {
    let entry: HistorySessionRow
    let timestampText: String
    let statusColor: Color
    let showsStatus: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 25))
                .foregroundStyle(.blue.gradient)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.folderName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 10) {
                    HistorySessionSummary(entry: entry)

                    Text(timestampText)
                        .lineLimit(1)

                    if let generationMetadata = entry.generationMetadata {
                        Label(generationMetadata, systemImage: "cpu")
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if showsStatus {
                Text(entry.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .contentShape(Rectangle())
    }
}

private struct HistorySessionSummary: View {
    let entry: HistorySessionRow

    var body: some View {
        HStack(spacing: 4) {
            if entry.status == .duplicatesCleanup {
                metric("\(entry.duplicatesDeleted ?? 0) deleted", systemImage: "trash")
                if let recovered = entry.recoveredSpace {
                    metric(
                        ByteCountFormatter.string(fromByteCount: recovered, countStyle: .file),
                        systemImage: "externaldrive"
                    )
                }
            } else {
                metric("\(entry.filesOrganized)", systemImage: "doc")
                metric("\(entry.foldersCreated)", systemImage: "folder")
            }
        }
    }

    private func metric(_ value: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(value)
                .monospacedDigit()
        }
    }
}

private struct HistorySessionCard: View {
    let entry: HistorySessionRow
    let isSelected: Bool
    let onSelect: () -> Void
    let onTryAgain: () -> Void

    @State private var isHovered = false

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

    private var canTryAgain: Bool {
        switch entry.status {
        case .failed, .cancelled, .skipped: true
        case .completed, .undo, .partiallyUndone, .duplicatesCleanup: false
        }
    }

    var body: some View {
        let timestampText = entry.timestamp.formatted(date: .abbreviated, time: .shortened)

        HStack(spacing: 4) {
            Button {
                onSelect()
            } label: {
                HistorySessionCardHeader(
                    entry: entry,
                    timestampText: timestampText,
                    statusColor: statusColor,
                    showsStatus: !canTryAgain
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(entry.folderName), \(entry.status.displayName)\(entry.generationMetadata.map { ", model and cost \($0)" } ?? ""), \(entry.filesOrganized) files, \(entry.foldersCreated) folders, \(timestampText)"
            )
            .accessibilityHint("Open session details")
            .accessibilityIdentifier("HistorySessionCard-\(entry.id.uuidString)")

            if canTryAgain {
                Button {
                    HapticFeedbackManager.shared.tap()
                    onTryAgain()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 30)
                        .background(
                            SortyDesignSystem.Colors.resolvedAccent.opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Try this organization again")
                .accessibilityHint("Choose a model and regenerate the organization")
                .accessibilityIdentifier("TryAgainButton-\(entry.id.uuidString)")
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 12)
                .accessibilityHidden(true)
        }
        .background(
            isHovered
                ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.055)
                : Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.5) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct LoadMoreHistoryRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Load More History", systemImage: "chevron.down.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Load more history entries")
        .accessibilityIdentifier("LoadMoreHistoryButton")
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
    @State private var feedbackGiven: LearningsManager.SessionOutcome?
    @State private var showFeedbackConfirmation = false

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

                    if learningsManager.summary.canProvideFeedback,
                       entry.status == .completed,
                       !entry.isUndone {
                        QuickFeedbackButtons(
                            feedbackGiven: $feedbackGiven,
                            showConfirmation: $showFeedbackConfirmation,
                            onFeedback: recordFeedback
                        )
                    }

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

    private func recordFeedback(_ outcome: LearningsManager.SessionOutcome) {
        learningsManager.recordSessionOutcomeFeedback(
            sessionId: entry.id.uuidString,
            outcome: outcome,
            folderPath: entry.directoryPath
        )
        DebugLogger.log("Session feedback recorded: \(outcome.rawValue) for session \(entry.id.uuidString)")
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
        Text(status.displayName.uppercased())
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
            .accessibilityLabel("Status: \(status.displayName)")
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

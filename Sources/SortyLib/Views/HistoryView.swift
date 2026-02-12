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
    @State private var selectedEntry: OrganizationHistoryEntry?
    @State private var isProcessing = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var selectedFilter: HistoryFilter = .all
    @State private var contentOpacity: Double = 0
    @State private var showingDetail = false
    
    // Lazy loading state
    @State private var displayedEntryCount: Int = 50
    @State private var isLoadingMore: Bool = false
    private let pageSize: Int = 50
    private let loadMoreThreshold: Int = 10 // Load more when within 10 items of end

    private var filteredEntries: [OrganizationHistoryEntry] {
        let allEntries: [OrganizationHistoryEntry]
        switch selectedFilter {
        case .all: allEntries = organizer.history.entries
        case .success: allEntries = organizer.history.entries.filter { $0.status == .completed }
        case .failed: allEntries = organizer.history.entries.filter { $0.status == .failed }
        case .skipped: allEntries = organizer.history.entries.filter { $0.status == .skipped || $0.status == .cancelled }
        }
        // Return only the entries up to the current display limit
        return Array(allEntries.prefix(displayedEntryCount))
    }
    
    private var hasMoreEntries: Bool {
        let totalCount: Int
        switch selectedFilter {
        case .all: totalCount = organizer.history.entries.count
        case .success: totalCount = organizer.history.entries.filter { $0.status == .completed }.count
        case .failed: totalCount = organizer.history.entries.filter { $0.status == .failed }.count
        case .skipped: totalCount = organizer.history.entries.filter { $0.status == .skipped || $0.status == .cancelled }.count
        }
        return displayedEntryCount < totalCount
    }

    enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case success = "Success"
        case failed = "Failed"
        case skipped = "Skipped"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header - matches DuplicatesView style
            HistoryHeader(
                manager: organizer,
                selectedFilter: $selectedFilter,
                onClearHistory: clearHistory
            )

            Divider()

            ZStack {
                if organizer.history.entries.isEmpty {
                    HistoryEmptyStateView()
                        .transition(TransitionStyles.scaleAndFade)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Summary Card - 6 stats in 2x3 grid
                            HistorySummaryCard(history: organizer.history)
                                .padding(.top, 16)
                                .accessibilityElement(children: .contain)
                                .accessibilityLabel("History Summary")

                            // Session Cards
                            ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                HistorySessionCard(
                                    entry: entry,
                                    isSelected: selectedEntry == entry,
                                    onSelect: {
                                        HapticFeedbackManager.shared.selection()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            selectedEntry = entry
                                            showingDetail = true
                                        }
                                    },
                                    onUndo: { handleUndo(entry) },
                                    onRedo: { handleRedo(entry) },
                                    onRedoWithModel: { provider, model in
                                        handleRedoWithModel(entry, provider: provider, model: model)
                                    }
                                )
                                .animatedAppearance(delay: Double(index) * 0.03)
                                .onAppear {
                                    // Load more when approaching the end of the list
                                    if index >= filteredEntries.count - loadMoreThreshold && hasMoreEntries && !isLoadingMore {
                                        loadMoreEntries()
                                    }
                                }
                            }
                            
                            // Load More Button
                            if hasMoreEntries {
                                LoadMoreButton(isLoading: isLoadingMore) {
                                    loadMoreEntries()
                                }
                                .padding(.vertical, 16)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(TransitionStyles.slideFromRight)
                }
            }
            .animation(.pageTransition, value: organizer.history.entries.isEmpty)
            .animation(.pageTransition, value: selectedFilter)
            .opacity(contentOpacity)
        }
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
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            // Reset pagination when filter changes
            displayedEntryCount = pageSize
        }
    }

    private func clearHistory() {
        HapticFeedbackManager.shared.tap()
        organizer.history.clearHistory()
        displayedEntryCount = pageSize // Reset pagination
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

    private func handleUndo(_ entry: OrganizationHistoryEntry) {
        isProcessing = true
        Task { @MainActor in
            do {
                let result = try await organizer.undoHistoryEntry(entry)
                if result.hasIssues {
                    HapticFeedbackManager.shared.tap()
                    alertMessage = "Partially restored: \(result.successfulOperations) file(s) reversed, \(result.missingFiles.count) could not be found."
                } else {
                    HapticFeedbackManager.shared.success()
                    alertMessage = "Operations reversed successfully."
                }
                showAlert = true
            } catch {
                HapticFeedbackManager.shared.error()
                alertMessage = "Error: \(error.localizedDescription)"
                showAlert = true
            }
            isProcessing = false
        }
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
            } catch {
                HapticFeedbackManager.shared.error()
                alertMessage = "Error: \(error.localizedDescription)"
                showAlert = true
            }
            isProcessing = false
        }
    }
}

// MARK: - History Header

struct HistoryHeader: View {
    @ObservedObject var manager: FolderOrganizer
    @Binding var selectedFilter: HistoryView.HistoryFilter
    let onClearHistory: () -> Void

    @State private var showClearConfirmation = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(.blue.gradient)
                    Text("Organization History")
                        .font(.title2.bold())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Organization History")

                Text("\(manager.history.totalSessions) sessions recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(manager.history.totalSessions) sessions recorded")
            }

            Spacer()

            // Filter Picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(HistoryView.HistoryFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            .accessibilityLabel("Filter history sessions")
            .accessibilityIdentifier("HistoryFilterPicker")
            .onChange(of: selectedFilter) { _, _ in
                HapticFeedbackManager.shared.selection()
            }

            Button {
                showClearConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(manager.history.entries.isEmpty)
            .accessibilityLabel("Clear all history")
            .accessibilityIdentifier("ClearHistoryButton")
            .confirmationDialog("Clear History?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear All History", role: .destructive) {
                    onClearHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently remove all history entries. This cannot be undone.")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History controls")
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

    private var totalCostValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 4
        return formatter.string(from: history.totalEstimatedCost as NSDecimalNumber) ?? "$0.00"
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Impact Dashboard", systemImage: "chart.bar.xaxis.ascending")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: gridColumns, spacing: 8) {
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
                    color: .purple
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

                HistoryStatItem(
                    title: "Total AI Cost",
                    value: totalCostValue,
                    icon: "dollarsign.circle.fill",
                    color: .mint
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Total AI cost: \(totalCostValue)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
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
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color.gradient)
                .accessibilityHidden(true)

            Text(value)
                .font(.headline)
                .contentTransition(.numericText())

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 70)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - History Session Card

struct HistorySessionCard: View {
    let entry: OrganizationHistoryEntry
    let isSelected: Bool
    let onSelect: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    var onRedoWithModel: ((AIProvider, String) -> Void)? = nil

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var showRedoModelPicker = false
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .skipped: return .secondary
        case .undo: return .orange
        case .partiallyUndone: return .yellow
        case .duplicatesCleanup: return .purple
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticFeedbackManager.shared.tap()
            } label: {
                HStack(spacing: 12) {
                    // Status Icon
                    FolderThumbnailView(url: URL(fileURLWithPath: entry.directoryPath), size: CGSize(width: 32, height: 32))
                        .frame(width: 32)
                        .accessibilityHidden(true)

                    // Main Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(URL(fileURLWithPath: entry.directoryPath).lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)

                        HStack(spacing: 16) {
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

                    Spacer()

                    // Timestamp
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Expand Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .padding(16)
                .contentShape(Rectangle())
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

                VStack(alignment: .leading, spacing: 12) {
                    // Full Path
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(entry.directoryPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Path: \(entry.directoryPath)")

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

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            onSelect()
                        } label: {
                            Label("View Details", systemImage: "info.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("View session details")
                        .accessibilityIdentifier("ViewDetailsButton-\(entry.id.uuidString)")

                        if entry.success && entry.status != .duplicatesCleanup {
                            if entry.isUndone {
                                Button {
                                    onRedo()
                                } label: {
                                    Label("Redo", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.onboardingPill)
                                .controlSize(.small)
                                .accessibilityLabel("Redo organization")
                                .accessibilityIdentifier("RedoButton-\(entry.id.uuidString)")
                            } else {
                                Button {
                                    onUndo()
                                } label: {
                                    Label("Undo", systemImage: "arrow.uturn.backward")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Undo organization")
                                .accessibilityIdentifier("UndoButton-\(entry.id.uuidString)")
                            }
                            
                            // Try with different model button
                            Button {
                                HapticFeedbackManager.shared.tap()
                                showRedoModelPicker = true
                            } label: {
                                Label("Try Different Model", systemImage: "wand.and.stars")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Try organization with a different AI model")
                            .accessibilityIdentifier("TryModelButton-\(entry.id.uuidString)")
                        }

                        Spacer()
                    }
                }
                .padding(16)
                .background(Color.black.opacity(0.02))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .sheet(isPresented: $showRedoModelPicker) {
            ModelSelectionPopover(
                isPresented: $showRedoModelPicker,
                currentProvider: settingsViewModel.config.provider,
                currentModel: settingsViewModel.config.model,
                onSelect: { provider, model in
                    onRedoWithModel?(provider, model)
                }
            )
        }
    }
}

// MARK: - History Empty State

struct HistoryEmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .opacity(0.8)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("No History Yet")
                    .font(.title2.bold())

                Text("Your organization sessions will appear here. Start by organizing a folder.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No history yet. Your organization sessions will appear here.")
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
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    private var currentEntry: OrganizationHistoryEntry {
        organizer.history.entries.first { $0.id == entry.id } ?? entry
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Info
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: entry.directoryPath).lastPathComponent)
                                    .font(.title.bold())
                                Text(entry.timestamp.formatted(date: .complete, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusBadge(status: entry.status)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(URL(fileURLWithPath: entry.directoryPath).lastPathComponent), \(entry.status.rawValue), \(entry.timestamp.formatted())")

                        // Full Path
                        Label(entry.directoryPath, systemImage: "folder")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                            .accessibilityLabel("Full path: \(entry.directoryPath)")
                    }

                    Divider()

                    // Stats Section
                    if entry.success || entry.status == .duplicatesCleanup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Session Statistics")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            HStack(spacing: 20) {
                                if entry.status == .duplicatesCleanup {
                                    DetailStatView(
                                        title: "Duplicates Deleted",
                                        value: "\(entry.duplicatesDeleted ?? 0)",
                                        icon: "trash.fill",
                                        color: .red
                                    )
                                    if let recovered = entry.recoveredSpace {
                                        DetailStatView(
                                            title: "Space Recovered",
                                            value: ByteCountFormatter.string(fromByteCount: recovered, countStyle: .file),
                                            icon: "externaldrive.fill",
                                            color: .green
                                        )
                                    }
                                } else {
                                    DetailStatView(
                                        title: "Files Organized",
                                        value: "\(entry.filesOrganized)",
                                        icon: "doc.fill",
                                        color: .blue
                                    )
                                    DetailStatView(
                                        title: "Folders Created",
                                        value: "\(entry.foldersCreated)",
                                        icon: "folder.fill",
                                        color: .purple
                                    )
                                    if let plan = entry.plan {
                                        DetailStatView(
                                            title: "Plan Version",
                                            value: "v\(plan.version)",
                                            icon: "number",
                                            color: .gray
                                        )
                                    }
                                }
                            }

                            // Nerd Stats Grid (if available)
                            if let stats = entry.plan?.generationStats {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Generation Metrics")
                                        .font(.headline)
                                        .padding(.top, 4)

                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 8)], spacing: 8) {
                                            NerdStatCard(
                                                icon: "bolt.fill",
                                                iconColor: .orange,
                                                title: "Speed",
                                                value: String(format: "%.1f", stats.tps),
                                                unit: "tok/s",
                                                description: "Processing throughput"
                                            )

                                            NerdStatCard(
                                                icon: "timer",
                                                iconColor: .blue,
                                                title: "Latency",
                                                value: String(format: "%.2f", stats.ttft),
                                                unit: "s",
                                                description: "Time to first token"
                                            )

                                            NerdStatCard(
                                                icon: "sum",
                                                iconColor: .purple,
                                                title: "Total",
                                                value: "\(stats.totalTokens)",
                                                unit: "tok",
                                                description: "Context consumption"
                                            )

                                            if let scanned = stats.filesScanned {
                                                NerdStatCard(
                                                    icon: "doc.text.magnifyingglass",
                                                    iconColor: .green,
                                                    title: "Scanned",
                                                    value: "\(scanned)",
                                                    unit: "files",
                                                    description: "Total files processed"
                                                )
                                            }

                                            if let size = stats.totalFileSize {
                                                let formatted = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                                                let components = formatted.components(separatedBy: " ")
                                                let value = components.first ?? formatted
                                                let unit = components.count > 1 ? components.last : nil

                                                NerdStatCard(
                                                    icon: "internaldrive",
                                                    iconColor: .cyan,
                                                    title: "Volume",
                                                    value: value,
                                                    unit: unit,
                                                    description: "Data footprint"
                                                )
                                            }

                                            if let dups = stats.duplicatesFound {
                                                NerdStatCard(
                                                    icon: "doc.on.doc",
                                                    iconColor: .red,
                                                    title: "Duplicates",
                                                    value: "\(dups)",
                                                    unit: nil,
                                                    description: "Content matches"
                                                )
                                            }
                                    }
                                }
                            }
                        }
                    }

                    // Error Section
                    if !entry.success, let error = entry.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Error", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.red)
                                .accessibilityAddTraits(.isHeader)

                            Text(error)
                                .font(.callout)
                                .foregroundColor(.red)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.red.opacity(0.05))
                                .cornerRadius(8)
                                .accessibilityLabel("Error: \(error)")
                        }
                    }

                    // Actions Section
                    if entry.success || entry.status == .duplicatesCleanup {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Actions")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            VStack(alignment: .leading, spacing: 8) {
                                if entry.status == .duplicatesCleanup {
                                    if let restorables = entry.restorableItems, !restorables.isEmpty {
                                        Button {
                                            handleRestoreDuplicates()
                                        } label: {
                                            Label("Restore Deleted Files", systemImage: "arrow.uturn.backward")
                                                .frame(minWidth: 150)
                                        }
                                        .buttonStyle(.onboardingPill)
                                        .controlSize(.large)
                                        .accessibilityLabel("Restore deleted files")
                                        .accessibilityIdentifier("RestoreDuplicatesButton")
                                    }
                                } else if entry.isUndone {
                                    Button {
                                        handleRedo()
                                    } label: {
                                        Label("Re-Apply Organization", systemImage: "arrow.clockwise")
                                            .frame(minWidth: 150)
                                    }
                                    .buttonStyle(.onboardingPill)
                                    .controlSize(.large)
                                    .accessibilityLabel("Re-apply this organization")
                                    .accessibilityIdentifier("RedoSessionButton")
                                } else {
                                    Button {
                                        handleRestore()
                                    } label: {
                                        Label("Restore to State", systemImage: "clock.arrow.circlepath")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.onboardingPill)
                                    .controlSize(.large)
                                    .accessibilityLabel("Restore folder to this state")
                                    .accessibilityIdentifier("RestoreStateButton")

                                    HStack(spacing: 12) {
                                        Button {
                                            handleUndo()
                                        } label: {
                                            Label("Undo Changes", systemImage: "arrow.uturn.backward")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.large)
                                        .accessibilityLabel("Undo these changes")
                                        .accessibilityIdentifier("UndoSessionButton")

                                        Button {
                                            HapticFeedbackManager.shared.tap()
                                            showRedoModelPicker = true
                                        } label: {
                                            Label("Try Different Model", systemImage: "wand.and.stars")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.large)
                                        .accessibilityLabel("Try organization with a different AI model")
                                        .accessibilityIdentifier("TryModelSessionButton")
                                    }
                                }
                            }
                        }
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
                        let ruledSuggestions = plan.suggestions.flatMap { collectRuledSuggestions($0) }
                        if !ruledSuggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                        .foregroundStyle(.orange)
                                    Text("Learnings Applied")
                                        .font(.headline)
                                    Text("\(ruledSuggestions.count)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.orange))
                                }
                                .accessibilityAddTraits(.isHeader)

                                ForEach(ruledSuggestions, id: \.id) { suggestion in
                                    HStack(spacing: 10) {
                                        ZStack {
                                            Circle()
                                                .fill(Color.orange.opacity(0.12))
                                                .frame(width: 28, height: 28)
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.orange)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(suggestion.folderName)
                                                .font(.callout)
                                                .fontWeight(.medium)
                                            if !suggestion.reasoning.isEmpty {
                                                Text(suggestion.reasoning)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.orange.opacity(0.15), lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    // AI Reasoning
                    if let plan = entry.plan, !plan.notes.isEmpty {
                        HistoryLiquidGlassReasoningCard(notes: plan.notes)
                    }

                    // Organization Details
                    if let plan = entry.plan {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Organization Details")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(plan.suggestions) { suggestion in
                                FolderHistoryDetailRow(suggestion: suggestion)
                            }

                            if !plan.unorganizedFiles.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Unorganized Files")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.orange)

                                    LazyVStack(alignment: .leading, spacing: 6) {
                                        ForEach(plan.unorganizedFiles) { fileItem in
                                            HStack {
                                                FileThumbnailView(url: URL(fileURLWithPath: fileItem.path), size: CGSize(width: 20, height: 20))
                                                Text(fileItem.displayName)
                                                Spacer()
                                            }
                                            .font(.caption)
                                            .accessibilityElement(children: .combine)
                                            .accessibilityLabel("Unorganized file: \(fileItem.displayName)")
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.orange.opacity(0.05))
                                .cornerRadius(8)
                            }
                        }
                    }

                    // Individual File Operations (only non-tag operations, since tags are shown in Organization Details)
                    if let operations = currentEntry.operations, !operations.isEmpty {
                        let fileOps = operations.filter { $0.type == .moveFile || $0.type == .renameFile }
                        if !fileOps.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("File Operations")
                                        .font(.headline)
                                        .accessibilityAddTraits(.isHeader)
                                    Spacer()
                                    Text("\(fileOps.count) operation\(fileOps.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                LazyVStack(spacing: 6) {
                                    ForEach(fileOps, id: \.id) { op in
                                        OperationRowView(
                                            operation: op,
                                            isUndone: undoneOperationIDs.contains(op.id),
                                            isFailed: failedOperationIDs.contains(op.id),
                                            isUndoing: undoingOperationID == op.id,
                                            isEntryUndone: currentEntry.isUndone,
                                            onUndo: { handleUndoSingleOperation(op) }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    // Restorable Items for Duplicates
                    if let restorables = entry.restorableItems, !restorables.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Deleted Files")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(restorables) { item in
                                HStack {
                                    FileThumbnailView(url: URL(fileURLWithPath: item.deletedPath), size: CGSize(width: 20, height: 20))
                                    Text(URL(fileURLWithPath: item.deletedPath).lastPathComponent)
                                    Spacer()
                                    Text("Original: \(URL(fileURLWithPath: item.originalPath).lastPathComponent)")
                                        .foregroundStyle(.tertiary)
                                        .font(.caption2)
                                }
                                .font(.caption)
                                .padding(8)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(6)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Deleted: \(URL(fileURLWithPath: item.deletedPath).lastPathComponent), original: \(URL(fileURLWithPath: item.originalPath).lastPathComponent)")
                            }
                        }
                    }

                    // Raw AI Response
                    if let raw = entry.rawAIResponse {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showRawAIResponse.toggle()
                                }
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
                                        CopyButtonWithAnimation(content: raw, label: "Copy Raw JSON")
                                            .accessibilityIdentifier("CopyRawJSONButton")
                                    }
                                    
                                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                                        Text(raw)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 500, alignment: .leading)
                                    .padding()
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(8)
                                    .accessibilityLabel("Raw AI response data")
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
                .padding(24)
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
        .frame(minWidth: 600, minHeight: 500)
        .sheet(isPresented: $showRedoModelPicker) {
            ModelSelectionPopover(
                isPresented: $showRedoModelPicker,
                currentProvider: settingsViewModel.config.provider,
                currentModel: settingsViewModel.config.model,
                onSelect: { provider, model in
                    handleRedoWithModel(provider: provider, model: model)
                }
            )
        }
    }

    private func handleUndo() {
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            do {
                try await organizer.undoHistoryEntry(entry)
                HapticFeedbackManager.shared.success()
                onAction("Operations reversed successfully.")
                onDismiss()
            } catch {
                HapticFeedbackManager.shared.error()
                onAction("Error: \(error.localizedDescription)")
            }
            isProcessing = false
        }
    }

    private func handleRestore() {
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            do {
                try await organizer.restoreToState(targetEntry: entry)
                HapticFeedbackManager.shared.success()
                onAction("Folder state restored.")
                onDismiss()
            } catch {
                HapticFeedbackManager.shared.error()
                onAction("Error: \(error.localizedDescription)")
            }
            isProcessing = false
        }
    }

    private func handleRedo() {
        HapticFeedbackManager.shared.tap()
        isProcessing = true
        Task {
            do {
                try await organizer.redoOrganization(from: entry)
                HapticFeedbackManager.shared.success()
                onAction("Organization re-applied.")
                onDismiss()
            } catch {
                HapticFeedbackManager.shared.error()
                onAction("Error: \(error.localizedDescription)")
            }
            isProcessing = false
        }
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
            for item in restorables {
                do {
                    try DuplicateRestorationManager.shared.restore(item: item)
                    restoredCount += 1
                } catch {
                    // Continue with other items
                }
            }
            HapticFeedbackManager.shared.success()
            onAction("Restored \(restoredCount) files.")
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

    private func collectRuledSuggestions(_ suggestion: FolderSuggestion) -> [FolderSuggestion] {
        var results: [FolderSuggestion] = []
        if suggestion.ruleId != nil {
            results.append(suggestion)
        }
        for sub in suggestion.subfolders {
            results.append(contentsOf: collectRuledSuggestions(sub))
        }
        return results
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
        case .moveFile: return "Moved"
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
                ProgressView()
                    .controlSize(.small)
            } else if !isUndone && !isEntryUndone {
                Button {
                    onUndo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
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
                    .contentTransition(.numericText())
            }
            Text(title)
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
        case .duplicatesCleanup: return .purple
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
    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var visibleFileCount: Int = 60
    private let filePageSize: Int = 60

    private func fileTags(for file: FileItem) -> [String]? {
        let tags = suggestion.tags(for: file)
        return tags.isEmpty ? nil : tags
    }

    private func fileComment(for file: FileItem) -> String? {
        suggestion.comment(for: file)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
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
                    .animation(.subtleBounce, value: isHovered)
                    .accessibilityHidden(true)

                    Text(suggestion.folderName)
                        .fontWeight(.semibold)

                    Text("(\(suggestion.totalFileCount) files)")
                        .font(.caption)
                        .foregroundColor(.secondary)

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
                            HStack(spacing: 8) {
                                FileThumbnailView(url: URL(fileURLWithPath: fileItem.path), size: CGSize(width: 20, height: 20))
                                Text(fileItem.displayName)

                                if let tags = fileTags(for: fileItem), !tags.isEmpty {
                                    TagDotsView(tags: tags)
                                }

                                if let comment = fileComment(for: fileItem), !comment.isEmpty {
                                    CommentBubbleButton(comment: comment)
                                }

                                Spacer()
                                Text(fileItem.formattedSize)
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.caption)
                            .padding(.leading, 12)
                            .opacity(isExpanded ? 1 : 0)
                            .offset(y: isExpanded ? 0 : -5)
                            .animation(
                                shouldAnimate
                                    ? .spring(response: 0.3, dampingFraction: 0.7).delay(Double(index) * 0.02)
                                    : .none,
                                value: isExpanded
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(fileItem.displayName), \(fileItem.formattedSize)")
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
                        FolderHistoryDetailRow(suggestion: subfolder)
                            .padding(.leading, 12)
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(8)
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
                    ProgressView()
                        .scaleEffect(0.8)
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
                    .fill(Color.accentColor.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "Loading more history entries" : "Load more history entries")
        .accessibilityIdentifier("LoadMoreHistoryButton")
    }
}

// MARK: - Liquid Glass AI Reasoning Card (History)

struct HistoryLiquidGlassReasoningCard: View {
    let notes: String
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                    .foregroundStyle(.purple)
                Text("AI Reasoning")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
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
                            .fill(Color.purple.opacity(0.12))
                            .frame(width: 28, height: 28)

                        Image(systemName: "brain")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.purple)
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
        }
    }
}

#Preview {
    HistoryView()
        .environmentObject(FolderOrganizer())
        .environmentObject(SettingsViewModel())
        .frame(width: 900, height: 700)
}

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
    @State private var selectedEntry: OrganizationHistoryEntry?
    @State private var isProcessing = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var selectedFilter: HistoryFilter = .all
    @State private var contentOpacity: Double = 0
    @State private var showingDetail = false

    private var filteredEntries: [OrganizationHistoryEntry] {
        switch selectedFilter {
        case .all: return organizer.history.entries
        case .success: return organizer.history.entries.filter { $0.status == .completed }
        case .failed: return organizer.history.entries.filter { $0.status == .failed }
        case .skipped: return organizer.history.entries.filter { $0.status == .skipped || $0.status == .cancelled }
        }
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
                                    onRedo: { handleRedo(entry) }
                                )
                                .animatedAppearance(delay: Double(index) * 0.03)
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
    }

    private func clearHistory() {
        HapticFeedbackManager.shared.tap()
        organizer.history.clearHistory()
    }

    private func handleUndo(_ entry: OrganizationHistoryEntry) {
        isProcessing = true
        Task {
            do {
                try await organizer.undoHistoryEntry(entry)
                HapticFeedbackManager.shared.success()
                alertMessage = "Operations reversed successfully."
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
        Task {
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
            }
            .buttonStyle(.bordered)
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

// MARK: - History Summary Card (6 Stats)

struct HistorySummaryCard: View {
    let history: OrganizationHistory

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 20) {
            HistoryStatItem(
                title: "Total Sessions",
                value: "\(history.totalSessions)",
                icon: "list.bullet.rectangle.fill",
                color: .gray
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Total sessions: \(history.totalSessions)")

            HistoryStatItem(
                title: "Files Organized",
                value: "\(history.totalFilesOrganized)",
                icon: "doc.on.doc.fill",
                color: .blue
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Files organized: \(history.totalFilesOrganized)")

            HistoryStatItem(
                title: "Folders Created",
                value: "\(history.totalFoldersCreated)",
                icon: "folder.fill.badge.plus",
                color: .purple
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Folders created: \(history.totalFoldersCreated)")

            HistoryStatItem(
                title: "Reverted",
                value: "\(history.revertedCount)",
                icon: "arrow.uturn.backward.circle.fill",
                color: .orange
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reverted: \(history.revertedCount)")

            HistoryStatItem(
                title: "Space Saved",
                value: ByteCountFormatter.string(fromByteCount: history.totalRecoveredSpace, countStyle: .file),
                icon: "externaldrive.fill.badge.checkmark",
                color: .green
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Space saved: \(ByteCountFormatter.string(fromByteCount: history.totalRecoveredSpace, countStyle: .file))")

            HistoryStatItem(
                title: "Success Rate",
                value: history.totalSessions > 0 ? "\(Int(Double(history.successCount) / Double(history.totalSessions) * 100))%" : "—",
                icon: "chart.line.uptrend.xyaxis.circle.fill",
                color: .teal
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Success rate: \(history.totalSessions > 0 ? "\(Int(Double(history.successCount) / Double(history.totalSessions) * 100)) percent" : "not available")")
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
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
                .font(.title2)
                .foregroundStyle(color.gradient)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.subtleBounce, value: isHovered)

            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 100)
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

    @State private var isExpanded = false
    @State private var isHovered = false

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        case .skipped: return .secondary
        case .undo: return .orange
        case .duplicatesCleanup: return .purple
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        case .skipped: return "arrow.right.circle.fill"
        case .undo: return "arrow.uturn.backward.circle.fill"
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
                    Image(systemName: statusIcon)
                        .font(.title3)
                        .foregroundStyle(statusColor)
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
                                .buttonStyle(.borderedProminent)
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
    @EnvironmentObject var organizer: FolderOrganizer

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

                            HStack(spacing: 12) {
                                if entry.status == .duplicatesCleanup {
                                    if let restorables = entry.restorableItems, !restorables.isEmpty {
                                        Button {
                                            handleRestoreDuplicates()
                                        } label: {
                                            Label("Restore Deleted Files", systemImage: "arrow.uturn.backward")
                                                .frame(minWidth: 150)
                                        }
                                        .buttonStyle(.borderedProminent)
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
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .accessibilityLabel("Re-apply this organization")
                                    .accessibilityIdentifier("RedoSessionButton")
                                } else {
                                    Button {
                                        handleUndo()
                                    } label: {
                                        Label("Undo Changes", systemImage: "arrow.uturn.backward")
                                            .frame(minWidth: 150)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .accessibilityLabel("Undo these changes")
                                    .accessibilityIdentifier("UndoSessionButton")

                                    Button {
                                        handleRestore()
                                    } label: {
                                        Label("Restore to State", systemImage: "clock.arrow.circlepath")
                                            .frame(minWidth: 150)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                    .accessibilityLabel("Restore folder to this state")
                                    .accessibilityIdentifier("RestoreStateButton")
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

                                    ForEach(plan.unorganizedFiles) { fileItem in
                                        HStack {
                                            Image(systemName: "doc")
                                                .foregroundStyle(.secondary)
                                            Text(fileItem.displayName)
                                            Spacer()
                                        }
                                        .font(.caption)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("Unorganized file: \(fileItem.displayName)")
                                    }
                                }
                                .padding()
                                .background(Color.orange.opacity(0.05))
                                .cornerRadius(8)
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
                                    Image(systemName: "doc")
                                        .foregroundColor(.secondary)
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
                        DisclosureGroup("Raw AI Response", isExpanded: $showRawAIResponse) {
                            Text(raw)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(8)
                                .accessibilityLabel("Raw AI response data")
                        }
                        .accessibilityIdentifier("RawAIResponseDisclosure")
                        .onChange(of: showRawAIResponse) { _, _ in
                            HapticFeedbackManager.shared.tap()
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

                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                        .animation(.subtleBounce, value: isHovered)
                        .accessibilityHidden(true)

                    Text(suggestion.folderName)
                        .fontWeight(.semibold)

                    Text("(\(suggestion.totalFileCount) files)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
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
                    if !suggestion.reasoning.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI REASONING")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.purple)
                            Text(suggestion.reasoning)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                                .background(Color.purple.opacity(0.05))
                                .cornerRadius(6)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("AI reasoning: \(suggestion.reasoning)")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(suggestion.files.enumerated()), id: \.element.id) { index, fileItem in
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                                Text(fileItem.displayName)
                                Spacer()
                                Text(fileItem.formattedSize)
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.caption)
                            .padding(.leading, 12)
                            .opacity(isExpanded ? 1 : 0)
                            .offset(y: isExpanded ? 0 : -5)
                            .animation(
                                .spring(response: 0.3, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.02),
                                value: isExpanded
                            )
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(fileItem.displayName), \(fileItem.formattedSize)")
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

#Preview {
    HistoryView()
        .environmentObject(FolderOrganizer())
        .frame(width: 900, height: 700)
}

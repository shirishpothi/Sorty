//
//  HistoryView.swift
//  FileOrganizer
//
//  Advanced History view with 4 stats, custom sidebar, and detailed reports
//  Enhanced with haptic feedback, micro-animations, and modal bounces
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
        HStack(spacing: 0) {
            // Internal Sidebar (Sessions List)
            VStack(spacing: 0) {
                if organizer.history.entries.isEmpty {
                    EmptyHistoryView()
                        .transition(TransitionStyles.scaleAndFade)
                } else {
                    // Quick Stats - 4 Cards
                    VStack(alignment: .leading, spacing: 12) {
                        Text("DASHBOARD")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .tracking(1.2)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            HistoryStatCard(title: "Sessions", value: "\(organizer.history.totalSessions)", icon: "list.bullet.rectangle", color: .gray)
                                .animatedAppearance(delay: 0.05)
                            HistoryStatCard(title: "Files", value: "\(organizer.history.totalFilesOrganized)", icon: "doc.on.doc", color: .blue)
                                .animatedAppearance(delay: 0.1)
                            HistoryStatCard(title: "Folders", value: "\(organizer.history.totalFoldersCreated)", icon: "folder.fill.badge.plus", color: .purple)
                                .animatedAppearance(delay: 0.15)
                            HistoryStatCard(title: "Reverted", value: "\(organizer.history.revertedCount)", icon: "arrow.uturn.backward", color: .orange)
                                .animatedAppearance(delay: 0.2)
                            HistoryStatCard(title: "Space Saved", value: "\(ByteCountFormatter.string(fromByteCount: organizer.history.totalRecoveredSpace, countStyle: .file))", icon: "externaldrive.fill.badge.plus", color: .green)
                                .animatedAppearance(delay: 0.25)
                        }
                    }
                    .padding(20)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    Divider()

                    // Filter Bar
                    LiquidDropdown(options: HistoryFilter.allCases, selection: $selectedFilter, title: "Show:")
                        .accessibilityIdentifier("HistoryFilterDropdown")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .onChange(of: selectedFilter) { oldValue, newValue in
                            HapticFeedbackManager.shared.selection()
                        }

                    List(Array(filteredEntries.enumerated()), id: \.element.id, selection: $selectedEntry) { index, entry in
                        HistoryEntryRow(entry: entry)
                            .tag(entry)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedEntry == entry ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                            .animatedAppearance(delay: Double(index) * 0.03)
                    }
                    .listStyle(.plain)
                    .padding(.top, 8)
                    .onChange(of: selectedEntry) { oldValue, newValue in
                        if newValue != nil {
                            HapticFeedbackManager.shared.selection()
                        }
                    }
                }
            }
            .frame(width: 400)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Detail Area
            ZStack {
                if let entry = selectedEntry {
                    HistoryDetailView(entry: entry, isProcessing: $isProcessing, onAction: { msg in
                        alertMessage = msg
                        showAlert = true
                    })
                    .id(entry.id)
                    .transition(TransitionStyles.slideFromRight)
                } else {
                    EmptyDetailView()
                        .transition(TransitionStyles.scaleAndFade)
                }
            }
            .animation(.pageTransition, value: selectedEntry?.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
    }
}

// MARK: - Empty History View

struct EmptyHistoryView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No History")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Select a session to view detailed report")
                .foregroundColor(.secondary)
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
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - History Entry Row

struct HistoryEntryRow: View {
    let entry: OrganizationHistoryEntry

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
        case .completed: return "checkmark"
        case .failed: return "xmark"
        case .cancelled: return "stop.fill"
        case .skipped: return "arrow.right.circle"
        case .undo: return "arrow.uturn.backward"
        case .duplicatesCleanup: return "trash.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.subtleBounce, value: isHovered)

            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: entry.directoryPath).lastPathComponent)
                    .font(.system(size: 14, weight: .semibold))
                    .strikethrough(entry.status == .undo)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    if entry.status == .completed {
                        Label("\(entry.filesOrganized) files", systemImage: "doc")
                            .font(.system(size: 11))
                        Label("\(entry.foldersCreated) folders", systemImage: "folder")
                            .font(.system(size: 11))
                    } else if entry.status == .duplicatesCleanup {
                        Label("\(entry.duplicatesDeleted ?? 0) deleted", systemImage: "trash")
                            .font(.system(size: 11))
                        if let recovered = entry.recoveredSpace {
                            Label(ByteCountFormatter.string(fromByteCount: recovered, countStyle: .file), systemImage: "externaldrive")
                                .font(.system(size: 11))
                        }
                    } else {
                        Text(entry.status.rawValue.capitalized)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(statusColor)
                    }
                    Spacer()
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .opacity(entry.status == .undo || entry.status == .skipped ? 0.6 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - History Detail View

struct HistoryDetailView: View {
    let entry: OrganizationHistoryEntry
    @Binding var isProcessing: Bool
    let onAction: (String) -> Void
    @State private var showRawAIResponse = false
    @State private var appeared = false

    @EnvironmentObject var organizer: FolderOrganizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.status == .completed ? "Organization Report" : "Session Detail")
                                .font(.title)
                                .fontWeight(.bold)
                            Text(entry.timestamp.formatted(date: .complete, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusBadge(status: entry.status)
                            .scaleEffect(appeared ? 1 : 0.8)
                            .opacity(appeared ? 1 : 0)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label(entry.directoryPath, systemImage: "folder")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)

                // Summary Stats in Detail
                if entry.success || entry.status == .duplicatesCleanup {
                    HStack(spacing: 20) {
                        if entry.status == .duplicatesCleanup {
                             DetailStatView(title: "Duplicates Deleted", value: "\(entry.duplicatesDeleted ?? 0)", icon: "trash.fill", color: .red)
                                .animatedAppearance(delay: 0.1)
                             if let recovered = entry.recoveredSpace {
                                 DetailStatView(title: "Space Recovered", value: ByteCountFormatter.string(fromByteCount: recovered, countStyle: .file), icon: "externaldrive.fill", color: .green)
                                    .animatedAppearance(delay: 0.15)
                             }
                        } else {
                            DetailStatView(title: "Files Organized", value: "\(entry.filesOrganized)", icon: "doc.fill", color: .blue)
                                .animatedAppearance(delay: 0.1)
                            DetailStatView(title: "Folders Created", value: "\(entry.foldersCreated)", icon: "folder.fill", color: .purple)
                                .animatedAppearance(delay: 0.15)
                            if let plan = entry.plan {
                                DetailStatView(title: "Plan Version", value: "v\(plan.version)", icon: "number", color: .gray)
                                    .animatedAppearance(delay: 0.2)
                            }
                        }
                    }
                }

                // Actions
                if entry.success || entry.status == .duplicatesCleanup {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Session Management")
                            .font(.headline)

                        HStack(spacing: 12) {
                            if entry.status == .duplicatesCleanup {
                                if let restorables = entry.restorableItems, !restorables.isEmpty {
                                    Button(action: handleRestoreDuplicates) {
                                        Label("Restore Deleted Files", systemImage: "arrow.uturn.backward")
                                            .frame(minWidth: 150)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.large)
                                } else {
                                    Text("No restore data available for this session")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } else if entry.isUndone {
                                Button(action: handleRedo) {
                                    Label("Re-Apply This Organization", systemImage: "arrow.clockwise")
                                        .frame(minWidth: 150)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .accessibilityIdentifier("RedoSessionButton")
                            } else {
                                Button(action: handleUndo) {
                                    Label("Undo These Changes", systemImage: "arrow.uturn.backward")
                                        .frame(minWidth: 150)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                                .accessibilityIdentifier("UndoSessionButton")

                                Button(action: handleRestore) {
                                    Label("Restore Folder to this State", systemImage: "clock.arrow.circlepath")
                                        .frame(minWidth: 150)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                        }
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: appeared)
                }

                // Timeline Section
                if entry.success {
                    CompactTimelineView(
                        entries: organizer.history.entries,
                        directoryPath: entry.directoryPath
                    )
                    .animatedAppearance(delay: 0.25)
                }

                if !entry.success, let error = entry.errorMessage {
                    SectionView(title: "Error Log", icon: "exclamationmark.triangle.fill", color: .red) {
                        Text(error)
                            .font(.callout)
                            .foregroundColor(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.05))
                            .cornerRadius(8)
                    }
                    .animatedAppearance(delay: 0.15)
                }

                // Expanded Plan List with reasoning and files
                if let plan = entry.plan {
                    SectionView(title: "Organization Details", icon: "list.bullet.indent", color: .blue) {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(Array(plan.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                FolderHistoryDetailRow(suggestion: suggestion)
                                    .animatedAppearance(delay: 0.3 + Double(index) * 0.05)
                            }

                            if !plan.unorganizedFiles.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Unorganized Files")
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)

                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(plan.unorganizedFiles) { fileItem in
                                            HStack {
                                                Image(systemName: "doc")
                                                Text(fileItem.displayName)
                                                Spacer()
                                            }
                                            .font(.caption)
                                            .padding(.leading, 12)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.orange.opacity(0.05))
                                .cornerRadius(8)
                                .animatedAppearance(delay: 0.4)
                            }
                        }
                    }
                } else if let restorables = entry.restorableItems, !restorables.isEmpty {
                    SectionView(title: "Deleted Files", icon: "trash", color: .red) {
                         VStack(alignment: .leading, spacing: 8) {
                             ForEach(restorables) { item in
                                 HStack {
                                     Image(systemName: "doc")
                                         .foregroundColor(.secondary)
                                     Text(URL(fileURLWithPath: item.deletedPath).lastPathComponent)
                                     Spacer()
                                     Text("Original: " + URL(fileURLWithPath: item.originalPath).lastPathComponent)
                                         .foregroundStyle(.tertiary)
                                         .font(.caption2)
                                 }
                                 .font(.caption)
                                 .padding(8)
                                 .background(Color.secondary.opacity(0.05))
                                 .cornerRadius(6)
                             }
                         }
                    }
                }

                // Raw AI Data
                if let raw = entry.rawAIResponse {
                    DisclosureGroup("View Raw AI Response Data", isExpanded: $showRawAIResponse) {
                        Text(raw)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(8)
                    }
                    .padding(.top, 8)
                    .onChange(of: showRawAIResponse) { oldValue, newValue in
                        HapticFeedbackManager.shared.tap()
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showRawAIResponse)
                }
            }
            .padding(40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private func handleUndo() {
        HapticFeedbackManager.shared.tap()
        processAction {
            try await organizer.undoHistoryEntry(entry)
            HapticFeedbackManager.shared.success()
            onAction("Operations reversed successfully.")
        }
    }

    private func handleRestore() {
        HapticFeedbackManager.shared.tap()
        processAction {
            try await organizer.restoreToState(targetEntry: entry)
            HapticFeedbackManager.shared.success()
            onAction("Folder state restored.")
        }
    }

    private func handleRedo() {
        HapticFeedbackManager.shared.tap()
        processAction {
            try await organizer.redoOrganization(from: entry)
            HapticFeedbackManager.shared.success()
            onAction("Organization re-applied.")
        }
    }
    
    private func handleRestoreDuplicates() {
        HapticFeedbackManager.shared.tap()
        processAction {
            guard let restorables = entry.restorableItems else { return }
            var restoredCount = 0
            
            for item in restorables {
                try DuplicateRestorationManager.shared.restore(item: item)
                restoredCount += 1
            }
            
            HapticFeedbackManager.shared.success()
            onAction("Restored \(restoredCount) files.")
        }
    }

    private func processAction(_ action: @escaping () async throws -> Void) {
        isProcessing = true
        Task {
            do {
                try await action()
                isProcessing = false
            } catch {
                HapticFeedbackManager.shared.error()
                onAction("Error: \(error.localizedDescription)")
                isProcessing = false
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
    }
}

// MARK: - History Stat Card

struct HistoryStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
            }
            .scaleEffect(isHovered ? 1.1 : 1.0)
            .animation(.subtleBounce, value: isHovered)

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .contentTransition(.numericText())
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.subtleBounce, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
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
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))

                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                        .animation(.subtleBounce, value: isHovered)

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
                    }

                    // Files
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(suggestion.files.enumerated()), id: \.element.id) { index, fileItem in
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundColor(.secondary)
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
                        }
                    }

                    // Subfolders
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
        .frame(width: 900, height: 600)
}

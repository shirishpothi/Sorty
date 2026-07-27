import Foundation
import SwiftUI

struct HistoryDetailHeaderSection: View {
    let entry: OrganizationHistoryEntry

    private var directoryName: String {
        URL(fileURLWithPath: entry.directoryPath).lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(directoryName)
                        .font(.title.bold())
                    Text(entry.timestamp.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(status: entry.status)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(directoryName), \(entry.status.displayName), \(entry.timestamp.formatted())")

            Label {
                PrivacySensitivePathText(path: entry.directoryPath)
            } icon: {
                Image(systemName: "folder")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
            .accessibilityLabel("Full path: \(PrivacyPathMasker.redactedPath(entry.directoryPath))")
        }
    }
}

struct HistorySessionStatisticsSection: View {
    let entry: OrganizationHistoryEntry
    let showsDetailedStats: Bool

    @ViewBuilder
    var body: some View {
        if entry.success || entry.status == .duplicatesCleanup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Session Statistics")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                HistoryPrimaryStats(entry: entry)

                if showsDetailedStats, let stats = entry.plan?.generationStats {
                    HistoryNerdStatsGrid(stats: stats)
                }
            }
        }
    }
}

private struct HistoryPrimaryStats: View {
    let entry: OrganizationHistoryEntry

    var body: some View {
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
                    color: .accentColor
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

private struct HistoryNerdStatsGrid: View {
    let stats: GenerationStats

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats for Nerds")
                .font(.headline)
                .padding(.top, 4)

            LazyVGrid(columns: columns, spacing: 8) {
                NerdStatCard(
                    icon: "clock.fill",
                    iconColor: .blue,
                    title: "AI Time",
                    value: GenerationStats.formatDuration(stats.duration),
                    unit: nil,
                    description: "Model response time"
                )
                NerdStatCard(
                    icon: "bolt.fill",
                    iconColor: .orange,
                    title: "Throughput",
                    value: String(format: "%.1f", stats.tps),
                    unit: "tok/s",
                    description: "Response throughput"
                )
                NerdStatCard(
                    icon: "timer",
                    iconColor: .green,
                    title: "TTFT",
                    value: GenerationStats.formatDuration(stats.ttft),
                    unit: nil,
                    description: "Time to first token"
                )
                NerdStatCard(
                    icon: "text.bubble",
                    iconColor: .accentColor,
                    title: "Response",
                    value: GenerationStats.formatCount(stats.responseTokens),
                    unit: "tok",
                    description: "Estimated output tokens"
                )
                HistoryOptionalNerdStats(stats: stats)
            }
        }
    }
}

private struct HistoryOptionalNerdStats: View {
    let stats: GenerationStats

    var body: some View {
        Group {
            if let promptTokens = stats.promptTokens {
                NerdStatCard(
                    icon: "text.alignleft",
                    iconColor: .indigo,
                    title: "Prompt",
                    value: GenerationStats.formatCount(promptTokens),
                    unit: "tok",
                    description: "Estimated input tokens"
                )
            }
            if let totalContextTokens = stats.totalContextTokens {
                NerdStatCard(
                    icon: "sum",
                    iconColor: .mint,
                    title: "Context",
                    value: GenerationStats.formatCount(totalContextTokens),
                    unit: "tok",
                    description: "Prompt plus response"
                )
            }
            if let scanned = stats.filesScanned {
                NerdStatCard(
                    icon: "doc.text.magnifyingglass",
                    iconColor: .green,
                    title: "Files",
                    value: GenerationStats.formatCount(scanned),
                    unit: "files",
                    description: "Items reviewed by Sorty"
                )
            }
            if let size = stats.formattedTotalFileSize {
                NerdStatCard(
                    icon: "internaldrive",
                    iconColor: .cyan,
                    title: "Volume",
                    value: size,
                    unit: nil,
                    description: "Data footprint"
                )
            }
            if stats.hasBillableCost {
                NerdStatCard(
                    icon: "dollarsign.circle",
                    iconColor: .yellow,
                    title: "Cost",
                    value: GenerationStats.formatCost(stats.computedCost),
                    unit: nil,
                    description: "Estimated API spend"
                )
            }
            if let duplicates = stats.duplicatesFound, duplicates > 0 {
                NerdStatCard(
                    icon: "doc.on.doc",
                    iconColor: .red,
                    title: "Duplicates",
                    value: GenerationStats.formatCount(duplicates),
                    unit: nil,
                    description: "Content matches"
                )
            }
        }
    }
}

struct HistoryDetailErrorSection: View {
    let entry: OrganizationHistoryEntry

    @ViewBuilder
    var body: some View {
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
    }
}

struct HistoryDetailActionsSection: View {
    let entry: OrganizationHistoryEntry
    let onRestoreDuplicates: () -> Void
    let onApplyOrRedo: () -> Void
    let onRestore: () -> Void
    let onUndo: () -> Void
    let onTryDifferentModel: () -> Void

    @ViewBuilder
    var body: some View {
        if entry.success || entry.status == .duplicatesCleanup || entry.hasApplicablePlan {
            VStack(alignment: .leading, spacing: 12) {
                Text("Actions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                actionControls
            }
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.status == .duplicatesCleanup {
                if let restorables = entry.restorableItems,
                   restorables.contains(where: DuplicateRestorationManager.shared.canRestore) {
                    Button(action: onRestoreDuplicates) {
                        Label("Restore Deleted Files", systemImage: "arrow.uturn.backward")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.onboardingPill)
                    .controlSize(.large)
                    .accessibilityLabel("Restore deleted files")
                    .accessibilityIdentifier("RestoreDuplicatesButton")
                }
            } else if entry.hasApplicablePlan {
                Button(action: onApplyOrRedo) {
                    Label("Apply Generated Plan", systemImage: "checkmark.circle")
                        .frame(minWidth: 170)
                }
                .buttonStyle(.onboardingPill)
                .controlSize(.large)
                .accessibilityLabel("Apply this generated organization plan")
                .accessibilityIdentifier("ApplyGeneratedPlanButton")
            } else if entry.isUndone {
                Button(action: onApplyOrRedo) {
                    Label("Re-Apply Organization", systemImage: "arrow.clockwise")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.onboardingPill)
                .controlSize(.large)
                .accessibilityLabel("Re-apply this organization")
                .accessibilityIdentifier("RedoSessionButton")
            } else {
                Button(action: onRestore) {
                    Label("Restore to State", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.onboardingPill)
                .controlSize(.large)
                .accessibilityLabel("Restore folder to this state")
                .accessibilityIdentifier("RestoreStateButton")

                HStack(spacing: 12) {
                    Button(action: onUndo) {
                        Label("Undo Changes", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sortyBordered)
                    .controlSize(.large)
                    .accessibilityLabel("Undo these changes")
                    .accessibilityIdentifier("UndoSessionButton")

                    Button(action: onTryDifferentModel) {
                        Label("Try Different Model", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sortyBordered)
                    .controlSize(.large)
                    .accessibilityLabel("Try organization with a different AI model")
                    .accessibilityIdentifier("TryModelSessionButton")
                    .modelSelectorTriggerBounds()
                }
            }
        }
    }
}

struct HistoryPlanDetailsSection: View {
    let entry: OrganizationHistoryEntry
    @Binding var highlightedFileID: UUID?

    @ViewBuilder
    var body: some View {
        if let plan = entry.plan {
            VStack(alignment: .leading, spacing: 12) {
                Text("Organization Details")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ForEach(plan.suggestions) { suggestion in
                    FolderHistoryDetailRow(
                        suggestion: suggestion,
                        rootDirectory: URL(fileURLWithPath: entry.directoryPath),
                        highlightedFileID: $highlightedFileID
                    )
                }

                if !plan.unorganizedFiles.isEmpty {
                    HistoryUnorganizedFilesSection(
                        files: plan.unorganizedFiles,
                        handoffDirectory: URL(fileURLWithPath: entry.directoryPath),
                        highlightedFileID: $highlightedFileID
                    )
                }
            }
        }
    }
}

private struct HistoryUnorganizedFilesSection: View {
    let files: [FileItem]
    let handoffDirectory: URL
    @Binding var highlightedFileID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unorganized Files")
                .font(.subheadline.bold())
                .foregroundColor(.orange)

            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(files) { file in
                    HistoryUnorganizedFileRow(
                        file: file,
                        siblings: files,
                        handoffDirectory: handoffDirectory,
                        highlightedFileID: $highlightedFileID
                    )
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
    }
}

private struct HistoryUnorganizedFileRow: View {
    let file: FileItem
    let siblings: [FileItem]
    let handoffDirectory: URL
    @Binding var highlightedFileID: UUID?

    private var duplicateInfo: DuplicateInfo? {
        guard let hash = file.sha256Hash, !hash.isEmpty else { return nil }
        let duplicates = siblings.filter { $0.id != file.id && $0.sha256Hash == hash }
        return duplicates.isEmpty ? nil : DuplicateInfo(file: file, duplicates: duplicates)
    }

    var body: some View {
        HStack {
            FileThumbnailView(
                url: URL(fileURLWithPath: file.path),
                size: CGSize(width: 20, height: 20)
            )
            Text(file.displayName)
            Spacer()

            if let duplicateInfo {
                LiquidGlassDuplicateButton(
                    duplicateInfo: duplicateInfo,
                    handoffDirectory: handoffDirectory,
                    highlightedFileID: $highlightedFileID
                )
            }
        }
        .font(.caption)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    highlightedFileID == file.id
                        ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.12)
                        : Color.clear
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unorganized file: \(file.displayName)")
    }
}

struct HistoryFileOperationsSection: View {
    let entry: OrganizationHistoryEntry
    let undoneOperationIDs: Set<UUID>
    let failedOperationIDs: Set<UUID>
    let undoingOperationID: UUID?
    let onUndo: (FileSystemManager.FileOperation) -> Void

    private var operations: [FileSystemManager.FileOperation] {
        (entry.operations ?? []).filter { operation in
            operation.type == .moveFile || operation.type == .renameFile
        }
    }

    @ViewBuilder
    var body: some View {
        if !operations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("File Operations")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(operations.count) operation\(operations.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .numericTextTransition(animationValue: operations.count)
                }

                LazyVStack(spacing: 6) {
                    ForEach(operations, id: \.id) { operation in
                        OperationRowView(
                            operation: operation,
                            isUndone: undoneOperationIDs.contains(operation.id),
                            isFailed: failedOperationIDs.contains(operation.id),
                            isUndoing: undoingOperationID == operation.id,
                            isEntryUndone: entry.isUndone,
                            onUndo: { onUndo(operation) }
                        )
                    }
                }
            }
        }
    }
}

struct HistoryRestorableItemsSection: View {
    let entry: OrganizationHistoryEntry

    @ViewBuilder
    var body: some View {
        if let items = entry.restorableItems, !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Deleted Files")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                ForEach(items) { item in
                    HistoryRestorableItemRow(item: item)
                }
            }
        }
    }
}

private struct HistoryRestorableItemRow: View {
    let item: RestorableDuplicate

    private var deletedName: String {
        URL(fileURLWithPath: item.deletedPath).lastPathComponent
    }

    private var originalName: String {
        URL(fileURLWithPath: item.originalPath).lastPathComponent
    }

    var body: some View {
        HStack {
            FileThumbnailView(
                url: URL(fileURLWithPath: item.deletedPath),
                size: CGSize(width: 20, height: 20)
            )
            Text(deletedName)
            Spacer()
            Text("Original: \(originalName)")
                .foregroundStyle(.tertiary)
                .font(.caption2)
        }
        .font(.caption)
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deleted: \(deletedName), original: \(originalName)")
    }
}

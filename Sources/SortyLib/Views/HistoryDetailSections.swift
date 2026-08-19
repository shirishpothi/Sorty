import Foundation
import AppKit
import SwiftUI

struct HistoryDetailHeaderSection: View {
    let entry: OrganizationHistoryEntry
    let reasoningNotes: String?

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

            HStack(alignment: .center, spacing: 12) {
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
                .layoutPriority(1)

                Spacer(minLength: 12)

                if let reasoningNotes, !reasoningNotes.isEmpty {
                    HistoryLiquidGlassReasoningCard(notes: reasoningNotes)
                        .fixedSize()
                }
            }
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
                HistoryPrimaryStats(entry: entry)

                if showsDetailedStats, let stats = entry.plan?.generationStats {
                    HistoryNerdStatsGrid(stats: stats)
                }
            }
        }
    }
}

struct HistoryPartialUndoSection: View {
    let entry: OrganizationHistoryEntry

    private var affectedItems: [PartialUndoItem] {
        let failedFiles = entry.undoFailedFiles ?? []
        var items = (entry.operations ?? []).map { operation in
            PartialUndoItem(
                name: URL(
                    fileURLWithPath: operation.destinationPath ?? operation.sourcePath
                ).lastPathComponent,
                operation: operation
            )
        }

        let operationNames = Set(items.map(\.name))
        items.append(contentsOf: failedFiles.compactMap { fileName in
            guard !operationNames.contains(fileName) else { return nil }
            return PartialUndoItem(name: fileName, operation: nil)
        })
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @ViewBuilder
    var body: some View {
        if entry.status == .partiallyUndone {
            VStack(alignment: .leading, spacing: 10) {
                Label("Not Undone", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.yellow)
                    .accessibilityAddTraits(.isHeader)

                if let restoredCount = entry.undoRestoredCount, restoredCount > 0 {
                    Text("Sorty restored \(restoredCount) operation\(restoredCount == 1 ? "" : "s"). The items below were not restored to their original locations.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("The items below were not restored to their original locations.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if affectedItems.isEmpty {
                    Text("Some changes could not be undone.")
                        .font(.callout.weight(.medium))
                } else {
                    VStack(spacing: 4) {
                        ForEach(affectedItems) { item in
                            PartialUndoItemRow(item: item)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                affectedItems.isEmpty
                    ? "Partially undone. Some changes were not restored."
                    : "Partially undone. Not restored: \(affectedItems.map(\.name).joined(separator: ", "))."
            )
        }
    }
}

private struct PartialUndoItem: Identifiable {
    let name: String
    let operation: FileSystemManager.FileOperation?

    var id: String {
        operation?.id.uuidString ?? name
    }

    var iconURL: URL {
        guard let operation else {
            return URL(fileURLWithPath: name)
        }
        return URL(fileURLWithPath: operation.destinationPath ?? operation.sourcePath)
    }

    var isFolder: Bool {
        operation?.type == .createFolder
    }
}

private struct PartialUndoItemRow: View {
    let item: PartialUndoItem

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            openItem()
        } label: {
            HStack(spacing: 8) {
                itemIcon

                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                    .opacity(isHovered ? 1 : 0)
                    .offset(
                        x: reduceMotion || isHovered ? 0 : -3,
                        y: reduceMotion || isHovered ? 0 : 3
                    )
                    .scaleEffect(reduceMotion || isHovered ? 1 : 0.75)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(isHovered ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
            value: isHovered
        )
        .onHover { isHovered = $0 }
        .help("Show in Finder")
        .accessibilityLabel("Show \(item.name) in Finder")
    }

    @ViewBuilder
    private var itemIcon: some View {
        if item.isFolder {
            FolderThumbnailView(url: item.iconURL, size: CGSize(width: 20, height: 20))
                .frame(width: 20, height: 20)
        } else {
            FileThumbnailView(url: item.iconURL, size: CGSize(width: 20, height: 20))
                .frame(width: 20, height: 20)
        }
    }

    private func openItem() {
        let fileManager = FileManager.default
        let candidates = [
            item.operation?.destinationPath,
            item.operation?.sourcePath,
            item.iconURL.path
        ].compactMap { $0 }

        if let existingPath = candidates.first(where: { fileManager.fileExists(atPath: $0) }) {
            NSWorkspace.shared.activateFileViewerSelecting([
                URL(fileURLWithPath: existingPath)
            ])
            return
        }

        for path in candidates {
            var parentURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            while parentURL.path != "/" {
                if fileManager.fileExists(atPath: parentURL.path) {
                    NSWorkspace.shared.open(parentURL)
                    return
                }
                parentURL.deleteLastPathComponent()
            }
        }
    }
}

private struct HistoryPrimaryStats: View {
    let entry: OrganizationHistoryEntry

    var body: some View {
        HStack(spacing: 0) {
            if entry.status == .duplicatesCleanup {
                HistorySummaryStatItem(
                    value: "\(entry.duplicatesDeleted ?? 0)",
                    label: "Duplicates Deleted",
                    icon: "trash.fill",
                    color: .red
                )

                if let recovered = entry.recoveredSpace {
                    HistorySummaryStatDivider()
                    HistorySummaryStatItem(
                        value: ByteCountFormatter.string(fromByteCount: recovered, countStyle: .file),
                        label: "Space Recovered",
                        icon: "externaldrive.fill",
                        color: .green
                    )
                }
            } else {
                HistorySummaryStatItem(
                    value: "\(entry.filesOrganized)",
                    label: "Files Organized",
                    icon: "doc.on.doc.fill",
                    color: .blue
                )

                HistorySummaryStatDivider()

                HistorySummaryStatItem(
                    value: "\(entry.foldersCreated)",
                    label: "Folders Created",
                    icon: "folder.fill.badge.plus",
                    color: .purple
                )

                if let plan = entry.plan, plan.version > 1 {
                    HistorySummaryStatDivider()
                    HistorySummaryStatItem(
                        value: "v\(plan.version)",
                        label: "Plan Version",
                        icon: "number",
                        color: .gray
                    )
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct HistorySummaryStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .numericTextTransition(animationValue: value)

                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

private struct HistorySummaryStatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(width: 1, height: 44)
            .accessibilityHidden(true)
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
        .accessibilityElement(children: .contain)
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

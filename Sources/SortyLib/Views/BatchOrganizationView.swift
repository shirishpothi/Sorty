//
//  BatchOrganizationView.swift
//  Sorty
//
//  Multi-folder batch organization view
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BatchOrganizationView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var batchManager: BatchOrganizationManager
    @State private var includeSubfolders: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var selectedPlanFolder: URL?
    @State private var showApplyConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            contentSection
        }
        .navigationTitle("Batch Organize")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("BatchOrganizationView")
        .accessibilityLabel("Batch organization workflow")
        .sheet(item: Binding(
            get: { selectedPlanFolder.map { PlanSheetItem(url: $0) } },
            set: { selectedPlanFolder = $0?.url }
        )) { item in
            BatchPlanDetailView(
                folderURL: item.url,
                plan: batchManager.results.first(where: { $0.folderURL == item.url })?.plan
            )
        }
        .confirmationDialog(
            "Apply Organization",
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply All Changes") {
                applyBatch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let totalFiles = batchManager.results.filter { $0.status == .previewed }.reduce(0) { $0 + $1.filesOrganized }
            let folderCount = batchManager.results.filter { $0.status == .previewed }.count
            Text("This will organize \(totalFiles) files across \(folderCount) folders. This can be undone.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title2)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Batch Organize")
                    .font(.headline)
                Text("\(batchManager.totalFolders) folder\(batchManager.totalFolders == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !batchManager.isProcessing {
                Button {
                    HapticFeedbackManager.shared.tap()
                    addFolders()
                } label: {
                    Label("Add Folders", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("BatchAddFoldersButton")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            if batchManager.selectedFolders.isEmpty && batchManager.results.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if batchManager.isProcessing {
                            overallProgressSection
                        }

                        optionsSection

                        configSummarySection

                        folderListSection

                        if batchManager.hasAnyOutcome && !batchManager.isProcessing {
                            resultsSection
                        }

                        actionButtons
                    }
                    .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Folders Selected")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Add multiple folders to organize them all at once.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Button {
                HapticFeedbackManager.shared.tap()
                addFolders()
            } label: {
                Label("Add Folders", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("BatchAddFoldersEmptyButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(TransitionStyles.scaleAndFade)
    }

    // MARK: - Overall Progress

    private var overallProgressSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Overall Progress")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    Text("\(batchManager.processedFolders) of \(batchManager.totalFolders)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: batchManager.overallProgress)
                    .progressViewStyle(.linear)
                    .accessibilityIdentifier("BatchOverallProgress")

                if let current = batchManager.activeFolders.first {
                    let remainder = max(0, batchManager.activeFolders.count - 1)
                    let moreText = remainder > 0 ? " (+\(remainder) more)" : ""
                    Text("Processing: \(current.lastPathComponent)\(moreText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(4)
        }
        .transition(TransitionStyles.slideFromBottom)
    }

    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Options")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    Toggle("Include Immediate Subfolders", isOn: $includeSubfolders)
                        .toggleStyle(.switch)

                    Spacer()

                    Stepper("Concurrent: \(batchManager.maxConcurrentFolders)", value: $batchManager.maxConcurrentFolders, in: 1...5)
                        .frame(maxWidth: 220)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(batchManager.isProcessing)
            }
            .padding(4)
        }
        .transition(TransitionStyles.slideFromBottom)
    }

    private var configSummarySection: some View {
        GroupBox {
            HStack(spacing: 16) {
                Label(settingsViewModel.config.provider.displayName, systemImage: "cpu")
                if !settingsViewModel.config.model.isEmpty {
                    Label(settingsViewModel.config.model, systemImage: "brain")
                }
                Spacer()
                Text("Using global AI settings")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(4)
        }
    }

    // MARK: - Folder List

    private var folderListSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Folders")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.bottom, 4)

                ForEach(batchManager.selectedFolders, id: \.self) { folder in
                    folderRow(for: folder)
                }
            }
            .padding(4)
        }
        .animation(.pageTransition, value: batchManager.selectedFolders.count)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func folderRow(for folder: URL) -> some View {
        HStack(spacing: 10) {
            FolderThumbnailView(url: folder, size: CGSize(width: 28, height: 28))

            VStack(alignment: .leading, spacing: 2) {
                Text(folder.lastPathComponent)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(folder.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let result = batchManager.results.first(where: { $0.folderURL == folder }),
               result.status == .previewed,
               let _ = result.plan {
                Button {
                    selectedPlanFolder = folder
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .help("View organization plan")
                .accessibilityIdentifier("BatchViewPlan-\(folder.lastPathComponent)")
            }

            statusBadge(for: folder)

            if let result = batchManager.results.first(where: { $0.folderURL == folder }),
               result.status == .failed,
               let errorMessage = result.error {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .trailing)
            }

                if let result = batchManager.results.first(where: { $0.folderURL == folder }),
               result.status == .failed,
               !batchManager.isProcessing {
                Button {
                    HapticFeedbackManager.shared.tap()
                    Task { await batchManager.retryFolder(folder) }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("BatchRetryFolder-\(folder.lastPathComponent)")
            }

            if !batchManager.isProcessing {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .accessibilityIdentifier("BatchRevealFolder-\(folder.lastPathComponent)")

                Button {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.pageTransition) {
                        batchManager.removeFolder(folder)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("BatchRemoveFolder-\(folder.lastPathComponent)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    @ViewBuilder
    private func statusBadge(for folder: URL) -> some View {
        if let result = batchManager.results.first(where: { $0.folderURL == folder }) {
            HStack(spacing: 4) {
                if result.status == .processing {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: statusIcon(for: result.status))
                        .font(.caption)
                }
                Text(statusLabel(for: result.status))
                    .font(.caption2)
            }
            .foregroundStyle(statusColor(for: result.status))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(statusColor(for: result.status).opacity(0.12))
            )
        }
    }

    // MARK: - Results

    private var resultsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Results")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.bottom, 4)

                HStack(spacing: 16) {
                    resultStat(
                        title: "Previewed",
                        value: batchManager.previewedFolders,
                        color: .blue,
                        icon: "eye.circle.fill"
                    )

                    resultStat(
                        title: "Completed",
                        value: batchManager.completedFolders,
                        color: .green,
                        icon: "checkmark.circle.fill"
                    )

                    resultStat(
                        title: "Failed",
                        value: batchManager.failedFolders,
                        color: .red,
                        icon: "xmark.circle.fill"
                    )

                    let skipped = batchManager.results.filter { $0.status == .skipped }.count
                    resultStat(
                        title: "Skipped",
                        value: skipped,
                        color: .orange,
                        icon: "arrow.right.circle.fill"
                    )
                }

                let totalFiles = batchManager.results.reduce(0) { $0 + $1.filesOrganized }
                if totalFiles > 0 {
                    let label = batchManager.completedFolders > 0 ? "organized" : "proposed"
                    Text("\(totalFiles) total files \(label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
        .transition(TransitionStyles.slideFromBottom)
    }

    private func resultStat(title: String, value: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if batchManager.isProcessing {
                Button {
                    HapticFeedbackManager.shared.error()
                    batchManager.cancelBatch()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("BatchCancelButton")
            } else {
                if !batchManager.results.isEmpty {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        withAnimation(.pageTransition) {
                            batchManager.reset()
                        }
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("BatchClearButton")
                }

                if !batchManager.selectedFolders.isEmpty {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        startPreview()
                    } label: {
                        Label("Preview Batch", systemImage: "eye.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("BatchPreviewButton")
                }

                if batchManager.canApplyPreview {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        showApplyConfirmation = true
                    } label: {
                        Label("Apply All", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("BatchApplyButton")
                }

                if batchManager.canUndoBatch {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        undoBatch()
                    } label: {
                        Label("Undo Batch", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("BatchUndoButton")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to organize"
        panel.prompt = "Add"

        if panel.runModal() == .OK {
            for url in panel.urls {
                withAnimation(.pageTransition) {
                    batchManager.addFolder(url, expandSubfolders: includeSubfolders)
                }
            }
            HapticFeedbackManager.shared.success()
        }
    }

    private func startPreview() {
        Task {
            await batchManager.startPreviewBatch(config: settingsViewModel.config, sharedOrganizer: organizer)
            if batchManager.failedFolders == 0 {
                HapticFeedbackManager.shared.success()
            } else {
                HapticFeedbackManager.shared.error()
            }
        }
    }

    private func applyBatch() {
        Task {
            await batchManager.applyPreviewedBatch(config: settingsViewModel.config, sharedOrganizer: organizer)
            if batchManager.failedFolders == 0 {
                HapticFeedbackManager.shared.success()
            } else {
                HapticFeedbackManager.shared.error()
            }
        }
    }

    private func undoBatch() {
        Task {
            await batchManager.undoLastBatch(using: organizer)
            HapticFeedbackManager.shared.success()
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileURLType = UTType.fileURL.identifier
        var handled = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(fileURLType) {
            provider.loadItem(forTypeIdentifier: fileURLType, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                Task { @MainActor in
                    withAnimation(.pageTransition) {
                        batchManager.addFolder(url, expandSubfolders: includeSubfolders)
                    }
                    HapticFeedbackManager.shared.success()
                }
            }
            handled = true
        }

        return handled
    }

    private func statusIcon(for status: BatchStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .previewed: return "eye.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "arrow.right.circle.fill"
        }
    }

    private func statusLabel(for status: BatchStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .previewed: return "Previewed"
        case .completed: return "Done"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        }
    }

    private func statusColor(for status: BatchStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .processing: return .accentColor
        case .previewed: return .blue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }
}

// MARK: - Plan Sheet Item

private struct PlanSheetItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Batch Plan Detail View

struct BatchPlanDetailView: View {
    let folderURL: URL
    let plan: OrganizationPlan?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organization Plan")
                        .font(.headline)
                    Text(folderURL.lastPathComponent)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
            .padding()

            Divider()

            if let plan = plan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        let totalFiles = plan.suggestions.reduce(0) { $0 + $1.totalFileCount }
                        let totalFolders = plan.suggestions.count
                        HStack(spacing: 24) {
                            Label("\(totalFiles) files", systemImage: "doc.fill")
                            Label("\(totalFolders) folders", systemImage: "folder.fill")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)

                        ForEach(plan.suggestions) { suggestion in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(.blue)
                                        Text(suggestion.folderName)
                                            .font(.callout)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Text("\(suggestion.totalFileCount) files")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if !suggestion.reasoning.isEmpty {
                                        FormattedReasoningText(
                                            text: suggestion.reasoning,
                                            font: .caption,
                                            secondaryFont: .caption2,
                                            foregroundStyle: .secondary,
                                            showSectionIcons: false
                                        )
                                    }

                                    ForEach(suggestion.files) { file in
                                        HStack(spacing: 8) {
                                            Image(systemName: "doc")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text(file.displayName)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                        }
                                        .padding(.leading, 20)
                                    }
                                }
                                .padding(4)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No plan available")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .frame(idealWidth: 600, idealHeight: 500)
    }
}

// MARK: - Previews

#Preview("Batch Organization - Empty") {
    BatchOrganizationView()
        .environmentObject(FolderOrganizer.preview)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(BatchOrganizationManager())
        .frame(width: 900, height: 600)
}

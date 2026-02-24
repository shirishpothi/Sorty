//
//  PreviewView.swift
//  Sorty
//
//  Lightweight container view for preview interface
//  Components split into Preview/ directory
//

import SwiftUI

struct PreviewView: View {
    let plan: OrganizationPlan
    let baseURL: URL
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var learningsManager: LearningsManager
    @StateObject private var dragDropManager = DragDropManager()
    @StateObject private var previewStore: PreviewStore
    @State private var showApplyConfirmation = false
    @State private var isApplying = false
    @State private var editablePlan: OrganizationPlan
    @State private var hasEdits = false
    @State private var showPostOrganizationHoning = false
    @State private var showRedoModelPicker = false
    @State private var isRedoingWithModel = false
    @State private var viewingHistoryIndex: Int? = nil
    @State private var showRenameSummary = false
    @State private var renameSummarySort: RenameSummarySort = .original
    @State private var showManualRenameTools = false
    @FocusState private var instructionsFocused: Bool

    private var displayedPlan: OrganizationPlan {
        if let idx = viewingHistoryIndex, idx < organizer.planHistory.count {
            return organizer.planHistory[idx]
        }
        return editablePlan
    }

    private var isViewingHistory: Bool {
        viewingHistoryIndex != nil
    }

    private var totalVersions: Int {
        organizer.planHistory.count + 1
    }
    
    private var renameCount: Int {
        editablePlan.suggestions.reduce(0) { $0 + $1.allFileRenameMappings.filter { $0.hasRename }.count }
    }

    private var renameSummaryEntries: [RenameSummaryEntry] {
        let entries = previewStore.renameSummaryEntries()
        switch renameSummarySort {
        case .original:
            return entries.sorted { $0.originalName.localizedCaseInsensitiveCompare($1.originalName) == .orderedAscending }
        case .confidence:
            return entries.sorted { ($0.confidence ?? -1) > ($1.confidence ?? -1) }
        case .folder:
            return entries.sorted { $0.folderName.localizedCaseInsensitiveCompare($1.folderName) == .orderedAscending }
        }
    }
    private var shouldDisableButtons: Bool { isApplying || organizer.state == .scanning || organizer.state == .organizing }
    private var isOrganizing: Bool { isApplying || organizer.state == .applying }
    private var scannedImageCount: Int {
        organizer.scannedFiles.filter { ["jpg", "jpeg", "png", "heic", "webp"].contains($0.extension.lowercased()) }.count
    }
    private var emptyStateType: PreviewListView.EmptyStateType {
        if editablePlan.totalFiles == 0 { return .emptyDirectory }
        if editablePlan.suggestions.isEmpty && !editablePlan.unorganizedFiles.isEmpty { return .allUnorganized(editablePlan.unorganizedFiles.count) }
        return .none
    }
    
    init(plan: OrganizationPlan, baseURL: URL) {
        self.plan = plan; self.baseURL = baseURL
        _previewStore = StateObject(wrappedValue: PreviewStore(plan: plan))
        _editablePlan = State(initialValue: plan)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            PreviewHeaderView(
                version: displayedPlan.version,
                hasEdits: isViewingHistory ? false : hasEdits,
                notes: displayedPlan.notes,
                totalFiles: displayedPlan.totalFiles,
                totalFolders: displayedPlan.totalFolders,
                renameCount: isViewingHistory ? 0 : renameCount,
                isDragging: dragDropManager.draggedFile != nil,
                totalVersions: totalVersions,
                isViewingHistory: isViewingHistory,
                onPreviousVersion: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if let idx = viewingHistoryIndex {
                            if idx > 0 {
                                viewingHistoryIndex = idx - 1
                            }
                        } else if !organizer.planHistory.isEmpty {
                            viewingHistoryIndex = organizer.planHistory.count - 1
                        }
                    }
                },
                onNextVersion: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if let idx = viewingHistoryIndex {
                            if idx >= organizer.planHistory.count - 1 {
                                viewingHistoryIndex = nil
                            } else {
                                viewingHistoryIndex = idx + 1
                            }
                        }
                    }
                },
                isRenameSummaryExpanded: showRenameSummary,
                onToggleRenameSummary: {
                    guard !isViewingHistory else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        showRenameSummary.toggle()
                    }
                },
                onAcceptAllRenames: {
                    guard !isViewingHistory else { return }
                    previewStore.acceptAllRenames()
                    editablePlan = previewStore.plan
                    hasEdits = true
                },
                onRejectAllRenames: {
                    guard !isViewingHistory else { return }
                    previewStore.rejectAllRenames()
                    editablePlan = previewStore.plan
                    hasEdits = true
                },
                isManualRenameEnabled: showManualRenameTools,
                onToggleManualRename: {
                    guard !isViewingHistory else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showManualRenameTools.toggle()
                    }
                }
            )
            if showRenameSummary && !isViewingHistory {
                RenameSummaryPanel(entries: renameSummaryEntries, sort: $renameSummarySort)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if scannedImageCount > 0 {
                VisionRecommendationBanner(
                    imageCount: scannedImageCount,
                    currentModel: settingsViewModel.config.model,
                    currentProvider: settingsViewModel.config.provider,
                    isVisionEnabled: settingsViewModel.config.enableVision,
                    onEnableVision: enableVisionAndReconfigure,
                    onSwitchModel: { showRedoModelPicker = true },
                    onDismiss: {}
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            if let summary = organizer.visionAnalysisSummary {
                visionSummaryRow(summary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            if settingsViewModel.config.showStatsForNerds {
                PreviewStatsView(stats: editablePlan.generationStats, showStatsForNerds: true, estimatedTimeRemaining: nil, currentFile: Int(organizer.progress * Double(editablePlan.totalFiles)), totalFiles: editablePlan.totalFiles, stage: organizer.organizationStage)
            }
            Divider()
            PreviewListView(
                store: previewStore,
                dragDropManager: dragDropManager,
                onPlanChanged: { hasEdits = true; editablePlan = previewStore.plan },
                emptyStateType: emptyStateType,
                onFocusInstructions: { instructionsFocused = true },
                onRegenerate: regeneratePreview,
                enableManualRenameTools: showManualRenameTools
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            bottomToolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("Apply Organization?", isPresented: $showApplyConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Apply") { applyOrganization() }
        } message: { Text("\(editablePlan.totalFiles) files will be organized. \(editablePlan.unorganizedFiles.count) files will remain in place.") }
        .onChange(of: organizer.state) { _, newState in
            if case .completed = newState {
                isApplying = false
                if learningsManager.consentManager.canCollectData { Task { @MainActor in try? await Task.sleep(nanoseconds: 500_000_000); showPostOrganizationHoning = true } }
            } else if case .error = newState { isApplying = false }
        }
        .onAppear {
            previewStore.dragDropManager = dragDropManager
        }
        .onChange(of: plan) { _, newPlan in editablePlan = newPlan; previewStore.updatePlan(newPlan); hasEdits = false }
        .onChange(of: viewingHistoryIndex) { _, newIndex in
            if let idx = newIndex, idx < organizer.planHistory.count {
                previewStore.updatePlan(organizer.planHistory[idx])
                showRenameSummary = false
            } else {
                previewStore.updatePlan(editablePlan)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .redoOrganizationWithModel)) { _ in
            guard organizer.state == .ready else { return }
            showRedoModelPicker = true
        }
        .sheet(isPresented: $showPostOrganizationHoning) { PostOrganizationHoningView(fileCount: editablePlan.totalFiles, folderCount: editablePlan.totalFolders, config: settingsViewModel.config, onComplete: { answers in Task { await learningsManager.saveHoningResults(answers); showPostOrganizationHoning = false } }, onSkip: { showPostOrganizationHoning = false }) }
        .sheet(isPresented: $showRedoModelPicker) { ModelSelectionPopover(isPresented: $showRedoModelPicker, currentProvider: settingsViewModel.config.provider, currentModel: settingsViewModel.config.model, onSelect: redoWithProviderAndModel) }
        .environmentObject(dragDropManager)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    @ViewBuilder
    private var bottomToolbar: some View {
        VStack(spacing: 0) {
            if !isOrganizing {
                PreviewInstructionsRow(instructions: $organizer.customInstructions, isFocused: _instructionsFocused, onInstructionsChanged: handleInstructionsChanged)
                Divider()
            }
            if isOrganizing {
                PreviewProgressView(progress: organizer.progress, stage: organizer.organizationStage, estimatedTimeRemaining: calculateTimeRemaining(), onCancel: { organizer.cancel() })
            } else {
                PreviewActionsView(
                    isApplying: isApplying,
                    hasEdits: hasEdits,
                    hasCustomInstructions: !organizer.customInstructions.isEmpty,
                    isRedoingWithModel: isRedoingWithModel,
                    shouldDisableButtons: shouldDisableButtons,
                    onCancel: { recordCancelledOrganization(); organizer.cancel() },
                    onReset: { HapticFeedbackManager.shared.tap(); editablePlan = plan; previewStore.updatePlan(plan); hasEdits = false },
                    onRegenerate: regeneratePreview,
                    onChooseModel: { showRedoModelPicker = true },
                    onApply: { HapticFeedbackManager.shared.tap(); showApplyConfirmation = true }
                )
            }
        }
    }
    
    private func handleInstructionsChanged(_ newValue: String) {
        if !newValue.isEmpty && learningsManager.consentManager.canCollectData { NotificationCenter.default.post(name: .steeringPromptProvided, object: nil, userInfo: ["prompt": newValue, "folderPath": baseURL.path]) }
    }
    
    private func regeneratePreview() {
        if !organizer.customInstructions.isEmpty && learningsManager.consentManager.canCollectData { learningsManager.recordGuidingInstruction(organizer.customInstructions) }
        Task { do { try await organizer.regeneratePreview() } catch { organizer.state = .error(error) } }
    }
    
    private func redoWithProviderAndModel(_ provider: AIProvider, _ model: String) {
        showRedoModelPicker = false; isRedoingWithModel = true; HapticFeedbackManager.shared.tap()
        Task {
            do { try await organizer.regenerateWithModel(provider: provider, model: model); await MainActor.run { HapticFeedbackManager.shared.success(); isRedoingWithModel = false } }
            catch { await MainActor.run { HapticFeedbackManager.shared.error(); isRedoingWithModel = false; organizer.state = .error(error) } }
        }
    }
    
    private func applyOrganization() {
        isApplying = true
        recordRenameLearningOutcomes(original: plan, final: editablePlan)
        if hasEdits { organizer.currentPlan = editablePlan }
        let resolvedURL = appState.resolveSelectedDirectoryWithAccess() ?? baseURL
        Task { @MainActor in do { try await organizer.apply(at: resolvedURL, dryRun: false, enableTagging: settingsViewModel.config.enableFileTagging); if case .completed = organizer.state { isApplying = false } } catch { organizer.state = .error(error); isApplying = false } }
    }
    
    private func calculateTimeRemaining() -> TimeInterval? {
        let remaining = editablePlan.totalFiles - Int(organizer.progress * Double(editablePlan.totalFiles))
        guard remaining > 0, organizer.progress > 0 else { return nil }
        return Double(remaining) * 0.3
    }
    
    private func recordCancelledOrganization() {
        let folderNames = editablePlan.suggestions.map { $0.folderName }
        let allFiles = editablePlan.suggestions.flatMap { $0.files }
        let extensionCounts = Dictionary(grouping: allFiles, by: { (file: FileItem) in
            file.extension.lowercased()
        }).mapValues { (files: [FileItem]) in
            files.count
        }
        learningsManager.recordCancelledOrganization(
            folderPath: baseURL.path,
            fileCount: editablePlan.totalFiles,
            proposedFolderCount: editablePlan.totalFolders,
            instructions: organizer.customInstructions.isEmpty ? nil : organizer.customInstructions,
            stage: "preview",
            proposedFolderNames: folderNames.isEmpty ? nil : folderNames,
            fileExtensionCounts: extensionCounts.isEmpty ? nil : extensionCounts,
            aiModel: settingsViewModel.config.model
        )
    }

    private func enableVisionAndReconfigure() {
        settingsViewModel.config.enableVision = true
        Task {
            try? await organizer.configure(with: settingsViewModel.config)
        }
    }

    private func recordRenameLearningOutcomes(original: OrganizationPlan, final: OrganizationPlan) {
        guard learningsManager.consentManager.canCollectData else { return }

        let originalMap = makeRenameMap(from: original)
        let finalMap = makeRenameMap(from: final)

        for (fileID, initial) in originalMap {
            guard initial.hasRename else { continue }
            let finalMapping = finalMap[fileID]
            let action: ExampleAction
            let finalName: String?

            if finalMapping?.hasRename == true, finalMapping?.suggestedName == initial.suggestedName {
                action = .accept
                finalName = finalMapping?.suggestedName
            } else if finalMapping?.hasRename == true, finalMapping?.suggestedName != initial.suggestedName {
                action = .edit
                finalName = finalMapping?.suggestedName
            } else {
                action = .reject
                finalName = nil
            }

            learningsManager.recordRenameFeedback(
                originalName: initial.originalFile.displayName,
                suggestedName: initial.suggestedName,
                finalName: finalName,
                folderPath: baseURL.path,
                action: action,
                confidence: initial.renameConfidence
            )
        }
    }

    private func makeRenameMap(from plan: OrganizationPlan) -> [UUID: FileRenameMapping] {
        var map: [UUID: FileRenameMapping] = [:]

        func walk(_ folder: FolderSuggestion) {
            for mapping in folder.fileRenameMappings {
                map[mapping.originalFile.id] = mapping
            }
            for sub in folder.subfolders {
                walk(sub)
            }
        }

        for suggestion in plan.suggestions {
            walk(suggestion)
        }
        return map
    }

    @ViewBuilder
    private func visionSummaryRow(_ summary: VisionAnalysisSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let warning = summary.warningMessage {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum RenameSummarySort: String, CaseIterable {
    case original = "Original Name"
    case confidence = "Confidence"
    case folder = "Folder"
}

private struct RenameSummaryPanel: View {
    let entries: [RenameSummaryEntry]
    @Binding var sort: RenameSummarySort

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Rename Summary")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Picker("Sort by", selection: $sort) {
                    ForEach(RenameSummarySort.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if entries.isEmpty {
                Text("No active rename suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Original")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("New Name")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Reason")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Confidence")
                            .frame(width: 86, alignment: .trailing)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(entries) { entry in
                                HStack(spacing: 8) {
                                    ExpandableSummaryCell(
                                        text: entry.originalName,
                                        textStyle: .primary,
                                        accessibilityID: "RenameSummaryOriginalCell-\(entry.id.uuidString)"
                                    )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    ExpandableSummaryCell(
                                        text: entry.newName,
                                        textStyle: entry.isLowConfidenceSkip ? .orange : .primary,
                                        accessibilityID: "RenameSummaryNewNameCell-\(entry.id.uuidString)"
                                    )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    ExpandableSummaryCell(
                                        text: entry.reason,
                                        textStyle: .secondary,
                                        accessibilityID: "RenameSummaryReasonCell-\(entry.id.uuidString)"
                                    )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(confidenceText(entry.confidence))
                                        .foregroundStyle(confidenceColor(entry.confidence))
                                        .frame(width: 86, alignment: .trailing)
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func confidenceText(_ confidence: Double?) -> String {
        guard let confidence else { return "n/a" }
        return "\(Int(confidence * 100))%"
    }

    private func confidenceColor(_ confidence: Double?) -> Color {
        guard let confidence else { return .secondary }
        if confidence < FileRenameMapping.lowConfidenceThreshold {
            return .orange
        }
        return .secondary
    }
}

private struct ExpandableSummaryCell: View {
    let text: String
    let textStyle: Color
    let accessibilityID: String

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            HStack(spacing: 4) {
                Text(text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(textStyle)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
        .help("Click to view full text")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Full Text")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(minWidth: 260, maxWidth: 420, alignment: .leading)
            .background(.ultraThinMaterial)
        }
    }
}

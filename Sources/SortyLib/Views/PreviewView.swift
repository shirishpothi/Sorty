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
    private var shouldDisableButtons: Bool { isApplying || organizer.state == .scanning || organizer.state == .organizing }
    private var isOrganizing: Bool { isApplying || organizer.state == .applying }
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
                }
            )
            if settingsViewModel.config.showStatsForNerds {
                PreviewStatsView(stats: editablePlan.generationStats, showStatsForNerds: true, estimatedTimeRemaining: nil, currentFile: Int(organizer.progress * Double(editablePlan.totalFiles)), totalFiles: editablePlan.totalFiles, stage: organizer.organizationStage)
            }
            Divider()
            PreviewListView(store: previewStore, dragDropManager: dragDropManager, onPlanChanged: { hasEdits = true; editablePlan = previewStore.plan }, emptyStateType: emptyStateType)
            Divider()
            bottomToolbar
        }
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
            } else {
                previewStore.updatePlan(editablePlan)
            }
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
                PreviewActionsView(isApplying: isApplying, hasEdits: hasEdits, hasCustomInstructions: !organizer.customInstructions.isEmpty, isRedoingWithModel: isRedoingWithModel, shouldDisableButtons: shouldDisableButtons, onCancel: { recordCancelledOrganization(); organizer.cancel() }, onReset: { HapticFeedbackManager.shared.tap(); editablePlan = plan; previewStore.updatePlan(plan); hasEdits = false }, onRegenerate: regeneratePreview, onChooseModel: { showRedoModelPicker = true }, onApply: { HapticFeedbackManager.shared.tap(); showApplyConfirmation = true })
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
        isApplying = true; if hasEdits { organizer.currentPlan = editablePlan }
        Task { @MainActor in do { try await organizer.apply(at: baseURL, dryRun: false, enableTagging: settingsViewModel.config.enableFileTagging); if case .completed = organizer.state { isApplying = false } } catch { organizer.state = .error(error); isApplying = false } }
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
}

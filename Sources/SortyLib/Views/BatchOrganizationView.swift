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
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var customPersonaStore: CustomPersonaStore
    @EnvironmentObject var steeringManager: SteeringPromptManager
    @EnvironmentObject var learningsManager: LearningsManager

    @StateObject private var sessionManager = AISessionManager.shared

    @State private var includeSubfolders: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var selectedPlanFolder: URL?
    @State private var focusedFolder: URL?
    @State private var showApplyConfirmation = false
    @State private var promptTargetFolder: URL?
    @State private var improvingFolders: Set<URL> = []

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
        .focusable()
        .onMoveCommand(perform: handleMoveCommand)
        .sheet(item: Binding(
            get: { selectedPlanFolder.map { PlanSheetItem(url: $0) } },
            set: { selectedPlanFolder = $0?.url }
        )) { item in
            BatchPlanEditorView(
                folderURL: item.url,
                plan: batchManager.results.first(where: { $0.folderURL == item.url })?.plan,
                historyPlans: batchManager.previewPlanHistory[item.url] ?? [],
                onSave: { updated in
                    batchManager.updatePreviewPlan(updated, for: item.url)
                }
            )
            .environmentObject(learningsManager)
        }
        .sheet(item: Binding(
            get: { promptTargetFolder.map { PlanSheetItem(url: $0) } },
            set: { promptTargetFolder = $0?.url }
        )) { item in
            SavedPromptsSheet(
                steeringManager: steeringManager,
                settingsConfig: settingsViewModel.config,
                onApplyPrompt: { prompt in
                    batchManager.updateInstructions(prompt, for: item.url)
                    promptTargetFolder = nil
                    HapticFeedbackManager.shared.success()
                }
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
        .onAppear {
            Task { await prewarmAIConnection() }
            if focusedFolder == nil {
                focusedFolder = batchManager.selectedFolders.first
            }
        }
        .onChange(of: settingsViewModel.config.provider) { _, _ in
            Task { await prewarmAIConnection() }
        }
        .onChange(of: batchManager.selectedFolders) { _, folders in
            if let current = focusedFolder, !folders.contains(current) {
                focusedFolder = folders.first
            } else if focusedFolder == nil {
                focusedFolder = folders.first
            }

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

            if sessionManager.prewarmingProvider != nil {
                Label("Connecting…", systemImage: "bolt.horizontal.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("BatchPrewarmStatusConnecting")
            } else if sessionManager.isPrewarmed {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("BatchPrewarmStatusConnected")
            } else if let error = sessionManager.prewarmError {
                Label("Connection Warning", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(error)
                    .accessibilityIdentifier("BatchPrewarmStatusWarning")
            }

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
                WorkflowContainer(currentStep: .configure) {
                    if batchManager.isProcessing {
                        overallProgressSection
                    }

                    WorkflowCard(title: "Batch Settings", icon: "slider.horizontal.3") {
                        optionsSection
                    }

                    WorkflowCard(title: "Folders", icon: "folder") {
                        folderListSection
                    }

                    if let focusedFolder {
                        WorkflowCard(title: "Folder Customization", icon: "wand.and.stars") {
                            folderCustomizationSection(for: focusedFolder)
                        }
                    }

                    if !previewFolders.isEmpty {
                        WorkflowCard(title: "Unified Preview", icon: "rectangle.3.group") {
                            unifiedPreviewSection
                        }
                    }

                    if batchManager.hasAnyOutcome && !batchManager.isProcessing {
                        WorkflowCard(title: "Results", icon: "chart.bar") {
                            resultsSection
                        }
                    }

                    actionButtons
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

                Text("Add multiple folders to customize instructions and run one polished batch preview.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
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

            SortyGradientProgressBar(progress: batchManager.overallProgress, height: 10)
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
        .transition(TransitionStyles.slideFromBottom)
    }

    private var showWorkflowOnboarding: Bool {
        !batchManager.selectedFolders.isEmpty &&
        !batchManager.isProcessing &&
        !batchManager.hasAnyOutcome
    }

    private var previewFolders: [URL] {
        batchManager.selectedFolders.filter { folder in
            batchManager.results.contains {
                $0.folderURL == folder && $0.status == .previewed && $0.plan != nil
            }
        }
    }

    private var focusedPreviewFolder: URL? {
        if let focusedFolder, previewFolders.contains(focusedFolder) {
            return focusedFolder
        }
        return previewFolders.first
    }

    private var workflowOnboardingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack")
                    .foregroundStyle(.blue)
                Text("Batch Flow")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("1 of 3")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                workflowStepBadge(number: 1, title: "Customize", subtitle: "Pick prompts/personas")
                workflowStepBadge(number: 2, title: "Generate", subtitle: "Create all previews")
                workflowStepBadge(number: 3, title: "Apply", subtitle: "Commit reviewed changes")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.08))
        )
    }

    private func workflowStepBadge(number: Int, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.blue))
            Text(title)
                .font(.caption.weight(.semibold))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.9))
        )
    }

    private var unifiedPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let folder = focusedPreviewFolder,
               let result = batchManager.results.first(where: { $0.folderURL == folder }),
               let plan = result.plan {
                HStack(spacing: 8) {
                    Button {
                        moveFocusedPreview(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .minimumHitTarget()
                    .disabled(previewFolders.count < 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.lastPathComponent)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("Preview \(previewPositionText(for: folder))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        moveFocusedPreview(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .minimumHitTarget()
                    .disabled(previewFolders.count < 2)
                }

                HStack(spacing: 12) {
                    unifiedStat(label: "Files", value: "\(plan.totalFiles)")
                    unifiedStat(label: "Folders", value: "\(plan.totalFolders)")
                    unifiedStat(label: "Unorganized", value: "\(plan.unorganizedFiles.count)")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Top Proposed Folders")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(plan.suggestions.prefix(3).enumerated()), id: \.offset) { _, suggestion in
                        HStack {
                            Text(suggestion.folderName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(suggestion.totalFileCount) files")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        selectedPlanFolder = folder
                    } label: {
                        Label("Open Full Preview", systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .minimumHitTarget()

                    Spacer()

                    Text("Use ←/→ keys to switch previews")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Generate previews to compare and navigate folder plans here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func unifiedStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func previewPositionText(for folder: URL) -> String {
        guard let index = previewFolders.firstIndex(of: folder) else { return "0 of \(previewFolders.count)" }
        return "\(index + 1) of \(previewFolders.count)"
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Toggle("Include Immediate Subfolders", isOn: $includeSubfolders)
                    .toggleStyle(.switch)

                Spacer()

                Stepper("Concurrent: \(batchManager.maxConcurrentFolders)", value: $batchManager.maxConcurrentFolders, in: 1...5)
                    .frame(maxWidth: 240)
                    .accessibilityIdentifier("BatchConcurrentStepper")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .disabled(batchManager.isProcessing)

            HStack(spacing: 12) {
                Label(settingsViewModel.config.provider.displayName, systemImage: "cpu")
                if !settingsViewModel.config.model.isEmpty {
                    Label(settingsViewModel.config.model, systemImage: "brain")
                }
                Spacer()
                Text("Per-folder overrides available")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Folder List

    private var folderListSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(batchManager.selectedFolders, id: \.self) { folder in
                    folderRow(for: folder)
                }
            }
        }
        .frame(maxHeight: 280)
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
        let config = batchManager.configuration(for: folder)
        return HStack(spacing: 10) {
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

            if config.personaSelection != .global {
                Label("Persona", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !config.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Label("Custom Prompt", systemImage: "text.bubble")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let result = batchManager.results.first(where: { $0.folderURL == folder }),
               result.status == .previewed,
               result.plan != nil {
                Button {
                    HapticFeedbackManager.shared.tap()
                    selectedPlanFolder = folder
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .help("Edit and compare preview")
                .accessibilityIdentifier("BatchViewPlan-\(folder.lastPathComponent)")
            }

            statusBadge(for: folder)

            if !batchManager.isProcessing {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .help("Reveal in Finder")
                .accessibilityIdentifier("BatchRevealFolder-\(folder.lastPathComponent)")

                Button {
                    HapticFeedbackManager.shared.selection()
                    focusedFolder = folder
                } label: {
                    Image(systemName: focusedFolder == folder ? "slider.horizontal.3" : "slider.horizontal.3.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .help("Customize this folder")
                .accessibilityIdentifier("BatchCustomizeFolder-\(folder.lastPathComponent)")

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
                .minimumHitTarget()
                .accessibilityIdentifier("BatchRemoveFolder-\(folder.lastPathComponent)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(focusedFolder == folder ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            guard !batchManager.isProcessing else { return }
            HapticFeedbackManager.shared.selection()
            focusedFolder = folder
        }
    }

    private func folderCustomizationSection(for folder: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FolderThumbnailView(url: folder, size: CGSize(width: 26, height: 26))

                VStack(alignment: .leading, spacing: 1) {
                    Text(folder.lastPathComponent)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(folder.path)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    moveFocusedFolder(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .minimumHitTarget()

                Button {
                    moveFocusedFolder(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .minimumHitTarget()

                Button("Back") {
                    HapticFeedbackManager.shared.tap()
                    focusedFolder = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("BatchFolderBackButton")

                Button("Clear") {
                    HapticFeedbackManager.shared.tap()
                    batchManager.clearFolderCustomization(for: folder)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("BatchFolderClearCustomizationsButton")
            }

            HStack(spacing: 10) {
                Text("Persona")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                BatchPersonaPicker(
                    selection: Binding(
                        get: { batchManager.configuration(for: folder).personaSelection },
                        set: { batchManager.updatePersonaSelection($0, for: folder) }
                    ),
                    personaManager: personaManager,
                    customStore: customPersonaStore
                )
                .accessibilityIdentifier("BatchFolderPersonaPicker")

                Spacer()

                if batchManager.results.first(where: { $0.folderURL == folder })?.plan != nil {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        selectedPlanFolder = folder
                    } label: {
                        Label("Open Preview", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("BatchFolderOpenPreviewButton")
                }
            }

            ZStack(alignment: .topLeading) {
                let currentInstructions = batchManager.configuration(for: folder).instructions
                if currentInstructions.isEmpty {
                    Text("Use this folder's own instructions, or keep it empty to inherit global instructions.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                if improvingFolders.contains(folder) {
                    HStack {
                        Spacer()
                        SortyGradientCircularLoader(size: 13, lineWidth: 2.4)
                        Text("Improving instructions…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    SubmittableTextEditor(
                        text: Binding(
                            get: { batchManager.configuration(for: folder).instructions },
                            set: { batchManager.updateInstructions($0, for: folder) }
                        )
                    ) {
                        startPreview()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 64, maxHeight: 110)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
            .accessibilityIdentifier("BatchFolderInstructionsEditor")

            HStack(spacing: 10) {
                Button {
                    promptTargetFolder = folder
                } label: {
                    Label(
                        steeringManager.prompts.isEmpty ? "Saved Prompts" : "Saved Prompts (\(steeringManager.prompts.count))",
                        systemImage: "text.alignleft"
                    )
                    .font(.caption2)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityIdentifier("BatchFolderSavedPromptsButton")

                if !batchManager.configuration(for: folder).instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        Task { await improvePromptForFolder(folder) }
                    } label: {
                        Label("Improve", systemImage: "wand.and.stars")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget()
                    .foregroundStyle(.purple)
                    .accessibilityIdentifier("BatchFolderImprovePromptButton")
                    .disabled(improvingFolders.contains(folder))
                }

                Spacer()
            }

            suggestedPromptChips(for: folder)
        }
        .transition(TransitionStyles.slideFromBottom)
    }

    private func suggestedPromptChips(for folder: URL) -> some View {
        let suggestions = [
            "Group by project and date",
            "Put screenshots in Screenshots and receipts by year",
            "Keep original filenames but normalize casing"
        ]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        HapticFeedbackManager.shared.selection()
                        batchManager.updateInstructions(suggestion, for: folder)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption2)
                }
            }
        }
        .accessibilityIdentifier("BatchPromptSuggestionsRow")
    }

    @ViewBuilder
    private func statusBadge(for folder: URL) -> some View {
        if let result = batchManager.results.first(where: { $0.folderURL == folder }) {
            HStack(spacing: 4) {
                if result.status == .processing {
                    SortyGradientCircularLoader(size: 10, lineWidth: 2)
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
        VStack(alignment: .leading, spacing: 8) {
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
        .accessibilityIdentifier("BatchResultsSection")
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

                if batchManager.hasFailedFolders {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        retryFailed()
                    } label: {
                        Label("Retry Failed", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("BatchRetryFailedButton")
                }

                if !batchManager.selectedFolders.isEmpty {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        startPreview()
                    } label: {
                        Label("Generate All Previews", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("BatchPreviewButton")
                }

                if let focusedFolder {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        Task { await batchManager.retryFolder(focusedFolder) }
                    } label: {
                        Label("Preview Focused Folder", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("BatchFocusedPreviewButton")
                    .disabled(batchManager.isProcessing)
                }

                if batchManager.canApplyPreview {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        showApplyConfirmation = true
                    } label: {
                        Label("Apply Reviewed Plans", systemImage: "checkmark.circle.fill")
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
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            if !previewFolders.isEmpty {
                moveFocusedPreview(by: -1)
            } else {
                moveFocusedFolder(by: -1)
            }
        case .right:
            if !previewFolders.isEmpty {
                moveFocusedPreview(by: 1)
            } else {
                moveFocusedFolder(by: 1)
            }
        default:
            break
        }
    }

    private func moveFocusedFolder(by delta: Int) {
        guard !batchManager.selectedFolders.isEmpty else { return }

        let folders = batchManager.selectedFolders
        let currentIndex = focusedFolder.flatMap { folders.firstIndex(of: $0) } ?? 0
        let nextIndex = max(0, min(folders.count - 1, currentIndex + delta))
        guard nextIndex != currentIndex || focusedFolder == nil else { return }

        focusedFolder = folders[nextIndex]
        HapticFeedbackManager.shared.selection()
    }

    private func moveFocusedPreview(by delta: Int) {
        guard !previewFolders.isEmpty else { return }

        let currentIndex = focusedPreviewFolder.flatMap { previewFolders.firstIndex(of: $0) } ?? 0
        let wrappedIndex = (currentIndex + delta + previewFolders.count) % previewFolders.count
        let next = previewFolders[wrappedIndex]

        focusedFolder = next
        HapticFeedbackManager.shared.selection()
    }

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

    private func retryFailed() {
        Task {
            await batchManager.retryAllFailed()
            if batchManager.failedFolders == 0 {
                HapticFeedbackManager.shared.success()
            } else {
                HapticFeedbackManager.shared.error()
            }
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

    private func prewarmAIConnection() async {
        await AISessionManager.shared.prewarm(
            provider: settingsViewModel.config.provider,
            config: settingsViewModel.config
        )
    }

    private func improvePromptForFolder(_ folder: URL) async {
        let original = batchManager.configuration(for: folder).instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return }

        improvingFolders.insert(folder)
        defer { improvingFolders.remove(folder) }

        do {
            let client = try AIClientFactory.createClient(config: settingsViewModel.config)
            let improved = try await client.generateText(
                prompt: "Improve these batch folder organization instructions so they are specific, concise, and actionable. Keep the user's intent. Return only rewritten instructions.\n\n\(original)",
                systemPrompt: "You improve short prompts for AI file organization workflows."
            )
            let trimmed = improved.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            batchManager.updateInstructions(trimmed, for: folder)
            HapticFeedbackManager.shared.success()
        } catch {
            HapticFeedbackManager.shared.error()
        }
    }
}

// MARK: - Plan Sheet Item

private struct PlanSheetItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct BatchPersonaPicker: View {
    @Binding var selection: BatchPersonaSelection
    let personaManager: PersonaManager
    let customStore: CustomPersonaStore

    var body: some View {
        Picker("Persona", selection: $selection) {
            Text("Global (\(globalPersonaName))")
                .tag(BatchPersonaSelection.global)

            Section("Built-in") {
                ForEach(PersonaType.allCases, id: \.self) { persona in
                    Label(persona.displayName, systemImage: persona.icon)
                        .tag(BatchPersonaSelection.builtIn(persona))
                }
            }

            if !customStore.customPersonas.isEmpty {
                Section("Custom") {
                    ForEach(customStore.customPersonas) { custom in
                        Label(custom.name, systemImage: custom.icon)
                            .tag(BatchPersonaSelection.custom(custom.id))
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
    }

    private var globalPersonaName: String {
        if let customID = personaManager.selectedCustomPersonaId,
           let custom = customStore.customPersonas.first(where: { $0.id == customID }) {
            return custom.name
        }
        return personaManager.selectedPersona.displayName
    }
}

// MARK: - Batch Plan Editor

private struct BatchPlanEditorView: View {
    let folderURL: URL
    let plan: OrganizationPlan?
    let historyPlans: [OrganizationPlan]
    let onSave: (OrganizationPlan) -> Void

    @Environment(\.dismiss) private var dismiss

    @StateObject private var dragDropManager = DragDropManager()
    @StateObject private var previewStore: PreviewStore
    @State private var editablePlan: OrganizationPlan
    @State private var hasEdits = false
    @State private var viewingHistoryIndex: Int?
    @State private var compareIndex: Int?

    init(
        folderURL: URL,
        plan: OrganizationPlan?,
        historyPlans: [OrganizationPlan],
        onSave: @escaping (OrganizationPlan) -> Void
    ) {
        self.folderURL = folderURL
        self.plan = plan
        self.historyPlans = historyPlans
        self.onSave = onSave

        let initialPlan = plan ?? OrganizationPlan()
        _previewStore = StateObject(wrappedValue: PreviewStore(plan: initialPlan))
        _editablePlan = State(initialValue: initialPlan)
    }

    private var displayedPlan: OrganizationPlan {
        if let idx = viewingHistoryIndex, idx < historyPlans.count {
            return historyPlans[idx]
        }
        return editablePlan
    }

    private var isViewingHistory: Bool {
        viewingHistoryIndex != nil
    }

    private var totalVersions: Int {
        historyPlans.count + 1
    }

    private var comparisonPlan: OrganizationPlan? {
        guard let idx = compareIndex, idx < historyPlans.count else { return nil }
        return historyPlans[idx]
    }

    private var emptyStateType: PreviewListView.EmptyStateType {
        if displayedPlan.totalFiles == 0 { return .emptyDirectory }
        if displayedPlan.suggestions.isEmpty && !displayedPlan.unorganizedFiles.isEmpty {
            return .allUnorganized(displayedPlan.unorganizedFiles.count)
        }
        return .none
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Batch Preview Editor")
                        .font(.headline)
                    Text(folderURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(12)

            Divider()

            if plan == nil {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No plan available")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PreviewHeaderView(
                    version: displayedPlan.version,
                    hasEdits: !isViewingHistory && hasEdits,
                    notes: displayedPlan.notes,
                    totalFiles: displayedPlan.totalFiles,
                    totalFolders: displayedPlan.totalFolders,
                    renameCount: renameCount(for: displayedPlan),
                    isDragging: dragDropManager.draggedFile != nil,
                    totalVersions: totalVersions,
                    isViewingHistory: isViewingHistory,
                    onPreviousVersion: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if let idx = viewingHistoryIndex {
                                if idx > 0 { viewingHistoryIndex = idx - 1 }
                            } else if !historyPlans.isEmpty {
                                viewingHistoryIndex = historyPlans.count - 1
                            }
                        }
                    },
                    onNextVersion: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if let idx = viewingHistoryIndex {
                                if idx >= historyPlans.count - 1 {
                                    viewingHistoryIndex = nil
                                } else {
                                    viewingHistoryIndex = idx + 1
                                }
                            }
                        }
                    }
                )

                if let comparisonPlan {
                    BatchComparisonStrip(current: displayedPlan, previous: comparisonPlan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }

                Divider()

                PreviewListView(
                    store: previewStore,
                    dragDropManager: dragDropManager,
                    onPlanChanged: {
                        guard !isViewingHistory else { return }
                        hasEdits = true
                        editablePlan = previewStore.plan
                    },
                    emptyStateType: emptyStateType
                )

                Divider()

                HStack {
                    if !historyPlans.isEmpty {
                        Picker("Compare", selection: $compareIndex) {
                            Text("No comparison").tag(Int?.none)
                            ForEach(Array(historyPlans.enumerated()), id: \.offset) { index, plan in
                                Text("Version \(plan.version)").tag(Int?.some(index))
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 180)
                        .accessibilityIdentifier("BatchPreviewComparePicker")
                    }

                    Spacer()

                    Button("Reset") {
                        HapticFeedbackManager.shared.tap()
                        editablePlan = plan ?? OrganizationPlan()
                        previewStore.updatePlan(editablePlan)
                        hasEdits = false
                        viewingHistoryIndex = nil
                    }
                    .buttonStyle(.bordered)

                    Button("Save Changes") {
                        HapticFeedbackManager.shared.success()
                        onSave(editablePlan)
                        hasEdits = false
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasEdits || isViewingHistory)
                    .accessibilityIdentifier("BatchPreviewSaveButton")
                }
                .padding(12)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            previewStore.dragDropManager = dragDropManager
        }
        .onChange(of: viewingHistoryIndex) { _, newValue in
            if let idx = newValue, idx < historyPlans.count {
                previewStore.updatePlan(historyPlans[idx])
            } else {
                previewStore.updatePlan(editablePlan)
            }
        }
    }

    private func renameCount(for plan: OrganizationPlan) -> Int {
        plan.suggestions.reduce(0) { $0 + $1.allFileRenameMappings.filter { $0.hasRename }.count }
    }
}

private struct BatchComparisonStrip: View {
    let current: OrganizationPlan
    let previous: OrganizationPlan

    var body: some View {
        HStack(spacing: 10) {
            comparisonBadge(
                title: "Files",
                value: current.totalFiles - previous.totalFiles,
                positiveColor: .green,
                negativeColor: .orange
            )

            comparisonBadge(
                title: "Folders",
                value: current.totalFolders - previous.totalFolders,
                positiveColor: .blue,
                negativeColor: .orange
            )

            Spacer()

            Text("Comparing v\(current.version) to v\(previous.version)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func comparisonBadge(title: String, value: Int, positiveColor: Color, negativeColor: Color) -> some View {
        let color: Color = value == 0 ? .secondary : (value > 0 ? positiveColor : negativeColor)
        let prefix = value > 0 ? "+" : ""
        return HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(prefix)\(value)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Previews

#Preview("Batch Organization - Empty") {
    BatchOrganizationView()
        .environmentObject(FolderOrganizer.preview)
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(BatchOrganizationManager())
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .environmentObject(SteeringPromptManager.shared)
        .environmentObject(LearningsManager())
        .frame(width: 900, height: 700)
}

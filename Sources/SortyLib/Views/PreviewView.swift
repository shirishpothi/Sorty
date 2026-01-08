//
//  PreviewView.swift
//  Sorty
//
//  Enhanced preview interface with reasoning support, drag-drop editing,
//  and post-organization honing integration for Learnings feature
//

import SwiftUI
import UniformTypeIdentifiers

struct PreviewView: View {
    let plan: OrganizationPlan
    let baseURL: URL
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var learningsManager: LearningsManager
    @StateObject private var previewManager = PreviewManager()
    @StateObject private var dragDropManager = DragDropManager()
    @State private var showApplyConfirmation = false
    @State private var isApplying = false
    @State private var editablePlan: OrganizationPlan
    @State private var hasEdits = false
    @State private var showPostOrganizationHoning = false

    init(plan: OrganizationPlan, baseURL: URL) {
        self.plan = plan
        self.baseURL = baseURL
        _editablePlan = State(initialValue: plan)
    }

    // Reset isApplying when organizer state changes to completed
    private var shouldDisableButtons: Bool {
        isApplying || (organizer.state == .applying)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with version info
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Preview \(editablePlan.version)")
                            .font(.headline)

                        if hasEdits {
                            Text("(Edited)")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }

                    if !editablePlan.notes.isEmpty {
                        Text(editablePlan.notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()

                // Drag hint
                if dragDropManager.draggedFile != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.caption)
                        Text("Drop on a folder")
                            .font(.caption)
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(6)
                }

                Text("\(editablePlan.totalFiles) files • \(editablePlan.totalFolders) folders")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            // Stats for Nerds
            if settingsViewModel.config.showStatsForNerds, let stats = editablePlan.generationStats {
                GenerationStatsView(stats: stats)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(editablePlan.suggestions) { suggestion in
                        EditableFolderTreeView(
                            suggestion: suggestion,
                            level: 0,
                            plan: $editablePlan,
                            dragDropManager: dragDropManager,
                            onPlanChanged: { hasEdits = true }
                        )
                    }

                    // Unorganized files section with drop support
                    if !editablePlan.unorganizedFiles.isEmpty || dragDropManager.draggedFile != nil {
                        UnorganizedFilesSection(
                            plan: $editablePlan,
                            dragDropManager: dragDropManager,
                            onPlanChanged: { hasEdits = true }
                        )
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            VStack(spacing: 12) {
                // Custom Instructions for Regeneration
                if !isApplying {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Guiding Instructions (for next attempt)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("e.g. 'Group by file size', 'Separate RAW files'", text: $organizer.customInstructions)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: organizer.customInstructions) { oldValue, newValue in
                                    // Track guiding instruction for learnings
                                    if !newValue.isEmpty && newValue != oldValue && learningsManager.consentManager.canCollectData {
                                        NotificationCenter.default.post(
                                            name: .steeringPromptProvided,
                                            object: nil,
                                            userInfo: ["prompt": newValue, "folderPath": baseURL.path]
                                        )
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }

                HStack {
                    Button("Cancel") {
                        organizer.reset()
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("PreviewCancelButton")

                    if hasEdits {
                        Button("Reset Edits") {
                            editablePlan = plan
                            hasEdits = false
                        }
                        .foregroundColor(.orange)
                        .accessibilityIdentifier("ResetEditsButton")
                    }

                    Spacer()

                    Button("Try Another Organisation") {
                        regeneratePreview()
                    }
                    .disabled(shouldDisableButtons)
                    .accessibilityIdentifier("TryAnotherOrganisationButton")

                    Button("Apply Organization") {
                        showApplyConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(shouldDisableButtons)
                    .accessibilityIdentifier("ApplyOrganizationButton")
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .alert("Apply Organization?", isPresented: $showApplyConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Apply") {
                applyOrganization()
            }
        } message: {
            Text("This will create \(editablePlan.totalFolders) folders and move \(editablePlan.totalFiles) files. This action can be undone.")
        }
        .onChange(of: organizer.state) { oldState, newState in
            if case .completed = newState {
                isApplying = false
                // Show post-organization honing if learnings is enabled
                if learningsManager.consentManager.canCollectData {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showPostOrganizationHoning = true
                    }
                }
            } else if case .error = newState {
                isApplying = false
            }
        }
        .onChange(of: plan) { oldPlan, newPlan in
            // Update editable plan when organizer regenerates
            editablePlan = newPlan
            hasEdits = false
        }
        .sheet(isPresented: $showPostOrganizationHoning) {
            PostOrganizationHoningView(
                fileCount: editablePlan.totalFiles,
                folderCount: editablePlan.totalFolders,
                config: settingsViewModel.config,
                onComplete: { answers in
                    Task {
                        await learningsManager.saveHoningResults(answers)
                        showPostOrganizationHoning = false
                    }
                },
                onSkip: {
                    showPostOrganizationHoning = false
                }
            )
        }
        .environmentObject(dragDropManager)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func regeneratePreview() {
        // Track guiding instruction if provided
        if !organizer.customInstructions.isEmpty && learningsManager.consentManager.canCollectData {
            learningsManager.recordGuidingInstruction(organizer.customInstructions)
        }
        
        Task {
            do {
                try await organizer.regeneratePreview()
            } catch {
                organizer.state = .error(error)
            }
        }
    }

    private func applyOrganization() {
        isApplying = true
        // Use the edited plan if there were edits
        if hasEdits {
            organizer.currentPlan = editablePlan
        }
        Task { @MainActor in
            do {
                try await organizer.apply(at: baseURL, dryRun: false, enableTagging: settingsViewModel.config.enableFileTagging)
                if case .completed = organizer.state {
                    isApplying = false
                }
            } catch {
                organizer.state = .error(error)
                isApplying = false
            }
        }
    }
}

// MARK: - Post-Organization Honing View

struct PostOrganizationHoningView: View {
    let fileCount: Int
    let folderCount: Int
    let config: AIConfig
    let onComplete: ([HoningAnswer]) -> Void
    let onSkip: () -> Void
    
    @StateObject private var engine: LearningsHoningEngine
    @State private var currentQuestionIndex = 0
    @State private var answers: [HoningAnswer] = []
    
    init(fileCount: Int, folderCount: Int, config: AIConfig, onComplete: @escaping ([HoningAnswer]) -> Void, onSkip: @escaping () -> Void) {
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.config = config
        self.onComplete = onComplete
        self.onSkip = onSkip
        _engine = StateObject(wrappedValue: LearningsHoningEngine(config: config))
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("Organization Complete!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Organized \(fileCount) files into \(folderCount) folders")
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            
            Divider()
            
            // Quick Feedback Section
            VStack(alignment: .leading, spacing: 16) {
                Text("Help us learn your preferences")
                    .font(.headline)
                
                Text("Answer a quick question to improve future organizations")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if engine.isGenerating {
                    ProgressView("Generating question...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if let session = engine.currentSession, !session.questions.isEmpty {
                    let question = session.questions.last!
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(question.text)
                            .font(.body)
                            .fontWeight(.medium)
                        
                        ForEach(question.options, id: \.self) { option in
                            Button(action: {
                                let answer = HoningAnswer(
                                    questionId: question.id,
                                    selectedOption: option
                                )
                                answers.append(answer)
                                onComplete(answers)
                            }) {
                                HStack {
                                    Text(option)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    // Fallback static question
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Was this organization helpful?")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        ForEach(["Yes, it was great!", "It was okay", "Not really useful"], id: \.self) { option in
                            Button(action: {
                                let answer = HoningAnswer(
                                    questionId: "post_org_feedback",
                                    selectedOption: option
                                )
                                answers.append(answer)
                                onComplete(answers)
                            }) {
                                HStack {
                                    Text(option)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
            
            // Skip button
            Button("Skip for now") {
                onSkip()
            }
            .foregroundColor(.secondary)
            .padding(.bottom, 24)
        }
        .frame(width: 450, height: 500)
        .onAppear {
            Task {
                await engine.startSession(questionCount: 1)
            }
        }
    }
}

// MARK: - Editable Folder Tree

struct EditableFolderTreeView: View {
    let suggestion: FolderSuggestion
    let level: Int
    @Binding var plan: OrganizationPlan
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void

    @State private var isExpanded = true
    @State private var showReasoning = false

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Folder header row - drop target
            HStack {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .frame(width: 20)

                Image(systemName: "folder.fill")
                    .foregroundColor(isDropTarget ? .purple : .blue)

                Text(suggestion.folderName)
                    .fontWeight(.medium)

                Text("(\(suggestion.totalFileCount) files)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Reasoning toggle
                if !suggestion.reasoning.isEmpty {
                    Button {
                        showReasoning.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(showReasoning ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View AI reasoning for this folder")
                }
            }
            .padding(.leading, CGFloat(level * 20))
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDropTarget ? Color.purple.opacity(0.1) : Color.clear)
                    .strokeBorder(isDropTarget ? Color.purple : Color.clear, lineWidth: 2)
            )
            .onDrop(of: [.text], delegate: FileDropDelegate(
                targetFolder: suggestion,
                plan: $plan,
                draggedFile: $dragDropManager.draggedFile,
                isTargeted: $isDropTarget
            ))

            // Reasoning Disclosure
            if showReasoning && !suggestion.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Reasoning")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)

                    Text(suggestion.reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                        )
                }
                .padding(.leading, CGFloat((level + 1) * 20))
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isExpanded {
                // Files in this folder - draggable
                ForEach(suggestion.files) { file in
                    DraggableFileRow(
                        file: file,
                        level: level + 1,
                        dragDropManager: dragDropManager
                    )
                }

                // Subfolders
                ForEach(suggestion.subfolders) { subfolder in
                    EditableFolderTreeView(
                        suggestion: subfolder,
                        level: level + 1,
                        plan: $plan,
                        dragDropManager: dragDropManager,
                        onPlanChanged: onPlanChanged
                    )
                }
            }
        }
    }
}

// MARK: - Draggable File Row

struct DraggableFileRow: View {
    let file: FileItem
    let level: Int
    @ObservedObject var dragDropManager: DragDropManager

    @State private var isDragging = false

    var body: some View {
        HStack {
            Image(systemName: "doc")
                .foregroundColor(.secondary)
            Text(file.displayName)
            Spacer()
            Text(file.formattedSize)
                .foregroundColor(.secondary)

            // Drag handle indicator
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.leading, CGFloat((level) * 20))
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .opacity(isDragging ? 0.5 : 1.0)
        .onDrag {
            isDragging = true
            dragDropManager.startDrag(file)
            return NSItemProvider(object: file.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            // Reset drag state when drop happens elsewhere
            isDragging = false
            return false
        }
    }
}

// MARK: - Unorganized Files Section

struct UnorganizedFilesSection: View {
    @Binding var plan: OrganizationPlan
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "questionmark.folder")
                    .foregroundColor(.orange)
                Text("Unorganized Files")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(plan.unorganizedFiles.count) files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDropTarget ? Color.orange.opacity(0.1) : Color.clear)
                    .strokeBorder(isDropTarget ? Color.orange : Color.clear, lineWidth: 2)
            )
            .onDrop(of: [.text], delegate: UnorganizedDropDelegate(
                plan: $plan,
                draggedFile: $dragDropManager.draggedFile,
                isTargeted: $isDropTarget
            ))

            ForEach(plan.unorganizedFiles) { file in
                HStack {
                    Image(systemName: "doc")
                        .foregroundColor(.secondary)
                    Text(file.displayName)
                    Spacer()
                    Text(file.formattedSize)
                        .foregroundColor(.secondary)

                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.leading, 20)
                .onDrag {
                    dragDropManager.startDrag(file)
                    return NSItemProvider(object: file.id.uuidString as NSString)
                }
            }

            // Unorganized details (reasons from AI)
            ForEach(plan.unorganizedDetails) { detail in
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text(detail.filename)
                        Text(detail.reason)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                }
                .padding(.leading, 20)
            }
        }
        .padding(.top)
    }
}

// MARK: - Legacy FolderTreeView for backward compatibility

struct FolderTreeView: View {
    let suggestion: FolderSuggestion
    let level: Int

    @State private var isExpanded = true
    @State private var showReasoning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .frame(width: 20)

                Image(systemName: "folder")
                    .foregroundColor(.blue)

                Text(suggestion.folderName)
                    .fontWeight(.medium)

                Text("(\(suggestion.totalFileCount) files)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if !suggestion.reasoning.isEmpty {
                    Button {
                        showReasoning.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(showReasoning ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View AI reasoning for this folder")
                }
            }
            .padding(.leading, CGFloat(level * 20))

            if showReasoning && !suggestion.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Reasoning")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)

                    Text(suggestion.reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                        )
                }
                .padding(.leading, CGFloat((level + 1) * 20))
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isExpanded {
                ForEach(suggestion.files) { file in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundColor(.secondary)
                        Text(file.displayName)
                        Spacer()
                        Text(file.formattedSize)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, CGFloat((level + 1) * 20))
                }

                ForEach(suggestion.subfolders) { subfolder in
                    FolderTreeView(suggestion: subfolder, level: level + 1)
                }
            }
        }
    }
}

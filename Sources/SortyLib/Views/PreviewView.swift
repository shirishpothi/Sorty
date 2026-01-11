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
    @State private var isInstructionsExpanded = false
    @FocusState private var instructionsFocused: Bool

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

            VStack(spacing: 0) {
                if !isApplying {
                    guidingInstructionsSection
                }
                
                Divider()
                
                HStack(spacing: 12) {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        organizer.reset()
                    } label: {
                        Text("Cancel")
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("PreviewCancelButton")
                    .accessibilityLabel("Cancel organization")

                    if hasEdits {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            editablePlan = plan
                            hasEdits = false
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                                Text("Reset Edits")
                            }
                        }
                        .foregroundColor(.orange)
                        .accessibilityIdentifier("ResetEditsButton")
                        .accessibilityLabel("Reset all manual edits")
                    }

                    Spacer()

                    Button {
                        HapticFeedbackManager.shared.tap()
                        regeneratePreview()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12))
                            Text("Try Another")
                        }
                    }
                    .disabled(shouldDisableButtons)
                    .accessibilityIdentifier("TryAnotherOrganisationButton")
                    .accessibilityLabel("Generate a different organization suggestion")

                    Button {
                        HapticFeedbackManager.shared.tap()
                        showApplyConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                            Text("Apply Organization")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(shouldDisableButtons)
                    .accessibilityIdentifier("ApplyOrganizationButton")
                    .accessibilityLabel("Apply this organization to your files")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
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

    private var guidingInstructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isInstructionsExpanded.toggle()
                    if isInstructionsExpanded {
                        instructionsFocused = true
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isInstructionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    
                    Image(systemName: "text.bubble")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    Text("Guiding Instructions")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("(for regeneration)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                    
                    if !organizer.customInstructions.isEmpty {
                        Text("\(organizer.customInstructions.count) chars")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.secondary.opacity(0.1))
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Guiding instructions for regeneration")
            .accessibilityHint(isInstructionsExpanded ? "Collapse instructions field" : "Expand instructions field")
            
            if isInstructionsExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ZStack(alignment: .topLeading) {
                        if organizer.customInstructions.isEmpty && !instructionsFocused {
                            Text("e.g. \"Group by file size\", \"Separate RAW files\", \"Create a folder for each year\"...")
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                        
                        TextEditor(text: $organizer.customInstructions)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .focused($instructionsFocused)
                            .onChange(of: organizer.customInstructions) { oldValue, newValue in
                                if !newValue.isEmpty && newValue != oldValue && learningsManager.consentManager.canCollectData {
                                    NotificationCenter.default.post(
                                        name: .steeringPromptProvided,
                                        object: nil,
                                        userInfo: ["prompt": newValue, "folderPath": baseURL.path]
                                    )
                                }
                            }
                    }
                    .frame(minHeight: 50, maxHeight: 70)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                instructionsFocused ? Color.accentColor : Color(NSColor.separatorColor),
                                lineWidth: instructionsFocused ? 2 : 1
                            )
                    )
                    .accessibilityIdentifier("GuidingInstructionsTextField")
                    .accessibilityLabel("Guiding instructions text field")
                    .accessibilityHint("Enter instructions to guide the AI when regenerating organization")
                    
                    Text("These instructions will be used when you click \"Try Another\"")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onAppear {
            if !organizer.customInstructions.isEmpty {
                isInstructionsExpanded = true
            }
        }
    }
    
    private func regeneratePreview() {
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
    @State private var hasAppeared = false
    @State private var selectedOption: String?
    
    init(fileCount: Int, folderCount: Int, config: AIConfig, onComplete: @escaping ([HoningAnswer]) -> Void, onSkip: @escaping () -> Void) {
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.config = config
        self.onComplete = onComplete
        self.onSkip = onSkip
        _engine = StateObject(wrappedValue: LearningsHoningEngine(config: config))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                headerSection
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    feedbackHeader
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                    
                    questionSection
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                }
                .padding(24)
            }
            
            Spacer()
            
            Divider()
            
            Button {
                HapticFeedbackManager.shared.tap()
                onSkip()
            } label: {
                Text("Skip for now")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
            .accessibilityIdentifier("SkipFeedbackButton")
            .accessibilityLabel("Skip feedback")
        }
        .frame(width: 480, height: 520)
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
            Task {
                await engine.startSession(questionCount: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post-organization feedback")
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 70, height: 70)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.green)
            }
            
            Text("Organization Complete!")
                .font(.title3)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                Label("\(fileCount) files", systemImage: "doc.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("→")
                    .foregroundStyle(.tertiary)
                
                Label("\(folderCount) folders", systemImage: "folder.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var feedbackHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                
                Text("Help Sorty Learn")
                    .font(.headline)
            }
            
            Text("Answer a quick question to improve future organizations")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var questionSection: some View {
        Group {
            if engine.isGenerating {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Preparing question...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if let session = engine.currentSession, !session.questions.isEmpty {
                let question = session.questions.last!
                dynamicQuestionView(question: question, questionId: question.id)
            } else {
                staticQuestionView
            }
        }
    }
    
    private func dynamicQuestionView(question: HoningQuestion, questionId: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(question.text)
                .font(.body)
                .fontWeight(.medium)
            
            ForEach(Array(question.options.enumerated()), id: \.element) { index, option in
                FeedbackOptionButton(
                    option: option,
                    isSelected: selectedOption == option,
                    delay: Double(index) * 0.05
                ) {
                    HapticFeedbackManager.shared.selection()
                    selectedOption = option
                    let answer = HoningAnswer(
                        questionId: questionId,
                        selectedOption: option
                    )
                    answers.append(answer)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onComplete(answers)
                    }
                }
            }
        }
    }
    
    private var staticQuestionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Was this organization helpful?")
                .font(.body)
                .fontWeight(.medium)
            
            ForEach(Array(["Yes, it was great!", "It was okay", "Not really useful"].enumerated()), id: \.element) { index, option in
                FeedbackOptionButton(
                    option: option,
                    isSelected: selectedOption == option,
                    delay: Double(index) * 0.05
                ) {
                    HapticFeedbackManager.shared.selection()
                    selectedOption = option
                    let answer = HoningAnswer(
                        questionId: "post_org_feedback",
                        selectedOption: option
                    )
                    answers.append(answer)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onComplete(answers)
                    }
                }
            }
        }
    }
}

struct FeedbackOptionButton: View {
    let option: String
    let isSelected: Bool
    let delay: Double
    let action: () -> Void
    
    @State private var hasAppeared = false
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(option)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isSelected ? .green : .secondary)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.green.opacity(0.1) : (isHovering ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -10)
        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay), value: hasAppeared)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            hasAppeared = true
        }
        .accessibilityLabel(option)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

//
//  LearningsView.swift
//  FileOrganizer
//
//  Main view for "The Learnings" feature - trainable example-based organization
//  Redesigned with wizard-style onboarding flow
//

import SwiftUI

// MARK: - Wizard Step Enum

enum LearningsStep: Int, CaseIterable {
    case welcome = 0
    case addFolders = 1
    case addExamples = 2
    case analyze = 3
    case apply = 4
    
    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .addFolders: return "Add Folders"
        case .addExamples: return "Add Examples"
        case .analyze: return "Analyze"
        case .apply: return "Apply"
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .addFolders: return "folder.badge.plus"
        case .addExamples: return "star.fill"
        case .analyze: return "magnifyingglass"
        case .apply: return "checkmark.circle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .welcome: return "Learn how The Learnings works"
        case .addFolders: return "Choose folders to organize"
        case .addExamples: return "Teach with examples"
        case .analyze: return "Infer organization rules"
        case .apply: return "Apply and review changes"
        }
    }
}

// MARK: - Main View

struct LearningsView: View {
    @StateObject private var manager = LearningsManager()
    @State private var currentStep: LearningsStep = .welcome
    @State private var projectName: String = ""
    enum ActivePicker {
        case none
        case rootFolder
        case exampleFolder
    }
    
    @State private var activePicker: ActivePicker = .none
    @State private var showingFileImporter = false
    @State private var showingProjectList = false
    @State private var hasStarted = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            if hasStarted {
                stepIndicator
                Divider()
            }
            
            // Content
            ScrollView {
                switch currentStep {
                case .welcome:
                    welcomeStep
                case .addFolders:
                    addFoldersStep
                case .addExamples:
                    addExamplesStep
                case .analyze:
                    analyzeStep
                case .apply:
                    applyStep
                }
            }
            
            // Navigation buttons
            if hasStarted {
                Divider()
                navigationButtons
            }
        }
        .frame(minWidth: 700, minHeight: 550)
        .alert("Error", isPresented: .constant(manager.error != nil)) {
            Button("OK") { manager.error = nil }
        } message: {
            if let error = manager.error {
                Text(error)
            }
        }
        .sheet(isPresented: $showingProjectList) {
            ProjectListSheet(manager: manager, onSelect: { name in
                Task {
                    await manager.loadProject(name: name)
                    projectName = manager.currentProject?.name ?? ""
                    hasStarted = true
                    currentStep = .addFolders
                }
            })
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                
                switch activePicker {
                case .rootFolder:
                    manager.addRootPath(url.path)
                case .exampleFolder:
                    manager.addExampleFolder(url.path)
                default:
                    break
                }
            }
            activePicker = .none
        }
    }
    
    // MARK: - Step Indicator
    
    private var stepIndicator: some View {
        HStack(spacing: 0) {
            ForEach(LearningsStep.allCases, id: \.rawValue) { step in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(stepColor(for: step))
                            .frame(width: 32, height: 32)
                        
                        if step.rawValue < currentStep.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Text("\(step.rawValue + 1)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(step == currentStep ? .white : .secondary)
                        }
                    }
                    
                    if step != .apply {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.green : Color.secondary.opacity(0.3))
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
    
    private func stepColor(for step: LearningsStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return .green
        } else if step == currentStep {
            return .accentColor
        } else {
            return .secondary.opacity(0.3)
        }
    }
    
    // MARK: - Welcome Step
    
    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Hero
            VStack(spacing: 16) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 72))
                    .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("The Learnings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Train a local, example-based file organizer that learns from your preferences.")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            
            // Features
            HStack(spacing: 32) {
                featureCard(icon: "folder.badge.plus", title: "Add Folders", description: "Choose which folders to organize")
                featureCard(icon: "star.fill", title: "Teach by Example", description: "Show the organizer how you like it")
                featureCard(icon: "sparkles", title: "Learn Rules", description: "AI infers patterns from your examples")
                featureCard(icon: "arrow.triangle.2.circlepath", title: "Apply & Rollback", description: "Safe changes with undo support")
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Actions
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    TextField("Project Name", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                    
                    Button(action: startNewProject) {
                        Label("Start New Project", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(projectName.isEmpty)
                }
                
                Button("Load Existing Project...") {
                    showingProjectList = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 32)
        }
        .padding()
    }
    
    private func featureCard(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
            
            Text(title)
                .font(.headline)
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 140)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func startNewProject() {
        manager.createProject(name: projectName, rootPaths: [])
        hasStarted = true
        currentStep = .addFolders
    }
    
    // MARK: - Add Folders Step
    
    private var addFoldersStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            stepHeader(
                icon: "folder.badge.plus",
                title: "Add Folders to Organize",
                subtitle: "Select the folders containing files you want to organize. These are your source directories."
            )
            
            // Folder list
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if let paths = manager.currentProject?.rootPaths, !paths.isEmpty {
                        ForEach(Array(paths.enumerated()), id: \.offset) { index, path in
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                
                                Spacer()
                                
                                Button(action: { manager.removeRootPath(at: index) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    } else {
                        emptyStateInline(
                            icon: "folder.badge.questionmark",
                            message: "No folders added yet. Click 'Add Folder' to get started."
                        )
                    }
                    
                    Button(action: { 
                        activePicker = .rootFolder
                        showingFileImporter = true 
                    }) {
                        Label("Add Folder", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // Tips
            tipCard(
                icon: "lightbulb.fill",
                title: "Tip",
                message: "Start with a Downloads folder or any directory with mixed files that need organizing."
            )
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Add Examples Step
    
    private var addExamplesStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepHeader(
                icon: "star.fill",
                title: "Teach by Example",
                subtitle: "Add folders that are already organized the way you want. The Learnings will learn from their structure."
            )
            
            // Example folders
            GroupBox("Example Folders") {
                VStack(alignment: .leading, spacing: 12) {
                    if let folders = manager.currentProject?.exampleFolders, !folders.isEmpty {
                        ForEach(Array(folders.enumerated()), id: \.offset) { index, path in
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .fontWeight(.medium)
                                    Text(path)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                
                                Spacer()
                                
                                Button(action: { manager.removeExampleFolder(at: index) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(12)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(8)
                        }
                    } else {
                        emptyStateInline(
                            icon: "star.slash",
                            message: "No example folders yet. Add a well-organized folder to teach the system."
                        )
                    }
                    
                    Button(action: { 
                        activePicker = .exampleFolder
                        showingFileImporter = true 
                    }) {
                        Label("Add Example Folder", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            
            // Labeled examples count
            if let examples = manager.currentProject?.labeledExamples, !examples.isEmpty {
                GroupBox("Manual Examples (\(examples.count))") {
                    Text("You have \(examples.count) manually labeled src → dst mappings that will help refine the rules.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            
            tipCard(
                icon: "info.circle.fill",
                title: "How it works",
                message: "The Learnings analyzes folder structures and file naming patterns to infer organization rules. More examples = better results!"
            )
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Analyze Step
    
    private var analyzeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepHeader(
                icon: "magnifyingglass",
                title: "Analyze & Learn Rules",
                subtitle: "Run analysis to infer organization rules from your examples and source folders."
            )
            
            if manager.analyzer.isAnalyzing {
                // Progress
                VStack(spacing: 16) {
                    ProgressView(value: manager.analyzer.progress, total: 1.0)
                        .progressViewStyle(.linear)
                    
                    Text(manager.analyzer.currentStatus)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            } else if let result = manager.analysisResult {
                // Results
                GroupBox("Inferred Rules (\(result.inferredRules.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(result.inferredRules.prefix(5)) { rule in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(rule.explanation)
                                    .font(.callout)
                            }
                        }
                        
                        if result.inferredRules.count > 5 {
                            Text("... and \(result.inferredRules.count - 5) more rules")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }
                
                // Confidence summary
                HStack(spacing: 16) {
                    confidenceBadge(label: "High", count: result.confidenceSummary.high, color: .green)
                    confidenceBadge(label: "Medium", count: result.confidenceSummary.medium, color: .orange)
                    confidenceBadge(label: "Low", count: result.confidenceSummary.low, color: .red)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
                
                Button("Re-analyze") {
                    Task { await manager.analyze() }
                }
                .buttonStyle(.bordered)
            } else {
                // Ready to analyze
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.purple)
                    
                    Text("Ready to Analyze")
                        .font(.headline)
                    
                    Text("Click 'Run Analysis' to infer organization rules from your examples.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        Task { await manager.analyze() }
                    }) {
                        Label("Run Analysis", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(32)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(12)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    private func confidenceBadge(label: String, count: Int, color: Color) -> some View {
        VStack {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 80)
        .padding()
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
    
    // MARK: - Apply Step
    
    @State private var enableBackup = true
    @State private var showApplyConfirmation = false
    
    private var applyStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepHeader(
                icon: "checkmark.circle.fill",
                title: "Review & Apply",
                subtitle: "Review proposed changes and apply them to your files."
            )
            
            if manager.isApplying {
                VStack(spacing: 16) {
                    ProgressView(value: manager.applyProgress, total: 1.0)
                        .progressViewStyle(.linear)
                    
                    Text("Applying changes...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            } else if let result = manager.analysisResult {
                // Preview
                GroupBox("Proposed Moves (\(result.proposedMappings.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(result.proposedMappings.prefix(10)) { mapping in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(URL(fileURLWithPath: mapping.srcPath).lastPathComponent)
                                            .font(.callout)
                                        Text("→ \(mapping.proposedDstPath)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(String(format: "%.0f%%", mapping.confidence * 100))
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(mapping.confidenceLevel == .high ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                            
                            if result.proposedMappings.count > 10 {
                                Text("... and \(result.proposedMappings.count - 10) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxHeight: 250)
                    .padding()
                }
                
                // Options
                HStack {
                    Toggle("Create Backup", isOn: $enableBackup)
                        .toggleStyle(.checkbox)
                    
                    Spacer()
                    
                    if let lastJobId = manager.lastJobId {
                        Button(action: {
                            Task { await manager.rollbackJob(jobId: lastJobId) }
                        }) {
                            Label("Undo Last Apply", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button(action: { showApplyConfirmation = true }) {
                        Label("Apply Changes", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(result.proposedMappings.isEmpty)
                }
                .confirmationDialog("Apply Changes?", isPresented: $showApplyConfirmation, titleVisibility: .visible) {
                    Button("Apply High-Confidence Only") {
                        Task {
                            let backupDir = enableBackup ? getBackupDirectory() : nil
                            await manager.applyMappings(backupDirectory: backupDir, onlyHighConfidence: true)
                        }
                    }
                    Button("Apply All") {
                        Task {
                            let backupDir = enableBackup ? getBackupDirectory() : nil
                            await manager.applyMappings(backupDirectory: backupDir, onlyHighConfidence: false)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will move files. \(enableBackup ? "A backup will be created." : "No backup will be created.")")
                }
            } else {
                emptyStateInline(
                    icon: "exclamationmark.triangle",
                    message: "No analysis results. Go back to the Analyze step first."
                )
            }
            
            // Save project
            HStack {
                Spacer()
                Button("Save Project") {
                    Task { await manager.saveProject() }
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    private func getBackupDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FileOrganizer/Learnings/Backups/\(Date().timeIntervalSince1970)")
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack {
            if currentStep != .welcome {
                Button(action: previousStep) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
            
            if currentStep != .apply {
                Button(action: nextStep) {
                    Label("Next", systemImage: "chevron.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
            }
        }
        .padding()
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .welcome:
            return !projectName.isEmpty
        case .addFolders:
            return !(manager.currentProject?.rootPaths.isEmpty ?? true)
        case .addExamples:
            return true // Optional step
        case .analyze:
            return manager.analysisResult != nil
        case .apply:
            return true
        }
    }
    
    private func nextStep() {
        if let next = LearningsStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.spring(response: 0.3)) {
                currentStep = next
            }
        }
    }
    
    private func previousStep() {
        if let prev = LearningsStep(rawValue: currentStep.rawValue - 1) {
            withAnimation(.spring(response: 0.3)) {
                currentStep = prev
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func stepHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(subtitle)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func emptyStateInline(icon: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary)
            Text(message)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private func tipCard(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Project List Sheet

struct ProjectListSheet: View {
    @ObservedObject var manager: LearningsManager
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var projects: [String] = []
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Load Project")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
            }
            .padding()
            
            Divider()
            
            if projects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No saved projects")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(projects, id: \.self) { name in
                    Button(action: {
                        onSelect(name)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            Text(name)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 400, height: 300)
        .task {
            projects = await manager.listProjects()
        }
    }
}

#Preview {
    LearningsView()
}

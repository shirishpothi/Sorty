//
//  OrchestrationDashboard.swift
//  Sorty
//
//  Single-screen view to manage and monitor all parallel generation runs
//

import SwiftUI

// MARK: - OrchestrationDashboard

public struct OrchestrationDashboard: View {
    @ObservedObject var orchestrator: GenerationOrchestrator
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var customPersonaStore: CustomPersonaStore
    
    let baseURL: URL
    let onSelectPlan: (OrganizationPlan) -> Void
    let onDismiss: () -> Void
    
    @State private var showSpecEditor = false
    @StateObject private var modelCatalog = ModelCatalog.shared
    @State private var sortOption: SortOption = .newest
    @State private var filterOption: FilterOption = .all
    @State private var cachedFiles: [FileItem] = []
    @State private var isPreparingFiles = false
    @State private var scanErrorMessage: String?
    @State private var lastScanUsedDeepScan = false
    
    private let detailPaneWidth: CGFloat = 320
    private let toolbarHeight: CGFloat = 54
    private let maxRunsAllowed = 4
    
    public init(
        orchestrator: GenerationOrchestrator,
        baseURL: URL,
        onSelectPlan: @escaping (OrganizationPlan) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.orchestrator = orchestrator
        self.baseURL = baseURL
        self.onSelectPlan = onSelectPlan
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            dashboardToolbar
            Divider()
            HStack(spacing: 0) {
                runsGrid
                Divider()
                detailPane
            }
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Parallel organization dashboard")
        .accessibilityHint("Configure and monitor parallel organization runs")
        .onAppear {
            if orchestrator.runs.isEmpty {
                seedDefaultRuns()
            }
            Task {
                await prepareFilesIfNeeded()
            }
        }
        .sheet(isPresented: $showSpecEditor) {
            GenerationSpecsEditor(
                orchestrator: orchestrator,
                onDismiss: { showSpecEditor = false },
                onStart: {
                    showSpecEditor = false
                }
            )
            .environmentObject(settingsViewModel)
            .environmentObject(customPersonaStore)
        }
    }
    
    // MARK: - Toolbar
    
    private var dashboardToolbar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Compare Organizations")
                    .font(.headline)
                    .fontWeight(.semibold)
                Text("Configure up to 4 runs and watch progress live")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            filterSortDropdown
            
            Divider()
                .frame(height: 24)
            
            if orchestrator.isAnyRunning {
                Button(action: { orchestrator.cancelAll() }) {
                    Label("Stop All", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel("Stop all runs")
                .accessibilityHint("Cancels all running generations")
            } else {
                Button(action: startAllRuns) {
                    Label("Start All", systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .disabled(orchestrator.runs.isEmpty || !hasRunnableRuns || isPreparingFiles)
                .accessibilityLabel("Start all runs")
                .accessibilityHint("Generates all configured organization plans")
            }
            
            Button(action: { showSpecEditor = true }) {
                Label("Edit Runs", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Edit run configurations")
            .accessibilityHint("Adjust providers, models, and personas")

            Text(filesStatusText())
                .font(.caption)
                .foregroundColor(isPreparingFiles ? .orange : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.08))
                )
                .accessibilityLabel("File scan status")
                .accessibilityValue(filesStatusText())
                .accessibilityHint(isPreparingFiles ? "Scanning files for comparison" : "File scan ready")
            
            Button(action: applySelectedPlan) {
                Text("Apply Selected")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canApplySelected)
            .accessibilityLabel("Apply selected plan")
            .accessibilityHint("Applies the chosen organization plan to your files")
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .accessibilityLabel("Close comparison dashboard")
        }
        .padding(.horizontal, 16)
        .frame(height: toolbarHeight)
        .background(.ultraThinMaterial)
    }
    
    private var filterSortDropdown: some View {
        Menu {
            Section("Sort By") {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(action: { sortOption = option }) {
                        HStack {
                            Text(option.label)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            
            Section("Filter") {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    Button(action: { filterOption = option }) {
                        HStack {
                            Text(option.label)
                            if filterOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text("Filter")
                    .font(.caption)
            }
            .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
    }
    
    // MARK: - Runs Grid
    
    private var runsGrid: some View {
        GeometryReader { geometry in
            let columns = columnsForWidth(geometry.size.width)
            let showCompact = true
            
            if filteredRuns.isEmpty {
                emptyRunsState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(sortedRuns.prefix(maxRunsAllowed)) { run in
                            RunCardView(
                                run: run,
                                isSelected: orchestrator.selectedRunID == run.id,
                                isCompact: showCompact,
                                onSelect: { orchestrator.selectRun(id: run.id) },
                                onCancel: { orchestrator.cancelRun(id: run.id) },
                                onRetry: { retryRun(run) }
                            )
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(16)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Run grid")
            }
        }
    }
    
    private var emptyRunsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No Runs Yet")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Add a run configuration to start comparing\norganization suggestions from different models.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { showSpecEditor = true }) {
                Label("Add Run", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Add run")
            .accessibilityHint("Opens the run configuration editor")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
    
    private func columnsForWidth(_ width: CGFloat) -> [GridItem] {
        let availableWidth = width - 32
        let minCardWidth: CGFloat = 260
        let maxColumns = 2
        
        let possibleColumns = max(1, min(maxColumns, Int(availableWidth / minCardWidth)))
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: possibleColumns)
    }
    
    // MARK: - Detail Pane
    
    private var detailPane: some View {
        VStack(spacing: 0) {
            if let selectedRun = orchestrator.selectedRun {
                RunDetailView(
                    run: selectedRun,
                    onViewPreview: { handleViewPreview(selectedRun) },
                    onRetry: { retryRun(selectedRun) },
                    onRemove: { orchestrator.removeSpec(id: selectedRun.id) }
                )
            } else {
                emptyDetailState
            }
        }
        .frame(width: detailPaneWidth)
        .background(Color(NSColor.controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run details")
    }
    
    private var emptyDetailState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("Select a Run")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Click on a card to view details")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Computed Properties
    
    private var filteredRuns: [GenerationRun] {
        switch filterOption {
        case .all:
            return orchestrator.runs
        case .running:
            return orchestrator.runs.filter { run in
                if case .running = run.status { return true }
                return false
            }
        case .finished:
            return orchestrator.completedRuns
        case .failed:
            return orchestrator.failedRuns
        }
    }
    
    private var sortedRuns: [GenerationRun] {
        switch sortOption {
        case .newest:
            return filteredRuns.sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
        case .oldest:
            return filteredRuns.sorted { ($0.startTime ?? .distantPast) < ($1.startTime ?? .distantPast) }
        case .provider:
            return filteredRuns.sorted { $0.spec.provider.displayName < $1.spec.provider.displayName }
        case .status:
            return filteredRuns.sorted { statusOrder($0.status) < statusOrder($1.status) }
        }
    }
    
    private var hasRunnableRuns: Bool {
        orchestrator.runs.contains { run in
            if case .queued = run.status { return true }
            if case .failed = run.status { return true }
            return false
        }
    }
    
    private var canApplySelected: Bool {
        guard let selected = orchestrator.selectedRun else { return false }
        if case .finished = selected.status { return true }
        return false
    }
    
    // MARK: - Actions
    
    private func startAllRuns() {
        Task {
            await prepareFilesIfNeeded()
            guard !cachedFiles.isEmpty else { return }
            await orchestrator.startAll(
                files: cachedFiles,
                baseURL: baseURL,
                config: settingsViewModel.config,
                using: organizer
            )
        }
    }
    
    private func retryRun(_ run: GenerationRun) {
        Task {
            await prepareFilesIfNeeded()
            guard !cachedFiles.isEmpty else { return }
            await orchestrator.startRun(
                id: run.id,
                files: cachedFiles,
                baseURL: baseURL,
                config: settingsViewModel.config,
                using: organizer
            )
        }
    }
    
    private func applySelectedPlan() {
        guard let selected = orchestrator.selectedRun,
              let plan = selected.generatedPlan else { return }
        onSelectPlan(plan)
    }
    
    private func handleViewPreview(_ run: GenerationRun) {
        guard let plan = run.generatedPlan else { return }
        onSelectPlan(plan)
    }
    
    private func statusOrder(_ status: GenerationStatus) -> Int {
        switch status {
        case .running: return 0
        case .queued: return 1
        case .finished: return 2
        case .failed: return 3
        case .canceled: return 4
        }
    }

    private func seedDefaultRuns() {
        let provider = settingsViewModel.config.provider
        
        // Use ModelCatalog for dynamic models, fallback to recommendedModels
        let catalogModels = modelCatalog.cachedModels(for: provider)
        let modelIDs: [String]
        if !catalogModels.isEmpty {
            modelIDs = Array(catalogModels.prefix(maxRunsAllowed).map { $0.id })
        } else {
            modelIDs = Array(provider.recommendedModels.prefix(maxRunsAllowed))
        }
        
        let specs = modelIDs.map { model in
            GenerationSpec(
                provider: provider,
                model: model,
                personaID: nil,
                customInstructions: "",
                enableReasoning: false,
                enableDeepScan: false,
                enableStreamingPreview: false
            )
        }
        specs.forEach { orchestrator.addSpec($0) }
        
        // Refresh models from catalog if needed
        if catalogModels.isEmpty {
            Task {
                await ModelCatalog.shared.refresh(provider: provider)
            }
        }
    }

    private func prepareFilesIfNeeded() async {
        guard !isPreparingFiles else { return }
        guard cachedFiles.isEmpty || organizer.scannedFileCount == 0 else { return }
        isPreparingFiles = true
        scanErrorMessage = nil
        let deepScanEnabled = orchestrator.runs.contains { $0.spec.enableDeepScan }
        lastScanUsedDeepScan = deepScanEnabled

        do {
            let scanner = DirectoryScanner()
            let files = try await scanner.scanDirectory(at: baseURL, deepScan: deepScanEnabled)
            await MainActor.run {
                cachedFiles = files
                isPreparingFiles = false
            }
        } catch {
            await MainActor.run {
                scanErrorMessage = error.localizedDescription
                isPreparingFiles = false
            }
        }
    }

    private func filesStatusText() -> String {
        if isPreparingFiles {
            return "Preparing files..."
        }
        if let scanErrorMessage {
            return "Scan failed: \(scanErrorMessage)"
        }
        if cachedFiles.isEmpty {
            return "No files scanned yet"
        }
        return "Ready with \(cachedFiles.count) files"
    }
}

// MARK: - Sort & Filter Options

private enum SortOption: CaseIterable {
    case newest, oldest, provider, status
    
    var label: String {
        switch self {
        case .newest: return "Newest First"
        case .oldest: return "Oldest First"
        case .provider: return "By Provider"
        case .status: return "By Status"
        }
    }
}

private enum FilterOption: CaseIterable {
    case all, running, finished, failed
    
    var label: String {
        switch self {
        case .all: return "All Runs"
        case .running: return "Running"
        case .finished: return "Finished"
        case .failed: return "Failed"
        }
    }
}

// MARK: - RunCardView

struct RunCardView: View {
    let run: GenerationRun
    let isSelected: Bool
    var isCompact: Bool = false
    let onSelect: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    
    @State private var isHovered = false
    
    private var statusInfo: (icon: String, color: Color, label: String) {
        switch run.status {
        case .queued:
            return ("clock", .orange, "Queued")
        case .running(let progress, let stage):
            let pct = Int(progress * 100)
            return ("arrow.triangle.2.circlepath", .blue, stage ?? "Running \(pct)%")
        case .finished:
            return ("checkmark.circle.fill", .green, "Finished")
        case .failed(let message):
            return ("exclamationmark.triangle.fill", .red, message)
        case .canceled:
            return ("xmark.circle", .secondary, "Canceled")
        }
    }
    
    private var isRunning: Bool {
        if case .running = run.status { return true }
        return false
    }
    
    private var isFailed: Bool {
        if case .failed = run.status { return true }
        return false
    }
    
    private var isFinished: Bool {
        if case .finished = run.status { return true }
        return false
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                headerRow
                
                if !isCompact {
                    statusRow
                    
                    if isFinished, let plan = run.generatedPlan {
                        metricsRow(plan: plan)
                    }
                }
                
                actionsRow
            }
            .padding(isCompact ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        }
        .accessibilityAddTraits(.isButton)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .accessibilityLabel("Run \(run.spec.provider.displayName) \(run.spec.model)")
        .accessibilityValue(statusInfo.label)
        .accessibilityHint("Select to view details")
        .accessibilityIdentifier("RunCard_\(run.id.uuidString)")
    }
    
    private var headerRow: some View {
        HStack(spacing: 8) {
            ProviderIcon(provider: run.spec.provider, size: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(run.spec.model)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Text(run.spec.provider.displayName)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            }
            
            Spacer()
            
            if let personaID = run.spec.personaID {
                personaBadge(personaID)
            }
        }
    }
    
    private func personaBadge(_ personaID: String) -> some View {
        Text(personaID)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(isSelected ? .white : .purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color.purple.opacity(0.15))
            )
            .lineLimit(1)
            .accessibilityLabel("Persona \(personaID)")
    }
    
    private var statusRow: some View {
        HStack(spacing: 6) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusInfo.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : statusInfo.color)
            }
            
            Text(statusInfo.label)
                .font(.caption)
                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                .lineLimit(1)
            
            Spacer()
            
            if isRunning, case .running(let progress, _) = run.status {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            }
        }
    }
    
    private func metricsRow(plan: OrganizationPlan) -> some View {
        HStack(spacing: 12) {
            metricPill(icon: "doc.fill", value: "\(plan.totalFiles)")
            metricPill(icon: "folder.fill", value: "\(plan.totalFolders)")
            
            if let stats = plan.generationStats {
                metricPill(icon: "clock", value: String(format: "%.1fs", stats.duration))
                metricPill(icon: "bolt.fill", value: String(format: "%.0f/s", stats.tps))
            }
        }
    }
    
    private func metricPill(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(value)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
    }
    
    private var actionsRow: some View {
        HStack(spacing: 8) {
            Spacer()
            
            if isRunning {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if isFailed {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if isFinished && !isSelected {
                Text("Select")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isFinished && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
            }
        }
    }
    
    private var cardBackground: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
        }
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(borderColor, lineWidth: isSelected || isFailed ? 2 : 1)
    }
    
    private var borderColor: Color {
        if isSelected {
            return .clear
        } else if isFailed {
            return .red.opacity(0.5)
        } else if isHovered {
            return Color.accentColor.opacity(0.4)
        } else {
            return Color.secondary.opacity(0.15)
        }
    }
}

// MARK: - RunDetailView

private struct RunDetailView: View {
    let run: GenerationRun
    let onViewPreview: () -> Void
    let onRetry: () -> Void
    let onRemove: () -> Void
    
    private var isFinished: Bool {
        if case .finished = run.status { return true }
        return false
    }
    
    private var isFailed: Bool {
        if case .failed = run.status { return true }
        return false
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                Divider()
                configurationSection

                if run.spec.enableStreamingPreview {
                    Divider()
                    streamingSection
                }
                
                if isFinished, let plan = run.generatedPlan {
                    Divider()
                    statsSection(plan: plan)
                }
                
                if isFailed, case .failed(let message) = run.status {
                    Divider()
                    errorSection(message: message)
                }
                
                Divider()
                actionsSection
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run details")
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderIcon(provider: run.spec.provider, size: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.spec.provider.displayName)
                        .font(.headline)
                    Text(run.spec.model)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if let personaID = run.spec.personaID {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                    Text("Persona: \(personaID)")
                        .font(.caption)
                }
                .foregroundColor(.purple)
            }
        }
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configuration")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            configRow(label: "Reasoning", value: run.spec.enableReasoning ? "Enabled" : "Disabled")
            configRow(label: "Deep Scan", value: run.spec.enableDeepScan ? "Enabled" : "Disabled")
            configRow(label: "Streaming", value: run.spec.enableStreamingPreview ? "On" : "Off")
            
            if !run.spec.customInstructions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Instructions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(run.spec.customInstructions)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                }
                .accessibilityLabel("Custom instructions")
            }
        }
        .accessibilityElement(children: .contain)
    }
    
    private func configRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var streamingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundColor(.purple)
                Text("Streaming Response")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            StreamingPreviewPane(
                content: run.streamingContent,
                isComplete: run.didCompleteStreaming,
                showAutoscrollToggle: true
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Streaming response")
    }
    
    private func statsSection(plan: OrganizationPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Generation Stats")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                statBox(icon: "doc.fill", value: "\(plan.totalFiles)", label: "Files")
                statBox(icon: "folder.fill", value: "\(plan.totalFolders)", label: "Folders")
            }
            
            if let stats = plan.generationStats {
                HStack(spacing: 16) {
                    statBox(icon: "clock", value: String(format: "%.2fs", stats.duration), label: "Duration")
                    statBox(icon: "bolt.fill", value: String(format: "%.1f", stats.tps), label: "tok/s")
                }
                
                HStack(spacing: 16) {
                    statBox(icon: "number", value: "\(stats.totalTokens)", label: "Tokens")
                    statBox(icon: "timer", value: String(format: "%.0fms", stats.ttft * 1000), label: "TTFT")
                }
            }
            
            if let startTime = run.startTime, let endTime = run.endTime {
                let duration = endTime.timeIntervalSince(startTime)
                Text("Total time: \(String(format: "%.1f", duration))s")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func statBox(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }
    
    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Error")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
            }
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
        }
    }
    
    private var actionsSection: some View {
        VStack(spacing: 10) {
            if isFinished {
                Button(action: onViewPreview) {
                    HStack {
                        Image(systemName: "eye")
                        Text("View Full Preview")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            
            if isFailed {
                Button(action: onRetry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            Button(role: .destructive, action: onRemove) {
                HStack {
                    Image(systemName: "trash")
                    Text("Remove")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Streaming Preview

private struct StreamingPreviewPane: View {
    let content: String
    let isComplete: Bool
    let showAutoscrollToggle: Bool

    @State private var autoscrollEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showAutoscrollToggle {
                Toggle("Auto-scroll", isOn: $autoscrollEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Auto-scroll streaming output")
                    .accessibilityHint("Keeps the latest output in view as it streams")
            }

            ScrollView {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(content.isEmpty ? "Waiting for streaming output..." : content)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("streamBottom")
                    }
                    .onChange(of: content) { _, _ in
                        guard autoscrollEnabled else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("streamBottom", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .accessibilityLabel("Streaming output")
            .accessibilityValue(content.isEmpty ? "No output yet" : "Streaming output")

            if isComplete {
                Text("Streaming complete")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

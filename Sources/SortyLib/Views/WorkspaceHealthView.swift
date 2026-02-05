//
//  WorkspaceHealthView.swift
//  Sorty
//
//  Displays Workspace Health insights with a modern "Liquid Glass" aesthetic
//

import SwiftUI

public struct WorkspaceHealthView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var healthManager: WorkspaceHealthManager
    
    @State private var selectedDirectory: URL?
    @State private var isAnalyzing = false
    @State private var showSettings = false
    @State private var selectedOpportunity: CleanupOpportunity?
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var analysisStage: String?
    @State private var analysisError: String?
    @State private var analysisStartedAt: Date?
    @State private var autoRefreshTask: Task<Void, Never>?
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Directory Selector
                    directorySelector

                    analysisStatusSection
                    
                    if selectedDirectory != nil {
                        // Stats Overview
                        statsOverview
                        
                        // Growth Chart (if data available)
                        if let growth = healthManager.getGrowth(for: selectedDirectory?.path ?? "") {
                            growthSection(growth)
                        }

                        topActionsSection
                        
                        // Cleanup Opportunities
                        opportunitiesSection
                        
                        // Insights
                        insightsSection
                    } else {
                        emptyState
                    }
                }
                .padding(32)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            if showToast, let message = toastMessage {
                ToastOverlay(
                    message: message,
                    actionLabel: "Undo",
                    action: {
                        Task {
                            try? await healthManager.undoLastAction()
                            await refreshAnalysis()
                            showToast = false
                        }
                    },
                    onDismiss: {
                        showToast = false
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        try? await healthManager.undoLastAction()
                        await refreshAnalysis()
                    }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(healthManager.cleanupHistory.isEmpty)
                .help("Undo last cleanup action")
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gear")
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await refreshAnalysis() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(selectedDirectory == nil || isAnalyzing)
            }
        }
        .sheet(isPresented: $showSettings) {
            WorkspaceHealthSettingsView(healthManager: healthManager)
        }
        .onAppear {
            if let dir = appState.selectedDirectory {
                selectedDirectory = dir
                Task { await refreshAnalysis() }
            }
        }
        .onChange(of: healthManager.fileChangeDetected) { _, _ in
            // Auto-refresh on file changes
            autoRefreshTask?.cancel()
            autoRefreshTask = Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await refreshAnalysis()
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Health")
                    .font(.largeTitle.bold())
                
                Text("Monitor clutter, track growth, and discover cleanup opportunities")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Health Score Badge
            if let snapshot = healthManager.snapshots[selectedDirectory?.path ?? ""]?.last {
                healthScoreBadge(snapshot: snapshot)
            }
        }
    }
    
    private func healthScoreBadge(snapshot: DirectorySnapshot) -> some View {
        let score = healthManager.healthScore(for: snapshot.directoryPath)
        let color = scoreColor(score)
        let healthDescription = scoreDescription(score)
        
        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .accessibilityHidden(true)
                
                Text("\(score)")
                    .font(.title.bold())
                    .foregroundColor(color)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Health Score")
            .accessibilityValue("\(score) out of 100, \(healthDescription)")
            .accessibilityAddTraits(.updatesFrequently)
            
            VStack(spacing: 4) {
                Text("Health Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("Based on opportunities, growth, and file age")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace Health Score")
        .accessibilityHint("Shows the overall health of your workspace from 0 to 100")
    }
    
    private func scoreDescription(_ score: Int) -> String {
        switch score {
        case 80...100: return "Excellent"
        case 60..<80: return "Good"
        case 40..<60: return "Fair"
        default: return "Needs Attention"
        }
    }
    
    // MARK: - Directory Selector
    
    private var directorySelector: some View {
        HStack {
            if let dir = selectedDirectory {
                Image(nsImage: NSWorkspace.shared.icon(forFile: dir.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/tmp"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .opacity(0.6)
            }
            
            if let dir = selectedDirectory {
                Text(dir.lastPathComponent)
                    .font(.headline)
                Text(dir.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Select a directory to analyze")
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Choose...") {
                selectDirectory()
            }
            .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
            .accessibilityIdentifier("WorkspaceHealthChooseDirectory")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Analysis Status

    private var analysisStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(analysisStage ?? "Analyzing workspace…")
                        .font(.callout)
                        .foregroundStyle(.primary)

                    Spacer()

                    if let startedAt = analysisStartedAt {
                        Text("Started \(startedAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Analyzing workspace")
            } else if let lastAnalysis = healthManager.lastAnalysisDate {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Last analyzed \(lastAnalysis, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let analysisError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(analysisError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Analysis error: \(analysisError)")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAnalyzing)
    }
    
    // MARK: - Stats Overview
    
    private var statsOverview: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            if let snapshot = healthManager.snapshots[selectedDirectory?.path ?? ""]?.last {
                StatCard(
                    title: "Total Files",
                    value: "\(snapshot.totalFiles)",
                    icon: "doc.fill",
                    color: .blue
                )
                
                StatCard(
                    title: "Total Size",
                    value: snapshot.formattedSize,
                    icon: "externaldrive.fill",
                    color: .purple
                )
                
                StatCard(
                    title: "Unorganized",
                    value: "\(snapshot.unorganizedCount)",
                    icon: "questionmark.folder.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Avg Age",
                    value: snapshot.formattedAverageAge,
                    icon: "clock.fill",
                    color: .gray
                )
            }
        }
    }
    
    // MARK: - Growth Section
    
    private func growthSection(_ growth: DirectoryGrowth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Growth Trends")
                    .font(.headline)
                
                Spacer()
                
                Label(growth.growthRate.rawValue, systemImage: growth.growthRate.icon)
                    .font(.caption)
                    .foregroundColor(growth.growthRate.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(growth.growthRate.color.opacity(0.15), in: Capsule())
            }
            
            HStack(spacing: 24) {
                GrowthMetric(
                    label: "Files",
                    value: "\(growth.fileCountChange >= 0 ? "+" : "")\(growth.fileCountChange)",
                    isPositive: growth.fileCountChange <= 0
                )
                
                GrowthMetric(
                    label: "Size",
                    value: growth.formattedSizeChange,
                    isPositive: growth.sizeChange <= 0
                )
                
                if !growth.topGrowingTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Top Growing Types")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 8) {
                            ForEach(growth.topGrowingTypes.prefix(3), id: \.extension) { item in
                                Text(".\(item.extension)")
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Opportunities Section
    
    private var topActionsSection: some View {
        let topActions = healthManager.topActionableOpportunities(for: selectedDirectory?.path)

        if topActions.isEmpty {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text("Top Actions")
                    .font(.headline)

                LazyVStack(spacing: 8) {
                    ForEach(topActions) { opportunity in
                        TopActionRow(opportunity: opportunity) {
                            if let action = opportunity.action,
                               UserDefaults.standard.bool(forKey: "skipPreview_\(action.rawValue.replacingOccurrences(of: " ", with: "_"))") {
                                Task {
                                    try? await healthManager.performAction(action, for: opportunity)
                                    await refreshAnalysis()
                                    await MainActor.run {
                                        toastMessage = "Action completed"
                                        showToast = true
                                    }
                                }
                            } else {
                                selectedOpportunity = opportunity
                            }
                        }
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    private var opportunitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cleanup Opportunities")
                    .font(.headline)
                
                Spacer()
                
                if !healthManager.activeOpportunities.isEmpty {
                    Text("\(healthManager.activeOpportunities.count) found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            let visibleOpportunities = healthManager.sortedActiveOpportunities(for: selectedDirectory?.path)
            let grouped = Dictionary(grouping: visibleOpportunities, by: { $0.priority })
            let orderedPriorities: [CleanupOpportunity.Priority] = [.critical, .high, .medium, .low]

            if visibleOpportunities.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No cleanup opportunities found. Your workspace looks healthy.")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(orderedPriorities, id: \.self) { priority in
                        if let items = grouped[priority], !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(priority.displayName)
                                    .font(.caption.bold())
                                    .foregroundStyle(priority.color)

                                LazyVStack(spacing: 8) {
                                    ForEach(items) { opportunity in
                                        OpportunityCard(
                                            opportunity: opportunity,
                                            onAction: {
                                                if let action = opportunity.action,
                                                   UserDefaults.standard.bool(forKey: "skipPreview_\(action.rawValue.replacingOccurrences(of: " ", with: "_"))") {
                                                    Task {
                                                        try? await healthManager.performAction(action, for: opportunity)
                                                        await refreshAnalysis()
                                                        await MainActor.run {
                                                            toastMessage = "Action completed"
                                                            showToast = true
                                                        }
                                                    }
                                                } else {
                                                    selectedOpportunity = opportunity
                                                }
                                            },
                                            onDismiss: {
                                                healthManager.dismissOpportunity(opportunity)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(item: $selectedOpportunity) { opportunity in
            CleanupPreviewSheet(
                opportunity: opportunity,
                onConfirm: { selectedFiles in
                    Task {
                        if let action = opportunity.action {
                             // Pass the filtered list of files to the action handler
                             // We might need to update performAction to accept file lists
                             // For now, we'll just perform the action as before but note that
                             // in step 3 we will update the manager to handle specific files
                            try? await healthManager.performAction(action, for: opportunity, selectedFiles: selectedFiles)
                            await refreshAnalysis()
                            
                            // Show toast
                            toastMessage = "Action completed"
                            showToast = true
                        }
                        selectedOpportunity = nil
                    }
                },
                onCancel: {
                    selectedOpportunity = nil
                }
            )
        }
    }
    
    // MARK: - Insights Section
    
    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Insights")
                    .font(.headline)
                
                Spacer()
                
                if !healthManager.insights.isEmpty {
                    Button("Clear All") {
                        healthManager.clearInsights()
                    }
                    .font(.caption)
                }
            }
            
            if healthManager.insights.isEmpty {
                Text("No insights yet. Analyze your workspace to generate insights.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(healthManager.insights.prefix(5)) { insight in
                        InsightRow(insight: insight) {
                            healthManager.markInsightAsRead(insight)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .opacity(0.7)
            
            VStack(spacing: 8) {
                Text("Select a Directory")
                    .font(.title2.bold())
                
                Text("Choose a directory to analyze its health and discover cleanup opportunities")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
            
            Button("Choose Directory") {
                selectDirectory()
            }
            .buttonStyle(.onboardingPill)
            .controlSize(.large)
            .accessibilityIdentifier("WorkspaceHealthEmptyChooseDirectory")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Helpers
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a directory to analyze"
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
            healthManager.startMonitoring(path: url.path)
            Task { await refreshAnalysis() }
        }
    }
    
    private func refreshAnalysis() async {
        guard let dir = selectedDirectory else { return }

        isAnalyzing = true
        analysisStage = "Scanning files…"
        analysisError = nil
        analysisStartedAt = Date()

        defer {
            isAnalyzing = false
            analysisStage = nil
            analysisStartedAt = nil
        }

        let directoryModDate = healthManager.directoryModDate(for: dir.path)
        let cachedFiles = healthManager.cachedFilesIfFresh(path: dir.path, directoryModDate: directoryModDate)
        let ignoredPaths = healthManager.config.ignoredPaths

        let files: [FileItem]
        do {
            if let cachedFiles {
                files = cachedFiles
            } else {
                files = try await Task.detached {
                    try WorkspaceHealthManager.scanFiles(at: dir, ignoredPaths: ignoredPaths)
                }.value
                await MainActor.run {
                    healthManager.updateScanCache(path: dir.path, directoryModDate: directoryModDate, files: files)
                }
            }
        } catch {
            analysisError = error.localizedDescription
            return
        }

        if healthManager.isAnalysisUpToDate(path: dir.path, files: files) {
            return
        }

        analysisStage = "Analyzing workspace…"

        await healthManager.takeSnapshot(at: dir.path, files: files)
        await healthManager.analyzeDirectory(path: dir.path, files: files)
        healthManager.markAnalysisComplete(path: dir.path, files: files)
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

// MARK: - Supporting Views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(color.opacity(0.1), in: Capsule())
                .foregroundStyle(color)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct GrowthMetric: View {
    let label: String
    let value: String
    let isPositive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((isPositive ? Color.green : Color.red).opacity(0.1), in: Capsule())
                .foregroundStyle(isPositive ? .green : .red)
        }
    }
}

private struct OpportunityCard: View {
    let opportunity: CleanupOpportunity
    let onAction: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: opportunity.type.icon)
                .font(.title2)
                .foregroundStyle(opportunity.type.color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(opportunity.type.rawValue)
                        .font(.headline)
                    
                    Text(opportunity.priority.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(opportunity.priority.color.opacity(0.15), in: Capsule())
                        .foregroundColor(opportunity.priority.color)
                }
                
                Text(opportunity.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if opportunity.estimatedSavings > 0 {
                    Text("Potential savings: \(opportunity.formattedSavings)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if opportunity.confidence < 100 {
                    Text("Confidence: \(opportunity.confidence)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                if opportunity.action != nil {
                    Button {
                        onAction()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .accessibilityLabel("Run \(opportunity.type.rawValue) action")
                }
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                .accessibilityLabel("Dismiss \(opportunity.type.rawValue)")
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(opportunity.type.rawValue), priority \(opportunity.priority.displayName)")
    }
}

private struct InsightRow: View {
    let insight: HealthInsight
    let onRead: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: insight.type.icon)
                .foregroundStyle(insight.type.color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.message)
                    .font(.subheadline)
                    .fontWeight(insight.isRead ? .regular : .semibold)
                
                Text(insight.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !insight.isRead {
                Button("Mark Read") {
                    onRead()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Mark insight as read")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct TopActionRow: View {
    let opportunity: CleanupOpportunity
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: opportunity.type.icon)
                .foregroundStyle(opportunity.type.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.type.rawValue)
                    .font(.subheadline.bold())
                Text(opportunity.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Fix") {
                onAction()
            }
            .buttonStyle(.onboardingPill(size: .small))
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top action: \(opportunity.type.rawValue)")
    }
}

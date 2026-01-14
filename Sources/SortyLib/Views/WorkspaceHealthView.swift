//
//  WorkspaceHealthView.swift
//  Sorty
//
//  Displays Workspace Health insights with a modern "Liquid Glass" aesthetic
//

import SwiftUI

public struct WorkspaceHealthView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var healthManager = WorkspaceHealthManager()
    
    @State private var selectedDirectory: URL?
    @State private var isAnalyzing = false
    @State private var showSettings = false
    @State private var selectedOpportunity: CleanupOpportunity?
    @State private var toastMessage: String?
    @State private var showToast = false
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Directory Selector
                    directorySelector
                    
                    if selectedDirectory != nil {
                        // Stats Overview
                        statsOverview
                        
                        // Growth Chart (if data available)
                        if let growth = healthManager.getGrowth(for: selectedDirectory?.path ?? "") {
                            growthSection(growth)
                        }
                        
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
            Task { await refreshAnalysis() }
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
        let score = calculateHealthScore(snapshot: snapshot)
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
            
            Text("Health Score")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
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
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .font(.title2)
            
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
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
    
    private var opportunitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cleanup Opportunities")
                    .font(.headline)
                
                Spacer()
                
                if !healthManager.opportunities.isEmpty {
                    Text("\(healthManager.opportunities.filter { !$0.isDismissed }.count) found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            let visibleOpportunities = healthManager.opportunities.filter { !$0.isDismissed }
            
            if visibleOpportunities.isEmpty {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No cleanup opportunities found. Your workspace is healthy!")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ForEach(visibleOpportunities) { opportunity in
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
                ForEach(healthManager.insights.prefix(5)) { insight in
                    InsightRow(insight: insight) {
                        healthManager.markInsightAsRead(insight)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            
            Text("Select a Directory")
                .font(.title2.bold())
            
            Text("Choose a directory to analyze its health and discover cleanup opportunities")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button("Choose Directory") {
                selectDirectory()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(64)
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
        defer { isAnalyzing = false }
        
        // Scan files
        let files = scanFiles(at: dir)
        
        // Take snapshot and analyze
        await healthManager.takeSnapshot(at: dir.path, files: files)
        await healthManager.analyzeDirectory(path: dir.path, files: files)
    }
    
    private func scanFiles(at url: URL) -> [FileItem] {
        var files: [FileItem] = []
        let fm = FileManager.default
        
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey])
            
            let item = FileItem(
                path: fileURL.path,
                name: fileURL.lastPathComponent,
                extension: fileURL.pathExtension,
                size: Int64(resourceValues?.fileSize ?? 0),
                isDirectory: resourceValues?.isDirectory ?? false,
                creationDate: resourceValues?.creationDate,
                modificationDate: resourceValues?.contentModificationDate
            )
            
            files.append(item)
        }
        
        return files
    }
    
    private func calculateHealthScore(snapshot: DirectorySnapshot) -> Int {
        var score = 100
        
        // Penalize for unorganized files
        let unorganizedRatio = Double(snapshot.unorganizedCount) / max(Double(snapshot.totalFiles), 1)
        score -= Int(unorganizedRatio * 30)
        
        // Penalize for high file count
        if snapshot.totalFiles > 1000 {
            score -= 10
        }
        
        // Penalize for very old average age
        let avgDays = snapshot.averageFileAge / 86400
        if avgDays > 365 {
            score -= 15
        }
        
        // Consider opportunities
        let opportunityCount = healthManager.opportunities.filter { !$0.isDismissed }.count
        score -= min(opportunityCount * 5, 25)
        
        return max(0, min(100, score))
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
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
                .foregroundColor(isPositive ? .green : .red)
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
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                if opportunity.action != nil {
                    Button {
                        onAction()
                    } label: {
                        Image(systemName: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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
            }
        }
        .padding(.vertical, 8)
    }
}

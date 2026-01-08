//
//  WorkspaceHealthView.swift
//  Sorty
//
//  Automated Workspace Health Insights Dashboard
//  Clean, minimal aesthetic focusing on actionable data.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct WorkspaceHealthView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @StateObject private var healthManager = WorkspaceHealthManager()
    @State private var selectedPeriod: TimePeriod = .week
    @State private var selectedDirectory: URL?
    @State private var accessingURL: URL?
    @State private var showingDirectoryPicker = false
    @State private var showingSettings = false
    @State private var isAnalyzing = false
    @State private var analysisError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header & Primary Actions
                HealthHeaderView(
                    healthManager: healthManager,
                    onAnalyze: { showingDirectoryPicker = true },
                    onOpenSettings: { showingSettings = true },
                    isAnalyzing: isAnalyzing
                )
                
                if let error = analysisError {
                    ErrorMessageView(message: error) {
                        analysisError = nil
                    }
                }

                // Primary Metrics Grid
                if !healthManager.opportunities.isEmpty || !healthManager.insights.isEmpty {
                    HealthStatsGrid(healthManager: healthManager)
                }

                // Insights List
                if !healthManager.unreadInsights.isEmpty {
                    InsightsList(healthManager: healthManager)
                }

                // Actionable Opportunities
                if !healthManager.activeOpportunities.isEmpty {
                    OpportunitiesList(
                        healthManager: healthManager,
                        onTakeAction: navigateToOrganize,
                        performAction: { opp, action in
                            try? await healthManager.performAction(action, for: opp)
                            if let url = selectedDirectory { performAnalysis(url) }
                        }
                    )
                }

                // Growth Charts
                if !healthManager.snapshots.isEmpty {
                    GrowthChartSection(
                        healthManager: healthManager,
                        selectedPeriod: $selectedPeriod
                    )
                }
                
                // Empty State
                if healthManager.opportunities.isEmpty && healthManager.insights.isEmpty && healthManager.snapshots.isEmpty {
                    EmptyStateView(onAnalyze: { showingDirectoryPicker = true })
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Workspace Health")
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                selectedDirectory = url
                setDirectory(url)
            }
        }
        .sheet(isPresented: $showingSettings) {
            WorkspaceHealthSettingsView(healthManager: healthManager)
        }
        .onChange(of: healthManager.fileChangeDetected) { _ in
            if let url = selectedDirectory {
                performAnalysis(url)
            }
        }
        .onDisappear {
            healthManager.stopMonitoring()
            accessingURL?.stopAccessingSecurityScopedResource()
            accessingURL = nil
        }
    }
    
    // MARK: - Logic Helpers
    
    private func setDirectory(_ url: URL) {
        if let oldUrl = accessingURL, oldUrl != url {
            oldUrl.stopAccessingSecurityScopedResource()
            accessingURL = nil
        }
        
        if url.startAccessingSecurityScopedResource() {
            accessingURL = url
        }
        
        healthManager.startMonitoring(path: url.path)
        performAnalysis(url)
    }
    
    private func performAnalysis(_ url: URL) {
        isAnalyzing = true
        Task {
            do {
                let files = try await organizer.scanner.scanDirectory(at: url)
                await healthManager.takeSnapshot(at: url.path, files: files)
                await healthManager.analyzeDirectory(path: url.path, files: files)
                isAnalyzing = false
            } catch {
                analysisError = "Analysis failed: \(error.localizedDescription)"
                isAnalyzing = false
            }
        }
    }

    private func navigateToOrganize(_ directoryPath: String) {
        let url = URL(fileURLWithPath: directoryPath)
        if !url.startAccessingSecurityScopedResource() {
             // Continue anyway, user will deal with permissions
        }
        appState.selectedDirectory = url
        appState.currentView = .organize
        organizer.reset()
    }
}

// MARK: - Components

struct HealthHeaderView: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    let onAnalyze: () -> Void
    let onOpenSettings: () -> Void
    let isAnalyzing: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workspace Health")
                    .font(.title2)
                    .fontWeight(.bold)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(healthManager.healthStatus.color)
                        .frame(width: 8, height: 8)
                    Text(healthManager.healthStatus.title)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .accessibilityLabel("Settings")
                }
                .buttonStyle(.plain)
                .controlSize(.large)
                
                Button(action: onAnalyze) {
                    if isAnalyzing {
                        ProgressView().controlSize(.small)
                            .frame(minWidth: 80)
                    } else {
                        Label("Analyze Folder", systemImage: "magnifyingglass")
                    }
                }
                .disabled(isAnalyzing)
                .accessibilityIdentifier("AnalyzeFolderButton")
            }
        }
        .padding(.bottom, 8)
        .overlay(Divider(), alignment: .bottom)
    }
}

struct ErrorMessageView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
            Button("Dismiss", action: onDismiss)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

struct HealthStatsGrid: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Insights",
                value: "\(healthManager.unreadInsights.count)",
                icon: "lightbulb.fill",
                color: .orange
            )
            
            StatCard(
                title: "Opportunities",
                value: "\(healthManager.activeOpportunities.count)",
                icon: "sparkles",
                color: .blue
            )
            
            StatCard(
                title: "Potential Savings",
                value: healthManager.formattedTotalSavings,
                icon: "externaldrive.fill",
                color: .green
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

struct InsightsList: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Insights")
                    .font(.headline)
                Spacer()
                Button("Clear All") { healthManager.clearInsights() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(healthManager.unreadInsights) { insight in
                        HealthInsightCard(insight: insight, healthManager: healthManager)
                    }
                }
                .padding(.vertical, 4) // For focus rings
            }
        }
    }
}

struct HealthInsightCard: View {
    let insight: HealthInsight
    @ObservedObject var healthManager: WorkspaceHealthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: insight.type.icon)
                    .foregroundStyle(insight.type.color)
                Spacer()
                Button(action: { healthManager.markInsightAsRead(insight) }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.message)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(insight.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(width: 240, height: 160)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

struct OpportunitiesList: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    let onTakeAction: (String) -> Void
    let performAction: (CleanupOpportunity, CleanupOpportunity.QuickAction) async -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cleanup Opportunities")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(healthManager.activeOpportunities) { opportunity in
                    OpportunityRow(
                        opportunity: opportunity,
                        onDismiss: { healthManager.dismissOpportunity(opportunity) },
                        onTakeAction: { onTakeAction(opportunity.directoryPath) },
                        performQuickAction: { action in await performAction(opportunity, action) }
                    )
                }
            }
        }
    }
}

struct OpportunityRow: View {
    let opportunity: CleanupOpportunity
    let onDismiss: () -> Void
    let onTakeAction: () -> Void
    let performQuickAction: (CleanupOpportunity.QuickAction) async -> Void
    
    @State private var isPerforming = false
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation(.snappy) { isExpanded.toggle() } }) {
                HStack(spacing: 16) {
                    Image(systemName: opportunity.type.icon)
                        .font(.title3)
                        .foregroundStyle(opportunity.type.color)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opportunity.type.rawValue)
                            .fontWeight(.medium)
                        Text("\(opportunity.fileCount) files • \(opportunity.formattedSavings)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if opportunity.priority == .critical {
                        Text("Critical")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .cornerRadius(4)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider() 
                VStack(alignment: .leading, spacing: 12) {
                    Text(opportunity.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(URL(fileURLWithPath: opportunity.directoryPath).lastPathComponent)
                            .font(.caption)
                            .padding(4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        Button("Dismiss") { onDismiss() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        
                        if let action = opportunity.action {
                            Button {
                                Task {
                                    isPerforming = true
                                    await performQuickAction(action)
                                    isPerforming = false
                                }
                            } label: {
                                if isPerforming {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label(action.rawValue, systemImage: action.icon)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        } else {
                            Button("Take Action") { onTakeAction() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.05))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

struct GrowthChartSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    @Binding var selectedPeriod: TimePeriod
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Growth Analytics")
                    .font(.headline)
                Spacer()
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            ForEach(Array(healthManager.snapshots.keys.sorted()), id: \.self) { path in
                if let snapshots = healthManager.snapshots[path], snapshots.count >= 2 {
                    SimpleChart(
                        path: path,
                        snapshots: snapshots,
                        growth: healthManager.getGrowth(for: path, period: selectedPeriod)
                    )
                }
            }
        }
    }
}

struct SimpleChart: View {
    let path: String
    let snapshots: [DirectorySnapshot]
    let growth: DirectoryGrowth?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .fontWeight(.medium)
                Spacer()
                if let growth = growth {
                    Text(growth.formattedSizeChange)
                        .font(.callout)
                        .foregroundStyle(growth.isGrowing ? .red : .green)
                }
            }
            
            if #available(macOS 14.0, *) {
                Chart(snapshots) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Size", Double(snapshot.totalSize) / 1_000_000_000)
                    )
                    .foregroundStyle(.blue)
                    .symbol(.circle)
                }
                .frame(height: 150)
                .chartYAxisLabel("Size (GB)")
            } else {
                Text("Chart requires macOS 14.0+")
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
    }
}

struct EmptyStateView: View {
    let onAnalyze: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No Active Opportunities")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Your workspace is looking healthy. Select a folder to analyzer deeper.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
            
            Button("Analyze Folder", action: onAnalyze)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [5]))
        )
    }
}

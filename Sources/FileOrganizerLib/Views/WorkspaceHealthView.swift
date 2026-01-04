//
//  WorkspaceHealthView.swift
//  FileOrganizer
//
//  Automated Workspace Health Insights Dashboard
//  Redesigned with "Liquid Glass" Aesthetic for Ideal Optimisation
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - Constants
private enum LiquidConstants {
    static let glassMaterial: Material = .ultraThin
    static let cardCornerRadius: CGFloat = 20
    static let shadowColor = Color.black.opacity(0.1)
    static let shadowRadius: CGFloat = 10
    static let shadowY: CGFloat = 5
}

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

    var body: some View {
        ZStack {
            // Ambient Background
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color.blue.opacity(0.05),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    // Header Section
                    LiquidHeaderSection(
                        healthManager: healthManager,
                        onAnalyze: { showingDirectoryPicker = true },
                        onOpenSettings: { showingSettings = true },
                        isAnalyzing: isAnalyzing
                    )
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

                    // Main Content Grid
                    VStack(spacing: 24) {
                        if !healthManager.opportunities.isEmpty || !healthManager.insights.isEmpty {
                            LiquidQuickStatsRefined(healthManager: healthManager)
                        }

                        if !healthManager.unreadInsights.isEmpty {
                            LiquidInsightsSection(healthManager: healthManager)
                        }

                        if !healthManager.activeOpportunities.isEmpty {
                            LiquidOpportunitiesSection(
                                healthManager: healthManager,
                                onTakeAction: navigateToOrganize,
                                performAction: { opp, action in
                                    try? await healthManager.performAction(action, for: opp)
                                    if let url = selectedDirectory { performAnalysis(url) }
                                }
                            )
                        }

                        if !healthManager.snapshots.isEmpty {
                            LiquidGrowthChartsSection(
                                healthManager: healthManager,
                                selectedPeriod: $selectedPeriod
                            )
                        }
                        
                        // Empty State
                        if healthManager.opportunities.isEmpty && healthManager.insights.isEmpty && healthManager.snapshots.isEmpty {
                            LiquidEmptyState(onAnalyze: { showingDirectoryPicker = true })
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 32)
            }
        }
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

// MARK: - Liquid Header

struct LiquidHeaderSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    let onAnalyze: () -> Void
    let onOpenSettings: () -> Void
    let isAnalyzing: Bool

    var body: some View {
        HStack {
            HStack(spacing: 20) {
                // Animated Ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 10)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .trim(from: 0, to: healthManager.healthScore / 100)
                        .stroke(
                            AngularGradient(
                                colors: [healthManager.healthStatus.color, healthManager.healthStatus.color.opacity(0.6)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: healthManager.healthStatus.color.opacity(0.3), radius: 8)
                    
                    VStack(spacing: 0) {
                        Text("\(Int(healthManager.healthScore))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workspace Health")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(healthManager.healthStatus.title)
                        .font(.headline)
                        .foregroundStyle(healthManager.healthStatus.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(healthManager.healthStatus.color.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.body)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                Button(action: onAnalyze) {
                    HStack {
                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "magnifyingglass")
                            Text("Analyze Folder")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .accentColor.opacity(0.3), radius: 5, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(isAnalyzing)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: LiquidConstants.cardCornerRadius)
                .fill(LiquidConstants.glassMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidConstants.cardCornerRadius)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: LiquidConstants.shadowColor, radius: LiquidConstants.shadowRadius, y: LiquidConstants.shadowY)
        )
        .padding(.horizontal)
    }
}

// MARK: - Liquid Quick Stats

struct LiquidQuickStatsRefined: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    
    var body: some View {
        HStack(spacing: 16) {
            LiquidStatCard(
                title: "Insights",
                value: "\(healthManager.unreadInsights.count)",
                icon: "lightbulb.fill",
                gradient: Gradient(colors: [.yellow.opacity(0.8), .orange])
            )
            
            LiquidStatCard(
                title: "Opportunities",
                value: "\(healthManager.activeOpportunities.count)",
                icon: "sparkles",
                gradient: Gradient(colors: [.green.opacity(0.8), .teal])
            )
            
            LiquidStatCard(
                title: "Savings",
                value: healthManager.formattedTotalSavings,
                icon: "externaldrive.fill",
                gradient: Gradient(colors: [.blue.opacity(0.8), .purple])
            )
        }
    }
}

struct LiquidStatCard: View {
    let title: String
    let value: String
    let icon: String
    let gradient: Gradient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .foregroundStyle(.white)
                }
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(16)
        .background(LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 3)
    }
}

// MARK: - Liquid Insights

struct LiquidInsightsSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Insights", systemImage: "lightbulb.fill")
                    .font(.headline)
                Spacer()
                Button("Clear All") { healthManager.clearInsights() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(healthManager.unreadInsights) { insight in
                        LiquidInsightCard(insight: insight, healthManager: healthManager)
                    }
                }
                .padding(.bottom, 20) // Space for shadow
            }
        }
    }
}

struct LiquidInsightCard: View {
    let insight: HealthInsight
    @ObservedObject var healthManager: WorkspaceHealthManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: insight.type.icon)
                    .font(.title3)
                    .foregroundStyle(insight.type.color)
                    .padding(8)
                    .background(insight.type.color.opacity(0.1))
                    .clipShape(Circle())
                
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
                    .fontWeight(.semibold)
                    .lineLimit(2)
                
                Text(insight.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(width: 240, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.6)) // More opaque for readability
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        )
    }
}

// MARK: - Liquid Opportunities

struct LiquidOpportunitiesSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    let onTakeAction: (String) -> Void
    let performAction: (CleanupOpportunity, CleanupOpportunity.QuickAction) async -> Void
    @State private var expandedId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Cleanup Opportunities", systemImage: "sparkles")
                .font(.headline)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                ForEach(healthManager.activeOpportunities) { opportunity in
                    LiquidOpportunityCard(
                        opportunity: opportunity,
                        isExpanded: expandedId == opportunity.id,
                        onToggle: {
                            withAnimation(.spring()) {
                                expandedId = (expandedId == opportunity.id) ? nil : opportunity.id
                            }
                        },
                        onDismiss: { healthManager.dismissOpportunity(opportunity) },
                        onTakeAction: { onTakeAction(opportunity.directoryPath) },
                        performQuickAction: { action in await performAction(opportunity, action) }
                    )
                }
            }
        }
    }
}

struct LiquidOpportunityCard: View {
    let opportunity: CleanupOpportunity
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDismiss: () -> Void
    let onTakeAction: () -> Void
    let performQuickAction: (CleanupOpportunity.QuickAction) async -> Void
    
    @State private var isPerforming = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: opportunity.type.icon)
                        .font(.headline)
                        .foregroundStyle(opportunity.type.color)
                        .padding(10)
                        .background(opportunity.type.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opportunity.type.rawValue)
                            .font(.body)
                            .fontWeight(.medium)
                        
                        Text("\(opportunity.fileCount) files • \(opportunity.formattedSavings)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if opportunity.priority == .critical {
                        Text("Critical")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
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
            
            // Expanded Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .background(.white.opacity(0.2))
                    
                    Text(opportunity.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(URL(fileURLWithPath: opportunity.directoryPath).lastPathComponent)
                            .font(.caption)
                            .padding(6)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        
                        Spacer()
                        
                        Button("Dismiss") { onDismiss() }
                            .buttonStyle(.plain)
                            .font(.subheadline)
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
                            .controlSize(.regular)
                        } else {
                            Button("Take Action") { onTakeAction() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                        }
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.03))
            }
        }
        .background(LiquidConstants.glassMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: LiquidConstants.shadowColor, radius: 5, y: 2)
    }
}

// MARK: - Liquid Charts

struct LiquidGrowthChartsSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    @Binding var selectedPeriod: TimePeriod
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Growth Analytics", systemImage: "chart.xyaxis.line")
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
            .padding(.horizontal, 4)
            
            ForEach(Array(healthManager.snapshots.keys.sorted()), id: \.self) { path in
                if let snapshots = healthManager.snapshots[path], snapshots.count >= 2 {
                    LiquidDirectoryChart(
                        path: path,
                        snapshots: snapshots,
                        growth: healthManager.getGrowth(for: path, period: selectedPeriod)
                    )
                }
            }
        }
    }
}

struct LiquidDirectoryChart: View {
    let path: String
    let snapshots: [DirectorySnapshot]
    let growth: DirectoryGrowth?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .fontWeight(.medium)
                Spacer()
                if let growth = growth {
                    Text(growth.formattedSizeChange)
                        .font(.subheadline)
                        .foregroundStyle(growth.isGrowing ? .red : .green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (growth.isGrowing ? Color.red : Color.green).opacity(0.1)
                        )
                        .clipShape(Capsule())
                }
            }
            
            if #available(macOS 14.0, *) {
                Chart(snapshots) { snapshot in
                    AreaMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Size", Double(snapshot.totalSize) / 1_000_000_000)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    
                    LineMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Size", Double(snapshot.totalSize) / 1_000_000_000)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
                }
                .frame(height: 180)
                .chartYAxisLabel("Size (GB)")
            } else {
                Text("Chart requires macOS 14.0+")
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
            }
        }
        .padding(20)
        .background(LiquidConstants.glassMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Liquid Empty State

struct LiquidEmptyState: View {
    let onAnalyze: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
            }
            
            Text("Your Workspace is Clean!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Select a folder to analyze deeply and find specific optimization opportunities.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 300)
            
            Button(action: onAnalyze) {
                Text("Analyze Folder")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .shadow(color: .accentColor.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.2), lineWidth: 1))
        )
    }
}

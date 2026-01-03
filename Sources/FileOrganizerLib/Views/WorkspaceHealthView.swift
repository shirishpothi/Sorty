//
//  WorkspaceHealthView.swift
//  FileOrganizer
//
//  Automated Workspace Health Insights Dashboard
//  Tracks clutter growth and cleanup opportunities with visual analytics
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
    @State private var showingDirectoryPicker = false
    @State private var isAnalyzing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HeaderSection(
                    healthManager: healthManager,
                    onAnalyze: {
                        showingDirectoryPicker = true
                    },
                    isAnalyzing: isAnalyzing
                )

                // Quick Stats
                if !healthManager.opportunities.isEmpty || !healthManager.insights.isEmpty {
                    QuickStatsSection(healthManager: healthManager)
                }

                // Insights
                if !healthManager.unreadInsights.isEmpty {
                    InsightsSection(healthManager: healthManager)
                }

                // Cleanup Opportunities
                if !healthManager.activeOpportunities.isEmpty {
                    OpportunitiesSection(healthManager: healthManager) { directoryPath in
                        navigateToOrganize(directoryPath)
                    }
                }

                // Growth Charts
                if !healthManager.snapshots.isEmpty {
                    GrowthChartsSection(
                        healthManager: healthManager,
                        selectedPeriod: $selectedPeriod
                    )
                }

                // Empty State
                if healthManager.opportunities.isEmpty && healthManager.insights.isEmpty && healthManager.snapshots.isEmpty {
                    EmptyStateView(onAnalyze: {
                        showingDirectoryPicker = true
                    })
                }
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Workspace Health")
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedDirectory = url
                    analyzeDirectory(url)
                }
            case .failure(let error):
                DebugLogger.log("Failed to select folder: \(error)")
            }
        }
    }

    private func analyzeDirectory(_ url: URL) {
        isAnalyzing = true

        Task {
            do {
                let files = try await organizer.scanner.scanDirectory(at: url)

                // Take snapshot
                await healthManager.takeSnapshot(at: url.path, files: files)

                // Analyze for opportunities
                await healthManager.analyzeDirectory(path: url.path, files: files)

                isAnalyzing = false
            } catch {
                isAnalyzing = false
                DebugLogger.log("Analysis failed: \(error)")
            }
        }
    }

    private func navigateToOrganize(_ directoryPath: String) {
        let url = URL(fileURLWithPath: directoryPath)
        // Request access to the directory
        guard url.startAccessingSecurityScopedResource() else {
            // If we can't access, just set the directory and let the user handle permissions
            appState.selectedDirectory = url
            appState.currentView = .organize
            organizer.reset()
            return
        }

        appState.selectedDirectory = url
        appState.currentView = .organize
        organizer.reset()
    }
}

// MARK: - Header Section

struct HeaderSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    let onAnalyze: () -> Void
    let isAnalyzing: Bool

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red.gradient)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workspace Health")
                            .font(.title)
                            .fontWeight(.bold)

                        if let lastDate = healthManager.lastAnalysisDate {
                            Text("Last analyzed: \(lastDate.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Button {
                onAnalyze()
            } label: {
                if isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(width: 20, height: 20)
                } else {
                    Label("Analyze Folder", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAnalyzing)
            .accessibilityIdentifier("AnalyzeFolderButton")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
        )
    }
}

// MARK: - Quick Stats Section

struct QuickStatsSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            HealthStatCard(
                title: "Insights",
                value: "\(healthManager.unreadInsights.count)",
                icon: "lightbulb.fill",
                color: .yellow,
                subtitle: "unread"
            )

            HealthStatCard(
                title: "Opportunities",
                value: "\(healthManager.activeOpportunities.count)",
                icon: "sparkles",
                color: .green,
                subtitle: "available"
            )

            HealthStatCard(
                title: "Potential Savings",
                value: healthManager.formattedTotalSavings,
                icon: "externaldrive.fill",
                color: .blue,
                subtitle: "recoverable"
            )

            HealthStatCard(
                title: "Tracked Folders",
                value: "\(healthManager.snapshots.count)",
                icon: "folder.fill",
                color: .purple,
                subtitle: "monitored"
            )
        }
    }
}

struct HealthStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color.gradient)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(color.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Insights Section

struct InsightsSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Insights", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundColor(.yellow)

                Spacer()

                if !healthManager.insights.isEmpty {
                    Button("Clear All") {
                        healthManager.clearInsights()
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("ClearInsightsButton")
                }
            }

            ForEach(healthManager.unreadInsights.prefix(5)) { insight in
                InsightCard(insight: insight, healthManager: healthManager)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct InsightCard: View {
    let insight: HealthInsight
    @ObservedObject var healthManager: WorkspaceHealthManager

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(insight.type.color.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: insight.type.icon)
                    .foregroundColor(insight.type.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.message)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(insight.details)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let prompt = insight.actionPrompt {
                    Text(prompt)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.top, 4)
                }

                Text(insight.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            Spacer()

            Button {
                healthManager.markInsightAsRead(insight)
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

// MARK: - Opportunities Section

struct OpportunitiesSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    @State private var expandedOpportunity: UUID?
    let onTakeAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Cleanup Opportunities", systemImage: "sparkles")
                .font(.headline)
                .foregroundColor(.green)

            ForEach(healthManager.activeOpportunities) { opportunity in
                OpportunityCard(
                    opportunity: opportunity,
                    isExpanded: expandedOpportunity == opportunity.id,
                    onToggle: {
                        withAnimation {
                            if expandedOpportunity == opportunity.id {
                                expandedOpportunity = nil
                            } else {
                                expandedOpportunity = opportunity.id
                            }
                        }
                    },
                    onDismiss: {
                        healthManager.dismissOpportunity(opportunity)
                    },
                    onTakeAction: {
                        onTakeAction(opportunity.directoryPath)
                    }
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct OpportunityCard: View {
    let opportunity: CleanupOpportunity
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDismiss: () -> Void
    let onTakeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(opportunity.type.color.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: opportunity.type.icon)
                        .foregroundColor(opportunity.type.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(opportunity.type.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        PriorityBadge(priority: opportunity.priority)
                    }

                    Text("\(opportunity.fileCount) files • \(opportunity.formattedSavings)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    onToggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(opportunity.description)
                        .font(.body)
                        .foregroundColor(.primary)

                    HStack {
                        Text(URL(fileURLWithPath: opportunity.directoryPath).lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)

                        Spacer()

                        Button("Dismiss") {
                            onDismiss()
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Button("Take Action") {
                            onTakeAction()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(opportunity.priority == .critical ? Color.red.opacity(0.3) : Color.clear, lineWidth: 2)
                )
        )
    }
}

struct PriorityBadge: View {
    let priority: CleanupOpportunity.Priority

    var body: some View {
        Text(priority.displayName)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(priority.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priority.color.opacity(0.1))
            .cornerRadius(4)
    }
}

// MARK: - Growth Charts Section

struct GrowthChartsSection: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    @Binding var selectedPeriod: TimePeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Growth Analytics", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundColor(.blue)

                Spacer()

                Picker("Period", selection: $selectedPeriod) {
                    ForEach(TimePeriod.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .accessibilityIdentifier("GrowthPeriodPicker")
            }

            // Show chart for each tracked directory
            ForEach(Array(healthManager.snapshots.keys.sorted()), id: \.self) { path in
                if let snapshots = healthManager.snapshots[path], snapshots.count >= 2 {
                    DirectoryGrowthChart(
                        path: path,
                        snapshots: snapshots,
                        growth: healthManager.getGrowth(for: path, period: selectedPeriod)
                    )
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

struct DirectoryGrowthChart: View {
    let path: String
    let snapshots: [DirectorySnapshot]
    let growth: DirectoryGrowth?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.blue)

                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if let growth = growth {
                    HStack(spacing: 4) {
                        Image(systemName: growth.growthRate.icon)
                            .foregroundColor(growth.growthRate.color)

                        Text(growth.formattedSizeChange)
                            .font(.caption)
                            .foregroundColor(growth.isGrowing ? .red : .green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(growth.growthRate.color.opacity(0.1))
                    .cornerRadius(6)
                }
            }

            // Size over time chart
            if #available(macOS 14.0, *) {
                Chart(snapshots) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Size", Double(snapshot.totalSize) / 1_000_000_000) // GB
                    )
                    .foregroundStyle(.blue.gradient)

                    AreaMark(
                        x: .value("Date", snapshot.timestamp),
                        y: .value("Size", Double(snapshot.totalSize) / 1_000_000_000)
                    )
                    .foregroundStyle(.blue.opacity(0.1))
                }
                .chartYAxisLabel("Size (GB)")
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5))
                }
                .frame(height: 150)
            } else {
                // Fallback for older macOS
                SimpleBarChart(snapshots: snapshots)
                    .frame(height: 150)
            }

            // File type breakdown
            if let latest = snapshots.last, !latest.filesByExtension.isEmpty {
                FileTypeBreakdown(filesByExtension: latest.filesByExtension)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

struct SimpleBarChart: View {
    let snapshots: [DirectorySnapshot]

    var maxSize: Int64 {
        snapshots.map { $0.totalSize }.max() ?? 1
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(snapshots.suffix(20)) { snapshot in
                    let height = CGFloat(snapshot.totalSize) / CGFloat(maxSize) * geometry.size.height

                    Rectangle()
                        .fill(.blue.gradient)
                        .frame(width: max(geometry.size.width / CGFloat(min(snapshots.count, 20)) - 4, 8), height: max(height, 2))
                }
            }
        }
    }
}

struct FileTypeBreakdown: View {
    let filesByExtension: [String: Int]

    var sortedExtensions: [(String, Int)] {
        filesByExtension
            .sorted { $0.value > $1.value }
            .prefix(6)
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File Types")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                ForEach(sortedExtensions, id: \.0) { ext, count in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForExtension(ext))
                            .frame(width: 8, height: 8)

                        Text(".\(ext)")
                            .font(.caption2)

                        Text("(\(count))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func colorForExtension(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "pdf": return .red
        case "jpg", "jpeg", "png", "gif", "heic": return .purple
        case "mp4", "mov": return .pink
        case "mp3", "wav", "m4a": return .orange
        case "doc", "docx", "txt", "pages": return .blue
        case "xls", "xlsx", "numbers": return .green
        case "zip", "rar": return .brown
        case "swift", "py", "js": return .cyan
        default: return .gray
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let onAnalyze: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("No Health Data Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Analyze a folder to start tracking its health and get cleanup suggestions")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                onAnalyze()
            } label: {
                Label("Analyze a Folder", systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Preview

#Preview {
    WorkspaceHealthView()
        .environmentObject(FolderOrganizer())
        .frame(width: 900, height: 800)
}

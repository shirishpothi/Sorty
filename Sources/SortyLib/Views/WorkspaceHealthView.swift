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
    
    @State private var showSettings = false
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var initialRefreshTask: Task<Void, Never>?
    @State private var refreshTask: Task<Void, Never>?
    @State private var contentOpacity: Double = 0
    @State private var emptyStateHasAppeared = false
    @State private var emptyStateBeamHasAppeared = false
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if selectedDirectory != nil {
                    analyzedWorkspaceContent
                } else {
                    EmptyView()
                }
            }

            VStack {
                HStack {
                    Spacer()
                    workspaceHealthControls
                        .padding(.top, 6)
                        .padding(.trailing, 16)
                }
                Spacer()
            }
            .allowsHitTesting(true)
            .zIndex(10)

            if selectedDirectory == nil {
                ZStack(alignment: .topLeading) {
                    emptyState
                        .padding(32)

                    headerSection
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
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
        .emptyStateWorkflowGradient(isVisible: selectedDirectory == nil)
        .opacity(contentOpacity)
        .sheet(isPresented: $showSettings) {
            WorkspaceHealthSettingsView(healthManager: healthManager)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
            if selectedDirectory == nil, let dir = appState.selectedDirectory {
                selectedDirectory = dir
                scheduleInitialRefresh()
            }
        }
        .onDisappear {
            initialRefreshTask?.cancel()
            autoRefreshTask?.cancel()
            refreshTask?.cancel()
        }
        .onChange(of: healthManager.fileChangeDetected) { _, _ in
            // Auto-refresh on file changes
            autoRefreshTask?.cancel()
            autoRefreshTask = Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                startRefreshAnalysis()
            }
        }
        .navigationTitle("Workspace Health")
    }
    
    // MARK: - Header

    private var selectedDirectory: URL? {
        get { appState.workspaceHealthSelectedDirectory }
        nonmutating set { appState.workspaceHealthSelectedDirectory = newValue }
    }

    private var workspaceHealthControls: some View {
        HStack(spacing: 10) {
            if selectedDirectory != nil {
                LiquidGlassToolbarIconButton(
                    systemImage: "arrow.uturn.backward",
                    help: "Undo last cleanup action",
                    isDisabled: healthManager.cleanupHistory.isEmpty
                ) {
                    Task {
                        try? await healthManager.undoLastAction()
                        await refreshAnalysis()
                    }
                }
            }

            LiquidGlassToolbarIconButton(
                systemImage: "gear",
                help: "Workspace Health settings"
            ) {
                showSettings = true
            }

            if selectedDirectory != nil {
                LiquidGlassToolbarIconButton(
                    systemImage: "arrow.clockwise",
                    help: "Refresh workspace health",
                    isDisabled: appState.workspaceHealthIsAnalyzing
                ) {
                    Task { await refreshAnalysis() }
                }
            }
        }
    }

    private var analyzedWorkspaceContent: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                        .animatedAppearance(delay: 0.03)

                    directorySelector
                        .animatedAppearance(delay: 0.06)

                    opportunitiesSection
                        .animatedAppearance(delay: 0.12)

                    insightsSection
                        .animatedAppearance(delay: 0.15)
                }
                .padding(.leading, 32)
                .padding(.vertical, 32)
                .padding(.trailing, 4)
            }

            rightRail
                .frame(width: 316)
                .padding(.top, 62)
                .padding(.trailing, 24)
                .padding(.bottom, 32)
        }
    }

    private var rightRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                analysisStatusSection
                    .animatedAppearance(delay: 0.09)

                if let snapshot = healthManager.snapshots[selectedDirectory?.path ?? ""]?.last {
                    compactHealthScore(snapshot: snapshot)
                        .animatedAppearance(delay: 0.12)

                    compactStats(snapshot: snapshot)
                        .animatedAppearance(delay: 0.14)
                }

                if let growth = healthManager.getGrowth(for: selectedDirectory?.path ?? "") {
                    compactGrowthSection(growth)
                        .animatedAppearance(delay: 0.16)
                }

                topActionsSection
                    .animatedAppearance(delay: 0.18)
            }
            .padding(.top, 2)
        }
        .scrollIndicators(.hidden)
    }
    
    private var headerSection: some View {
        HStack {
            HStack(spacing: 12) {
                if appState.navigatedFromSettings {
                    GlassyBackButton {
                        HapticFeedbackManager.shared.tap()
                        appState.navigatedFromSettings = false
                        appState.openSettingsWindow(section: .help)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Workspace Health")
                        .font(.largeTitle.bold())

                    Text("Monitor clutter, track growth, and discover cleanup opportunities")
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if selectedDirectory == nil,
               let snapshot = healthManager.snapshots[selectedDirectory?.path ?? ""]?.last {
                healthScoreBadge(snapshot: snapshot)
            }
        }
    }
    
    private func healthScoreBadge(snapshot: DirectorySnapshot) -> some View {
        let score = healthManager.healthScore(for: snapshot.directoryPath)
        let healthDescription = scoreDescription(score)
        let healthColor = healthManager.healthScoreBand(for: score).color
        
        return VStack(spacing: 14) {
            WorkspaceHealthBeamScore(score: score, healthColor: healthColor)
                .accessibilityHidden(true)

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
        .accessibilityValue("\(score) out of 100, \(healthDescription)")
        .accessibilityHint("Shows the overall health of your workspace from 0 to 100")
    }

    private func scoreDescription(_ score: Int) -> String {
        switch score {
        case 80...100: return "Excellent"
        case 60..<80: return "Good"
        default: return "Needs Attention"
        }
    }

    private func compactHealthScore(snapshot: DirectorySnapshot) -> some View {
        let score = healthManager.healthScore(for: snapshot.directoryPath)
        let healthDescription = scoreDescription(score)
        let healthColor = healthManager.healthScoreBand(for: score).color

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                WorkspaceHealthBeamScore(score: score, healthColor: healthColor)
                    .frame(width: 76, height: 76)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(healthDescription)
                        .font(.headline.weight(.semibold))
                    Text("Health score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Based on cleanup opportunities, growth, and file age")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Workspace health score")
        .accessibilityValue("\(score) out of 100, \(healthDescription)")
    }

    private struct WorkspaceHealthBeamScore: View {
        let score: Int
        let healthColor: Color

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .systemLiquidGlassBackground(cornerRadius: 44)

                Text("\(score)")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(healthColor)
                    .shadow(color: healthColor.opacity(0.22), radius: 8, x: 0, y: 2)
            }
            .frame(width: 88, height: 88)
            .overlay {
                ReferenceCircularBeamFallback(
                    accent: healthColor,
                    active: true,
                    includesInteriorGlow: true
                )
            }
        }
    }

    private struct ReferenceCircularBeamFallback: View {
        let accent: Color
        let active: Bool
        let includesInteriorGlow: Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            SwiftUI.TimelineView(.animation(paused: reduceMotion || !active)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let phase = reduceMotion ? 0 : organicPhase(at: time)

                ZStack {
                    if includesInteriorGlow {
                        beamInteriorGlow(phase: phase)
                    }

                    beamStroke(phase: phase, opacity: 0.76, lineWidth: 2.5)
                    beamStroke(phase: -phase * 0.43 + 0.37, opacity: 0.32, lineWidth: 1.5)
                }
                .opacity(active ? 0.88 : 0)
                .animation(.easeOut(duration: 0.6), value: active)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }

        private func organicPhase(at time: TimeInterval) -> TimeInterval {
            (time / 4.2)
                + (sin(time * 0.72) * 0.055)
                + (sin(time * 1.67) * 0.026)
                + (sin(time * 2.31) * 0.012)
        }

        private func beamStroke(phase: TimeInterval, opacity: Double, lineWidth: CGFloat) -> some View {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        stops: beamStops,
                        center: .center,
                        angle: .degrees((phase.truncatingRemainder(dividingBy: 1)) * 360)
                    ),
                    lineWidth: lineWidth
                )
                .opacity(opacity)
        }

        private func beamInteriorGlow(phase: TimeInterval) -> some View {
            Circle()
                .inset(by: 4)
                .fill(
                    AngularGradient(
                        stops: glowStops,
                        center: .center,
                        angle: .degrees((phase.truncatingRemainder(dividingBy: 1)) * 360)
                    )
                )
                .blur(radius: 9)
                .mask {
                    Circle()
                        .strokeBorder(lineWidth: 22)
                        .blur(radius: 7)
                }
        }

        private var beamStops: [Gradient.Stop] {
            [
            .init(color: .clear, location: 0.00),
            .init(color: .clear, location: 0.10),
            .init(color: accent.opacity(0.18), location: 0.17),
            .init(color: accent.opacity(0.68), location: 0.28),
            .init(color: accent.opacity(0.48), location: 0.38),
            .init(color: accent.opacity(0.22), location: 0.50),
            .init(color: .clear, location: 0.62),
            .init(color: .clear, location: 1.00)
            ]
        }

        private var glowStops: [Gradient.Stop] {
            [
            .init(color: .clear, location: 0.00),
            .init(color: accent.opacity(0.05), location: 0.16),
            .init(color: accent.opacity(0.13), location: 0.28),
            .init(color: accent.opacity(0.08), location: 0.40),
            .init(color: .clear, location: 0.62),
            .init(color: .clear, location: 1.00)
            ]
        }
    }

    // MARK: - Directory Selector
    
    private var directorySelector: some View {
        HStack {
            if let dir = selectedDirectory {
                AppKitImageView(
                    image: NSWorkspace.shared.icon(forFile: dir.path),
                    size: CGSize(width: 28, height: 28)
                )
                .frame(width: 28, height: 28)
            } else {
                AppKitImageView(
                    image: NSWorkspace.shared.icon(forFile: "/tmp"),
                    size: CGSize(width: 28, height: 28),
                    opacity: 0.6
                )
                .frame(width: 28, height: 28)
            }
            
            if let dir = selectedDirectory {
                Text(dir.lastPathComponent)
                    .font(.headline)
                PrivacySensitivePathText(path: dir.path)
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
            if appState.workspaceHealthIsAnalyzing {
                HStack(spacing: 10) {
                    SortyGradientLoadingBar(width: 96, height: 8)
                    Text(appState.workspaceHealthAnalysisStage ?? "Analyzing workspace…")
                        .font(.callout)
                        .foregroundStyle(.primary)

                    Spacer()

                    if let startedAt = appState.workspaceHealthAnalysisStartedAt {
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

            if let analysisError = appState.workspaceHealthAnalysisError {
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
        .animation(.easeInOut(duration: 0.2), value: appState.workspaceHealthIsAnalyzing)
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

    private func compactStats(snapshot: DirectorySnapshot) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ], spacing: 10) {
            CompactStatTile(
                title: "Files",
                value: "\(snapshot.totalFiles)",
                icon: "doc.fill",
                color: .blue
            )

            CompactStatTile(
                title: "Size",
                value: snapshot.formattedSize,
                icon: "externaldrive.fill",
                color: .purple
            )

            CompactStatTile(
                title: "Unorganized",
                value: "\(snapshot.unorganizedCount)",
                icon: "questionmark.folder.fill",
                color: .orange
            )

            CompactStatTile(
                title: "Avg age",
                value: snapshot.formattedAverageAge,
                icon: "clock.fill",
                color: .gray
            )
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

    private func compactGrowthSection(_ growth: DirectoryGrowth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Growth", systemImage: growth.growthRate.icon)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(growth.growthRate.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(growth.growthRate.color)
            }

            HStack(spacing: 10) {
                CompactGrowthMetric(
                    label: "Files",
                    value: "\(growth.fileCountChange >= 0 ? "+" : "")\(growth.fileCountChange)",
                    isPositive: growth.fileCountChange <= 0
                )

                CompactGrowthMetric(
                    label: "Size",
                    value: growth.formattedSizeChange,
                    isPositive: growth.sizeChange <= 0
                )
            }

            if !growth.topGrowingTypes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(growth.topGrowingTypes.prefix(4), id: \.extension) { item in
                        Text(".\(item.extension)")
                            .font(.caption2.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Growth trends")
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
                                appState.workspaceHealthSelectedOpportunity = opportunity
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
                                                    appState.workspaceHealthSelectedOpportunity = opportunity
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
        .sheet(item: $appState.workspaceHealthSelectedOpportunity) { opportunity in
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
                        appState.workspaceHealthSelectedOpportunity = nil
                    }
                },
                onCancel: {
                    appState.workspaceHealthSelectedOpportunity = nil
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
                .opacity(emptyStateHasAppeared ? 1 : 0)
                .scaleEffect(emptyStateHasAppeared ? 1 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: emptyStateHasAppeared)
            
            VStack(spacing: 8) {
                Text("Select a Directory")
                    .font(.title2.bold())
                
                Text("Choose a directory to analyze its health and discover cleanup opportunities")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
            .opacity(emptyStateHasAppeared ? 1 : 0)
            .offset(y: emptyStateHasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: emptyStateHasAppeared)
            
            Button("Choose Directory") {
                selectDirectory()
            }
            .buttonStyle(.onboardingPill)
            .onboardingBeamBorder(variant: .featured, active: emptyStateBeamHasAppeared)
            .controlSize(.large)
            .accessibilityIdentifier("WorkspaceHealthEmptyChooseDirectory")
            .opacity(emptyStateHasAppeared ? 1 : 0)
            .offset(y: emptyStateHasAppeared ? 0 : 15)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: emptyStateHasAppeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                emptyStateHasAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                emptyStateBeamHasAppeared = true
            }
        }
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
            startRefreshAnalysis()
        }
    }

    private func scheduleInitialRefresh() {
        initialRefreshTask?.cancel()
        guard selectedDirectory != nil else { return }

        initialRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            startRefreshAnalysis()
        }
    }

    private func startRefreshAnalysis() {
        refreshTask?.cancel()
        refreshTask = Task {
            await refreshAnalysis()
        }
    }

    private func refreshAnalysis() async {
        guard let dir = selectedDirectory else { return }
        guard !appState.workspaceHealthIsAnalyzing else { return }

        appState.workspaceHealthIsAnalyzing = true
        appState.workspaceHealthAnalysisStage = "Scanning files…"
        appState.workspaceHealthAnalysisError = nil
        appState.workspaceHealthAnalysisStartedAt = Date()

        defer {
            appState.workspaceHealthIsAnalyzing = false
            appState.workspaceHealthAnalysisStage = nil
            appState.workspaceHealthAnalysisStartedAt = nil
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
                try Task.checkCancellation()
                await MainActor.run {
                    healthManager.updateScanCache(path: dir.path, directoryModDate: directoryModDate, files: files)
                }
            }
        } catch {
            if Task.isCancelled { return }
            appState.workspaceHealthAnalysisError = error.localizedDescription
            return
        }

        guard !Task.isCancelled else { return }

        if healthManager.isAnalysisUpToDate(path: dir.path, files: files) {
            return
        }

        appState.workspaceHealthAnalysisStage = "Analyzing workspace…"

        await healthManager.takeSnapshot(at: dir.path, files: files)
        await healthManager.analyzeDirectory(path: dir.path, files: files)
        healthManager.markAnalysisComplete(path: dir.path, files: files)
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

private struct CompactStatTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct CompactGrowthMetric: View {
    let label: String
    let value: String
    let isPositive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .foregroundStyle(isPositive ? .green : .red)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isPositive ? Color.green : Color.red).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct OpportunityCard: View {
    let opportunity: CleanupOpportunity
    let onAction: () -> Void
    let onDismiss: () -> Void
    @State private var isActionHovering = false
    
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
                    .onboardingBeamBorder(variant: .featured, active: isActionHovering, size: .small)
                    .onHover { hovering in
                        isActionHovering = hovering
                    }
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
                .buttonStyle(.sortyBordered)
                .controlSize(.small)
                .accessibilityLabel("Mark insight as read")
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct LiquidGlassToolbarIconButton: View {
    let systemImage: String
    let help: String
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            HapticFeedbackManager.shared.selection()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isDisabled ? .tertiary : (isHovered ? .primary : .secondary))
                .frame(width: 38, height: 38)
                .background {
                    Circle()
                        .fill(Color.primary.opacity(isHovered ? 0.075 : 0.035))
                }
                .systemLiquidGlassBackground(cornerRadius: 999)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.46 : 1)
        .help(help)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isDisabled)
    }
}

private struct TopActionRow: View {
    let opportunity: CleanupOpportunity
    let onAction: () -> Void
    @State private var isFixHovering = false

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
            .onboardingBeamBorder(variant: .featured, active: isFixHovering, size: .small)
            .onHover { hovering in
                isFixHovering = hovering
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top action: \(opportunity.type.rawValue)")
    }
}

//
//  ParallelGenerationView.swift
//  Sorty
//
//  Parallel organization generation UI with Cursor-style model comparison
//  Allows users to generate multiple organization suggestions side-by-side
//

import SwiftUI

// MARK: - Parallel Generation Manager

@MainActor
public class ParallelGenerationManager: ObservableObject {
    @Published public var plans: [GeneratedPlan] = []
    @Published public var selectedPlanIndex: Int = 0
    @Published public var isGenerating: Bool = false
    @Published public var generationProgress: [UUID: Double] = [:]
    @Published public var generationErrors: [UUID: String] = [:]
    @Published public var activeGenerations: [ActiveGeneration] = []
    
    private var lastProgressUpdate: [UUID: Date] = [:]
    private static let progressThrottleInterval: TimeInterval = 0.1
    
    public struct GeneratedPlan: Identifiable {
        public let id: UUID
        public var plan: OrganizationPlan
        public let provider: AIProvider
        public let model: String
        public let generatedAt: Date
        public var isLoading: Bool
        public var error: String?
        
        public init(id: UUID = UUID(), plan: OrganizationPlan, provider: AIProvider, model: String, generatedAt: Date = Date(), isLoading: Bool = false, error: String? = nil) {
            self.id = id
            self.plan = plan
            self.provider = provider
            self.model = model
            self.generatedAt = generatedAt
            self.isLoading = isLoading
            self.error = error
        }
    }
    
    public struct ActiveGeneration: Identifiable {
        public let id: UUID
        public let provider: AIProvider
        public let model: String
        public var progress: Double
        
        public init(id: UUID = UUID(), provider: AIProvider, model: String, progress: Double = 0) {
            self.id = id
            self.provider = provider
            self.model = model
            self.progress = progress
        }
    }
    
    public func addActiveGeneration(provider: AIProvider, model: String) -> UUID {
        let id = UUID()
        activeGenerations.append(ActiveGeneration(id: id, provider: provider, model: model))
        return id
    }
    
    public func completeGeneration(id: UUID, plan: OrganizationPlan, provider: AIProvider, model: String) {
        activeGenerations.removeAll { $0.id == id }
        addPlan(plan, provider: provider, model: model)
    }
    
    public func failGeneration(id: UUID, provider: AIProvider, model: String, error: Error) {
        activeGenerations.removeAll { $0.id == id }
        let errorId = UUID()
        generationErrors[errorId] = "\(provider.displayName) \(model): \(error.localizedDescription)"
    }
    
    public var selectedPlan: GeneratedPlan? {
        guard selectedPlanIndex >= 0 && selectedPlanIndex < plans.count else { return nil }
        return plans[selectedPlanIndex]
    }
    
    public var completedGenerationsCount: Int {
        plans.filter { !$0.isLoading }.count
    }
    
    public var totalGenerationsCount: Int {
        plans.count + activeGenerations.count
    }
    
    public var overallProgress: Double {
        guard totalGenerationsCount > 0 else { return 0 }
        let completedProgress = Double(completedGenerationsCount)
        let activeProgress = activeGenerations.reduce(0.0) { $0 + $1.progress }
        return (completedProgress + activeProgress) / Double(totalGenerationsCount)
    }
    
    public init() {}
    
    public func addPlan(_ plan: OrganizationPlan, provider: AIProvider, model: String) {
        let generatedPlan = GeneratedPlan(
            plan: plan,
            provider: provider,
            model: model
        )
        plans.append(generatedPlan)
    }
    
    public func updatePlan(at index: Int, with plan: OrganizationPlan) {
        guard index >= 0 && index < plans.count else { return }
        plans[index].plan = plan
        plans[index] = GeneratedPlan(
            id: plans[index].id,
            plan: plan,
            provider: plans[index].provider,
            model: plans[index].model,
            generatedAt: Date(),
            isLoading: false
        )
    }
    
    public func clearPlans() {
        plans.removeAll()
        selectedPlanIndex = 0
        generationProgress.removeAll()
        generationErrors.removeAll()
        activeGenerations.removeAll()
    }
    
    public func selectPlan(at index: Int) {
        guard index >= 0 && index < plans.count else { return }
        selectedPlanIndex = index
    }
    
    public func cancelGeneration(id: UUID) {
        activeGenerations.removeAll { $0.id == id }
    }
    
    public func cancelAllGenerations() {
        activeGenerations.removeAll()
        isGenerating = false
    }
    
    public func updateProgressThrottled(for id: UUID, progress: Double) {
        let now = Date()
        if let lastUpdate = lastProgressUpdate[id],
           now.timeIntervalSince(lastUpdate) < Self.progressThrottleInterval {
            return
        }
        lastProgressUpdate[id] = now
        generationProgress[id] = progress
        if let index = activeGenerations.firstIndex(where: { $0.id == id }) {
            activeGenerations[index] = ActiveGeneration(
                id: id,
                provider: activeGenerations[index].provider,
                model: activeGenerations[index].model,
                progress: progress
            )
        }
    }
    
    public func updateProgress(for id: UUID, progress: Double) {
        generationProgress[id] = progress
        if let index = activeGenerations.firstIndex(where: { $0.id == id }) {
            activeGenerations[index] = ActiveGeneration(
                id: id,
                provider: activeGenerations[index].provider,
                model: activeGenerations[index].model,
                progress: progress
            )
        }
    }
}

// MARK: - Plan Card View

struct PlanCardView: View {
    let plan: ParallelGenerationManager.GeneratedPlan
    let isSelected: Bool
    let index: Int
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var viewId = UUID()
    
    private var hasError: Bool {
        plan.error != nil
    }
    
    private var totalFilesText: String {
        "\(plan.plan.totalFiles)"
    }
    
    private var totalFoldersText: String {
        "\(plan.plan.totalFolders)"
    }
    
    private var generationStatsFormatted: (tps: String, duration: String)? {
        guard let stats = plan.plan.generationStats else { return nil }
        return (String(format: "%.1f tok/s", stats.tps), String(format: "%.2fs", stats.duration))
    }
    
    private var accessibilityValueText: String {
        if isSelected { return "Selected" }
        if plan.isLoading { return "Loading" }
        if hasError { return "Error" }
        return "Ready"
    }
    
    var body: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Option \(index + 1), \(plan.provider.displayName) using \(plan.model)")
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint("Double tap to select this plan")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
    
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerSection
            modelBadge
            Divider()
                .background(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
            
            if plan.isLoading {
                loadingSkeletonSection
            } else if hasError {
                errorSection
            } else {
                statsSection
                generationStatsSection
            }
        }
        .padding(16)
        .frame(minWidth: 220)
        .background(cardBackground)
        .overlay(cardOverlay)
        .scaleEffect(isHovered && !isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
    }
    
    private var headerSection: some View {
        HStack {
            Text("Option \(index + 1)")
                .font(.headline)
                .foregroundColor(isSelected ? .white : .primary)
            
            Spacer()
            
            if isSelected {
                selectedBadge
            } else if plan.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if hasError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .opacity(0.7)
            }
        }
    }
    
    private var selectedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text("Selected")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.25))
        )
    }
    
    private var modelBadge: some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: plan.provider, size: 16)
            Text(plan.model)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.1))
        )
    }
    
    private var loadingSkeletonSection: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.15))
                .frame(height: 16)
                .shimmer(isLoading: true)
            
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 50, height: 12)
                    .shimmer(isLoading: true)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 50, height: 12)
                    .shimmer(isLoading: true)
            }
        }
    }
    
    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                Text("Generation Failed")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
            }
            
            if let error = plan.error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
    
    private var statsSection: some View {
        HStack(spacing: 16) {
            PlanStatPill(
                icon: "doc.fill",
                value: totalFilesText,
                isSelected: isSelected
            )
            
            PlanStatPill(
                icon: "folder.fill",
                value: totalFoldersText,
                isSelected: isSelected
            )
        }
    }
    
    @ViewBuilder
    private var generationStatsSection: some View {
        if let formatted = generationStatsFormatted {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                Text(formatted.tps)
                    .font(.system(size: 10, design: .monospaced))
                Text("•")
                Text(formatted.duration)
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
        }
    }
    
    private var cardBackground: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.85)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 12, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
        }
    }
    
    private var cardOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(overlayStrokeColor, lineWidth: hasError ? 2 : 1)
    }
    
    private var overlayStrokeColor: Color {
        if hasError {
            return .red.opacity(0.7)
        } else if isSelected {
            return .clear
        } else if isHovered {
            return Color.accentColor.opacity(0.5)
        } else {
            return Color.secondary.opacity(0.2)
        }
    }
}

struct PlanStatPill: View {
    let icon: String
    let value: String
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(isSelected ? .white : .primary)
    }
}

struct ProviderIcon: View {
    let provider: AIProvider
    let size: CGFloat
    
    /// Load provider logo from bundle's Images folder (same as AIProviderSettingsView)
    private var providerImage: Image {
        if provider.usesSystemImage {
            return Image(systemName: provider.logoImageName)
        }
        
        // Try to load from Images folder in bundle
        if let resourceURL = Bundle.module.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // Fallback to asset catalog
        return Image(provider.logoImageName, bundle: .module)
    }
    
    var body: some View {
        providerImage
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

// MARK: - Generation Status Indicator

struct GenerationStatusIndicator: View {
    @ObservedObject var manager: ParallelGenerationManager
    let onCancel: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        if manager.isGenerating && !manager.activeGenerations.isEmpty {
            HStack(spacing: 12) {
                // Status text
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        
                        Text(statusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: geometry.size.width * manager.overallProgress)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: manager.overallProgress)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: 200)
                
                Spacer()
                
                // Cancel button
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Cancel")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isHovered ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
            )
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
        }
    }
    
    private var statusText: String {
        let completed = manager.completedGenerationsCount
        let total = manager.totalGenerationsCount
        return "Generating \(completed + 1) of \(total)..."
    }
}

// MARK: - Plan Comparison Summary

struct PlanComparisonSummary: View {
    let plans: [ParallelGenerationManager.GeneratedPlan]
    let selectedIndex: Int
    
    private var validPlans: [ParallelGenerationManager.GeneratedPlan] {
        plans.filter { !$0.isLoading && $0.error == nil }
    }
    
    var body: some View {
        if validPlans.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Summary")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    // Files comparison
                    comparisonMetric(
                        icon: "doc.fill",
                        title: "Files",
                        values: validPlans.map { $0.plan.totalFiles },
                        selectedIndex: selectedIndex
                    )
                    
                    Divider()
                        .frame(height: 40)
                    
                    // Folders comparison
                    comparisonMetric(
                        icon: "folder.fill",
                        title: "Folders",
                        values: validPlans.map { $0.plan.totalFolders },
                        selectedIndex: selectedIndex
                    )
                    
                    Divider()
                        .frame(height: 40)
                    
                    // Speed comparison
                    speedComparisonMetric
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                )
                
                // Highlight differences
                differencesSection
            }
            .padding(.horizontal)
        }
    }
    
    private func comparisonMetric(icon: String, title: String, values: [Int], selectedIndex: Int) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    Text("\(value)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(index == selectedIndex ? .accentColor : .primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == selectedIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                }
            }
        }
    }
    
    @ViewBuilder
    private var speedComparisonMetric: some View {
        let speeds: [(index: Int, tps: Double)] = validPlans.enumerated().compactMap { index, plan in
            guard let stats = plan.plan.generationStats else { return nil }
            return (index, stats.tps)
        }
        
        if !speeds.isEmpty {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                    Text("Speed")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    ForEach(speeds, id: \.index) { item in
                        Text(String(format: "%.1f", item.tps))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(item.index == selectedIndex ? .accentColor : .primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(item.index == selectedIndex ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var differencesSection: some View {
        let differences = computeDifferences()
        
        if !differences.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(differences, id: \.self) { diff in
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Text(diff)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private func computeDifferences() -> [String] {
        guard validPlans.count >= 2 else { return [] }
        
        var differences: [String] = []
        
        // Compare folders
        let folderCounts = validPlans.enumerated().map { ($0.offset + 1, $0.element.plan.totalFolders) }
        if let maxFolders = folderCounts.max(by: { $0.1 < $1.1 }),
           let minFolders = folderCounts.min(by: { $0.1 < $1.1 }),
           maxFolders.1 != minFolders.1 {
            let diff = maxFolders.1 - minFolders.1
            differences.append("Option \(maxFolders.0) has \(diff) more folder\(diff == 1 ? "" : "s")")
        }
        
        // Compare files
        let fileCounts = validPlans.enumerated().map { ($0.offset + 1, $0.element.plan.totalFiles) }
        if let maxFiles = fileCounts.max(by: { $0.1 < $1.1 }),
           let minFiles = fileCounts.min(by: { $0.1 < $1.1 }),
           maxFiles.1 != minFiles.1 {
            let diff = maxFiles.1 - minFiles.1
            differences.append("Option \(maxFiles.0) organizes \(diff) more file\(diff == 1 ? "" : "s")")
        }
        
        // Compare speed
        let speeds: [(index: Int, tps: Double)] = validPlans.enumerated().compactMap { index, plan in
            guard let stats = plan.plan.generationStats else { return nil }
            return (index + 1, stats.tps)
        }
        if speeds.count >= 2,
           let fastest = speeds.max(by: { $0.tps < $1.tps }),
           let slowest = speeds.min(by: { $0.tps < $1.tps }),
           fastest.tps > slowest.tps * 1.2 {
            differences.append("Option \(fastest.index) was generated faster")
        }
        
        return differences
    }
}

// MARK: - Plan Carousel View (Grid Layout)

struct OrganizationPlanCarousel: View {
    @ObservedObject var manager: ParallelGenerationManager
    let onSelectPlan: (OrganizationPlan) -> Void
    let onGenerateMore: () -> Void
    
    @State private var gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // Toolbar row
            toolbarRow
            
            if manager.plans.isEmpty && !manager.isGenerating && manager.activeGenerations.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Grid layout for side-by-side comparison
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        // Completed plans
                        ForEach(Array(manager.plans.enumerated()), id: \.element.id) { index, plan in
                            PlanCardView(
                                plan: plan,
                                isSelected: index == manager.selectedPlanIndex,
                                index: index,
                                onSelect: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        manager.selectPlan(at: index)
                                        onSelectPlan(plan.plan)
                                    }
                                }
                            )
                        }
                        
                        // Loading placeholders for generating plans
                        ForEach(manager.activeGenerations) { generation in
                            GeneratingPlanCard(
                                provider: generation.provider,
                                model: generation.model,
                                progress: generation.progress,
                                onCancel: {
                                    manager.cancelGeneration(id: generation.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Organization plan comparison")
    }
    
    private var toolbarRow: some View {
        HStack {
            // Options label
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12))
                Text("Comparing \(manager.plans.count + manager.activeGenerations.count) Model\(manager.plans.count + manager.activeGenerations.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.secondary)
            
            Spacer()
            
            if manager.plans.count > 0 {
                Text("\(manager.selectedPlanIndex + 1) of \(manager.plans.count) Selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
            
            // Generate More button
            GenerateMoreButton(
                isGenerating: manager.isGenerating,
                onGenerate: onGenerateMore
            )
        }
        .padding(.horizontal)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 4) {
                Text("No Organization Plans")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Generate your first plan to see AI-powered organization suggestions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onGenerateMore) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("Generate Plan")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("g", modifiers: .command)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Generate More Button

struct GenerateMoreButton: View {
    let isGenerating: Bool
    let onGenerate: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onGenerate) {
            HStack(spacing: 6) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12))
                }
                Text(isGenerating ? "Generating..." : "Generate More")
                    .font(.subheadline)
                
                if !isGenerating {
                    // Keyboard hint
                    Text("G")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.15) : Color.accentColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isGenerating)
            .keyboardShortcut("g", modifiers: .command)
            .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .accessibilityLabel("Generate more organization alternatives")
            }
            }

            // MARK: - Generating Plan Card

struct GeneratingPlanCard: View {
    let provider: AIProvider
    let model: String
    let progress: Double
    let onCancel: () -> Void
    
    @State private var animationPhase: Double = 0
    @State private var isCancelHovered: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with cancel button
            HStack {
                Text("Generating...")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                
                // Cancel button
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(isCancelHovered ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isCancelHovered = hovering
                    }
                }
                .accessibilityLabel("Cancel generation")
            }
            
            // Provider/Model badge
            HStack(spacing: 6) {
                ProviderIcon(provider: provider, size: 14)
                Text(model)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.1))
            )
            
            Divider()
            
            // Shimmer placeholders
            VStack(spacing: 8) {
                shimmerBar(height: 20, delay: 0)
                
                HStack(spacing: 12) {
                    shimmerBar(height: 16, width: 60, delay: 0.1)
                    shimmerBar(height: 16, width: 60, delay: 0.2)
                }
                
                shimmerBar(height: 12, delay: 0.3)
            }
            
            // Progress indicator
            if progress > 0 {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
            }
        }
        .padding(16)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                animationPhase = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating plan with \(provider.displayName) using \(model)")
        .accessibilityValue("Progress \(Int(progress * 100)) percent")
        .accessibilityHint("Double tap to cancel")
    }
    
    private func shimmerBar(height: CGFloat, width: CGFloat? = nil, delay: Double = 0) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.1))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.5)
                    .offset(x: (animationPhase * 1.5 - 0.25 - delay).truncatingRemainder(dividingBy: 1.0) * geometry.size.width * 2 - geometry.size.width * 0.25)
                }
            )
            .clipped()
    }
}

// MARK: - Generate Alternatives Button

struct GenerateAlternativesButton: View {
    let isGenerating: Bool
    let onGenerate: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onGenerate) {
            HStack(spacing: 6) {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                }
                Text(isGenerating ? "Generating..." : "Generate Alternatives")
                    .font(.subheadline)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(isGenerating)
        .opacity(isHovered ? 0.85 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Model Picker for Redo

struct RedoWithModelPicker: View {
    @Binding var isPresented: Bool
    let currentProvider: AIProvider
    let currentModel: String
    let onSelect: (AIProvider, String) -> Void
    
    @StateObject private var modelCatalog = ModelCatalog.shared
    
    @State private var selectedProvider: AIProvider = .openAI
    @State private var selectedModel: String = ""
    @State private var expandedProviders: Set<AIProvider> = []
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var customModelText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    
    private var availableProviders: [AIProvider] {
        AIProvider.allCases.filter { $0.isAvailable }
    }
    
    private var filteredProviders: [AIProvider] {
        if debouncedSearchText.isEmpty {
            return availableProviders
        }
        return availableProviders.filter { provider in
            provider.displayName.localizedCaseInsensitiveContains(debouncedSearchText) ||
            getModelsForProvider(provider).contains { $0.localizedCaseInsensitiveContains(debouncedSearchText) }
        }
    }
    
    private var crossProviderSearchResults: [(provider: AIProvider, models: [ModelInfo])] {
        guard !debouncedSearchText.isEmpty else { return [] }
        return modelCatalog.searchAllProviders(query: debouncedSearchText)
            .filter { $0.provider.isAvailable }
    }
    
    private var hasCrossProviderResults: Bool {
        !crossProviderSearchResults.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search integrated
            headerWithSearch
            
            Divider()
            
            // Provider list with expandable sections
            modelListContent
            
            Divider()
            
            // Selection preview & Actions (OpenRouter-style)
            selectionFooter
        }
        .frame(width: 420, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20)
        .onAppear {
            selectedProvider = currentProvider
            selectedModel = currentModel
            expandedProviders.insert(currentProvider)
            // Always refresh models when picker opens to ensure fresh data
            Task {
                await modelCatalog.refreshAllAvailable(force: true)
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        debouncedSearchText = newValue
                    }
                }
            }
        }
    }
    
    // MARK: - Header with Search
    
    private var headerWithSearch: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Choose Model")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        debouncedSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Model List Content
    
    private var modelListContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Search results when searching
                    if hasCrossProviderResults {
                        searchResultsSection
                    }
                    
                    // Provider sections
                    ForEach(filteredProviders, id: \.self) { provider in
                        ProviderSection(
                            provider: provider,
                            isExpanded: expandedProviders.contains(provider),
                            isCurrentProvider: provider == currentProvider,
                            currentModel: currentModel,
                            selectedProvider: selectedProvider,
                            selectedModel: selectedModel,
                            models: getModelsForProvider(provider),
                            isFetching: modelCatalog.isFetching[provider] ?? false,
                            searchText: debouncedSearchText,
                            onToggleExpand: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    if expandedProviders.contains(provider) {
                                        expandedProviders.remove(provider)
                                    } else {
                                        expandedProviders.insert(provider)
                                        Task {
                                            await modelCatalog.refresh(provider: provider)
                                        }
                                    }
                                }
                            },
                            onSelectModel: { model in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedProvider = provider
                                    selectedModel = model
                                }
                            }
                        )
                        .id(provider)
                        
                        if provider != filteredProviders.last {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                    
                    // Custom model input (collapsed, expandable)
                    customModelSection
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Search Results Section
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search Results")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            ForEach(crossProviderSearchResults, id: \.provider) { result in
                ForEach(result.models.prefix(3)) { model in
                    modelResultRow(provider: result.provider, model: model)
                }
            }
            
            Divider()
                .padding(.top, 8)
        }
    }
    
    private func modelResultRow(provider: AIProvider, model: ModelInfo) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedProvider = provider
                selectedModel = model.id
            }
        } label: {
            HStack(spacing: 10) {
                ProviderIcon(provider: provider, size: 16)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Text(provider.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if selectedProvider == provider && selectedModel == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                (selectedProvider == provider && selectedModel == model.id)
                    ? Color.accentColor.opacity(0.1)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Custom Model Section
    
    private var customModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.top, 8)
            
            Text("Custom Model for \(selectedProvider.displayName)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            
            Text("Enter a model name if it's not listed above")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.horizontal, 16)
            
            HStack(spacing: 8) {
                TextField("Enter model name...", text: $customModelText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                Button {
                    if !customModelText.isEmpty {
                        selectedModel = customModelText
                        customModelText = ""
                    }
                } label: {
                    Text("Use")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(customModelText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Selection Footer
    
    private var selectionFooter: some View {
        VStack(spacing: 12) {
            // Current selection preview
            if !selectedModel.isEmpty {
                HStack(spacing: 10) {
                    ProviderIcon(provider: selectedProvider, size: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedModel)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(selectedProvider.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if selectedProvider == currentProvider && selectedModel == currentModel {
                        Text("Current")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button {
                    onSelect(selectedProvider, selectedModel)
                    isPresented = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                        Text("Regenerate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedModel.isEmpty || (selectedProvider == currentProvider && selectedModel == currentModel))
            }
        }
        .padding()
    }
    
    private func getModelsForProvider(_ provider: AIProvider) -> [String] {
        let catalogModels = modelCatalog.cachedModels(for: provider)
        // Always use ModelCatalog - never fall back to hardcoded models
        return catalogModels.map { $0.id }
    }
}

// MARK: - Provider Section (Expandable)

struct ProviderSection: View {
    let provider: AIProvider
    let isExpanded: Bool
    let isCurrentProvider: Bool
    let currentModel: String
    let selectedProvider: AIProvider
    let selectedModel: String
    let models: [String]
    let isFetching: Bool
    let searchText: String
    let onToggleExpand: () -> Void
    let onSelectModel: (String) -> Void
    
    @State private var isHeaderHovered: Bool = false
    
    private var filteredModels: [String] {
        if searchText.isEmpty {
            return models
        }
        return models.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Provider header
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Provider logo
                    ZStack {
                        Circle()
                            .fill(isCurrentProvider ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                            .frame(width: 36, height: 36)
                        
                        ProviderIcon(provider: provider, size: 18)
                            .foregroundColor(isCurrentProvider ? .accentColor : .primary)
                    }
                    
                    // Provider name
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            
                            if isCurrentProvider {
                                Text("Current")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.accentColor.opacity(0.1)))
                            }
                        }
                        
                        Text("\(models.count) models available")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isHeaderHovered ? Color.secondary.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHeaderHovered = hovering
                }
            }
            
            // Expanded models list
            if isExpanded {
                VStack(spacing: 0) {
                    if isFetching {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.leading, 52)
                    } else if filteredModels.isEmpty {
                        Text("No models found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                            .padding(.leading, 52)
                    } else {
                        // Limit displayed models to prevent performance issues
                        let displayedModels = Array(filteredModels.prefix(50))
                        
                        ForEach(displayedModels, id: \.self) { model in
                            ModelRow(
                                model: model,
                                isSelected: selectedProvider == provider && selectedModel == model,
                                isDefault: model == provider.defaultModel,
                                isCurrent: isCurrentProvider && model == currentModel,
                                onSelect: { onSelectModel(model) }
                            )
                        }
                        
                        if filteredModels.count > 50 {
                            Text("+ \(filteredModels.count - 50) more models (use search to find)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.leading, 52)
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }
}

// MARK: - Model Row

struct ModelRow: View {
    let model: String
    let isSelected: Bool
    let isDefault: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Indent spacer
                Color.clear
                    .frame(width: 36)
                
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
                
                // Model name
                Text(model)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                // Badges
                HStack(spacing: 4) {
                    if isDefault {
                        Text("Default")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.1)))
                    }
                    
                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.1)))
                    }
                }
                
                Spacer()
                
                // Checkmark for selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isHovered ? Color.secondary.opacity(0.05) :
                (isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Legacy Model Provider Card (kept for QuickModelPicker compatibility)

struct ModelProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                // Provider icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
                        .frame(width: 44, height: 44)
                    
                    ProviderIcon(provider: provider, size: 24)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                }
                
                // Provider name
                Text(provider.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                
                // Current indicator
                if isCurrent {
                    Text("Current")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.1)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.3) : Color.clear), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.02 : 1.0)
    }
}

// MARK: - Quick Model Picker (Inline)

struct QuickModelPicker: View {
    @Binding var isExpanded: Bool
    let availableProviders: [AIProvider]
    let onSelectProvider: (AIProvider) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12))
                    Text("Different Model")
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.purple.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableProviders, id: \.self) { provider in
                            QuickProviderButton(provider: provider) {
                                onSelectProvider(provider)
                                withAnimation {
                                    isExpanded = false
                                }
                            }
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }
}

struct QuickProviderButton: View {
    let provider: AIProvider
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                ProviderIcon(provider: provider, size: 14)
                Text(provider.displayName)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered ? 1.03 : 1.0)
    }
}

// MARK: - Multi-Model Selection Sheet (For Parallel Generation)

/// Sheet for selecting multiple models to run in parallel
struct MultiModelSelectionSheet: View {
    @Binding var isPresented: Bool
    let onSelectModels: ([(provider: AIProvider, model: String)]) -> Void
    let currentProvider: AIProvider
    let currentModel: String
    
    @StateObject private var modelCatalog = ModelCatalog.shared
    @State private var selectedModels: Set<ModelSelection> = []
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var expandedProviders: Set<AIProvider> = []
    @State private var isLoading: Bool = false
    
    struct ModelSelection: Hashable, Identifiable {
        let provider: AIProvider
        let model: String
        var id: String { "\(provider.rawValue):\(model)" }
    }
    
    private var availableProviders: [AIProvider] {
        AIProvider.allCases.filter { $0.isAvailable }
    }
    
    private var filteredProviders: [AIProvider] {
        if debouncedSearchText.isEmpty {
            return availableProviders
        }
        return availableProviders.filter { provider in
            provider.displayName.localizedCaseInsensitiveContains(debouncedSearchText) ||
            getModelsForProvider(provider).contains { $0.localizedCaseInsensitiveContains(debouncedSearchText) }
        }
    }
    
    private var crossProviderSearchResults: [(provider: AIProvider, models: [ModelInfo])] {
        guard !debouncedSearchText.isEmpty else { return [] }
        return modelCatalog.searchAllProviders(query: debouncedSearchText)
            .filter { $0.provider.isAvailable }
    }
    
    private var hasCrossProviderResults: Bool {
        !crossProviderSearchResults.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            headerWithSearch
            
            Divider()
            
            // Model list content
            modelListContent
            
            Divider()
            
            // Footer with selection summary and actions
            selectionFooter
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20)
        .onAppear {
            // Initialize with current model selected
            selectedModels.insert(ModelSelection(provider: currentProvider, model: currentModel))
            expandedProviders.insert(currentProvider)
            
            // Refresh all models
            isLoading = true
            Task {
                await modelCatalog.refreshAllAvailable()
                await MainActor.run {
                    isLoading = false
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        debouncedSearchText = newValue
                    }
                }
            }
        }
    }
    
    // MARK: - Header with Search
    
    private var headerWithSearch: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Select Models to Compare")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        debouncedSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Model List Content
    
    private var modelListContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                    } else {
                        // Search results when searching
                        if hasCrossProviderResults {
                            searchResultsSection
                        }
                        
                        // Provider sections
                        ForEach(filteredProviders, id: \.self) { provider in
                            MultiModelProviderSection(
                                provider: provider,
                                isExpanded: expandedProviders.contains(provider),
                                selectedModels: selectedModels,
                                models: getModelsForProvider(provider),
                                isFetching: modelCatalog.isFetching[provider] ?? false,
                                searchText: debouncedSearchText,
                                onToggleExpand: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        if expandedProviders.contains(provider) {
                                            expandedProviders.remove(provider)
                                        } else {
                                            expandedProviders.insert(provider)
                                            Task {
                                                await modelCatalog.refresh(provider: provider)
                                            }
                                        }
                                    }
                                },
                                onToggleModel: { model in
                                    let selection = ModelSelection(provider: provider, model: model)
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if selectedModels.contains(selection) {
                                            selectedModels.remove(selection)
                                        } else {
                                            selectedModels.insert(selection)
                                        }
                                    }
                                }
                            )
                            .id(provider)
                            
                            if provider != filteredProviders.last {
                                Divider()
                                    .padding(.leading, 48)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    // MARK: - Search Results Section
    
    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Search Results")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            
            ForEach(crossProviderSearchResults, id: \.provider) { result in
                ForEach(result.models.prefix(5)) { model in
                    multiModelResultRow(provider: result.provider, model: model)
                }
            }
            
            Divider()
                .padding(.top, 8)
        }
    }
    
    private func multiModelResultRow(provider: AIProvider, model: ModelInfo) -> some View {
        let selection = ModelSelection(provider: provider, model: model.id)
        let isSelected = selectedModels.contains(selection)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isSelected {
                    selectedModels.remove(selection)
                } else {
                    selectedModels.insert(selection)
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                
                ProviderIcon(provider: provider, size: 16)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                    Text(provider.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                (isSelected ? Color.accentColor : Color.clear)
                    .opacity(isSelected ? 0.1 : 1.0)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Selection Footer
    
    private var selectionFooter: some View {
        VStack(spacing: 12) {
            // Selected models summary
            if !selectedModels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Models (\(selectedModels.count))")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedModels.sorted(by: { $0.id < $1.id }), id: \.id) { selection in
                                HStack(spacing: 6) {
                                    ProviderIcon(provider: selection.provider, size: 14)
                                    Text(selection.model)
                                        .font(.system(size: 11))
                                    Button {
                                        _ = withAnimation {
                                            selectedModels.remove(selection)
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .opacity(0.1)
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                        .opacity(0.05)
                )
            }
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button {
                    let models = Array(selectedModels).map { (provider: $0.provider, model: $0.model) }
                    onSelectModels(models)
                    isPresented = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text("Generate \(selectedModels.count) Model\(selectedModels.count == 1 ? "" : "s")")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedModels.isEmpty)
            }
        }
        .padding()
    }
    
    private func getModelsForProvider(_ provider: AIProvider) -> [String] {
        let catalogModels = modelCatalog.cachedModels(for: provider)
        if !catalogModels.isEmpty {
            return catalogModels.map { $0.id }
        }
        // Don't fall back to hardcoded - return empty if catalog is empty
        return []
    }
}

// MARK: - Multi-Model Provider Section

struct MultiModelProviderSection: View {
    let provider: AIProvider
    let isExpanded: Bool
    let selectedModels: Set<MultiModelSelectionSheet.ModelSelection>
    let models: [String]
    let isFetching: Bool
    let searchText: String
    let onToggleExpand: () -> Void
    let onToggleModel: (String) -> Void
    
    @State private var isHeaderHovered: Bool = false
    
    private var filteredModels: [String] {
        if searchText.isEmpty {
            return models
        }
        return models.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Provider header
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Provider logo
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.05))
                            .frame(width: 36, height: 36)
                        
                        ProviderIcon(provider: provider, size: 18)
                            .foregroundColor(.primary)
                    }
                    
                    // Provider name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text("\(models.count) models available")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isHeaderHovered ? Color.secondary.opacity(0.05) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isHeaderHovered = hovering
                }
            }
            
            // Expanded models list
            if isExpanded {
                VStack(spacing: 0) {
                    if isFetching {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.leading, 52)
                    } else if filteredModels.isEmpty {
                        Text("No models found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                            .padding(.leading, 52)
                    } else {
                        let displayedModels = Array(filteredModels.prefix(50))
                        
                        ForEach(displayedModels, id: \.self) { model in
                            let selection = MultiModelSelectionSheet.ModelSelection(provider: provider, model: model)
                            let isSelected = selectedModels.contains(selection)
                            
                            MultiModelRow(
                                model: model,
                                isSelected: isSelected,
                                onToggle: { onToggleModel(model) }
                            )
                        }
                        
                        if filteredModels.count > 50 {
                            Text("+ \(filteredModels.count - 50) more models (use search to find)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                                .padding(.leading, 52)
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }
}

// MARK: - Multi-Model Row

struct MultiModelRow: View {
    let model: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // Indent spacer
                Color.clear
                    .frame(width: 36)
                
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                }
                
                // Model name
                Text(model)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isHovered {
                        Color.secondary.opacity(0.05)
                    } else if isSelected {
                        Color.accentColor.opacity(0.05)
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Quick Add Model Sheet (Provider-First Selection)

/// A two-step model selection sheet for quick model addition: first select provider, then select model
struct QuickAddModelSheet: View {
    @Binding var isPresented: Bool
    let onAddModel: (AIProvider, String) -> Void
    
    @StateObject private var modelCatalog = ModelCatalog.shared
    
    // Step tracking
    enum SelectionStep {
        case selectProvider
        case selectModel
    }
    
    @State private var currentStep: SelectionStep = .selectProvider
    @State private var selectedProvider: AIProvider?
    @State private var selectedModel: String = ""
    @State private var customModelText: String = ""
    @State private var isTestingConnection: Bool = false
    @State private var testConnectionResult: (success: Bool, message: String)?
    @State private var searchText: String = ""
    
    private var availableProviders: [AIProvider] {
        AIProvider.allCases.filter { $0.isAvailable }
    }
    
    private var modelsForSelectedProvider: [String] {
        guard let provider = selectedProvider else { return [] }
        // Always use ModelCatalog - never fall back to hardcoded models
        let catalogModels = modelCatalog.cachedModels(for: provider)
        return catalogModels.map { $0.id }
    }
    
    private var filteredModels: [String] {
        if searchText.isEmpty {
            return modelsForSelectedProvider
        }
        return modelsForSelectedProvider.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader
            
            Divider()
            
            // Content based on step
            switch currentStep {
            case .selectProvider:
                providerSelectionView
            case .selectModel:
                modelSelectionView
            }
            
            Divider()
            
            // Footer with actions
            sheetFooter
        }
        .frame(width: 440, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 20)
    }
    
    // MARK: - Header
    
    private var sheetHeader: some View {
        VStack(spacing: 8) {
            HStack {
                // Step indicator
                HStack(spacing: 8) {
                    ParallelStepIndicator(number: 1, title: "Provider", isActive: currentStep == .selectProvider, isComplete: selectedProvider != nil)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    ParallelStepIndicator(number: 2, title: "Model", isActive: currentStep == .selectModel, isComplete: !selectedModel.isEmpty)
                }
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            
            Text("Add Model to Multi-Model View")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Provider Selection
    
    private var providerSelectionView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(availableProviders, id: \.self) { provider in
                    ParallelProviderCard(
                        provider: provider,
                        isSelected: selectedProvider == provider,
                        onSelect: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedProvider = provider
                            }
                            Task {
                                await modelCatalog.refresh(provider: provider)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Model Selection
    
    private var modelSelectionView: some View {
        VStack(spacing: 0) {
            // Provider header with back button
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        currentStep = .selectProvider
                        selectedModel = ""
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                }
                .buttonStyle(.plain)
                
                if let provider = selectedProvider {
                    ProviderIcon(provider: provider, size: 24)
                    Text(provider.displayName)
                        .font(.headline)
                }
                
                Spacer()
                
                // Search
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    TextField("Search models...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .frame(width: 160)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Model list
            ScrollView {
                LazyVStack(spacing: 0) {
                    if modelCatalog.isFetching[selectedProvider ?? .openAI] == true {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading models...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    } else if filteredModels.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 8) {
                            Text("No models match '\(searchText)'")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Try using a custom model name below")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .padding()
                    } else {
                        ForEach(filteredModels.prefix(50), id: \.self) { model in
                            ParallelModelRow(
                                model: model,
                                isSelected: selectedModel == model,
                                isDefault: model == selectedProvider?.defaultModel,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedModel = model
                                    }
                                }
                            )
                        }
                        
                        if filteredModels.count > 50 {
                            Text("+ \(filteredModels.count - 50) more (use search)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    
                    // Custom model section
                    customModelInputSection
                }
            }
        }
    }
    
    // MARK: - Custom Model Input
    
    private var customModelInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.vertical, 8)
            
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 11))
                Text("Custom Model")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            
            Text("Can't find your model? Enter the name manually.")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.horizontal, 16)
            
            HStack(spacing: 8) {
                TextField("Model name (e.g., gpt-4-turbo)", text: $customModelText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                Button {
                    if !customModelText.isEmpty {
                        selectedModel = customModelText
                        customModelText = ""
                    }
                } label: {
                    Text("Use")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(customModelText.isEmpty)
            }
            .padding(.horizontal, 16)
            
            // Test connection result
            if let result = testConnectionResult {
                HStack(spacing: 6) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    Text(result.message)
                        .font(.caption)
                        .foregroundColor(result.success ? .green : .red)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Footer
    
    private var sheetFooter: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            
            Spacer()
            
            if currentStep == .selectProvider {
                Button {
                    if selectedProvider != nil {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            currentStep = .selectModel
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProvider == nil)
            } else {
                Button {
                    if let provider = selectedProvider, !selectedModel.isEmpty {
                        onAddModel(provider, selectedModel)
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add Model")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedProvider == nil || selectedModel.isEmpty)
            }
        }
        .padding()
    }
}

// MARK: - Step Indicator (Parallel Generation)

private struct ParallelStepIndicator: View {
    let number: Int
    let title: String
    let isActive: Bool
    let isComplete: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.accentColor : (isComplete ? Color.green : Color.secondary.opacity(0.2)))
                    .frame(width: 20, height: 20)
                
                if isComplete && !isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isActive ? .white : .secondary)
                }
            }
            
            Text(title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }
}

// MARK: - Provider Selection Card (Parallel Generation)

private struct ParallelProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        .frame(width: 48, height: 48)
                    
                    ProviderIcon(provider: provider, size: 26)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                }
                
                Text(provider.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                
                if !provider.typicallyRequiresAPIKey {
                    Text("No API key needed")
                        .font(.system(size: 9))
                        .foregroundColor(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.15)), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
    }
}

// MARK: - Model Selection Row (Parallel Generation)

private struct ParallelModelRow: View {
    let model: String
    let isSelected: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 10, height: 10)
                    }
                }
                
                // Model name
                Text(model)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                // Default badge
                if isDefault {
                    Text("Default")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.12)))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isHovered ? Color.secondary.opacity(0.05) :
                (isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

//
//  OrganizationCompleteView.swift
//  Sorty
//
//  A dedicated completion view component for the organization workflow
//

import SwiftUI

struct OrganizationCompleteView: View {
    let stats: GenerationStats?
    let totalFiles: Int
    let totalFolders: Int
    let directoryURL: URL
    
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    
    @State private var iconAppeared = false
    @State private var ringExpanded = false
    @State private var titleAppeared = false
    @State private var timeSavedAppeared = false
    @State private var summaryAppeared = false
    @State private var buttonsAppeared = false
    @State private var historyLinkAppeared = false
    @State private var showParticles = false
    
    @State private var displayedFiles = 0
    @State private var displayedFolders = 0
    @State private var countUpTask: Task<Void, Never>?
    
    private var shouldShowStorageSuggestion: Bool {
        totalFiles >= 50 && storageLocationsManager.enabledLocations.isEmpty
    }
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.1))
                                .frame(width: 100, height: 100)
                                .scaleEffect(iconAppeared ? 1 : 0.5)
                                .opacity(iconAppeared ? 1 : 0)
                            
                            Circle()
                                .stroke(Color.green.opacity(ringExpanded ? 0 : 0.5), lineWidth: 3)
                                .frame(width: 100, height: 100)
                                .scaleEffect(ringExpanded ? 2 : 1)
                            
                            ZStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 58, height: 58)
                                
                                Image(systemName: "checkmark")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .scaleEffect(iconAppeared ? 1 : 0.3)
                            
                            if showParticles {
                                ConfettiParticlesView()
                            }
                        }
                        
                        VStack(spacing: 8) {
                            Text("Organization Complete")
                                .font(.title.bold())
                                .opacity(titleAppeared ? 1 : 0)
                                .offset(y: titleAppeared ? 0 : 10)
                            
                            Text("Successfully organized your files into a clean structure.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .opacity(titleAppeared ? 1 : 0)
                                .offset(y: titleAppeared ? 0 : 10)
                            
                            let effectiveTimeSaved: TimeInterval = {
                                if let stats = stats, stats.estimatedTimeSaved > 0 {
                                    return stats.estimatedTimeSaved
                                }
                                return Double(totalFiles) * 4.0
                            }()
                            
                            if effectiveTimeSaved > 0 {
                                HStack(spacing: 6) {
                                    Image(systemName: "hourglass.badge.plus")
                                        .foregroundStyle(.blue)
                                    Text("You saved approximately **\(timeSavedString(effectiveTimeSaved))** of manual work!")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                                .opacity(timeSavedAppeared ? 1 : 0)
                                .offset(y: timeSavedAppeared ? 0 : 10)
                            }
                        }
                    }
                    
                    HStack(spacing: 40) {
                        SummaryStatItem(
                            value: "\(displayedFiles)",
                            label: totalFiles == 1 ? "File Moved" : "Files Moved",
                            icon: "doc.on.doc.fill",
                            color: .blue
                        )
                        
                        SummaryStatItem(
                            value: "\(displayedFolders)",
                            label: totalFolders == 1 ? "Folder Created" : "Folders Created",
                            icon: "folder.fill.badge.plus",
                            color: .purple
                        )
                    }
                    .padding(24)
                    .frame(maxWidth: 420)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                    .opacity(summaryAppeared ? 1 : 0)
                    .offset(y: summaryAppeared ? 0 : 30)
                    
                    if shouldShowStorageSuggestion {
                        CompletionFeatureSuggestionCard(
                            icon: "externaldrive.fill",
                            title: "Route large runs to preferred destinations",
                            description: "Add storage locations to send future results directly into archive or project folders.",
                            actionTitle: "Set Up Locations"
                        ) {
                            HapticFeedbackManager.shared.tap()
                            withAnimation(.pageTransition) {
                                appState.currentView = .storageLocations
                            }
                        }
                        .frame(maxWidth: 560)
                        .opacity(summaryAppeared ? 1 : 0)
                        .offset(y: summaryAppeared ? 0 : 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    VStack(spacing: 12) {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            NSWorkspace.shared.open(directoryURL)
                        } label: {
                            Label("View in Finder", systemImage: "folder.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.sortyPrimary(size: .large))
                        .onHover { hovering in
                            if hovering {
                                HapticFeedbackManager.shared.selection()
                            }
                        }
                        .help("Open the organized folder in Finder")
                        .accessibilityHint("Shows your organized files in Finder")
                        
                        HStack(spacing: 12) {
                            Button {
                                HapticFeedbackManager.shared.tap()
                                undoLastOrganization()
                            } label: {
                                Label("Undo", systemImage: "arrow.uturn.backward")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.sortySecondary(size: .regular))
                            .onHover { hovering in
                                if hovering {
                                    HapticFeedbackManager.shared.selection()
                                }
                            }
                            .help("Undo the latest organization for this folder")
                            .accessibilityHint("Restores files from the most recent successful run")
                            
                            Button {
                                HapticFeedbackManager.shared.tap()
                                withAnimation(.pageTransition) {
                                    appState.selectedDirectory = nil
                                    organizer.reset()
                                }
                            } label: {
                                Label("Organize Another", systemImage: "plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.sortySecondary(size: .regular))
                            .onHover { hovering in
                                if hovering {
                                    HapticFeedbackManager.shared.selection()
                                }
                            }
                            .help("Choose another folder to organize")
                            .accessibilityHint("Returns to folder selection")
                        }
                    }
                    .frame(maxWidth: 560)
                    .opacity(buttonsAppeared ? 1 : 0)
                    .offset(y: buttonsAppeared ? 0 : 20)
                    
                    Button {
                        HapticFeedbackManager.shared.tap()
                        appState.currentView = .history
                    } label: {
                        Label("View History", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering {
                            HapticFeedbackManager.shared.selection()
                        }
                    }
                    .help("Review this run and previous organization sessions")
                    .accessibilityHint("Opens organization history")
                    .padding(.top, 8)
                    .opacity(historyLinkAppeared ? 1 : 0)
                    .offset(y: historyLinkAppeared ? 0 : 10)
                    
                    if let stats = stats, settingsViewModel.config.showStatsForNerds {
                        OrganizationResultView(stats: stats)
                            .padding(.horizontal, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: 640)
                .frame(minHeight: proxy.size.height - 40)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .background(WorkflowGradientBackground())
        .onAppear {
            HapticFeedbackManager.shared.success()
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                iconAppeared = true
            }
            
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                ringExpanded = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showParticles = true
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                titleAppeared = true
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35)) {
                timeSavedAppeared = true
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5)) {
                summaryAppeared = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                startCountUp()
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.65)) {
                buttonsAppeared = true
            }
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.8)) {
                historyLinkAppeared = true
            }
        }
        .onDisappear {
            countUpTask?.cancel()
            countUpTask = nil
        }
    }
    
    @MainActor
    private func startCountUp() {
        let steps = 20
        let interval = 0.5 / Double(steps)
        
        countUpTask?.cancel()
        countUpTask = Task {
            for currentStep in 1...steps {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                
                let progress = Double(currentStep) / Double(steps)
                let easedProgress = 1 - pow(1 - progress, 3)
                
                await MainActor.run {
                    displayedFiles = Int(round(Double(totalFiles) * easedProgress))
                    displayedFolders = Int(round(Double(totalFolders) * easedProgress))
                }
            }
            
            await MainActor.run {
                countUpTask = nil
                displayedFiles = totalFiles
                displayedFolders = totalFolders
                HapticFeedbackManager.shared.alignment()
            }
        }
    }
    
    private func undoLastOrganization() {
        guard let lastEntry = organizer.history.entries.first(where: { $0.directoryPath == directoryURL.path && $0.success && !$0.isUndone }) else { return }
        
        Task {
            do {
                try await organizer.undoHistoryEntry(lastEntry)
                await MainActor.run {
                    HapticFeedbackManager.shared.success()
                }
                withAnimation(.pageTransition) {
                    organizer.reset()
                }
            } catch {
                await MainActor.run {
                    HapticFeedbackManager.shared.error()
                }
                print("Failed to undo organization: \(error)")
            }
        }
    }
    
    private func timeSavedString(_ seconds: TimeInterval) -> String {
        if seconds >= 3600 {
            let hours = seconds / 3600
            return String(format: "%.1f hours", hours)
        } else if seconds >= 60 {
            let minutes = seconds / 60
            return String(format: "%.0f minutes", minutes)
        } else {
            return String(format: "%.0f seconds", seconds)
        }
    }
}

private struct ConfettiParticlesView: View {
    struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let distance: CGFloat
        let color: Color
        let size: CGFloat
        let delay: Double
    }
    
    @State private var burstedParticles: Set<UUID> = []
    
    private let particles: [Particle] = {
        let colors: [Color] = [.green, .blue, .purple, .orange, .yellow, .mint]
        return (0..<12).map { i in
            Particle(
                angle: Double(i) * 30 + Double.random(in: -10...10),
                distance: CGFloat.random(in: 50...80),
                color: colors[i % colors.count],
                size: CGFloat.random(in: 4...7),
                delay: Double.random(in: 0...0.25)
            )
        }
    }()
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                let isBursted = burstedParticles.contains(particle.id)
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .offset(
                        x: isBursted ? cos(particle.angle * .pi / 180) * particle.distance : 0,
                        y: isBursted ? sin(particle.angle * .pi / 180) * particle.distance : 0
                    )
                    .opacity(isBursted ? 0 : 0.8)
                    .scaleEffect(isBursted ? 0.3 : 1)
            }
        }
        .onAppear {
            for particle in particles {
                withAnimation(.easeOut(duration: Double.random(in: 0.5...0.9)).delay(particle.delay)) {
                    burstedParticles.insert(particle.id)
                }
            }
        }
    }
}

private struct SummaryStatItem: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            VStack(spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompletionFeatureSuggestionCard: View {
    let icon: String
    let title: String
    let description: String
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(description)
            }
            
            Spacer()
            
            Button(action: action) {
                Text(actionTitle)
                    .lineLimit(1)
                    .font(.subheadline.weight(.semibold))
            }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .help("Open storage location settings")
        }
        .padding(14)
        .background(CompletionLiquidGlassBackground(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 5)
        .help(description)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityHint("Use this suggestion to configure destinations for future runs")
    }
}

private struct CompletionLiquidGlassBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    Color(NSColor.controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.86 : 0.94)
                )
            
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.45),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

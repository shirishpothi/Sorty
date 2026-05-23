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
    let renameCount: Int
    let mode: OrganizationMode
    let directoryURL: URL
    let onReturnToStart: (() -> Void)?
    
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
    @State private var undoState: UndoPresentationState = .idle
    @State private var undoRestoredCount = 0
    @State private var undoSkippedCount = 0
    
    @State private var displayedFiles = 0
    @State private var displayedFolders = 0
    @State private var countUpTask: Task<Void, Never>?

    private enum UndoPresentationState: Equatable {
        case idle
        case undoing
        case completed
        case failed

        var isUndoing: Bool {
            if case .undoing = self {
                return true
            }
            return false
        }
    }
    
    private var shouldShowStorageSuggestion: Bool {
        mode != .renameOnly && totalFiles >= 50 && storageLocationsManager.enabledLocations.isEmpty
    }

    private var primaryStatLabel: String {
        switch mode {
        case .renameOnly: return renameCount == 1 ? "Name Changed" : "Names Changed"
        case .organize, .organizeAndRename: return totalFiles == 1 ? "File Moved" : "Files Moved"
        }
    }

    private var secondaryStatValue: String {
        switch mode {
        case .renameOnly: return "\(max(totalFiles - renameCount, 0))"
        case .organize, .organizeAndRename: return "\(displayedFolders)"
        }
    }

    private var secondaryStatLabel: String {
        switch mode {
        case .renameOnly: return max(totalFiles - renameCount, 0) == 1 ? "File Unchanged" : "Files Unchanged"
        case .organize, .organizeAndRename: return totalFolders == 1 ? "Folder Created" : "Folders Created"
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(statusColor.opacity(0.1))
                                .frame(width: 100, height: 100)
                                .scaleEffect(iconAppeared ? 1 : 0.5)
                                .opacity(iconAppeared ? 1 : 0)

                            Circle()
                                .stroke(statusColor.opacity(ringExpanded ? 0 : 0.5), lineWidth: 3)
                                .frame(width: 100, height: 100)
                                .scaleEffect(ringExpanded ? 2 : 1)

                            ZStack {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 58, height: 58)

                                Image(systemName: statusIcon)
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(.white)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .scaleEffect(iconAppeared ? 1 : 0.3)

                            if showParticles {
                                ConfettiParticlesView()
                            }
                        }
                        
                        VStack(spacing: 8) {
                            Text(statusTitle)
                                .font(.title.bold())
                                .opacity(titleAppeared ? 1 : 0)
                                .offset(y: titleAppeared ? 0 : 10)
                                .contentTransition(.opacity)

                            Text(statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .opacity(titleAppeared ? 1 : 0)
                                .offset(y: titleAppeared ? 0 : 10)
                                .contentTransition(.opacity)

                            let effectiveTimeSaved: TimeInterval = {
                                if let stats = stats, stats.estimatedTimeSaved > 0 {
                                    return stats.estimatedTimeSaved
                                }
                                return Double(totalFiles) * 4.0
                            }()
                            
                            if effectiveTimeSaved > 0 && undoState == .idle {
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
                            label: primaryStatLabel,
                            icon: mode == .renameOnly ? "pencil.line" : "doc.on.doc.fill",
                            color: .blue
                        )
                        
                        SummaryStatItem(
                            value: secondaryStatValue,
                            label: secondaryStatLabel,
                            icon: mode == .renameOnly ? "doc.text" : "folder.fill.badge.plus",
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
                            Label(mode == .renameOnly ? "Show Renamed Files" : "View in Finder", systemImage: "folder.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.sortyPrimary(size: .large))
                        .onHover { hovering in
                            if hovering {
                                HapticFeedbackManager.shared.selection()
                            }
                        }
                        .help(mode == .renameOnly ? "Open the folder containing renamed files" : "Open the organized folder in Finder")
                        .accessibilityHint(mode == .renameOnly ? "Shows your renamed files in Finder" : "Shows your organized files in Finder")
                        .disabled(undoState.isUndoing || undoState == .completed)

                        HStack(spacing: 12) {
                            Button {
                                HapticFeedbackManager.shared.tap()
                                undoLastOrganization()
                            } label: {
                                if undoState.isUndoing {
                                    Label("Undoing...", systemImage: "arrow.triangle.2.circlepath")
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Undo", systemImage: "arrow.uturn.backward")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.sortySecondary(size: .regular))
                            .onHover { hovering in
                                if hovering {
                                    HapticFeedbackManager.shared.selection()
                                }
                            }
                            .help("Undo the latest organization for this folder")
                            .accessibilityHint("Restores files from the most recent successful run")
                            .disabled(undoState != .idle)

                            Button {
                                HapticFeedbackManager.shared.tap()
                                returnToStart()
                            } label: {
                                Label("Start Again", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.sortySecondary(size: .regular))
                            .onHover { hovering in
                                if hovering {
                                    HapticFeedbackManager.shared.selection()
                                }
                            }
                            .help("Return to the start screen for this folder")
                            .accessibilityHint("Returns to the start organization screen")
                            .disabled(undoState.isUndoing || undoState == .completed)
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
                    
                    if undoState == .completed {
                        UndoCompletionSummary(restoredCount: undoRestoredCount, skippedCount: undoSkippedCount)
                            .frame(maxWidth: 420)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let stats = stats, settingsViewModel.config.showStatsForNerds, undoState == .idle {
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
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: undoState)
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

    private var statusIcon: String {
        switch undoState {
        case .idle:
            return "checkmark"
        case .undoing:
            return "arrow.uturn.backward"
        case .completed:
            return "arrow.uturn.backward.circle.fill"
        case .failed:
            return "exclamationmark"
        }
    }

    private var statusColor: Color {
        switch undoState {
        case .idle:
            return .green
        case .undoing:
            return .blue
        case .completed:
            return .mint
        case .failed:
            return .red
        }
    }

    private var statusTitle: String {
        switch undoState {
        case .idle:
            return mode.completionTitle
        case .undoing:
            return "Undoing Changes"
        case .completed:
            return "Undo Complete"
        case .failed:
            return "Undo Failed"
        }
    }

    private var statusMessage: String {
        switch undoState {
        case .idle:
            return mode.completionMessage
        case .undoing:
            return "Restoring files to their previous locations..."
        case .completed:
            if undoSkippedCount > 0 {
                return "\(undoRestoredCount) restored, \(undoSkippedCount) skipped. Returning to the start screen."
            }
            return "\(undoRestoredCount) restored. Returning to the start screen."
        case .failed:
            return "Sorty could not restore this run. Please review history for details."
        }
    }
    
    @MainActor
    private func startCountUp() {
        let steps = 20
        let interval = 0.5 / Double(steps)
        let primaryTarget = mode == .renameOnly ? renameCount : totalFiles
        let secondaryTarget = mode == .renameOnly ? max(totalFiles - renameCount, 0) : totalFolders
        
        countUpTask?.cancel()
        countUpTask = Task {
            for currentStep in 1...steps {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                
                let progress = Double(currentStep) / Double(steps)
                let easedProgress = 1 - pow(1 - progress, 3)
                
                await MainActor.run {
                    displayedFiles = Int(round(Double(primaryTarget) * easedProgress))
                    displayedFolders = Int(round(Double(secondaryTarget) * easedProgress))
                }
            }
            
            await MainActor.run {
                countUpTask = nil
                displayedFiles = primaryTarget
                displayedFolders = secondaryTarget
                HapticFeedbackManager.shared.alignment()
            }
        }
    }
    
    private func undoLastOrganization() {
        guard undoState == .idle else { return }
        guard let lastEntry = organizer.history.entries.first(where: { $0.directoryPath == directoryURL.path && $0.success && !$0.isUndone }) else { return }

        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            undoState = .undoing
            showParticles = false
        }
        
        Task {
            do {
                let result = try await organizer.undoHistoryEntry(lastEntry)
                await MainActor.run {
                    undoRestoredCount = result.successfulOperations
                    undoSkippedCount = result.missingFiles.count
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        undoState = .completed
                        ringExpanded = false
                    }
                    HapticFeedbackManager.shared.success()
                }

                try? await Task.sleep(for: .milliseconds(950))

                await MainActor.run {
                    returnToStart()
                }
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        undoState = .failed
                    }
                    HapticFeedbackManager.shared.error()
                }
                print("Failed to undo organization: \(error)")

                try? await Task.sleep(for: .seconds(2))

                await MainActor.run {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                        undoState = .idle
                    }
                }
            }
        }
    }

    private func returnToStart() {
        if let onReturnToStart {
            onReturnToStart()
        } else {
            withAnimation(.smooth(duration: 0.34)) {
                organizer.reset()
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

private struct UndoCompletionSummary: View {
    let restoredCount: Int
    let skippedCount: Int

    private var summaryText: String {
        if skippedCount > 0 {
            return "\(restoredCount) restored, \(skippedCount) skipped"
        }
        return "\(restoredCount) restored"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.mint)
                .frame(width: 32, height: 32)
                .systemLiquidGlassBackground(cornerRadius: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text("Files restored")
                    .font(.subheadline.weight(.semibold))

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .systemLiquidGlassBackground(cornerRadius: 14)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.mint.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Undo complete. \(summaryText).")
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
                .buttonStyle(.sortyProminent)
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

//
//  OrganizationResultView.swift
//  Sorty
//
//  Post-organization feedback view with undo and redo support
//

import SwiftUI

struct OrganizationResultView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var isProcessing = false
    @State private var processError: String?
    @State private var hasUndone = false
    @State private var hasAppeared = false
    @State private var showConfetti = false

    var body: some View {
        VStack(spacing: 0) {
            if let stats = organizer.currentPlan?.generationStats {
                GenerationStatsView(stats: stats)
                    .opacity(hasAppeared ? 1 : 0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
            }

            Spacer()

            VStack(spacing: 32) {
                successIcon
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
                
                statusSection
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 15)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)

                if let error = processError {
                    errorBanner(error)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                actionButtons
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 15)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
            }

            Spacer()
            
            quickActions
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: hasAppeared)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
            if !hasUndone {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showConfetti = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hasUndone ? "Organization reverted" : "Organization complete")
    }
    
    private var successIcon: some View {
        ZStack {
            Circle()
                .fill(hasUndone ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                .frame(width: 120, height: 120)
                .scaleEffect(showConfetti && !hasUndone ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatCount(2, autoreverses: true), value: showConfetti)
            
            Image(systemName: hasUndone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(hasUndone ? .orange : .green)
                .symbolEffect(.bounce, value: hasAppeared)
        }
    }
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            Text(hasUndone ? "Organization Reverted" : "Organization Complete!")
                .font(.title2)
                .fontWeight(.bold)

            if let plan = organizer.currentPlan {
                HStack(spacing: 16) {
                    StatBadge(
                        icon: "doc.fill",
                        value: "\(plan.totalFiles)",
                        label: "files"
                    )
                    
                    StatBadge(
                        icon: "folder.fill",
                        value: "\(plan.totalFolders)",
                        label: "folders"
                    )
                }
            }
            
            if hasUndone {
                Text("Your files have been restored to their original locations")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            Text(error)
                .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
        .accessibilityLabel("Error: \(error)")
    }

    private var actionButtons: some View {
        HStack(spacing: 16) {
            if !hasUndone {
                Button {
                    HapticFeedbackManager.shared.tap()
                    handleUndo()
                } label: {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 12))
                        }
                        Text("Undo Changes")
                    }
                    .frame(minWidth: 130)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
                .accessibilityIdentifier("UndoChangesButton")
                .accessibilityLabel("Undo organization changes")
                .accessibilityHint("Restores files to their original locations")
            } else {
                Button {
                    HapticFeedbackManager.shared.tap()
                    handleRedo()
                } label: {
                    HStack(spacing: 6) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        Text("Redo Changes")
                    }
                    .frame(minWidth: 130)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
                .accessibilityIdentifier("RedoChangesButton")
                .accessibilityLabel("Redo organization changes")
                .accessibilityHint("Re-applies the organization")
            }

            Button {
                HapticFeedbackManager.shared.success()
                organizer.reset()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Done")
                }
                .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing)
            .accessibilityIdentifier("DoneButton")
            .accessibilityLabel("Finish and return to folder selection")
        }
    }
    
    private var quickActions: some View {
        HStack(spacing: 20) {
            QuickActionButton(
                icon: "folder",
                label: "Open in Finder"
            ) {
                if let url = organizer.history.entries.first?.directoryPath {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url)
                }
            }
            
            QuickActionButton(
                icon: "clock",
                label: "View History"
            ) {
            }
        }
        .padding(.bottom, 32)
    }

    private func handleUndo() {
        guard let latestEntry = organizer.history.entries.first, latestEntry.success else { return }

        isProcessing = true
        processError = nil

        Task {
            do {
                try await organizer.undoHistoryEntry(latestEntry)
                HapticFeedbackManager.shared.success()
                hasUndone = true
                isProcessing = false
            } catch {
                HapticFeedbackManager.shared.error()
                processError = "Undo failed: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }

    private func handleRedo() {
        guard let latestEntry = organizer.history.entries.first, latestEntry.isUndone else { return }

        isProcessing = true
        processError = nil

        Task {
            do {
                try await organizer.redoOrganization(from: latestEntry)
                HapticFeedbackManager.shared.success()
                hasUndone = false
                isProcessing = false
            } catch {
                HapticFeedbackManager.shared.error()
                processError = "Redo failed: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
}

struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
            
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct GenerationStatsView: View {
    let stats: GenerationStats
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    
                    Text("Stats for Nerds")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        NerdStatPill(icon: "bolt.fill", value: String(format: "%.1f", stats.tps), unit: "tok/s", color: .orange)
                        NerdStatPill(icon: "clock.fill", value: String(format: "%.2f", stats.duration), unit: "s", color: .blue)
                        NerdStatPill(icon: "cpu", value: stats.model, unit: nil, color: .purple)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stats for nerds. \(isExpanded ? "Collapse" : "Expand") for details")
            
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                HStack(spacing: 0) {
                    NerdStatCard(
                        icon: "bolt.fill",
                        iconColor: .orange,
                        title: "Throughput",
                        value: String(format: "%.1f", stats.tps),
                        unit: "tokens/sec",
                        description: "Generation speed"
                    )
                    
                    Divider()
                        .frame(height: 50)
                    
                    NerdStatCard(
                        icon: "timer",
                        iconColor: .green,
                        title: "Time to First Token",
                        value: String(format: "%.2f", stats.ttft),
                        unit: "seconds",
                        description: "Initial response latency"
                    )
                    
                    Divider()
                        .frame(height: 50)
                    
                    NerdStatCard(
                        icon: "clock.fill",
                        iconColor: .blue,
                        title: "Total Duration",
                        value: String(format: "%.2f", stats.duration),
                        unit: "seconds",
                        description: "End-to-end time"
                    )
                    
                    Divider()
                        .frame(height: 50)
                    
                    NerdStatCard(
                        icon: "number",
                        iconColor: .teal,
                        title: "Tokens Generated",
                        value: "\(stats.totalTokens)",
                        unit: "tokens",
                        description: "Estimated output size"
                    )
                    
                    Divider()
                        .frame(height: 50)
                    
                    NerdStatCard(
                        icon: "cpu",
                        iconColor: .purple,
                        title: "Model",
                        value: stats.model,
                        unit: nil,
                        description: "AI model used"
                    )
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
        .accessibilityElement(children: .contain)
    }
}

struct NerdStatPill: View {
    let icon: String
    let value: String
    let unit: String?
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            
            if let unit = unit {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

struct NerdStatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String?
    let description: String
    
    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(iconColor)
                
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                
                if let unit = unit {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Text(description)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit ?? "")")
    }
}

struct StatItem: View {
    let label: String
    let value: String
    var isMonospaced: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }
}

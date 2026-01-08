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

    var body: some View {
        VStack(spacing: 0) {
            // Stats for Nerds
            // Stats for Nerds
            if let stats = organizer.currentPlan?.generationStats {
                GenerationStatsView(stats: stats)
            }

            Spacer()

            VStack(spacing: 30) {
                Image(systemName: hasUndone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(hasUndone ? .orange : .green)

            VStack(spacing: 8) {
                Text(hasUndone ? "Organization Reverted" : "Organization Complete!")
                    .font(.title)
                    .fontWeight(.bold)

                if let plan = organizer.currentPlan {
                    Text("\(plan.totalFiles) files • \(plan.totalFolders) folders")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }

            if let error = processError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            HStack(spacing: 16) {
                if !hasUndone {
                    Button(action: handleUndo) {
                        HStack {
                            if isProcessing {
                                ProgressView().controlSize(.small).scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            Text("Undo Changes")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                    .accessibilityIdentifier("UndoChangesButton")
                } else {
                    Button(action: handleRedo) {
                        HStack {
                            if isProcessing {
                                ProgressView().controlSize(.small).scaleEffect(0.6)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Redo Changes")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                    .accessibilityIdentifier("RedoChangesButton")
                }

                Button("Done") {
                    organizer.reset()
                }
                .buttonStyle(.borderedProminent)
                .frame(minWidth: 120)
                .disabled(isProcessing)
                .accessibilityIdentifier("DoneButton")
            }
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    private func handleUndo() {
        guard let latestEntry = organizer.history.entries.first, latestEntry.success else { return }

        isProcessing = true
        processError = nil

        Task {
            do {
                try await organizer.undoHistoryEntry(latestEntry)
                hasUndone = true
                isProcessing = false
            } catch {
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
                hasUndone = false
                isProcessing = false
            } catch {
                processError = "Redo failed: \(error.localizedDescription)"
                isProcessing = false
            }
        }
    }
}

struct GenerationStatsView: View {
    let stats: GenerationStats
    
    var body: some View {
        HStack(spacing: 20) {
            StatItem(label: "Tokens/Sec", value: String(format: "%.1f", stats.tps))
            Divider().frame(height: 20)
            StatItem(label: "Time to First Token", value: String(format: "%.2fs", stats.ttft))
            Divider().frame(height: 20)
            StatItem(label: "Total Duration", value: String(format: "%.2fs", stats.duration))
            Divider().frame(height: 20)
            StatItem(label: "Est. Tokens", value: "\(stats.totalTokens)")
            Divider().frame(height: 20)
            StatItem(label: "Model", value: stats.model, isMonospaced: false)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
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
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            Text(value)
                .font(isMonospaced ? .system(.caption, design: .monospaced) : .caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

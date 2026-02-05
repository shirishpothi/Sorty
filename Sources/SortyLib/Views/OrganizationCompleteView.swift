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
    
    @State private var appeared = false
    @State private var showStats = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Success Animation Header
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 100, height: 100)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                        .scaleEffect(appeared ? 1 : 0.5)
                        .opacity(appeared ? 1 : 0)
                }
                
                VStack(spacing: 8) {
                    Text("Organization Complete")
                        .font(.title.bold())
                    
                    Text("Successfully organized your files into a clean structure.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Show time saved - use filesScanned from stats, fallback to totalFiles
                    let effectiveTimeSaved: TimeInterval = {
                        if let stats = stats, stats.estimatedTimeSaved > 0 {
                            return stats.estimatedTimeSaved
                        }
                        // Fallback: 4 seconds per file organized
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
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                    }
                }
            }
            
            // Summary Card
            HStack(spacing: 40) {
                SummaryStatItem(
                    value: "\(totalFiles)",
                    label: totalFiles == 1 ? "File Moved" : "Files Moved",
                    icon: "doc.on.doc.fill",
                    color: .blue
                )
                
                SummaryStatItem(
                    value: "\(totalFolders)",
                    label: totalFolders == 1 ? "Folder Created" : "Folders Created",
                    icon: "folder.fill.badge.plus",
                    color: .purple
                )
            }
            .padding(24)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            
            // Action Buttons
            VStack(spacing: 12) {
                Button {
                    HapticFeedbackManager.shared.tap()
                    NSWorkspace.shared.open(directoryURL)
                } label: {
                    Label("View in Finder", systemImage: "folder.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.sortyPrimary(size: .large))
                
                HStack(spacing: 12) {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        undoLastOrganization()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sortySecondary(size: .regular))
                    
                    Button {
                        HapticFeedbackManager.shared.tap()
                        withAnimation(.pageTransition) {
                            appState.selectedDirectory = nil  // Clear selection to go back to folder picker
                            organizer.reset()
                        }
                    } label: {
                        Label("Organize Another", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sortySecondary(size: .regular))
                }
                
                Button {
                    HapticFeedbackManager.shared.tap()
                    appState.currentView = .history
                } label: {
                    Label("View History", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .frame(maxWidth: 400)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            
            // Stats Area
            if let stats = stats, settingsViewModel.config.showStatsForNerds {
                OrganizationResultView(stats: stats)
                    .padding(.horizontal, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            Spacer()
        }
        .padding(40)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                appeared = true
            }
        }
    }
    
    private func undoLastOrganization() {
        guard let lastEntry = organizer.history.entries.first(where: { $0.directoryPath == directoryURL.path && $0.success && !$0.isUndone }) else { return }
        
        Task {
            do {
                try await organizer.undoHistoryEntry(lastEntry)
                withAnimation(.pageTransition) {
                    organizer.reset()
                }
            } catch {
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
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

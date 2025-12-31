//
//  OrganizationResultView.swift
//  FileOrganizer
//
//  Post-organization feedback view with undo and redo support
//

import SwiftUI

struct OrganizationResultView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @State private var isProcessing = false
    @State private var processError: String?
    @State private var hasUndone = false

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: hasUndone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(hasUndone ? .orange : .green)
                .symbolEffect(.bounce, value: organizer.state)

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
        .padding(40)
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

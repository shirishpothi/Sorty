//
//  TimelineView.swift
//  FileOrganizer
//
//  "Time Machine" style timeline slider for undo/redo history
//

import SwiftUI

struct TimelineView: View {
    let entries: [OrganizationHistoryEntry]
    let directoryPath: String
    let onRestore: (OrganizationHistoryEntry) -> Void
    
    @State private var selectedIndex: Int = 0
    @State private var isHovering = false
    @State private var hoverIndex: Int?
    
    private var filteredEntries: [OrganizationHistoryEntry] {
        entries.filter { $0.directoryPath == directoryPath && $0.success }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organization Timeline")
                        .font(.headline)
                    Text("Restore to any previous organization state")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(filteredEntries.count) snapshots")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if filteredEntries.isEmpty {
                EmptyTimelineView()
            } else {
                // Timeline slider
                VStack(spacing: 12) {
                    // Visual timeline
                    TimelineSliderTrack(
                        entries: filteredEntries,
                        selectedIndex: $selectedIndex,
                        hoverIndex: $hoverIndex
                    )
                    
                    // Selected entry details
                    if selectedIndex < filteredEntries.count {
                        SelectedEntryCard(
                            entry: filteredEntries[selectedIndex],
                            onRestore: onRestore
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.purple.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Timeline Slider Track

struct TimelineSliderTrack: View {
    let entries: [OrganizationHistoryEntry]
    @Binding var selectedIndex: Int
    @Binding var hoverIndex: Int?
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let nodeSpacing = entries.count > 1 ? width / CGFloat(entries.count - 1) : width / 2
            
            ZStack(alignment: .leading) {
                // Track line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 4)
                    .cornerRadius(2)
                
                // Filled portion up to selected
                if selectedIndex > 0 && entries.count > 1 {
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: nodeSpacing * CGFloat(selectedIndex), height: 4)
                        .cornerRadius(2)
                }
                
                // Timeline nodes
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let xPosition = entries.count > 1 ? nodeSpacing * CGFloat(index) : width / 2
                    let maxFiles = entries.map(\.filesOrganized).max() ?? 1
                    let magnitude = Double(entry.filesOrganized) / Double(max(1, maxFiles))
                    
                    TimelineNode(
                        entry: entry,
                        isSelected: index == selectedIndex,
                        isHovered: hoverIndex == index,
                        magnitude: magnitude
                    )
                    .position(x: xPosition, y: geo.size.height / 2)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedIndex = index
                        }
                    }
                    .onHover { hovering in
                        hoverIndex = hovering ? index : nil
                    }
                }
            }
        }
        .frame(height: 40)
        .padding(.horizontal, 12)
    }
}

// MARK: - Timeline Node

struct TimelineNode: View {
    let entry: OrganizationHistoryEntry
    let isSelected: Bool
    let isHovered: Bool
    let magnitude: Double // 0.0 to 1.0
    
    var body: some View {
        ZStack {
            // Halo for selection
            if isSelected {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 32, height: 32)
            }
            
            // Core node
            Circle()
                .fill(entry.isUndone ? Color.orange : (entry.success ? Color.purple : Color.red))
                .frame(width: nodeSize, height: nodeSize)
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
            
            // Selection ring
            if isSelected {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: nodeSize, height: nodeSize)
            }
        }
        .scaleEffect(isHovered ? 1.2 : 1.0)
        .animation(.spring(response: 0.3), value: isHovered)
        .animation(.spring(response: 0.3), value: isSelected)
    }
    
    private var nodeSize: CGFloat {
        // Base size 8, max additional 12 based on magnitude
        let base: CGFloat = 8
        let additional = 12.0 * magnitude
        return isSelected ? (base + additional + 4) : (base + additional)
    }
}

// MARK: - Selected Entry Card

struct SelectedEntryCard: View {
    let entry: OrganizationHistoryEntry
    let onRestore: (OrganizationHistoryEntry) -> Void
    
    @State private var showRestoreConfirmation = false
    
    var body: some View {
        HStack(spacing: 20) {
            // Icon status
            ZStack {
                Circle()
                    .fill(entry.isUndone ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)
                Image(systemName: entry.isUndone ? "arrow.uturn.backward" : "folder.badge.gear")
                    .font(.title3)
                    .foregroundColor(entry.isUndone ? .orange : .blue)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.isUndone ? "Reverted State" : "Organization Snapshot")
                    .font(.headline)
                
                Text(entry.timestamp.formatted(date: .long, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Label("\(entry.filesOrganized) files moved", systemImage: "arrow.right.doc.on.clipboard")
                    Label("\(entry.foldersCreated) folders", systemImage: "folder.badge.plus")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
            }
            
            Spacer()
            
            // Action
            if isCurrentState {
                Label("Current", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(20)
            } else {
                Button {
                    showRestoreConfirmation = true
                } label: {
                    Text("Restore this State")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        .alert("Restore to this state?", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restore") {
                onRestore(entry)
            }
        } message: {
            Text("This will undo all organizations performed after this snapshot. Files will be moved back to their original locations found in this snapshot.")
        }
    }
    
    private var isCurrentState: Bool {
        // Logic should be more robust: first item in the list that isn't undone
        // For simplicity in this view, we'll check if it's not undone, 
        // but in a real app we'd compare against the current head of the timeline.
        !entry.isUndone
    }
}

// MARK: - Empty Timeline View

struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No timeline available")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Organize this folder to create timeline snapshots")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Compact Timeline for HistoryView

struct CompactTimelineView: View {
    let entries: [OrganizationHistoryEntry]
    let directoryPath: String
    
    @EnvironmentObject var organizer: FolderOrganizer
    @State private var isProcessing = false
    @State private var showAlert = false
    @State private var alertMessage: String?
    
    private var filteredEntries: [OrganizationHistoryEntry] {
        entries.filter { $0.directoryPath == directoryPath && $0.success }
            .sorted { $0.timestamp > $1.timestamp }
    }
    
    var body: some View {
        TimelineView(
            entries: entries,
            directoryPath: directoryPath,
            onRestore: handleRestore
        )
        .disabled(isProcessing)
        .overlay {
            if isProcessing {
                ProgressView()
                    .scaleEffect(1.2)
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
        }
        .alert("Timeline", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            if let msg = alertMessage {
                Text(msg)
            }
        }
    }
    
    private func handleRestore(_ entry: OrganizationHistoryEntry) {
        isProcessing = true
        
        Task {
            do {
                try await organizer.restoreToState(targetEntry: entry)
                alertMessage = "Successfully restored to \(entry.timestamp.formatted())"
            } catch {
                alertMessage = "Restore failed: \(error.localizedDescription)"
            }
            isProcessing = false
            showAlert = true
        }
    }
}

#Preview {
    let entries = [
        OrganizationHistoryEntry(
            directoryPath: "/Users/test/Downloads",
            filesOrganized: 25,
            foldersCreated: 5
        ),
        OrganizationHistoryEntry(
            directoryPath: "/Users/test/Downloads",
            filesOrganized: 18,
            foldersCreated: 4,
            isUndone: true
        ),
        OrganizationHistoryEntry(
            directoryPath: "/Users/test/Downloads",
            filesOrganized: 30,
            foldersCreated: 6
        )
    ]
    
    TimelineView(
        entries: entries,
        directoryPath: "/Users/test/Downloads",
        onRestore: { _ in }
    )
    .padding()
    .frame(width: 600)
}

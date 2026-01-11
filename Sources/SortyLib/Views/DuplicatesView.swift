//
//  DuplicatesView.swift
//  Sorty
//
//  UI for displaying and managing duplicate files
//  Enhanced with haptic feedback, "Liquid Glass" aesthetic, and card-based layout
//

import SwiftUI

struct DuplicatesView: View {
    @StateObject private var detectionManager = DuplicateDetectionManager()
    @StateObject private var settingsManager = DuplicateSettingsManager()
    @EnvironmentObject var appState: AppState
    @State private var selectedGroup: DuplicateGroup?
    @State private var showDeleteConfirmation = false
    @State private var filesToDelete: [FileItem] = []
    @State private var contentOpacity: Double = 0
    @State private var showSettings = false
    @AppStorage("enableSafeDeletion") private var enableSafeDeletion = true
    @State private var localDirectory: URL?
    
    // Derived directory: Use local if set, otherwise fallback to global
    private var effectiveDirectory: URL? {
        localDirectory ?? appState.selectedDirectory
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DuplicatesHeaderNew(
                manager: detectionManager,
                currentDirectory: effectiveDirectory,
                onSelectDirectory: selectDirectory,
                onScan: startScan,
                onBulkDelete: prepareBulkDelete,
                onSettings: { showSettings = true }
            )
            
            Divider()

            ZStack {
                if effectiveDirectory == nil {
                    // Start State: No directory selected
                    DuplicatesEmptyStateView(
                        title: "Select a Directory",
                        description: "Select a folder to scan for identical files and recover disk space.",
                        icon: "doc.on.doc",
                        actionTitle: "Choose Directory",
                        action: selectDirectory
                    )
                    .transition(TransitionStyles.scaleAndFade)
                } else if detectionManager.isScanning {
                    // Scanning State
                    ScanProgressViewNew(progress: detectionManager.scanProgress)
                        .transition(TransitionStyles.scaleAndFade)
                } else if detectionManager.duplicateGroups.isEmpty {
                    if detectionManager.lastScanDate == nil {
                        // Ready State: Directory selected but not scanned
                        DuplicatesEmptyStateView(
                            title: "Ready to Scan",
                            description: "Identical files in \(effectiveDirectory?.lastPathComponent ?? "this folder") will be identified using SHA-256 hashing.",
                            icon: "waveform.path.ecg",
                            actionTitle: "Start Scan",
                            action: startScan
                        )
                        .transition(TransitionStyles.scaleAndFade)
                    } else {
                        // Success State: Scanned and no duplicates
                        DuplicatesEmptyStateView(
                            title: "No Duplicates Found",
                            description: "All files in this folder are unique. Your workspace is healthy!",
                            icon: "checkmark.circle.fill",
                            iconColor: .green,
                            actionTitle: "Scan Again",
                            action: startScan
                        )
                        .transition(TransitionStyles.scaleAndFade)
                    }
                } else {
                    // Results State
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Summary Card
                            DuplicatesSummaryCard(manager: detectionManager)
                                .padding(.top, 16)
                            
                            ForEach(Array(detectionManager.duplicateGroups.enumerated()), id: \.element.id) { index, group in
                                DuplicateGroupCard(
                                    group: group,
                                    onDelete: { files in
                                        filesToDelete = files
                                        showDeleteConfirmation = true
                                    }
                                )
                                .animatedAppearance(delay: Double(index) * 0.03)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(TransitionStyles.slideFromRight)
                }
            }
            .animation(.pageTransition, value: detectionManager.isScanning)
            .animation(.pageTransition, value: detectionManager.duplicateGroups.isEmpty)
            .animation(.pageTransition, value: effectiveDirectory)
            .opacity(contentOpacity)
        }
        .navigationTitle("Duplicate Files")
        .alert("Delete Duplicate Files?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                HapticFeedbackManager.shared.tap()
            }
            Button("Delete", role: .destructive) {
                HapticFeedbackManager.shared.error()
                deleteFiles(filesToDelete)
            }
        } message: {
            Text("This will permanently delete \(filesToDelete.count) file(s). This cannot be undone.")
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
        .sheet(isPresented: $showSettings) {
            DuplicateSettingsView(settingsManager: settingsManager)
        }
    }

    private func startScan() {
        guard let directory = effectiveDirectory else { return }
        HapticFeedbackManager.shared.tap()

        Task {
            let scanner = DirectoryScanner()
            do {
                let files = try await scanner.scanDirectory(at: directory, computeHashes: true)
                await detectionManager.scanForDuplicates(files: files)
                HapticFeedbackManager.shared.success()
            } catch {
                HapticFeedbackManager.shared.error()
                DebugLogger.log("Duplicate scan failed: \(error)")
            }
        }
    }

    private func deleteFiles(_ files: [FileItem]) {
        let fm = FileManager.default
        do {
            if enableSafeDeletion {
                var totalDeleted = 0
                var totalSizeRecovered: Int64 = 0
                var potentialRestorables: [RestorableDuplicate] = []
                
                for file in files {
                    if let group = detectionManager.duplicateGroups.first(where: { $0.files.contains(file) }) {
                        if let survivor = group.files.first(where: { !files.contains($0) }) {
                            let restorables = try DuplicateRestorationManager.shared.deleteSafely(filesToDelete: [file], originalFile: survivor)
                            potentialRestorables.append(contentsOf: restorables)
                            totalDeleted += 1
                            totalSizeRecovered += file.size
                        } else {
                            try fm.removeItem(atPath: file.path)
                            totalDeleted += 1
                            totalSizeRecovered += file.size
                        }
                    } else {
                        try fm.removeItem(atPath: file.path)
                    }
                }
                
                Task { @MainActor in
                    let entry = OrganizationHistoryEntry(
                        directoryPath: effectiveDirectory?.path ?? "",
                        filesOrganized: 0,
                        foldersCreated: 0,
                        success: true,
                        status: .duplicatesCleanup,
                        duplicatesDeleted: totalDeleted,
                        recoveredSpace: totalSizeRecovered,
                        restorableItems: potentialRestorables
                    )
                    appState.organizer?.history.addEntry(entry)
                }
            } else {
                for file in files {
                    try? fm.removeItem(atPath: file.path)
                }
            }
            HapticFeedbackManager.shared.success()
        } catch {
            HapticFeedbackManager.shared.error()
            DebugLogger.log("Delete failed: \(error)")
        }
        startScan()
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            localDirectory = url
            detectionManager.clearResults()
        }
    }

    private func prepareBulkDelete(keepNewest: Bool) {
        var filesToDelete: [FileItem] = []
        for group in detectionManager.duplicateGroups {
            let sortedFiles = group.files.sorted { f1, f2 in
                let d1 = f1.creationDate ?? Date.distantPast
                let d2 = f2.creationDate ?? Date.distantPast
                return keepNewest ? (d1 > d2) : (d1 < d2)
            }
            if sortedFiles.count > 1 {
                filesToDelete.append(contentsOf: sortedFiles.dropFirst())
            }
        }
        if !filesToDelete.isEmpty {
            self.filesToDelete = filesToDelete
            self.showDeleteConfirmation = true
        }
    }
}

// MARK: - Redesigned Header

struct DuplicatesHeaderNew: View {
    @ObservedObject var manager: DuplicateDetectionManager
    let currentDirectory: URL?
    let onSelectDirectory: () -> Void
    let onScan: () -> Void
    let onBulkDelete: (Bool) -> Void
    let onSettings: () -> Void
    
    @AppStorage("enableSafeDeletion") private var enableSafeDeletion = true
    @State private var showInfo = false
    @State private var showSafeDeletionWarning = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundStyle(.blue)
                        .font(.title2)
                    
                    Text("Duplicate Files")
                        .font(.title2.bold())
                }
                
                if let dir = currentDirectory {
                    HStack(spacing: 4) {
                        Text(dir.lastPathComponent)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(dir.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // Safe Deletion Toggle with Tooltip
                HStack(spacing: 4) {
                    Toggle("", isOn: $enableSafeDeletion)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .onChange(of: enableSafeDeletion) { _, newValue in
                            if !newValue { showSafeDeletionWarning = true }
                        }
                    
                    Button { showInfo.toggle() } label: {
                        Image(systemName: "lifepreserver")
                            .foregroundStyle(enableSafeDeletion ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Safe Deletion: \(enableSafeDeletion ? "Enabled" : "Disabled")")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .popover(isPresented: $showInfo) {
                    SafeDeletionInfoPopover(isEnabled: enableSafeDeletion)
                }
                
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .help("Settings")

                Button(action: onSelectDirectory) {
                     Text("Change Folder")
                }
                .buttonStyle(.bordered)
                
                if !manager.duplicateGroups.isEmpty {
                    Menu {
                        Button { onBulkDelete(true) } label: {
                            Label("Keep Newest", systemImage: "clock")
                        }
                        Button { onBulkDelete(false) } label: {
                            Label("Keep Oldest", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Label("Cleanup All", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                
                Button(action: onScan) {
                    Label(manager.lastScanDate == nil ? "Start Scan" : "Rescan", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isScanning || currentDirectory == nil)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .alert("Disable Safe Deletion?", isPresented: $showSafeDeletionWarning) {
            Button("Disable", role: .destructive) { enableSafeDeletion = false }
            Button("Cancel", role: .cancel) { enableSafeDeletion = true }
        } message: {
            Text("Permanently deleting files cannot be undone. Are you sure you want to disable the safety net?")
        }
    }
}

// MARK: - Components

struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let onDelete: ([FileItem]) -> Void
    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.orange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundStyle(.orange)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.files.first?.displayName ?? "Unknown File")
                        .font(.headline)
                    
                    Text("\(group.files.count) identical files • \(ByteCountFormatter.string(fromByteCount: group.files.first?.size ?? 0, countStyle: .file)) each")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Save \(ByteCountFormatter.string(fromByteCount: group.potentialSavings, countStyle: .file))")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.1), in: Capsule())
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Text(isExpanded ? "Hide Details" : "Show Details")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }
            .onHover { isHovered = $0 }
            
            if isExpanded {
                Divider().padding(.horizontal, 16)
                
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                        HStack(spacing: 12) {
                            if index == 0 {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption2)
                                    .help("Original / Keeping")
                            } else {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                    .font(.caption2)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.displayName)
                                    .font(.caption)
                                    .fontWeight(index == 0 ? .medium : .regular)
                                
                                Text(file.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            if index > 0 {
                                Button { onDelete([file]) } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(file.displayName)")
                                .accessibilityHint("Remove this duplicate file")
                            }
                        }
                        .padding(.horizontal, 16)

                    }
                    
                    HStack {
                        Spacer()
                        Button("Keep First, Cleanup Others") {
                            onDelete(Array(group.files.dropFirst()))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)

                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.02))
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)

    }
}

struct DuplicatesSummaryCard: View {
    @ObservedObject var manager: DuplicateDetectionManager
    
    var body: some View {
        HStack(spacing: 0) {
            DuplicateStatItem(
                title: "Duplicates",
                value: "\(manager.totalDuplicates)",
                icon: "doc.on.doc.fill",
                color: .orange
            )
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 40)
            
            DuplicateStatItem(
                title: "Recoverable",
                value: manager.formattedSavings,
                icon: "externaldrive.fill",
                color: .green
            )
            .frame(maxWidth: .infinity)
            
            Divider()
                .frame(height: 40)
            
            DuplicateStatItem(
                title: "Groups",
                value: "\(manager.duplicateGroups.count)",
                icon: "square.grid.2x2.fill",
                color: .blue
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

private struct DuplicateStatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(value)
                .font(.headline)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct DuplicatesEmptyStateView: View {
    let title: String
    let description: String
    let icon: String
    var iconColor: Color = .secondary
    let actionTitle: String
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .opacity(0.7)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title). \(description)")
            
            Button(action: action) {
                Text(actionTitle)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel(actionTitle)
            .accessibilityHint("Activate to \(actionTitle.lowercased())")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct ScanProgressViewNew: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.1), lineWidth: 10)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Scanning")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scan progress")
            .accessibilityValue("\(Int(progress * 100)) percent complete")
            
            VStack(spacing: 6) {
                Text("Computing File Hashes")
                    .font(.subheadline.weight(.medium))
                Text("Comparing file content to find exact matches...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                LoadingDotsView(dotCount: 3, dotSize: 5, color: .accentColor)
                    .padding(.top, 6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Computing file hashes to find exact duplicate matches")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scanning for duplicate files, \(Int(progress * 100)) percent complete")
    }
}

struct SafeDeletionInfoPopover: View {
    let isEnabled: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isEnabled ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(isEnabled ? .green : .orange)
                    .font(.title3)
                Text(isEnabled ? "Safe Deletion is ON" : "Safe Deletion is OFF")
                    .font(.headline)
            }
            
            if isEnabled {
                Text("Files are moved to a hidden recovery zone, not deleted immediately. You can restore them from History.")
                    .font(.caption)
                Text("• Zero risk of accidental loss\n• Recoverable at any time\n• Disk space freed only after cleanup")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("WARNING: Files will be permanently deleted! This action is irreversible.")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text("• Irreversible action\n• No recovery possible\n• Immediate disk space recovery")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}

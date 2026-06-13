//
//  DuplicatesView.swift
//  Sorty
//
//  UI for displaying and managing duplicate files
//  Enhanced with haptic feedback, "Liquid Glass" aesthetic, and Split View layout
//

import Beam
import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var detectionManager: DuplicateDetectionManager
    @EnvironmentObject var settingsManager: DuplicateSettingsManager
    @State private var showDeleteConfirmation = false
    @State private var filesToDelete: [FileItem] = []
    @State private var contentOpacity: Double = 0
    @State private var showSettings = false
    @AppStorage("enableSafeDeletion") private var enableSafeDeletion = true
    @State private var handoffFilePaths: [String] = []
    @State private var currentScanTask: Task<Void, Never>?
    @State private var capturedDirectory: URL?
    @State private var semanticScanProgress: String?
    
    // Derived directory: Use local if set, otherwise fallback to global
    private var effectiveDirectory: URL? {
        appState.duplicateSelectedDirectory ?? appState.selectedDirectory
    }

    private var isShowingEmptyContent: Bool {
        guard effectiveDirectory != nil else { return true }

        switch detectionManager.state {
        case .preparing, .scanning:
            return false
        case .idle:
            return true
        case .completed, .failed:
            return detectionManager.duplicateGroups.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if effectiveDirectory == nil {
                // Base page: Workspace-Health-style layout
                ZStack(alignment: .topLeading) {
                    duplicatesBaseEmptyState()
                        .padding(32)
                        .animatedAppearance(delay: 0.08)

                    duplicatesBaseHeaderSection()
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .animatedAppearance(delay: 0.03)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            // Header
            DuplicatesHeaderNew(
                manager: detectionManager,
                currentDirectory: effectiveDirectory,
                onSelectDirectory: selectDirectory,
                onScan: startScan,
                onCancel: cancelScan,
                onBulkDelete: prepareBulkDelete,
                onSettings: { showSettings = true }
            )
            .animatedAppearance(delay: 0.03)
            
            ZStack {
                    switch detectionManager.state {
                    case .preparing:
                        ScanProgressViewNew(progress: 0, isPreparing: true)
                            .transition(.sortyScaleAndFade)
                        
                    case .scanning(let progress):
                        ScanProgressViewNew(progress: progress, isPreparing: false)
                            .transition(.sortyScaleAndFade)
                        
                    case .idle:
                        if detectionManager.lastScanDate == nil {
                            DuplicatesEmptyStateView(
                                title: "Ready to Scan",
                                description: "Identical files in \(effectiveDirectory?.lastPathComponent ?? "this folder") will be identified.",
                                icon: "waveform.path.ecg",
                                actionTitle: "Start Scan",
                                action: startScan
                            )
                            .transition(.sortyScaleAndFade)
                        } else {
                            noDuplicatesView
                                .transition(.sortyScaleAndFade)
                        }
                        
                    case .completed, .failed:
                        if detectionManager.duplicateGroups.isEmpty {
                            noDuplicatesView
                                .transition(.sortyScaleAndFade)
                        } else {
                            resultsView
                                .transition(.sortySlideFromRight)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.sortySpringStandard, value: detectionManager.state)
                .animation(.sortySpringStandard, value: effectiveDirectory)
                .opacity(contentOpacity)
            }
        }
        .emptyStateWorkflowGradient(isVisible: isShowingEmptyContent)
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
            consumePendingHandoffIfNeeded()
        }
        .onChange(of: effectiveDirectory) { _, _ in
            // Cancel in-flight scan if directory changes
            currentScanTask?.cancel()
            // Clear results when switching directories to prevent showing stale data
            detectionManager.clearResults()
            appState.duplicateSelectedGroup = nil
        }
        .onChange(of: appState.pendingDuplicatesHandoff) { _, handoff in
            guard let handoff else { return }
            apply(handoff: handoff)
        }
        .onDisappear {
            currentScanTask?.cancel()
            currentScanTask = nil
        }
        .sheet(isPresented: $showSettings) {
            DuplicateSettingsView(settingsManager: settingsManager)
        }
    }

    private func consumePendingHandoffIfNeeded() {
        guard let handoff = appState.pendingDuplicatesHandoff else { return }
        apply(handoff: handoff)
    }

    private func apply(handoff: AppState.DuplicatesHandoff) {
        currentScanTask?.cancel()
        currentScanTask = nil

        if let directory = handoff.directory {
            appState.duplicateSelectedDirectory = directory
            appState.selectedDirectory = directory
        }
        handoffFilePaths = handoff.filePaths

        detectionManager.clearResults()
        appState.duplicateSelectedGroup = nil
        appState.pendingDuplicatesHandoff = nil

        if handoff.autoStart, effectiveDirectory != nil {
            startScan()
        }
    }

    // MARK: - Base Page (No Directory Selected)

    @ViewBuilder
    private func duplicatesBaseHeaderSection() -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicate Files")
                    .font(.largeTitle.bold())

                Text("Find identical files, recover disk space, and keep your workspace tidy")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func duplicatesBaseDirectorySelector() -> some View {
        HStack {
            AppKitImageView(
                image: NSWorkspace.shared.icon(forFile: "/tmp"),
                size: CGSize(width: 28, height: 28),
                opacity: 0.6
            )
            .frame(width: 28, height: 28)

            Text("Select a directory to scan")
                .foregroundStyle(.secondary)

            Spacer()

            Button("Choose...") {
                selectDirectory()
            }
            .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
            .accessibilityIdentifier("DuplicatesBaseChooseDirectory")
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func duplicatesBaseEmptyState() -> some View {
        DuplicatesEmptyStateView(
            title: "Select a Directory",
            description: "Choose a folder to scan for identical files and recover disk space",
            icon: "doc.on.doc",
            actionTitle: "Choose Directory",
            actionAccessibilityIdentifier: "DuplicatesEmptyChooseDirectory",
            action: selectDirectory
        )
    }

    private var noDuplicatesView: some View {
        DuplicatesEmptyStateView(
            title: "No Duplicates Found",
            description: "All files in this folder are unique. Your workspace is healthy!",
            icon: "checkmark.circle.fill",
            iconColor: .green,
            actionTitle: "Scan Again",
            action: startScan
        )
    }

    private var resultsView: some View {
        HSplitView {
            // Left Pane: List of Groups
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review groups")
                        .font(.headline)

                    Text("\(detectionManager.allGroups.count) groups • \(detectionManager.formattedSavingsIncludingSemantic) recoverable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                List(selection: $appState.duplicateSelectedGroup) {
                    ForEach(detectionManager.allGroups) { group in
                        UnifiedDuplicateGroupRow(group: group)
                            .tag(group)
                            .scaleEffect(appState.duplicateSelectedGroup == group ? 1.01 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: appState.duplicateSelectedGroup)
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 240, idealWidth: 320, maxWidth: 420)

            // Right Pane: Detail View
            if let group = appState.duplicateSelectedGroup {
                UnifiedDuplicateGroupDetailView(
                    group: group,
                    onDelete: { files in
                        filesToDelete = files
                        showDeleteConfirmation = true
                    }
                )
                .frame(minWidth: 420, maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Choose a group")
                        .font(.headline)
                    Text("The right panel shows the recommended file to keep, what you can recover, and the files in that group.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func startScan() {
        guard let directory = effectiveDirectory else { return }
        let handoffPaths = handoffFilePaths
        handoffFilePaths = []
        HapticFeedbackManager.shared.tap()

        // Cancel any in-flight scan
        currentScanTask?.cancel()

        // Capture current directory
        capturedDirectory = directory
        detectionManager.state = .preparing

        currentScanTask = Task {
            let scanner = DirectoryScanner()
            do {
                let files = try await resolveFilesForScan(
                    scanner: scanner,
                    directory: directory,
                    handoffPaths: handoffPaths,
                    deepScan: settingsManager.settings.includeSemanticDuplicates
                )

                // Verify directory hasn't changed since scan started
                if capturedDirectory == effectiveDirectory && !Task.isCancelled {
                    await detectionManager.scanForDuplicates(files: files, settings: settingsManager.settings)

                    if !Task.isCancelled {
                        // Auto-select first group
                        if let first = detectionManager.allGroups.first {
                            appState.duplicateSelectedGroup = first
                        }
                        HapticFeedbackManager.shared.success()
                    }
                }
            } catch {
                if !Task.isCancelled {
                    detectionManager.state = .failed(error.localizedDescription)
                    HapticFeedbackManager.shared.error()
                    DebugLogger.log("Duplicate scan failed: \(error)")
                }
            }
        }
    }

    private func resolveFilesForScan(
        scanner: DirectoryScanner,
        directory: URL,
        handoffPaths: [String],
        deepScan: Bool
    ) async throws -> [FileItem] {
        guard !handoffPaths.isEmpty else {
            // Pass false for computeHashes because we compute them in detectionManager with progress.
            return try await scanner.scanDirectory(at: directory, deepScan: deepScan, computeHashes: false)
        }

        var targetedFiles: [FileItem] = []
        for path in handoffPaths {
            if Task.isCancelled { break }

            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            if let scannedFile = try? await scanner.scanFile(at: fileURL, deepScan: deepScan, computeHashes: false), !scannedFile.isDirectory {
                targetedFiles.append(scannedFile)
            }
        }

        if targetedFiles.count >= 2 {
            return targetedFiles
        }

        // Fallback when history paths no longer exist or are insufficient.
        return try await scanner.scanDirectory(at: directory, deepScan: deepScan, computeHashes: false)
    }

    private func cancelScan() {
        currentScanTask?.cancel()
        currentScanTask = nil
        detectionManager.isScanning = false
        detectionManager.state = .idle
        HapticFeedbackManager.shared.tap()
    }

    private func deleteFiles(_ files: [FileItem]) {
        let fm = FileManager.default
        var totalDeleted = 0
        var totalSizeRecovered: Int64 = 0
        var potentialRestorables: [RestorableDuplicate] = []
        let cleanupMode: DuplicateCleanupMode = enableSafeDeletion ? .safeDeletion : .directDelete

        do {
            if enableSafeDeletion {
                for file in files {
                    if let exactGroup = detectionManager.duplicateGroups.first(where: { $0.files.contains(file) }) {
                        if let survivor = exactGroup.files.first(where: { !files.contains($0) }) {
                            let restorables = try DuplicateRestorationManager.shared.deleteSafely(filesToDelete: [file], originalFile: survivor)
                            potentialRestorables.append(contentsOf: restorables)
                            totalDeleted += 1
                            totalSizeRecovered += file.size
                        } else {
                            // No survivor found (all in group are being deleted) 
                            // Fallback to Trash for safety instead of permanent delete
                            try fm.trashItem(at: URL(fileURLWithPath: file.path), resultingItemURL: nil)
                            totalDeleted += 1
                            totalSizeRecovered += file.size
                        }
                    } else {
                        // Group not found - fallback to Trash
                        try fm.trashItem(at: URL(fileURLWithPath: file.path), resultingItemURL: nil)
                        totalDeleted += 1
                        totalSizeRecovered += file.size
                    }
                }
            } else {
                for file in files {
                    do {
                        try fm.removeItem(atPath: file.path)
                        totalDeleted += 1
                        totalSizeRecovered += file.size
                    } catch {
                         DebugLogger.log("Failed to remove file: \(file.path), error: \(error.localizedDescription)")
                         // Continue deleting others
                    }
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
                    restorableItems: potentialRestorables,
                    duplicateCleanupMode: cleanupMode
                )
                appState.organizer?.history.addEntry(entry)
            }

            HapticFeedbackManager.shared.success()
        } catch {
            HapticFeedbackManager.shared.error()
            DebugLogger.log("Delete failed: \(error)")
        }
        
        // Refresh the scan
        startScan()
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            appState.duplicateSelectedDirectory = url
            detectionManager.clearResults()
            appState.duplicateSelectedGroup = nil
        }
    }

    private func prepareBulkDelete(keepNewest: Bool) {
        var filesToDelete: [FileItem] = []
        
        // Only include exact matches and high-confidence semantic matches
        for group in detectionManager.allGroups {
            // Skip low-confidence semantic matches from bulk delete
            if group.isSemantic && group.confidenceLevel == .low {
                continue
            }
            
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
    let onCancel: () -> Void
    let onBulkDelete: (Bool) -> Void
    let onSettings: () -> Void
    
    @AppStorage("enableSafeDeletion") private var enableSafeDeletion = true
    @State private var showInfo = false
    @State private var showSafeDeletionWarning = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            headerLayout(spacing: 20, showsFullControls: true)
            headerLayout(spacing: 12, showsFullControls: false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .alert("Disable Safe Deletion?", isPresented: $showSafeDeletionWarning) {
            Button("Disable", role: .destructive) { enableSafeDeletion = false }
            Button("Cancel", role: .cancel) { enableSafeDeletion = true }
        } message: {
            Text("Permanently deleting files cannot be undone. Are you sure you want to disable the safety net?")
        }
    }

    private func headerLayout(spacing: CGFloat, showsFullControls: Bool) -> some View {
        HStack(spacing: spacing) {
            // Left Side: Title & Target Folder
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duplicate Files")
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let dir = currentDirectory {
                        Button(action: onSelectDirectory) {
                            HStack(spacing: 4) {
                                AppKitImageView(
                                    image: NSWorkspace.shared.icon(forFile: dir.path),
                                    size: CGSize(width: 16, height: 16)
                                )
                                .frame(width: 16, height: 16)
                                Text(dir.lastPathComponent)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .buttonStyle(.plain)
                        .help(PrivacyPathMasker.redactedPath(dir.path))
                    } else {
                        Text("No folder selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 260, alignment: .leading)
            }
            .layoutPriority(1)
            
            Spacer()
            
            // Right Side: Controls
            HStack(spacing: showsFullControls ? 12 : 8) {
                // Safe Deletion Status
                Button { showInfo.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: enableSafeDeletion ? "shield.checkered" : "shield.slash")
                        if showsFullControls {
                            Text(enableSafeDeletion ? "Safe Mode" : "Direct Delete")
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(enableSafeDeletion ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .systemLiquidGlassBackground(cornerRadius: 999)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(showInfo ? 0.45 : 0.28),
                                        Color.white.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                }
                .contentShape(Capsule())
                .buttonStyle(.plain)
                .popover(isPresented: $showInfo) {
                    SafeDeletionInfoPopover(isEnabled: enableSafeDeletion)
                        .systemLiquidGlassPopover(cornerRadius: 12)
                }
                
                Divider()
                    .frame(height: 20)
                
                HStack(spacing: 8) {
                    Button(action: onSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                    .help("Detection Settings")
                    .disabled(manager.isScanning)

                    if !manager.allGroups.isEmpty && !manager.isScanning {
                        Menu {
                            Button { onBulkDelete(true) } label: {
                                Label("Keep Newest", systemImage: "clock")
                            }
                            Button { onBulkDelete(false) } label: {
                                Label("Keep Oldest", systemImage: "clock.arrow.circlepath")
                            }
                            Divider()
                            Text("Note: Low-confidence matches excluded")
                                .font(.caption)
                        } label: {
                            Label(showsFullControls ? "Cleanup All" : "Cleanup", systemImage: "trash")
                        }
                        .buttonStyle(.onboardingPill(size: .small))
                        .tint(.red)
                    }

                    if manager.isScanning {
                        Button(action: onCancel) {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                        .tint(.red)
                    } else {
                        Button(action: onScan) {
                            Label(
                                manager.lastScanDate == nil ? (showsFullControls ? "Start Scan" : "Scan") : "Rescan",
                                systemImage: manager.lastScanDate == nil ? "play.fill" : "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.onboardingPill(size: .small))
                        .disabled(currentDirectory == nil)
                    }
                }
            }
        }
    }
}

// MARK: - Components

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    
    private var firstFileURL: URL? {
        guard let path = group.files.first?.path else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if let url = firstFileURL {
                FileThumbnailView(url: url, size: CGSize(width: 36, height: 36))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.orange.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundStyle(.orange)
                        .font(.body)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(group.files.first?.displayName ?? "Unknown File")
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text("\(group.files.count) copies")
                    Text("•")
                    Text("Save \(ByteCountFormatter.string(fromByteCount: group.potentialSavings, countStyle: .file))")
                        .foregroundStyle(.green)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct UnifiedDuplicateGroupRow: View {
    let group: UnifiedDuplicateGroup
    
    private var firstFileURL: URL? {
        guard let path = group.files.first?.path else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail with badge
            ZStack(alignment: .topTrailing) {
                if let url = firstFileURL {
                    FileThumbnailView(url: url, size: CGSize(width: 36, height: 36))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(group.isSemantic ? Color.blue.opacity(0.1) : Color.orange.opacity(0.1))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: group.isSemantic ? "waveform.path" : "doc.on.doc.fill")
                            .foregroundStyle(group.isSemantic ? .blue : .orange)
                            .font(.body)
                    }
                }
                
                // Badge for semantic matches
                if group.isSemantic {
                    Text("Similar")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue))
                        .offset(x: 8, y: -4)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    // Group type tag
                    if group.isSemantic {
                        Text(group.groupTypeLabel)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.1)))
                    }
                }
                
                HStack(spacing: 4) {
                    Text("\(group.files.count) \(group.isExact ? "copies" : "versions")")
                    
                    if let similarity = group.similarityPercentage {
                        Text("•")
                        Text(similarity)
                            .foregroundStyle(group.isExact ? .green : .blue)
                    }
                    
                    Text("•")
                    Text("Save \(ByteCountFormatter.string(fromByteCount: group.potentialSavings, countStyle: .file))")
                        .foregroundStyle(.green)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct DuplicateGroupDetailView: View {
    let group: DuplicateGroup
    let onDelete: ([FileItem]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.files.first?.displayName ?? "Unknown File")
                        .font(.title2.bold())
                    
                    Text("\(group.files.count) identical files found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(1)

                Spacer()
                
                Button {
                    let sortedFiles = group.files.sorted { f1, f2 in
                        let d1 = f1.creationDate ?? Date.distantPast
                        let d2 = f2.creationDate ?? Date.distantPast
                        return d1 < d2 // Keep oldest
                    }
                    onDelete(Array(sortedFiles.dropFirst()))
                } label: {
                    Text("Keep First")
                }
                .buttonStyle(.onboardingPill)
                .tint(.red)
                .layoutPriority(2)
                .help("Keep the first file and clean up the rest.")
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // File List
            List {
                let sortedFiles = group.files.sorted { f1, f2 in
                    let d1 = f1.creationDate ?? Date.distantPast
                    let d2 = f2.creationDate ?? Date.distantPast
                    return d1 < d2
                }
                
                ForEach(Array(sortedFiles.enumerated()), id: \.element.id) { index, file in
                    DuplicateFileDetailRow(file: file, isOriginal: index == 0, onDelete: {
                        onDelete([file])
                    })
                }
            }
            .listStyle(.inset)
        }
    }
}

struct DuplicateFileDetailRow: View {
    let file: FileItem
    let isOriginal: Bool
    let onDelete: () -> Void
    
    private var fileURL: URL {
        URL(fileURLWithPath: file.path)
    }
    
    private var parentFolderName: String {
        fileURL.deletingLastPathComponent().lastPathComponent
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                FileThumbnailView(url: fileURL, size: CGSize(width: 36, height: 36))
                
                if isOriginal {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 10))
                        .padding(2)
                        .background(Circle().fill(.white))
                        .offset(x: 4, y: 4)
                        .help("Original / Keeping")
                }
            }
            .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.displayName)
                    .font(.headline)
                
                Button {
                    NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                } label: {
                    HStack(spacing: 4) {
                        AppKitImageView(
                            image: NSWorkspace.shared.icon(forFile: fileURL.deletingLastPathComponent().path),
                            size: CGSize(width: 12, height: 12)
                        )
                        .frame(width: 12, height: 12)
                        Text(parentFolderName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                    .foregroundStyle(.secondary)
                }
                .contentShape(Capsule())
                .buttonStyle(.plain)
                .help("Reveal in Finder: \(PrivacyPathMasker.redactedPath(fileURL.deletingLastPathComponent().path))")
                
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    if let date = file.creationDate {
                        Text("•")
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !isOriginal {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.small)
            } else {
                Text("Original")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.1), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct UnifiedDuplicateGroupDetailView: View {
    let group: UnifiedDuplicateGroup
    let onDelete: ([FileItem]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupOverview

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(sortedFiles, id: \.id) { file in
                        UnifiedFileDetailRow(
                            file: file,
                            isRecommended: file.id == group.recommendedFileId,
                            recommendation: recommendationLabel(for: file),
                            onDelete: {
                                onDelete([file])
                            }
                        )
                    }
                }
                .padding(18)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.35))
        }
    }

    private var groupOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    overviewTitle

                    Spacer(minLength: 12)

                    primaryActionButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    overviewTitle
                    primaryActionButton
                }
            }

            ViewThatFits(in: .horizontal) {
                metricsRow
                VStack(spacing: 8) {
                    metricsRow
                }
            }

            Text(detailGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 10) {
            DuplicateMetricTile(value: "\(group.files.count)", label: group.isExact ? "copies" : "versions", color: .primary)
            DuplicateMetricTile(value: ByteCountFormatter.string(fromByteCount: group.potentialSavings, countStyle: .file), label: "recoverable", color: .green)
            DuplicateMetricTile(value: group.similarityPercentage ?? "Exact", label: group.isExact ? "match" : "similarity", color: group.isExact ? .orange : .blue)
        }
    }

    private var overviewTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.groupTypeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(group.isExact ? .orange : .blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(group.isExact ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1), in: Capsule())

                confidenceBadge
            }

            Text(group.displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
    }

    private var confidenceBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(confidenceColor)
                .frame(width: 6, height: 6)
            Text(group.confidenceLevel.rawValue)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(confidenceColor.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        if let recommendation = group.recommendation {
            Button {
                applyRecommendation()
            } label: {
                Text(compactButtonTitle(for: recommendation))
            }
            .buttonStyle(.onboardingPill)
            .tint(.blue)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)
            .help(recommendation.description)
        } else {
            Button {
                let sortedFiles = group.files.sorted { f1, f2 in
                    let d1 = f1.creationDate ?? Date.distantPast
                    let d2 = f2.creationDate ?? Date.distantPast
                    return d1 < d2
                }
                onDelete(Array(sortedFiles.dropFirst()))
            } label: {
                Text("Keep First")
            }
            .buttonStyle(.onboardingPill)
            .tint(.red)
            .controlSize(.regular)
            .fixedSize(horizontal: true, vertical: false)
            .help("Keep the first file and clean up the rest.")
        }
    }
    
    private var confidenceColor: Color {
        switch group.confidenceLevel {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        }
    }
    
    private var sortedFiles: [FileItem] {
        // Put recommended file first, then sort by date
        let recommendedId = group.recommendedFileId
        return group.files.sorted { f1, f2 in
            if f1.id == recommendedId { return true }
            if f2.id == recommendedId { return false }
            let d1 = f1.creationDate ?? Date.distantPast
            let d2 = f2.creationDate ?? Date.distantPast
            return d1 < d2
        }
    }
    
    private func recommendationLabel(for file: FileItem) -> String? {
        guard file.id == group.recommendedFileId else { return nil }
        
        switch group.recommendation {
        case .keepHighestResolution:
            return "Highest Res"
        case .keepNewest:
            return "Newest"
        case .keepOldest:
            return "Original"
        case .keepLargest:
            return "Largest"
        case .archiveOlderVersions:
            return "Latest Draft"
        case .manualReview, .none:
            return "Recommended"
        }
    }

    private var detailGuidance: String {
        if group.isExact {
            return "Exact matches have identical content. Keep one copy, then remove the rest when you are confident about the location you want to preserve."
        }

        return "Similar files may be versions or variants. Review thumbnails, dates, and resolution before applying the recommendation."
    }

    private func compactButtonTitle(for recommendation: SemanticDuplicateGroup.DuplicateRecommendation) -> String {
        switch recommendation {
        case .keepHighestResolution:
            return "Keep Highest Res"
        case .keepNewest:
            return "Keep Newest"
        case .keepOldest:
            return "Keep Original"
        case .keepLargest:
            return "Keep Largest"
        case .archiveOlderVersions:
            return "Archive Older"
        case .manualReview:
            return "Review"
        }
    }
    
    private func applyRecommendation() {
        guard let recommendedId = group.recommendedFileId else {
            // Manual review - delete none
            return
        }
        let filesToRemove = group.files.filter { $0.id != recommendedId }
        onDelete(filesToRemove)
    }
}

private struct DuplicateMetricTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }
}

struct UnifiedFileDetailRow: View {
    let file: FileItem
    let isRecommended: Bool
    let recommendation: String?
    let onDelete: () -> Void
    
    private var fileURL: URL {
        URL(fileURLWithPath: file.path)
    }
    
    private var parentFolderName: String {
        fileURL.deletingLastPathComponent().lastPathComponent
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                FileThumbnailView(url: fileURL, size: CGSize(width: 44, height: 44))
                
                if isRecommended {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 10))
                        .padding(2)
                        .background(Circle().fill(.white))
                        .offset(x: 4, y: 4)
                        .help("Recommended to Keep")
                }
            }
            .frame(width: 44, height: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(file.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    if let label = recommendation {
                        Text(label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue))
                    }
                }
                
                Button {
                    NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                } label: {
                    HStack(spacing: 4) {
                        AppKitImageView(
                            image: NSWorkspace.shared.icon(forFile: fileURL.deletingLastPathComponent().path),
                            size: CGSize(width: 12, height: 12)
                        )
                        .frame(width: 12, height: 12)
                        Text(parentFolderName)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
                    .foregroundStyle(.secondary)
                }
                .contentShape(Capsule())
                .buttonStyle(.plain)
                .help("Reveal in Finder: \(PrivacyPathMasker.redactedPath(fileURL.deletingLastPathComponent().path))")
                
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    if let date = file.creationDate {
                        Text("•")
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let pixels = file.totalPixels, pixels > 0 {
                        Text("•")
                        Text("\(formatPixels(pixels))")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .layoutPriority(1)
            
            if !isRecommended {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.small)
                .help("Delete this duplicate")
            } else {
                Label("Keep", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(isRecommended ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(isRecommended ? Color.green.opacity(0.22) : Color.white.opacity(0.08), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
    
    private func formatPixels(_ pixels: Int) -> String {
        let mp = Double(pixels) / 1_000_000.0
        return String(format: "%.1f MP", mp)
    }
}

struct DuplicatesSummaryCardMini: View {
    @ObservedObject var manager: DuplicateDetectionManager
    
    var body: some View {
        HStack(spacing: 0) {
            Text("Scan Results")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize()
            
            Spacer()
            
            HStack(spacing: 8) {
                if manager.exactGroupCount > 0 {
                    HStack(spacing: 4) {
                        Text("\(manager.totalDuplicates)")
                            .font(.subheadline.bold())
                        Text("exact")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                
                if manager.semanticGroupCount > 0 {
                    if manager.exactGroupCount > 0 {
                        Text("+")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("\(manager.semanticGroups.reduce(0) { $0 + max(0, $1.files.count - 1) })")
                            .font(.subheadline.bold())
                            .foregroundStyle(.blue)
                        Text("similar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                }
                
                Divider()
                    .frame(height: 12)
                
                HStack(spacing: 4) {
                    Text(manager.formattedSavingsIncludingSemantic)
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                    Text("recoverable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// Reused components
struct DuplicatesEmptyStateView: View {
    let title: String
    let description: String
    let icon: String
    var iconColor: Color = .secondary
    let actionTitle: String
    var actionAccessibilityIdentifier: String?
    let action: () -> Void
    @State private var hasAppeared = false
    @State private var beamHasAppeared = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(iconColor)
                .opacity(0.7)
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.8)
                .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
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
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
            
            Button(action: action) {
                Text(actionTitle)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.onboardingPill)
            .onboardingBeamBorder(variant: .featured, active: beamHasAppeared)

            .controlSize(.large)
            .accessibilityLabel(actionTitle)
            .accessibilityHint("Activate to \(actionTitle.lowercased())")
            .accessibilityIdentifier(actionAccessibilityIdentifier ?? "\(title.replacingOccurrences(of: " ", with: ""))Action")
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 15)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                beamHasAppeared = true
            }
        }
    }
}

struct ScanProgressViewNew: View {
    let progress: Double
    var isPreparing: Bool = false

    private var clampedProgress: Double {
        max(0, min(1, progress))
    }

    private var percent: Int {
        Int((clampedProgress * 100).rounded())
    }

    private var title: String {
        isPreparing ? "Preparing Scan..." : "Computing File Hashes"
    }

    private var subtitle: String {
        isPreparing ? "Reading directory structure..." : "Comparing file content to find exact matches..."
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                progressCard
            }
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isPreparing ? "Preparing scan" : "Scanning for duplicate files, \(percent) percent complete")
    }

    private var progressCard: some View {
        ZStack {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isPreparing ? "magnifyingglass" : "doc.text.magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(title)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if !isPreparing {
                            Text("\(percent)%")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.3), value: percent)
                        }
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                LoadingDotsView(dotCount: 3, dotSize: 5, color: .accentColor)
                    .frame(width: 34)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 390, height: 94)
        .background {
            beamSurface
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPreparing ? "Preparing to scan for duplicates" : "Computing file hashes to find exact duplicate matches")
        .accessibilityValue(isPreparing ? subtitle : "\(percent) percent complete, \(subtitle)")
    }

    private var beamSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.clear)
                .systemLiquidGlassBackground(cornerRadius: 16)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
        .beam(
            .medium,
            palette: .colorful,
            theme: .dark,
            active: true,
            cornerRadius: 16,
            strength: 1.0
        )
        .scanProgressReferenceBeamFallback(cornerRadius: 16, active: true, includesInteriorGlow: true)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    func scanProgressReferenceBeamFallback(
        cornerRadius: CGFloat,
        active: Bool,
        includesInteriorGlow: Bool = false
    ) -> some View {
        overlay {
            ScanProgressReferenceBeamFallback(
                cornerRadius: cornerRadius,
                active: active,
                includesInteriorGlow: includesInteriorGlow
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct ScanProgressReferenceBeamFallback: View {
    let cornerRadius: CGFloat
    let active: Bool
    let includesInteriorGlow: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.TimelineView(.animation(paused: reduceMotion || !active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = reduceMotion ? 0 : time / 1.96
            ZStack {
                if includesInteriorGlow {
                    beamInteriorGlow(phase: phase)
                }

                beamStroke(phase: phase)
            }
            .opacity(active ? 0.82 : 0)
            .animation(.easeOut(duration: 0.6), value: active)
        }
    }

    private func beamStroke(phase: TimeInterval) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .clear, location: 0.08),
                        .init(color: Color(red: 0.08, green: 0.80, blue: 1.0).opacity(0.36), location: 0.16),
                        .init(color: Color(red: 0.92, green: 0.16, blue: 0.58).opacity(0.62), location: 0.25),
                        .init(color: .white.opacity(0.88), location: 0.32),
                        .init(color: Color(red: 1.0, green: 0.34, blue: 0.18).opacity(0.54), location: 0.39),
                        .init(color: Color(red: 0.40, green: 0.20, blue: 1.0).opacity(0.36), location: 0.48),
                        .init(color: .clear, location: 0.58),
                        .init(color: .clear, location: 1.00),
                    ],
                    center: .center,
                    angle: .degrees((phase.truncatingRemainder(dividingBy: 1)) * 360)
                ),
                lineWidth: 1
            )
    }

    private func beamInteriorGlow(phase: TimeInterval) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: 3)
            .fill(
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: Color(red: 0.08, green: 0.80, blue: 1.0).opacity(0.10), location: 0.15),
                        .init(color: Color(red: 0.92, green: 0.16, blue: 0.58).opacity(0.20), location: 0.25),
                        .init(color: .white.opacity(0.16), location: 0.32),
                        .init(color: Color(red: 1.0, green: 0.34, blue: 0.18).opacity(0.14), location: 0.40),
                        .init(color: .clear, location: 0.58),
                        .init(color: .clear, location: 1.00),
                    ],
                    center: .center,
                    angle: .degrees((phase.truncatingRemainder(dividingBy: 1)) * 360)
                )
            )
            .blur(radius: 9)
            .mask {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(lineWidth: 22)
                    .blur(radius: 7)
            }
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

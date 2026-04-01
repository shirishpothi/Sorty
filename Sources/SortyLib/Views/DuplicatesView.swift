//
//  DuplicatesView.swift
//  Sorty
//
//  UI for displaying and managing duplicate files
//  Enhanced with haptic feedback, "Liquid Glass" aesthetic, and Split View layout
//

import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var detectionManager: DuplicateDetectionManager
    @EnvironmentObject var settingsManager: DuplicateSettingsManager
    @State private var selectedGroup: UnifiedDuplicateGroup?
    @State private var showDeleteConfirmation = false
    @State private var filesToDelete: [FileItem] = []
    @State private var contentOpacity: Double = 1
    @State private var showSettings = false
    @AppStorage("enableSafeDeletion") private var enableSafeDeletion = true
    @State private var localDirectory: URL?
    @State private var handoffFilePaths: [String] = []
    @State private var currentScanTask: Task<Void, Never>?
    @State private var capturedDirectory: URL?
    @State private var semanticScanProgress: String?
    
    // Derived directory: Use local if set, otherwise fallback to global
    private var effectiveDirectory: URL? {
        localDirectory ?? appState.selectedDirectory
    }

    var body: some View {
        VStack(spacing: 0) {
            if effectiveDirectory == nil {
                // Base page: Workspace-Health-style layout
                ScrollView {
                    VStack(spacing: 24) {
                        duplicatesBaseHeaderSection()
                        duplicatesBaseDirectorySelector()
                        duplicatesBaseEmptyState()
                    }
                    .padding(32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
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
            consumePendingHandoffIfNeeded()
        }
        .onChange(of: effectiveDirectory) { _, _ in
            // Cancel in-flight scan if directory changes
            currentScanTask?.cancel()
            // Clear results when switching directories to prevent showing stale data
            detectionManager.clearResults()
            selectedGroup = nil
        }
        .onChange(of: appState.pendingDuplicatesHandoff) { _, handoff in
            guard let handoff else { return }
            apply(handoff: handoff)
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
            localDirectory = directory
            appState.selectedDirectory = directory
        }
        handoffFilePaths = handoff.filePaths

        detectionManager.clearResults()
        selectedGroup = nil
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: "/tmp"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .opacity(0.6)

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
        VStack(spacing: 20) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .opacity(0.7)

            VStack(spacing: 8) {
                Text("Select a Directory")
                    .font(.title2.bold())

                Text("Choose a folder to scan for identical files and recover disk space")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }

            Button("Choose Directory") {
                selectDirectory()
            }
            .buttonStyle(.onboardingPill)
            .controlSize(.large)
            .accessibilityIdentifier("DuplicatesEmptyChooseDirectory")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        GeometryReader { geometry in
            HSplitView {
                // Left Pane: List of Groups
                VStack(spacing: 0) {
                    // Summary Header
                    DuplicatesSummaryCardMini(manager: detectionManager)
                        .padding()
                    
                    Divider()
                    
                    List(selection: $selectedGroup) {
                        ForEach(detectionManager.allGroups) { group in
                            UnifiedDuplicateGroupRow(group: group)
                                .tag(group)
                                .scaleEffect(selectedGroup == group ? 1.01 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedGroup)
                        }
                    }
                    .listStyle(.inset)
                }
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                
                // Right Pane: Detail View
                if let group = selectedGroup {
                    UnifiedDuplicateGroupDetailView(
                        group: group,
                        onDelete: { files in
                            filesToDelete = files
                            showDeleteConfirmation = true
                        }
                    )
                    .frame(minWidth: 400, maxWidth: .infinity)
                } else {
                    VStack {
                        Image(systemName: "arrow.left")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Select a duplicate group to view details")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
                            selectedGroup = first
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
            localDirectory = url
            detectionManager.clearResults()
            selectedGroup = nil
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
        HStack(spacing: 20) {
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
                    
                    if let dir = currentDirectory {
                        Button(action: onSelectDirectory) {
                            HStack(spacing: 4) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: dir.path))
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                                Text(dir.lastPathComponent)
                                    .fontWeight(.medium)
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
                    }
                }
            }
            
            Spacer()
            
            // Right Side: Controls
            HStack(spacing: 12) {
                // Safe Deletion Status
                Button { showInfo.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: enableSafeDeletion ? "shield.checkered" : "shield.slash")
                        Text(enableSafeDeletion ? "Safe Mode" : "Direct Delete")
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

                    Button(action: onSelectDirectory) {
                         Label("Change Folder", systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
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
                            Label("Cleanup All", systemImage: "trash")
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
                            Label(manager.lastScanDate == nil ? "Start Scan" : "Rescan", systemImage: manager.lastScanDate == nil ? "play.fill" : "arrow.clockwise")
                        }
                        .buttonStyle(.onboardingPill(size: .small))
                        .disabled(currentDirectory == nil)
                    }
                }
            }
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
                        Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.deletingLastPathComponent().path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
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
                .buttonStyle(.bordered)
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
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(group.displayName)
                                .font(.title2.bold())
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Type badge
                            Text(group.groupTypeLabel)
                                .font(.caption.bold())
                                .foregroundStyle(group.isExact ? .orange : .blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(group.isExact ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                                )
                        }
                        
                        HStack(spacing: 8) {
                            Text("\(group.files.count) \(group.isExact ? "identical files" : "similar files") found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            if let similarity = group.similarityPercentage {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                Text("\(similarity) Similar")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(group.similarity >= 0.98 ? .green : (group.similarity >= 0.90 ? .blue : .orange))
                            }
                            
                            // Confidence indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(confidenceColor)
                                    .frame(width: 6, height: 6)
                                Text(group.confidenceLevel.rawValue)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(confidenceColor.opacity(0.1), in: Capsule())
                        }
                    }
                    .layoutPriority(1)
                    
                    Spacer()
                    
                    // Action button based on recommendation
                    if let recommendation = group.recommendation {
                        Button {
                            applyRecommendation()
                        } label: {
                            Text(compactButtonTitle(for: recommendation))
                        }
                        .buttonStyle(.onboardingPill)
                        .tint(.blue)
                        .layoutPriority(2)
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
                        .layoutPriority(2)
                        .help("Keep the first file and clean up the rest.")
                    }
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // File List
            List {
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
            .listStyle(.inset)
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
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                FileThumbnailView(url: fileURL, size: CGSize(width: 36, height: 36))
                
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
            .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(file.displayName)
                        .font(.headline)
                    
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
                        Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.deletingLastPathComponent().path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
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
                    if let pixels = file.totalPixels, pixels > 0 {
                        Text("•")
                        Text("\(formatPixels(pixels))")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !isRecommended {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Keep")
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
                    .buttonStyle(.onboardingPill)

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
    var isPreparing: Bool = false

    var body: some View {
        VStack(spacing: 28) {
            ZStack {
                if isPreparing {
                    SortyGradientCircularLoader(size: 120, lineWidth: 10)
                } else {
                    SortyGradientCircularProgress(progress: progress, size: 120, lineWidth: 10)
                }
                
                if isPreparing {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.accentColor)
                } else {
                    VStack(spacing: 2) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                        Text("Scanning")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Scan progress")
            .accessibilityValue(isPreparing ? "Preparing scan" : "\(Int(progress * 100)) percent complete")
            
            VStack(spacing: 6) {
                Text(isPreparing ? "Preparing Scan..." : "Computing File Hashes")
                    .font(.subheadline.weight(.medium))
                Text(isPreparing ? "Reading directory structure..." : "Comparing file content to find exact matches...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                LoadingDotsView(dotCount: 3, dotSize: 5, color: .accentColor)
                    .padding(.top, 6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isPreparing ? "Preparing to scan for duplicates" : "Computing file hashes to find exact duplicate matches")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isPreparing ? "Preparing scan" : "Scanning for duplicate files, \(Int(progress * 100)) percent complete")
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

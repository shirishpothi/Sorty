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
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var showDeleteConfirmation = false
    @State private var filesToDelete: [FileItem] = []
    @State private var contentOpacity: Double = 0
    @State private var showSettings = false
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
            return detectionManager.allGroups.isEmpty
        }
    }

    private var isPreparingScan: Bool {
        detectionManager.state == .preparing
    }

    private var duplicateScanProgress: Double {
        guard case .scanning(let progress) = detectionManager.state else { return 0 }
        return progress
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
                    case .preparing, .scanning:
                        ScanProgressViewNew(
                            progress: duplicateScanProgress,
                            isPreparing: isPreparingScan,
                            stage: detectionManager.scanStage
                        )
                            .transition(.sortyScaleAndFade)

                    case .idle:
                        if detectionManager.lastScanDate == nil {
                            DuplicatesEmptyStateView(
                                title: "Ready to Scan",
                                description:
                                    "Identical files in \(effectiveDirectory?.lastPathComponent ?? "this folder") will be identified.",
                                icon: "waveform.path.ecg",
                                iconColor: SortyDesignSystem.Colors.resolvedAccent,
                                actionTitle: "Start Scan",
                                animatesIcon: true,
                                isDefaultAction: true,
                                action: startScan
                            )
                            .transition(.sortyScaleAndFade)
                        } else {
                            noDuplicatesView
                                .transition(.sortyScaleAndFade)
                        }

                    case .completed, .failed:
                        if detectionManager.allGroups.isEmpty {
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
        .alert("Move Duplicate Files to Trash?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                HapticFeedbackManager.shared.tap()
            }
            Button("Delete", role: .destructive) {
                HapticFeedbackManager.shared.error()
                AnalyticsManager.shared.captureImportantButton(
                    "confirm_duplicate_cleanup",
                    screen: "duplicates",
                    feature: "duplicate_cleanup"
                )
                deleteFiles(filesToDelete)
            }
        } message: {
            Text(
                "\(filesToDelete.count) file(s) will be moved to Trash. History can restore them until Trash is emptied."
            )
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
            title: detectionManager.unreadableFileCount > 0
                ? "Scan Incomplete"
                : "No Duplicates Found",
            description: detectionManager.unreadableFileCount > 0
                ? "Sorty couldn't read \(detectionManager.unreadableFileCount) file\(detectionManager.unreadableFileCount == 1 ? "" : "s"). Make cloud files available offline or reconnect the drive, then scan again."
                : "All readable files in this folder are unique.",
            icon: detectionManager.unreadableFileCount > 0
                ? "exclamationmark.triangle.fill"
                : "checkmark.circle.fill",
            heroTint: detectionManager.unreadableFileCount > 0 ? .orange : .green,
            actionTitle: "Scan Another Folder",
            action: selectDirectory
        )
    }

    private var resultsView: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    DuplicatesResultsSidebarHeader(
                        manager: detectionManager,
                        showsStats: settingsViewModel.config.showStatsForNerds
                    )

                    Divider()

                    List(selection: $appState.duplicateSelectedGroup) {
                        if !exactGroups.isEmpty {
                            Section {
                                ForEach(exactGroups) { group in
                                    UnifiedDuplicateGroupRow(group: group)
                                        .tag(group)
                                }
                            } header: {
                                Text("Exact duplicates")
                            }
                        }

                        if !similarGroups.isEmpty {
                            Section {
                                ForEach(similarGroups) { group in
                                    UnifiedDuplicateGroupRow(group: group)
                                        .tag(group)
                                }
                            } header: {
                                Text("Similarity matches")
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                }
                .frame(width: 340, height: geometry.size.height, alignment: .topLeading)

                Divider()

                if let group = appState.duplicateSelectedGroup {
                    UnifiedDuplicateGroupDetailView(
                        group: group,
                        settings: settingsManager.settings,
                        onDelete: { files in
                            filesToDelete = files
                            showDeleteConfirmation = true
                        }
                    )
                    .frame(
                        minWidth: 0,
                        maxWidth: .infinity,
                        minHeight: 0,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Choose a group")
                            .font(.headline)
                        Text(
                            "Review exact duplicates first. Similarity matches stay separate and need individual confirmation."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .topLeading
            )
        }
    }

    private var exactGroups: [UnifiedDuplicateGroup] {
        detectionManager.allGroups.filter { $0.isExact }
    }

    private var similarGroups: [UnifiedDuplicateGroup] {
        detectionManager.allGroups.filter { $0.isSemantic }
    }

    private func startScan() {
        guard let directory = effectiveDirectory else { return }
        let handoffPaths = handoffFilePaths
        handoffFilePaths = []
        let settings = settingsManager.settings
        HapticFeedbackManager.shared.tap()

        // Cancel any in-flight scan
        currentScanTask?.cancel()

        // Capture current directory
        capturedDirectory = directory
        detectionManager.state = .preparing

        currentScanTask = Task {
            let scanner = DirectoryScanner()
            do {
                let scanSource = try await resolveFilesForScan(
                    scanner: scanner,
                    directory: directory,
                    handoffPaths: handoffPaths,
                    settings: settings
                )

                // Verify directory hasn't changed since scan started
                if capturedDirectory == effectiveDirectory && !Task.isCancelled {
                    switch scanSource {
                    case .inventory(let inventory):
                        await detectionManager.scanForDuplicates(
                            inventory: inventory,
                            settings: settings
                        )
                    case .files(let files):
                        await detectionManager.scanForDuplicates(
                            files: files,
                            settings: settings
                        )
                    }

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
                    AnalyticsManager.shared.captureWorkflow(
                        workflow: "duplicate_scan",
                        stage: "preparing",
                        outcome: "failed"
                    )
                    AnalyticsManager.shared.capture(
                        error: error,
                        feature: "duplicates",
                        operation: "scan_directory"
                    )
                }
            }
        }
    }

    private func resolveFilesForScan(
        scanner: DirectoryScanner,
        directory: URL,
        handoffPaths: [String],
        settings: DuplicateSettings
    ) async throws -> ResolvedDuplicateScan {
        guard !handoffPaths.isEmpty else {
            let inventory = try await scanner.scanDirectoryForDuplicates(
                at: directory,
                settings: settings
            ) { scanned, stage in
                self.detectionManager.scanStage = "\(stage) \(scanned.formatted()) scanned"
            }
            return .inventory(inventory)
        }

        var targetedFiles: [FileItem] = []
        for path in handoffPaths {
            if Task.isCancelled { break }

            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            if let scannedFile = try? await scanner.scanFile(
                at: fileURL,
                deepScan: false,
                computeHashes: false
            ), !scannedFile.isDirectory
            {
                targetedFiles.append(scannedFile)
            }
        }

        if targetedFiles.count >= 2 {
            return .files(targetedFiles)
        }

        // Fallback when history paths no longer exist or are insufficient.
        let inventory = try await scanner.scanDirectoryForDuplicates(
            at: directory,
            settings: settings
        ) { scanned, stage in
            self.detectionManager.scanStage = "\(stage) \(scanned.formatted()) scanned"
        }
        return .inventory(inventory)
    }

    private enum ResolvedDuplicateScan {
        case inventory(DuplicateScanInventory)
        case files([FileItem])
    }

    private func cancelScan() {
        AnalyticsManager.shared.captureImportantButton(
            "cancel_duplicate_scan",
            screen: "duplicates",
            feature: "duplicate_scan"
        )
        currentScanTask?.cancel()
        currentScanTask = nil
        detectionManager.isScanning = false
        detectionManager.state = .idle
        HapticFeedbackManager.shared.tap()
    }

    private func deleteFiles(_ files: [FileItem]) {
        var totalDeleted = 0
        var totalSizeRecovered: Int64 = 0

        do {
            let potentialRestorables = try DuplicateRestorationManager.shared.moveToTrash(
                files: files)
            totalDeleted = potentialRestorables.count
            totalSizeRecovered = files.reduce(0) { $0 + $1.size }

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
                    duplicateCleanupMode: .trash
                )
                appState.organizer?.history.addEntry(entry)
            }

            HapticFeedbackManager.shared.success()
            AnalyticsManager.shared.captureFeature(
                feature: "duplicates",
                subfeature: "cleanup",
                action: "move_to_trash",
                outcome: "success",
                properties: [
                    "count_bucket": AnalyticsManager.countBucket(totalDeleted),
                ]
            )
        } catch {
            HapticFeedbackManager.shared.error()
            DebugLogger.log("Delete failed: \(error)")
            AnalyticsManager.shared.captureFeature(
                feature: "duplicates",
                subfeature: "cleanup",
                action: "move_to_trash",
                outcome: "failed",
                properties: [
                    "count_bucket": AnalyticsManager.countBucket(files.count),
                ]
            )
            AnalyticsManager.shared.capture(
                error: error,
                feature: "duplicates",
                operation: "move_to_trash"
            )
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

    private func prepareBulkDelete(strategyOverride: KeepStrategy?) {
        var filesToDelete: [FileItem] = []

        // Bulk cleanup is intentionally limited to byte-identical files.
        for group in detectionManager.allGroups where group.isExact {
            let keepFileID = strategyOverride
                .flatMap { CleanupPreferenceResolver.preferredFileID(in: group.files, strategy: $0) }
                ?? CleanupPreferenceResolver.preferredFileID(
                    in: group.files,
                    strategy: settingsManager.settings.defaultKeepStrategy
                )

            filesToDelete.append(contentsOf: group.files.filter { $0.id != keepFileID })
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
    let onBulkDelete: (KeepStrategy?) -> Void
    let onSettings: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            headerLayout(spacing: 20, showsFullControls: true)
                .frame(minWidth: 760)
            headerLayout(spacing: 12, showsFullControls: false)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
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
                            .background(
                                Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
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
                HStack(spacing: 8) {
                    Button(action: onSettings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .systemLiquidGlassButton()
                    .help("Detection Settings")
                    .disabled(manager.isScanning)

                    if manager.exactGroupCount > 0 && !manager.isScanning {
                        Menu {
                            Button {
                                onBulkDelete(.newest)
                            } label: {
                                Label("Keep Newest", systemImage: "clock")
                            }
                            Button {
                                onBulkDelete(.oldest)
                            } label: {
                                Label("Keep Oldest", systemImage: "clock.arrow.circlepath")
                            }
                            Divider()
                            Text("Similar matches always require individual review")
                                .font(.caption)
                        } label: {
                            Label(
                                showsFullControls ? "Cleanup All" : "Cleanup", systemImage: "trash")
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
                    } else if manager.lastScanDate == nil {
                        Button(action: onScan) {
                            Label(
                                showsFullControls ? "Start Scan" : "Scan", systemImage: "play.fill")
                        }
                        .buttonStyle(.onboardingPill(size: .small))
                        .disabled(currentDirectory == nil)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
        }
    }
}

// MARK: - Components

private struct DuplicatesResultsSidebarHeader: View {
    @ObservedObject var manager: DuplicateDetectionManager
    let showsStats: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review groups")
                    .font(.headline)

                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .numericTextTransition(animationValue: summaryText)
            }

            if showsStats {
                DuplicatesNerdStatsStrip(manager: manager)
            }

            if manager.unreadableFileCount > 0 {
                Label(
                    "\(manager.unreadableFileCount) file\(manager.unreadableFileCount == 1 ? " was" : "s were") unavailable and excluded from these results.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .numericTextTransition(animationValue: manager.unreadableFileCount)
            }

            if manager.semanticSkippedFileCount > 0 {
                Label(
                    "Exact duplicate results are complete. Similarity matching was skipped for this large folder to keep resource use stable.",
                    systemImage: "leaf"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if manager.semanticGroupCount > 0 {
                Label("Cleanup All only removes exact duplicates.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summaryText: String {
        let exact = "\(manager.exactGroupCount) exact group\(manager.exactGroupCount == 1 ? "" : "s")"
        let similar = "\(manager.semanticGroupCount) similarity match\(manager.semanticGroupCount == 1 ? "" : "es")"
        let recoverable = "\(manager.formattedSavings) safely recoverable"
        return [exact, similar, recoverable].joined(separator: " • ")
    }
}

private struct DuplicatesNerdStatsStrip: View {
    @ObservedObject var manager: DuplicateDetectionManager

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                stat("Scanned", value: "\(manager.scannedFileCount)")
                stat("Candidates", value: "\(manager.hashCandidateCount)")
            }
            HStack(spacing: 8) {
                stat("Sampled", value: "\(manager.sampledFileCount)")
                stat("Full hashes", value: "\(manager.hashedFileCount)")
            }
            HStack(spacing: 8) {
                stat("Cache hits", value: "\(manager.hashCacheHitCount)")
                stat("Similar analyzed", value: "\(manager.semanticAnalyzedFileCount)")
            }
            if manager.unreadableFileCount > 0 {
                stat("Unreadable", value: "\(manager.unreadableFileCount)")
            }
            stat("Duration", value: formattedDuration)
        }
        .padding(10)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Duplicate scan stats. \(manager.scannedFileCount) files scanned. \(manager.hashCandidateCount) hash candidates. \(manager.sampledFileCount) files sampled. \(manager.hashedFileCount) files fully hashed. \(manager.hashCacheHitCount) cache hits. \(manager.semanticAnalyzedFileCount) files analyzed for similarity. \(manager.semanticSkippedFileCount) files skipped for similarity. \(manager.unreadableFileCount) unreadable files. Duration \(formattedDuration)."
        )
    }

    private func stat(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .numericTextTransition(animationValue: value)
        }
        .font(.caption2)
    }

    private var formattedDuration: String {
        guard manager.scanDuration > 0 else { return "—" }
        return String(format: "%.2fs", manager.scanDuration)
    }
}

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
                        .numericTextTransition(animationValue: group.files.count)
                    Text("•")
                    Text(
                        "Save \(ByteCountFormatter.string(fromByteCount: group.potentialSavings, countStyle: .file))"
                    )
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

    private var folderSummary: String {
        let folders = Set(
            group.files.map {
                URL(fileURLWithPath: $0.path).deletingLastPathComponent().lastPathComponent
            })
        if folders.count == 1, let folder = folders.first, !folder.isEmpty {
            return folder
        }
        return "Across \(folders.count) folders"
    }

    private var badgeColor: Color {
        group.isExact ? .orange : .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            if let url = firstFileURL {
                FileThumbnailView(url: url, size: CGSize(width: 40, height: 40))
                    .frame(width: 40, height: 40)
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(badgeColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: group.isExact ? "doc.on.doc.fill" : "waveform.path")
                            .foregroundStyle(badgeColor)
                            .symbolReplaceTransition(animationValue: group.isExact)
                    }
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(group.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(group.displayName)

                HStack(spacing: 5) {
                    Label(folderSummary, systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text("•")
                    Text("\(group.files.count) \(group.isExact ? "copies" : "matches")")
                        .numericTextTransition(animationValue: group.files.count)
                    Text("•")
                    Text(
                        ByteCountFormatter.string(
                            fromByteCount: group.potentialSavings, countStyle: .file)
                    )
                    .foregroundStyle(.green)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .layoutPriority(1)

            if !group.isExact {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(group.similarityPercentage ?? "")
                        .font(.caption.monospacedDigit().weight(.semibold))

                    Text("Similarity")
                        .font(.caption2.weight(.semibold))
                        .numericTextTransition(animationValue: group.isExact)
                }
                .foregroundStyle(badgeColor)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 7)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
                        .numericTextTransition(animationValue: group.files.count)
                }
                .layoutPriority(1)

                Spacer()

                Button {
                    let sortedFiles = group.files.sorted { f1, f2 in
                        let d1 = f1.creationDate ?? Date.distantPast
                        let d2 = f2.creationDate ?? Date.distantPast
                        return d1 < d2  // Keep oldest
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
                    DuplicateFileDetailRow(
                        file: file, isOriginal: index == 0,
                        onDelete: {
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
                    NSWorkspace.shared.selectFile(
                        file.path,
                        inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                } label: {
                    HStack(spacing: 4) {
                        AppKitImageView(
                            image: NSWorkspace.shared.icon(
                                forFile: fileURL.deletingLastPathComponent().path),
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
                .help(
                    "Reveal in Finder: \(PrivacyPathMasker.redactedPath(fileURL.deletingLastPathComponent().path))"
                )

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
    let settings: DuplicateSettings
    let onDelete: ([FileItem]) -> Void
    @State private var selectedKeepFileId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            groupOverview

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(sortedFiles, id: \.id) { file in
                        UnifiedFileDetailRow(
                            file: file,
                            isRecommended: file.id == effectiveKeepFileId,
                            recommendation: recommendationLabel(for: file),
                            onKeep: {
                                HapticFeedbackManager.shared.selection()
                                selectedKeepFileId = file.id
                            },
                            onDelete: {
                                onDelete([file])
                            }
                        )
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            selectedKeepFileId = preferredKeepFileId()
        }
        .onChange(of: group.id) { _, _ in
            selectedKeepFileId = preferredKeepFileId()
        }
        .onChange(of: settings.defaultKeepStrategy) { _, _ in
            selectedKeepFileId = preferredKeepFileId()
        }
    }

    private var groupOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                overviewTitle
                Spacer(minLength: 8)
            }

            HStack {
                primaryActionButton
                Spacer(minLength: 0)
            }

            metricsGrid

            if !group.isExact {
                Label(
                    "Excluded from Cleanup All. Review before applying a recommendation.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let recommendation = group.recommendation, recommendation == .manualReview {
                Text("This group needs manual review before Sorty will choose files to remove.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(detailGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 720, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 104), spacing: 8)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            DuplicateMetricTile(
                value: "\(group.files.count)", label: group.isExact ? "copies" : "versions",
                color: .primary)
            DuplicateMetricTile(
                value: ByteCountFormatter.string(
                    fromByteCount: group.potentialSavings, countStyle: .file), label: "recoverable",
                color: .green)
            DuplicateMetricTile(
                value: group.isExact ? "100%" : (group.similarityPercentage ?? "Review"),
                label: group.isExact ? "match" : "similarity",
                color: group.isExact ? .orange : .blue)
        }
    }

    private var overviewTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !group.isExact || group.confidenceLevel != .high {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        overviewBadges
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        overviewBadges
                    }
                }
            }

            Text(group.displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var overviewBadges: some View {
        if !group.isExact {
            Text(group.groupTypeLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1), in: Capsule())
        }

        if group.confidenceLevel != .high {
            confidenceBadge
        }
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
                removeFilesExceptSelectedKeepFile()
            } label: {
                Text(compactButtonTitle(for: recommendation))
            }
            .buttonStyle(.onboardingPill)
            .tint(.blue)
            .controlSize(.regular)
            .help(recommendation.description)
        } else {
            Button {
                removeFilesExceptSelectedKeepFile()
            } label: {
                Text("Clean Up Selected")
            }
            .buttonStyle(.onboardingPill)
            .tint(.red)
            .controlSize(.regular)
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
        let recommendedId = effectiveKeepFileId
        return group.files.sorted { f1, f2 in
            if f1.id == recommendedId { return true }
            if f2.id == recommendedId { return false }
            let d1 = f1.creationDate ?? Date.distantPast
            let d2 = f2.creationDate ?? Date.distantPast
            return d1 < d2
        }
    }

    private func recommendationLabel(for file: FileItem) -> String? {
        guard file.id == effectiveKeepFileId else { return nil }

        if selectedKeepFileId == file.id {
            return "Selected"
        }

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
            return
                "Exact matches have identical content. Keep one copy, then remove the rest when you are confident about the location you want to preserve."
        }

        return
            "Similar files may be versions or variants. Review thumbnails, dates, and resolution before applying the recommendation."
    }

    private func compactButtonTitle(
        for recommendation: SemanticDuplicateGroup.DuplicateRecommendation
    ) -> String {
        switch recommendation {
        case .keepHighestResolution:
            return "Clean Up Selected"
        case .keepNewest:
            return "Clean Up Selected"
        case .keepOldest:
            return "Clean Up Selected"
        case .keepLargest:
            return "Clean Up Selected"
        case .archiveOlderVersions:
            return "Archive Older"
        case .manualReview:
            return "Clean Up Selected"
        }
    }

    private var effectiveKeepFileId: UUID? {
        selectedKeepFileId ?? preferredKeepFileId()
    }

    private func removeFilesExceptSelectedKeepFile() {
        guard let keepId = effectiveKeepFileId else { return }
        let filesToRemove = group.files.filter { $0.id != keepId }
        onDelete(filesToRemove)
    }

    private func preferredKeepFileId() -> UUID? {
        if let recommended = group.recommendedFileId {
            return recommended
        }

        return keepFile(using: settings.defaultKeepStrategy)?.id
    }

    private func keepFile(using strategy: KeepStrategy) -> FileItem? {
        switch strategy {
        case .newest:
            return group.files.max { comparableDate(for: $0) < comparableDate(for: $1) }
        case .oldest:
            return group.files.min { comparableDate(for: $0) < comparableDate(for: $1) }
        case .largest:
            return group.files.max { $0.size < $1.size }
        case .smallest:
            return group.files.min { $0.size < $1.size }
        case .shortestPath:
            return group.files.min { $0.path.count < $1.path.count }
        }
    }

    private func comparableDate(for file: FileItem) -> Date {
        file.modificationDate ?? file.creationDate ?? .distantPast
    }
}

private struct DuplicateMetricTile: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .numericTextTransition(animationValue: value)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .systemLiquidGlassBackground(cornerRadius: 10)
        .frame(minHeight: 50)
        .accessibilityElement(children: .combine)
    }
}

struct UnifiedFileDetailRow: View {
    let file: FileItem
    let isRecommended: Bool
    let recommendation: String?
    let onKeep: () -> Void
    let onDelete: () -> Void

    private var fileURL: URL {
        URL(fileURLWithPath: file.path)
    }

    private var parentFolderName: String {
        fileURL.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        verticalLayout
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isRecommended ? Color.green.opacity(0.24) : Color.primary.opacity(0.07),
                    lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                fileSummary
            }

            HStack {
                if isRecommended {
                    keepBadge
                } else {
                    keepButton
                    deleteButton
                }
                Spacer()
            }
        }
    }

    private var thumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            FileThumbnailView(url: fileURL, size: CGSize(width: 44, height: 44))

            if isRecommended {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption2)
                    .padding(2)
                    .background(Circle().fill(.white))
                    .offset(x: 4, y: 4)
                    .help("Recommended to Keep")
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44)
    }

    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.displayName)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)

            if let label = recommendation {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.blue))
            }

            revealButton

            fileMetadata
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var revealButton: some View {
        Button {
            NSWorkspace.shared.selectFile(
                file.path,
                inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
        } label: {
            Label {
                Text(parentFolderName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                AppKitImageView(
                    image: NSWorkspace.shared.icon(
                        forFile: fileURL.deletingLastPathComponent().path),
                    size: CGSize(width: 12, height: 12)
                )
                .frame(width: 12, height: 12)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.1), in: Capsule())
            .foregroundStyle(.secondary)
        }
        .contentShape(Capsule())
        .buttonStyle(.plain)
        .help("Reveal in Finder: \(PrivacyPathMasker.redactedPath(fileURL.deletingLastPathComponent().path))")
    }

    private var fileMetadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
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

            VStack(alignment: .leading, spacing: 3) {
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                if let date = file.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                }
                if let pixels = file.totalPixels, pixels > 0 {
                    Text("\(formatPixels(pixels))")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Label("Remove", systemImage: "trash")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.sortyBordered)
        .controlSize(.small)
        .foregroundStyle(.red)
        .help("Delete this duplicate")
        .accessibilityLabel("Delete \(file.displayName)")
    }

    private var keepButton: some View {
        Button(action: onKeep) {
            Label("Keep This", systemImage: "checkmark.circle")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.sortyBordered)
        .controlSize(.small)
        .help("Keep this file and mark the others for cleanup")
    }

    private var keepBadge: some View {
        Label("Keep", systemImage: "checkmark.circle.fill")
            .font(.caption.bold())
            .foregroundStyle(.green)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.green.opacity(0.1), in: Capsule())
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
                            .numericTextTransition(animationValue: manager.totalDuplicates)
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
                        Text(
                            "\(manager.semanticGroups.reduce(0) { $0 + max(0, $1.files.count - 1) })"
                        )
                        .font(.subheadline.bold())
                        .foregroundStyle(.blue)
                        .numericTextTransition(
                            animationValue: manager.semanticGroups.reduce(0) {
                                $0 + max(0, $1.files.count - 1)
                            }
                        )
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
                        .numericTextTransition(
                            animationValue: manager.formattedSavingsIncludingSemantic
                        )
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
    var heroTint: Color?
    let actionTitle: String
    var actionAccessibilityIdentifier: String?
    var animatesIcon = false
    var isDefaultAction = false
    let action: () -> Void
    @State private var hasAppeared = false
    @State private var beamHasAppeared = false

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if animatesIcon {
                    ScanningPulseIcon(systemName: icon, color: iconColor)
                } else {
                    EmptyStateHeroIcon(systemName: icon, tint: heroTint)
                }
            }
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: hasAppeared)
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(LocalizedStringKey(title))
                    .font(.title2.bold())

                Text(LocalizedStringKey(description))
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
            .modifier(DefaultActionShortcut(isEnabled: isDefaultAction))
            .accessibilityLabel(actionTitle)
            .accessibilityHint(
                isDefaultAction
                    ? "Press Enter to \(actionTitle.lowercased())"
                    : "Activate to \(actionTitle.lowercased())"
            )
            .accessibilityIdentifier(
                actionAccessibilityIdentifier
                    ?? "\(title.replacingOccurrences(of: " ", with: ""))Action"
            )
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

private struct DefaultActionShortcut: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}

private struct ScanningPulseIcon: View {
    let systemName: String
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) {
            timeline in
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let pulse = reduceMotion ? 0.5 : (sin(elapsed * 3.2) + 1) / 2
            let beamPhase = reduceMotion ? 0.5 : elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8

            Image(systemName: systemName)
                .font(.system(size: 48))
                .foregroundStyle(color.opacity(0.55 + pulse * 0.2))
                .overlay {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [
                                .clear, .white, SortyDesignSystem.Colors.resolvedAccent, .clear,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.65)
                        .offset(
                            x: (proxy.size.width * 1.65 * beamPhase) - (proxy.size.width * 0.65))
                    }
                    .mask {
                        Image(systemName: systemName)
                            .font(.system(size: 48))
                    }
                    .opacity(reduceMotion ? 0.35 : 0.95)
                }
                .scaleEffect(reduceMotion ? 1 : 1 + pulse * 0.035)
                .shadow(
                    color: SortyDesignSystem.Colors.resolvedAccent.opacity(
                        reduceMotion ? 0.18 : 0.16 + pulse * 0.22),
                    radius: reduceMotion ? 4 : 4 + pulse * 5
                )
        }
        .frame(width: 72, height: 56)
        .accessibilityHidden(true)
    }
}

struct ScanProgressViewNew: View {
    let progress: Double
    var isPreparing: Bool = false
    var stage: String = ""

    @Environment(\.controlActiveState) private var controlActiveState

    private var isAnimationActive: Bool {
        controlActiveState != .inactive
    }

    private var clampedProgress: Double {
        max(0, min(1, progress))
    }

    private var percent: Int {
        Int((clampedProgress * 100).rounded())
    }

    private var title: String {
        if isPreparing {
            return "Preparing Scan..."
        }
        return stage.localizedCaseInsensitiveContains("semantic")
            ? "Finding Similar Files"
            : "Finding Exact Duplicates"
    }

    private var scanIcon: String {
        isPreparing ? "folder.badge.gearshape" : "doc.text.magnifyingglass"
    }

    private var subtitle: String {
        if !stage.isEmpty {
            return stage
        }
        return isPreparing
            ? "Reading directory structure..." : "Comparing file content to find exact matches..."
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
        .accessibilityLabel(
            isPreparing
                ? "Preparing scan" : "Scanning for duplicate files, \(percent) percent complete")
    }

    private var progressCard: some View {
        ZStack {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: scanIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .symbolReplaceTransition(animationValue: scanIcon)
                    .frame(width: 30)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(LocalizedStringKey(title))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                            .numericTextTransition(animationValue: title)

                        if !isPreparing {
                            Text("\(percent)%")
                                .monospacedDigit()
                                .fixedSize(horizontal: true, vertical: false)
                                .numericTextTransition(
                                    animationValue: percent,
                                    animation: .easeInOut(duration: 0.3)
                                )
                        }
                    }
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                    Text(LocalizedStringKey(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .numericTextTransition(animationValue: subtitle)
                }

                Spacer(minLength: 0)

                MinsangGlassLoader(
                    textChangeTrigger: title,
                    size: 54,
                    isActive: isAnimationActive
                )
                .frame(width: 54)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 420, height: 94)
        .background {
            beamSurface
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isPreparing
                ? "Preparing to scan for duplicates"
                : "Computing file hashes to find exact duplicate matches"
        )
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
            active: isAnimationActive,
            cornerRadius: 16,
            strength: 1.0
        )
        .scanProgressReferenceBeamFallback(
            cornerRadius: 16, active: true, includesInteriorGlow: true
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    fileprivate func scanProgressReferenceBeamFallback(
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
    @Environment(\.controlActiveState) private var controlActiveState

    private var shouldAnimate: Bool {
        active && !reduceMotion && controlActiveState != .inactive
    }

    var body: some View {
        SwiftUI.TimelineView(
            .animation(minimumInterval: 1.0 / 20.0, paused: !shouldAnimate)
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = shouldAnimate ? time / 1.96 : 0
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
                        .init(
                            color: Color(red: 0.08, green: 0.80, blue: 1.0).opacity(0.36),
                            location: 0.16),
                        .init(
                            color: Color(red: 0.92, green: 0.16, blue: 0.58).opacity(0.62),
                            location: 0.25),
                        .init(color: .white.opacity(0.88), location: 0.32),
                        .init(
                            color: Color(red: 1.0, green: 0.34, blue: 0.18).opacity(0.54),
                            location: 0.39),
                        .init(
                            color: Color(red: 0.40, green: 0.20, blue: 1.0).opacity(0.36),
                            location: 0.48),
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
                        .init(
                            color: Color(red: 0.08, green: 0.80, blue: 1.0).opacity(0.10),
                            location: 0.15),
                        .init(
                            color: Color(red: 0.92, green: 0.16, blue: 0.58).opacity(0.20),
                            location: 0.25),
                        .init(color: .white.opacity(0.16), location: 0.32),
                        .init(
                            color: Color(red: 1.0, green: 0.34, blue: 0.18).opacity(0.14),
                            location: 0.40),
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

//
//  DuplicatesView.swift
//  FileOrganizer
//
//  UI for displaying and managing duplicate files
//  Enhanced with haptic feedback, modal bounces, and micro-animations
//

import SwiftUI

struct DuplicatesView: View {
    @StateObject private var detectionManager = DuplicateDetectionManager()
    @EnvironmentObject var appState: AppState
    @State private var selectedGroup: DuplicateGroup?
    @State private var showDeleteConfirmation = false
    @State private var filesToDelete: [FileItem] = []
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DuplicatesHeader(
                manager: detectionManager,
                onScan: startScan,
                onBulkDelete: { keepNewest in
                    HapticFeedbackManager.shared.tap()
                    prepareBulkDelete(keepNewest: keepNewest)
                }
            )
            .transition(TransitionStyles.slideFromBottom)

            Divider()

            // Content with animated transitions
            ZStack {
                if detectionManager.isScanning {
                    ScanProgressView(progress: detectionManager.scanProgress)
                        .transition(TransitionStyles.scaleAndFade)
                } else if detectionManager.duplicateGroups.isEmpty {
                    EmptyDuplicatesView(hasScanned: detectionManager.lastScanDate != nil)
                        .transition(TransitionStyles.scaleAndFade)
                } else {
                    DuplicatesList(
                        groups: detectionManager.duplicateGroups,
                        selectedGroup: $selectedGroup,
                        onDelete: { files in
                            HapticFeedbackManager.shared.tap()
                            filesToDelete = files
                            showDeleteConfirmation = true
                        }
                    )
                    .transition(TransitionStyles.slideFromRight)
                }
            }
            .animation(.pageTransition, value: detectionManager.isScanning)
            .animation(.pageTransition, value: detectionManager.duplicateGroups.isEmpty)
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
    }

    private func startScan() {
        guard let directory = appState.selectedDirectory else { return }

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
        for file in files {
            try? fm.removeItem(atPath: file.path)
        }
        // Refresh scan
        startScan()
    }

    private func prepareBulkDelete(keepNewest: Bool) {
        var filesToDelete: [FileItem] = []

        for group in detectionManager.duplicateGroups {
            // Sort files based on criteria
            let sortedFiles = group.files.sorted { f1, f2 in
                let d1 = f1.creationDate ?? Date.distantPast
                let d2 = f2.creationDate ?? Date.distantPast
                return keepNewest ? (d1 > d2) : (d1 < d2)
            }

            // Keep the first one (best match for criteria), delete the rest
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

// MARK: - Header

struct DuplicatesHeader: View {
    @ObservedObject var manager: DuplicateDetectionManager
    let onScan: () -> Void
    let onBulkDelete: (Bool) -> Void // Bool: keepNewest

    @State private var isHovered = false
    @State private var appeared = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Duplicate Files")
                    .font(.title2)
                    .fontWeight(.semibold)

                if !manager.duplicateGroups.isEmpty {
                    Text("Found \(manager.totalDuplicates) duplicates • \(manager.formattedSavings) recoverable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            Spacer()

            if let lastScan = manager.lastScanDate {
                Text("Last scan: \(lastScan, style: .relative) ago")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .transition(.opacity)
            }

            if !manager.duplicateGroups.isEmpty {
                Menu {
                    Button {
                        onBulkDelete(true)
                    } label: {
                        Label("Delete All (Keep Newest)", systemImage: "clock")
                    }

                    Button {
                        onBulkDelete(false)
                    } label: {
                        Label("Delete All (Keep Oldest)", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Label("Cleanup", systemImage: "trash")
                }
                .disabled(manager.isScanning)
                .accessibilityIdentifier("CleanupDuplicatesMenu")
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            Button(action: onScan) {
                Label("Scan for Duplicates", systemImage: "doc.on.doc.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.isScanning)
            .accessibilityIdentifier("ScanDuplicatesButton")
            .bounceTap(scale: 0.95)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.subtleBounce, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Scan Progress

struct ScanProgressView: View {
    let progress: Double

    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerOffset: CGFloat = -300
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            // Animated progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 300, height: 10)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geometry.size.width * progress))

                        // Shimmer effect
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.4), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 50)
                            .offset(x: shimmerOffset)
                            .mask(
                                RoundedRectangle(cornerRadius: 6)
                                    .frame(width: max(0, geometry.size.width * progress))
                            )
                    }
                }
                .frame(width: 300, height: 10)
            }
            .frame(width: 300, height: 10)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerOffset = 300
                }
            }

            Text("Scanning files... \(Int(progress * 100))%")
                .font(.body)
                .foregroundColor(.secondary)
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulseScale = 1.03
                    }
                }

            HStack(spacing: 4) {
                Text("Computing file hashes to find duplicates")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.6))

                LoadingDotsView(dotCount: 3, dotSize: 4, color: .secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

// MARK: - Empty State

struct EmptyDuplicatesView: View {
    let hasScanned: Bool

    @State private var iconScale: CGFloat = 1.0
    @State private var iconRotation: Double = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasScanned ? "checkmark.circle" : "doc.on.doc")
                .font(.system(size: 48))
                .foregroundStyle(hasScanned ? .green : .secondary)
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(iconRotation))
                .onAppear {
                    if hasScanned {
                        // Success bounce animation
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                            iconScale = 1.2
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                iconScale = 1.0
                            }
                        }
                    } else {
                        // Idle floating animation
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            iconScale = 1.05
                            iconRotation = 3
                        }
                    }
                }

            if hasScanned {
                Text("No Duplicates Found")
                    .font(.headline)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Text("All files in this folder are unique")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Find Duplicate Files")
                    .font(.headline)
                Text("Scan your folder to identify files with identical content")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
}

// MARK: - Duplicates List

struct DuplicatesList: View {
    let groups: [DuplicateGroup]
    @Binding var selectedGroup: DuplicateGroup?
    let onDelete: ([FileItem]) -> Void

    var body: some View {
        List(Array(groups.enumerated()), id: \.element.id, selection: $selectedGroup) { index, group in
            DuplicateGroupRow(
                group: group,
                onDeleteDuplicates: { keepFirst in
                    let toDelete = keepFirst ? Array(group.files.dropFirst()) : Array(group.files.dropLast())
                    onDelete(toDelete)
                }
            )
            .tag(group)
            .animatedAppearance(delay: Double(index) * 0.05)
        }
        .listStyle(.inset)
    }
}

// MARK: - Duplicate Group Row

struct DuplicateGroupRow: View {
    let group: DuplicateGroup
    let onDeleteDuplicates: (Bool) -> Void

    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Button(action: {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .buttonStyle(.plain)

                Image(systemName: "doc.on.doc.fill")
                    .foregroundColor(.orange)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.subtleBounce, value: isHovered)

                Text("\(group.files.count) identical files")
                    .fontWeight(.medium)

                Text("• \(ByteCountFormatter.string(fromByteCount: group.files.first?.size ?? 0, countStyle: .file)) each")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Save \(ByteCountFormatter.string(fromByteCount: group.potentialSavings, countStyle: .file))")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
                    .scaleEffect(isHovered ? 1.05 : 1.0)
                    .animation(.subtleBounce, value: isHovered)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded file list with animation
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                        HStack {
                            if index == 0 {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundColor(.yellow)
                            } else {
                                Image(systemName: "doc")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(file.displayName)
                                .font(.caption)

                            Spacer()

                            Text(file.path)
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.leading, 24)
                        .opacity(isExpanded ? 1 : 0)
                        .offset(y: isExpanded ? 0 : -10)
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.7)
                                .delay(Double(index) * 0.03),
                            value: isExpanded
                        )
                    }

                    HStack {
                        Spacer()

                        Button("Keep First, Delete Others") {
                            HapticFeedbackManager.shared.tap()
                            onDeleteDuplicates(true)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .bounceTap(scale: 0.95)
                    }
                    .padding(.top, 8)
                    .opacity(isExpanded ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1), value: isExpanded)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    DuplicatesView()
        .environmentObject(AppState())
        .frame(width: 700, height: 500)
}

// MARK: - AppState Extension (if not exists)
// Note: Add selectedDirectory to AppState if not already present

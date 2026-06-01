//
//  OrganizingFlightStageView.swift
//  Sorty
//
//  Files flying into folders animation. This view is purely presentational:
//  it never gates the AI response, preview creation, or transition to ready.
//
//  Note: there is no public API to reuse Finder's exact drop-into-folder
//  animation in an arbitrary view. The legacy `kOpenFolderIcon` resource
//  only ships at 32x32 and looks pixelated at our sizes, so we render the
//  real high-resolution folder icon and use the same kind of subtle scale
//  bump + halo that Finder itself shows on a successful drop.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OrganizingFlightStageView: View {
    let suggestions: [FolderSuggestion]
    var prioritizesFilenames = false

    var stageWidth: CGFloat = 430
    var stageHeight: CGFloat = 170
    var maxBuckets: Int = 5

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var cardOffset: CGSize = .zero
    @State private var cardScale: CGFloat = 0.85
    @State private var cardOpacity: Double = 0
    @State private var bumpedIndex: Int?
    @State private var haloIndex: Int?
    @State private var bumpTrigger: Int = 0
    @State private var currentFileIcon: NSImage = AnalysisIconProvider.icon(for: .data)
    @State private var currentFileName = ""
    @State private var currentRenamedFileName: String?
    @State private var isShowingRenamedFileName = false
    @State private var displayedSuggestions: [FolderSuggestion] = []
    @State private var flightTask: Task<Void, Never>?
    @State private var flightStep = 0

    private let dropTravel: CGFloat = 76
    private let cardSize = CGSize(width: 28, height: 28)
    private let bucketSize = CGSize(width: 56, height: 56)

    private var fileCardSize: CGSize {
        prioritizesFilenames ? CGSize(width: 342, height: 64) : CGSize(width: 188, height: 42)
    }

    private var visibleSuggestions: [FolderSuggestion] {
        let source = displayedSuggestions.isEmpty ? suggestions : displayedSuggestions
        return Array(source.prefix(maxBuckets))
    }

    private var bucketCount: Int { visibleSuggestions.count }

    var body: some View {
        Group {
            if visibleSuggestions.isEmpty {
                EmptyView()
            } else {
                ZStack {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            ForEach(Array(visibleSuggestions.enumerated()), id: \.element.folderName) { index, suggestion in
                                destinationView(suggestion: suggestion, index: index)
                                    .frame(maxWidth: .infinity)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.4, anchor: .bottom)
                                            .combined(with: .opacity)
                                            .combined(with: .offset(y: 14)),
                                        removal: .opacity.combined(with: .scale(scale: 0.85))
                                    ))
                            }
                        }
                        .padding(.bottom, 6)
                        .animation(
                            systemReduceMotion
                                ? .easeInOut(duration: 0.18)
                                : .spring(response: 0.42, dampingFraction: 0.72),
                            value: visibleSuggestions.map(\.folderName)
                        )
                    }

                    fileCard
                        .offset(cardOffset)
                        .scaleEffect(cardScale)
                        .opacity(cardOpacity)
                        .allowsHitTesting(false)
                }
                .frame(width: stageWidth, height: stageHeight)
                .accessibilityHidden(true)
                .onAppear {
                    mergeDisplayedSuggestions(animated: false)
                    startCycleIfNeeded()
                }
                .onDisappear { stopCycle() }
                .onChange(of: suggestions) { _, _ in
                    mergeDisplayedSuggestions(animated: true)
                }
            }
        }
    }

    // MARK: - Subviews

    private var fileCard: some View {
        HStack(spacing: 10) {
            AppKitImageView(image: currentFileIcon, size: cardSize)
                .frame(width: cardSize.width, height: cardSize.height)
                .shadow(color: Color.black.opacity(0.16), radius: 4, x: 0, y: 2)

            if !currentFileName.isEmpty {
                fileNameLabel
            }

            if !prioritizesFilenames {
                Image(systemName: "arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: fileCardSize.width, height: fileCardSize.height)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 5)
    }

    private var fileNameLabel: some View {
        Group {
            if prioritizesFilenames, let currentRenamedFileName {
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentFileName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .strikethrough(isShowingRenamedFileName, color: .secondary.opacity(0.7))

                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.purple.opacity(0.78))
                            .accessibilityHidden(true)

                        Text(isShowingRenamedFileName ? currentRenamedFileName : "Preparing better name...")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isShowingRenamedFileName ? .primary : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .opacity(isShowingRenamedFileName ? 1 : 0.68)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                ZStack {
                    if let currentRenamedFileName, isShowingRenamedFileName {
                        Text(currentRenamedFileName)
                            .foregroundStyle(.primary.opacity(0.92))
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else {
                        Text(currentFileName)
                            .foregroundStyle(.primary.opacity(0.72))
                            .strikethrough(currentRenamedFileName != nil, color: .secondary.opacity(0.7))
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func destinationView(suggestion: FolderSuggestion, index: Int) -> some View {
        let isBumped = bumpedIndex == index
        let showHalo = haloIndex == index

        VStack(spacing: 4) {
            ZStack {
                if showHalo {
                    Circle()
                        .fill(Color.accentColor.opacity(0.22))
                        .frame(width: bucketSize.width + 18, height: bucketSize.width + 18)
                        .blur(radius: 10)
                        .transition(.opacity)
                }

                AppKitImageView(image: FolderDropBucket.folderIcon, size: bucketSize)
                    .frame(width: bucketSize.width, height: bucketSize.height)
                    .scaleEffect(isBumped ? 1.07 : 1.0)
                    .shadow(color: Color.black.opacity(isBumped ? 0.18 : 0.10),
                            radius: isBumped ? 8 : 4, x: 0, y: 3)
            }
            .frame(width: bucketSize.width + 18, height: bucketSize.height + 6)
            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: bumpTrigger)
            .animation(.easeOut(duration: 0.25), value: showHalo)

            Text(suggestion.folderName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: bucketSize.width + 24)
        }
    }

    // MARK: - Geometry

    private func centerOffset(for index: Int) -> CGFloat {
        guard bucketCount > 0 else { return 0 }
        let step = stageWidth / CGFloat(bucketCount)
        let pos = step * (CGFloat(index) + 0.5)
        return pos - stageWidth / 2
    }

    private func folderTopOffset() -> CGFloat {
        // Folders sit pinned to the bottom of the stage; this gives the
        // approximate Y position of the folder's center for the file to
        // land into.
        let folderCenterY = stageHeight / 2 - bucketSize.height / 2 - 15
        return folderCenterY
    }

    // MARK: - Animation cycle

    private func startCycleIfNeeded() {
        guard flightTask == nil, !systemReduceMotion, bucketCount > 0 else { return }

        flightTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let flight = nextFlight() else {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    continue
                }
                currentFileIcon = iconForPath(flight.file.path)
                currentFileName = flight.file.displayName
                currentRenamedFileName = flight.renameMapping?.suggestedName
                isShowingRenamedFileName = false
                await runFlight(toIndex: flight.folderIndex)
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
        }
    }

    private func stopCycle() {
        flightTask?.cancel()
        flightTask = nil
        cardOpacity = 0
        bumpedIndex = nil
        haloIndex = nil
        isShowingRenamedFileName = false
    }

    private func runFlight(toIndex index: Int) async {
        // Phase 1: appear at the top of the stage.
        let startY: CGFloat = -dropTravel
        cardOffset = CGSize(width: 0, height: startY)
        cardScale = 0.9
        cardOpacity = 0
        haloIndex = nil

        withAnimation(.easeOut(duration: 0.18)) {
            cardOpacity = 1
            cardScale = 1.0
        }
        try? await Task.sleep(nanoseconds: 160_000_000)
        if Task.isCancelled { return }

        // Phase 2: glide toward the destination folder along an arc.
        let destX = centerOffset(for: index)
        let landingY = folderTopOffset() - 8

        if currentRenamedFileName != nil {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                isShowingRenamedFileName = true
            }
            HapticFeedbackManager.shared.selection()
        }

        try? await Task.sleep(nanoseconds: currentRenamedFileName == nil ? 40_000_000 : 220_000_000)
        if Task.isCancelled { return }

        // Show the receive halo just before the file lands.
        withAnimation(.easeIn(duration: 0.32).delay(0.18)) {
            haloIndex = index
        }

        withAnimation(.timingCurve(0.34, 0.04, 0.2, 1.0, duration: 0.46)) {
            cardOffset = CGSize(width: destX, height: landingY)
        }
        try? await Task.sleep(nanoseconds: 360_000_000)
        if Task.isCancelled { return }

        // Phase 3: the file tucks into the folder, the folder bumps.
        withAnimation(.timingCurve(0.42, 0.0, 0.28, 1.0, duration: 0.18)) {
            cardOffset = CGSize(width: destX, height: landingY + 18)
            cardScale = 0.3
            cardOpacity = 0
        }
        bumpedIndex = index
        bumpTrigger &+= 1
        HapticFeedbackManager.shared.selection()

        try? await Task.sleep(nanoseconds: 220_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.25)) {
            haloIndex = nil
        }
        bumpedIndex = nil
    }

    // MARK: - Suggestions and file selection

    private func mergeDisplayedSuggestions(animated: Bool = true) {
        let incoming = Array(suggestions.prefix(maxBuckets))
        guard !incoming.isEmpty else { return }

        var merged = displayedSuggestions
        var didInsert = false
        for suggestion in incoming {
            if let index = merged.firstIndex(where: { $0.folderName == suggestion.folderName }) {
                merged[index] = suggestion
            } else if merged.count < maxBuckets {
                merged.append(suggestion)
                didInsert = true
            }
        }

        guard merged != displayedSuggestions else { return }

        if animated && didInsert && !systemReduceMotion {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) {
                displayedSuggestions = merged
            }
            HapticFeedbackManager.shared.light()
        } else {
            displayedSuggestions = merged
        }

        startCycleIfNeeded()
    }

    private struct FlightCandidate {
        let folderIndex: Int
        let file: FileItem
        let renameMapping: FileRenameMapping?
    }

    private func nextFlight() -> FlightCandidate? {
        let candidates = visibleSuggestions.enumerated().flatMap { index, suggestion in
            filesWithRenames(in: suggestion).map {
                FlightCandidate(folderIndex: index, file: $0.file, renameMapping: $0.renameMapping)
            }
        }
        guard !candidates.isEmpty else { return nil }
        let candidate = candidates[flightStep % candidates.count]
        flightStep &+= 1
        return candidate
    }

    private func filesWithRenames(in suggestion: FolderSuggestion) -> [(file: FileItem, renameMapping: FileRenameMapping?)] {
        var items = suggestion.files.map { file in
            (file: file, renameMapping: suggestion.renameMapping(for: file).flatMap { $0.hasRename ? $0 : nil })
        }
        for subfolder in suggestion.subfolders {
            items.append(contentsOf: filesWithRenames(in: subfolder))
        }
        return items
    }

    private func iconForPath(_ path: String) -> NSImage {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension
        if !ext.isEmpty {
            return AnalysisIconProvider.icon(forFileExtension: ext)
        }
        return AnalysisIconProvider.icon(for: .data)
    }
}

private enum FolderDropBucket {
    static let folderIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = NSSize(width: 128, height: 128)
        return icon
    }()
}

#Preview {
    OrganizingFlightStageView(
        suggestions: [
            FolderSuggestion(folderName: "Screenshots"),
            FolderSuggestion(folderName: "Invoices"),
            FolderSuggestion(folderName: "Projects"),
            FolderSuggestion(folderName: "Music")
        ]
    )
    .padding()
    .frame(width: 500, height: 320)
}

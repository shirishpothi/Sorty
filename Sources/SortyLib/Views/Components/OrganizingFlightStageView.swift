//
//  OrganizingFlightStageView.swift
//  Sorty
//
//  Binky-inspired "files flying into folders" animation. Once the AI
//  produces a plan, this view animates a file card from the top of the
//  stage down into one of the planned destination folder buckets, then
//  bounces the bucket on landing — cycling through the planned folders.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct OrganizingFlightStageView: View {
    let suggestions: [FolderSuggestion]

    var stageWidth: CGFloat = 360
    var stageHeight: CGFloat = 200
    var maxBuckets: Int = 5

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @State private var cardOffset: CGSize = .zero
    @State private var cardRotation: Double = 0
    @State private var cardScale: CGFloat = 0.55
    @State private var cardOpacity: Double = 0
    @State private var bumpedIndex: Int?
    @State private var bumpTrigger: Int = 0
    @State private var currentFileIcon: NSImage = AnalysisIconProvider.icon(for: .data)
    @State private var flightTask: Task<Void, Never>?

    private let dropDistance: CGFloat = 130
    private let cardSize = CGSize(width: 56, height: 76)
    private let bucketSize = CGSize(width: 70, height: 54)

    private var visibleSuggestions: [FolderSuggestion] {
        Array(suggestions.prefix(maxBuckets))
    }

    private var bucketCount: Int { visibleSuggestions.count }

    var body: some View {
        Group {
            if visibleSuggestions.isEmpty {
                EmptyView()
            } else {
                ZStack {
                    // Buckets pinned to the bottom of the stage.
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 0) {
                            ForEach(Array(visibleSuggestions.enumerated()), id: \.offset) { index, suggestion in
                                destinationView(suggestion: suggestion, index: index)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.bottom, 4)
                    }

                    // The flying file card sits on top of everything else.
                    fileCard
                        .offset(cardOffset)
                        .rotationEffect(.degrees(cardRotation))
                        .scaleEffect(cardScale)
                        .opacity(cardOpacity)
                        .allowsHitTesting(false)
                }
                .frame(width: stageWidth, height: stageHeight)
                .accessibilityHidden(true)
                .onAppear { startCycle() }
                .onDisappear { stopCycle() }
                .onChange(of: bucketCount) { _, _ in
                    restartCycle()
                }
            }
        }
    }

    // MARK: - Subviews

    private var fileCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            Image(nsImage: currentFileIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(8)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private func destinationView(suggestion: FolderSuggestion, index: Int) -> some View {
        let isBumped = bumpedIndex == index

        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isBumped ? 0.14 : 0.07))
                    .frame(width: bucketSize.width, height: bucketSize.height)

                Image(nsImage: AnalysisIconProvider.icon(for: .folder))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
                    .scaleEffect(isBumped ? 1.18 : 1.0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.5), value: bumpTrigger)
            }
            .animation(.easeOut(duration: 0.25), value: bumpedIndex)

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

    // MARK: - Animation cycle

    private func startCycle() {
        stopCycle()
        guard !systemReduceMotion, bucketCount > 0 else { return }

        flightTask = Task { @MainActor in
            var step = 0
            while !Task.isCancelled {
                let count = visibleSuggestions.count
                guard count > 0 else { break }
                let index = step % count
                let suggestion = visibleSuggestions[index]
                currentFileIcon = pickFileIcon(for: suggestion)
                await runFlight(toIndex: index)
                try? await Task.sleep(nanoseconds: 220_000_000)
                step &+= 1
            }
        }
    }

    private func stopCycle() {
        flightTask?.cancel()
        flightTask = nil
        cardOpacity = 0
        bumpedIndex = nil
    }

    private func restartCycle() {
        stopCycle()
        startCycle()
    }

    private func runFlight(toIndex index: Int) async {
        // Phase 1 — Spawn above the stage center, small and invisible.
        cardOffset = CGSize(width: 0, height: -dropDistance + 30)
        cardRotation = Double.random(in: -10 ... 10)
        cardScale = 0.55
        cardOpacity = 0

        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
            cardOffset = CGSize(width: 0, height: -dropDistance + 60)
            cardScale = 1.0
            cardOpacity = 1
            cardRotation = 0
        }
        try? await Task.sleep(nanoseconds: 480_000_000)
        if Task.isCancelled { return }

        // Phase 2 — Glide diagonally toward the destination bucket.
        let destX = centerOffset(for: index)
        let leanAngle: Double = destX < -1 ? -8 : (destX > 1 ? 8 : 0)

        withAnimation(.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.55)) {
            cardOffset = CGSize(width: destX, height: 6)
            cardRotation = leanAngle
        }
        try? await Task.sleep(nanoseconds: 420_000_000)
        if Task.isCancelled { return }

        // Phase 3 — Drop into the bucket, shrinking and fading.
        withAnimation(.easeIn(duration: 0.22)) {
            cardOffset = CGSize(width: destX, height: 30)
            cardScale = 0.3
            cardOpacity = 0
        }
        bumpedIndex = index
        bumpTrigger &+= 1
        HapticFeedbackManager.shared.selection()

        try? await Task.sleep(nanoseconds: 260_000_000)
        if Task.isCancelled { return }
        bumpedIndex = nil
        try? await Task.sleep(nanoseconds: 90_000_000)
    }

    // MARK: - Icon selection

    private func pickFileIcon(for suggestion: FolderSuggestion) -> NSImage {
        if let item = suggestion.files.randomElement() {
            return iconForPath(item.path)
        }
        for sub in suggestion.subfolders {
            if let item = sub.files.randomElement() {
                return iconForPath(item.path)
            }
        }
        return AnalysisIconProvider.icon(for: .data)
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

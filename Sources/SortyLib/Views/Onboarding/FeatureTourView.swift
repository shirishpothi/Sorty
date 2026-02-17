//
//  FeatureTourView.swift
//  Sorty
//
//  Guided feature tour shown after onboarding or from Help menu.
//

import SwiftUI

public struct FeatureTourView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentIndex = 0
    @State private var isForwardTransition = true
    @State private var mockupPhase = 0
    @State private var phaseTask: Task<Void, Never>?
    @State private var hasAppeared = false

    private var step: FeatureTourStep { FeatureTourStep.all[currentIndex] }

    public init() {}

    public var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            AnimatedGradientBackground(
                revealed: true,
                color1: .blue,
                color2: .cyan,
                color3: .mint
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ambientBlobs
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                leftPanel
                rightPanel
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            .padding(28)
            .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 14)
            .opacity(hasAppeared ? 1 : 0)
            .scaleEffect(hasAppeared ? 1 : 0.98)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: hasAppeared)
        }
        .frame(minWidth: 1080, minHeight: 760)
        .onAppear {
            hasAppeared = true
            startMockupPhaseAnimation()
        }
        .onDisappear {
            phaseTask?.cancel()
        }
        .onChange(of: currentIndex) { _, _ in
            startMockupPhaseAnimation()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FeatureTourView")
        .accessibilityLabel("Feature Tour")
    }

    private var ambientBlobs: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.cyan.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: -380, y: -220)
                .blur(radius: 60)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.mint.opacity(0.14), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 280
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: 440, y: 240)
                .blur(radius: 70)
        }
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 14, weight: .semibold))
                Text("Feature Tour")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            ZStack(alignment: .leading) {
                stepText
                    .id(step.id)
                    .transition(isForwardTransition ? TransitionStyles.slideFromRight : TransitionStyles.slideFromLeft)
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentIndex)

            progressPips

            Spacer(minLength: 8)

            navigationButtons
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 34)
        .frame(width: 440)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }

    private var stepText: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(step.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(step.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(step.howItWorks, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(step.accent.opacity(0.8))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var progressPips: some View {
        HStack(spacing: 8) {
            ForEach(Array(FeatureTourStep.all.enumerated()), id: \.offset) { index, item in
                Capsule(style: .continuous)
                    .fill(index == currentIndex ? item.accent : Color.secondary.opacity(0.2))
                    .frame(width: index == currentIndex ? 26 : 8, height: 8)
                    .animation(.subtleBounce, value: currentIndex)
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .frame(minWidth: 82)
            }
            .buttonStyle(.bordered)
            .disabled(currentIndex == 0)
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button {
                skipTour()
            } label: {
                Text("Skip")
                    .frame(minWidth: 66)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])

            Spacer(minLength: 0)

            Button {
                goNext()
            } label: {
                HStack(spacing: 6) {
                    Text(currentIndex == FeatureTourStep.all.count - 1 ? "Finish" : "Next")
                    Image(systemName: "chevron.right")
                }
                .frame(minWidth: 92)
            }
            .buttonStyle(.onboardingPill)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Live Demo")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)

                HStack(spacing: 0) {
                    simulatedSidebar

                    Divider()
                        .overlay(.white.opacity(0.1))

                    ZStack {
                        mockupArea
                            .id(step.id)
                            .transition(isForwardTransition ? TransitionStyles.slideFromRight : TransitionStyles.slideFromLeft)
                    }
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentIndex)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var simulatedSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sidebar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(FeatureTourStep.all) { item in
                FeatureSidebarRow(item: item, isCurrent: item.id == step.id)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: currentIndex)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 238, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.08))
        )
    }

    @ViewBuilder
    private var mockupArea: some View {
        switch step.mockupKind {
        case .workspaceHealthGauge:
            WorkspaceHealthMockup(step: step, phase: mockupPhase)
        case .duplicateClusterMerge:
            DuplicatesMockup(step: step, phase: mockupPhase)
        case .historyTimeline:
            HistoryMockup(step: step, phase: mockupPhase)
        case .batchQueueProgress:
            BatchMockup(step: step, phase: mockupPhase)
        case .exclusionFilterBuilder:
            ExclusionMockup(step: step, phase: mockupPhase)
        case .watchFolderLiveFeed:
            WatchFolderMockup(step: step, phase: mockupPhase)
        case .learningsRuleCards:
            LearningsMockup(step: step, phase: mockupPhase)
        }
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        isForwardTransition = false
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            currentIndex -= 1
        }
        HapticFeedbackManager.shared.selection()
    }

    private func goNext() {
        isForwardTransition = true
        if currentIndex < FeatureTourStep.all.count - 1 {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                currentIndex += 1
            }
            HapticFeedbackManager.shared.selection()
            return
        }

        finishTour()
    }

    private func skipTour() {
        appState.completeFeatureTour()
        HapticFeedbackManager.shared.selection()
        dismiss()
    }

    private func finishTour() {
        appState.completeFeatureTour()
        HapticFeedbackManager.shared.success()
        dismiss()
    }

    private func startMockupPhaseAnimation() {
        phaseTask?.cancel()
        mockupPhase = 0

        guard !reduceMotion else {
            mockupPhase = 2
            return
        }

        phaseTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                await MainActor.run {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.82)) {
                        mockupPhase = (mockupPhase + 1) % 3
                    }
                }
            }
        }
    }
}

private enum FeatureMockupKind {
    case workspaceHealthGauge
    case duplicateClusterMerge
    case historyTimeline
    case batchQueueProgress
    case exclusionFilterBuilder
    case watchFolderLiveFeed
    case learningsRuleCards
}

private enum FeatureTourStepID: String, CaseIterable, Identifiable {
    case workspaceHealth
    case duplicates
    case history
    case batchOrganize
    case exclusionRules
    case watchFolders
    case learnings

    var id: String { rawValue }
}

private struct FeatureTourStep: Identifiable {
    let id: FeatureTourStepID
    let sidebarTitle: String
    let sidebarIcon: String
    let title: String
    let description: String
    let howItWorks: [String]
    let ctaHint: String
    let mockupKind: FeatureMockupKind
    let accent: Color
    let sidebarAccessibilityIdentifier: String

    static let all: [FeatureTourStep] = [
        FeatureTourStep(
            id: .workspaceHealth,
            sidebarTitle: "Workspace Health",
            sidebarIcon: "heart.text.square",
            title: "Workspace Health",
            description: "Scan a folder to detect clutter, stale files, and cleanup opportunities with a single health score.",
            howItWorks: [
                "Sorty scores each workspace on freshness, structure, and duplicates.",
                "Actionable recommendations prioritize the highest-impact cleanups.",
                "Use the highlighted entry to open health diagnostics quickly."
            ],
            ctaHint: "Scan Health",
            mockupKind: .workspaceHealthGauge,
            accent: .mint,
            sidebarAccessibilityIdentifier: "FeatureTourSidebarWorkspaceHealth"
        ),
        FeatureTourStep(
            id: .duplicates,
            sidebarTitle: "Duplicates",
            sidebarIcon: "doc.on.doc",
            title: "Duplicates",
            description: "Group exact and near-duplicate files, preview differences, and keep the best copy with confidence.",
            howItWorks: [
                "Sorty clusters duplicates by checksum and semantic similarity.",
                "You can review each group before applying any move or delete action.",
                "The highlighted navigation target takes you directly to duplicate review."
            ],
            ctaHint: "Review Duplicates",
            mockupKind: .duplicateClusterMerge,
            accent: .orange,
            sidebarAccessibilityIdentifier: "FeatureTourSidebarDuplicates"
        ),
        FeatureTourStep(
            id: .history,
            sidebarTitle: "History",
            sidebarIcon: "clock",
            title: "History",
            description: "Track every organization run, inspect what changed, and undo safely when you need to roll back.",
            howItWorks: [
                "Each run stores a timeline with moved, renamed, and skipped files.",
                "Open a run to inspect details before undoing.",
                "The highlighted entry is your control center for past sessions."
            ],
            ctaHint: "Undo Last Run",
            mockupKind: .historyTimeline,
            accent: .blue,
            sidebarAccessibilityIdentifier: "FeatureTourSidebarHistory"
        ),
        FeatureTourStep(
            id: .batchOrganize,
            sidebarTitle: "Batch Organize",
            sidebarIcon: "square.stack.3d.up.fill",
            title: "Batch Organize",
            description: "Queue multiple folders and run a coordinated organization pass with progress and per-folder results.",
            howItWorks: [
                "Add multiple folders and assign one strategy to all or tune per folder.",
                "Sorty processes the queue with per-job status and completion metrics.",
                "Use the highlighted sidebar item when you need large-scale cleanup."
            ],
            ctaHint: "Start Batch",
            mockupKind: .batchQueueProgress,
            accent: .indigo,
            sidebarAccessibilityIdentifier: "FeatureTourSidebarBatchOrganize"
        ),
        FeatureTourStep(
            id: .exclusionRules,
            sidebarTitle: "Exclusions",
            sidebarIcon: "eye.slash",
            title: "Exclusion Rules",
            description: "Define patterns and folders Sorty should never touch, keeping sensitive or system files out of runs.",
            howItWorks: [
                "Create path, extension, or wildcard rules in one place.",
                "Rules are applied before scanning so excluded content is never planned.",
                "The highlighted navigation target opens rule management instantly."
            ],
            ctaHint: "Add Rule",
            mockupKind: .exclusionFilterBuilder,
            accent: .red,
            sidebarAccessibilityIdentifier: "FeatureTourSidebarExclusions"
        ),
        FeatureTourStep(
            id: .watchFolders,
            sidebarTitle: "Watched Folders",
            sidebarIcon: "eye",
            title: "Watch Folders",
            description: "Continuously monitor selected folders and trigger automation when new files arrive.",
            howItWorks: [
                "Choose watched locations and set auto-organize behavior.",
                "Incoming file events stream in real time so automation remains visible.",
                "Use the highlighted section to control monitoring and schedules."
            ],
            ctaHint: "Auto-Organize",
            mockupKind: .watchFolderLiveFeed,
            accent: .teal,
            sidebarAccessibilityIdentifier: "FeatureTourSidebarWatchedFolders"
        ),
        FeatureTourStep(
            id: .learnings,
            sidebarTitle: "The Learnings",
            sidebarIcon: "brain",
            title: "Learnings",
            description: "Capture your manual corrections and convert them into reusable rules that improve future organization runs.",
            howItWorks: [
                "Sorty observes accepted and rejected suggestions from your workflows.",
                "Proposed rules are surfaced for review before activation.",
                "Open the highlighted destination to tune long-term behavior."
            ],
            ctaHint: "Apply Suggestions",
            mockupKind: .learningsRuleCards,
            accent: .purple,
            sidebarAccessibilityIdentifier: "FeatureTourSidebarLearnings"
        )
    ]
}

private struct MockupShell<Content: View>: View {
    let step: FeatureTourStep
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.headline)
                    Text("Relevant action: \(step.ctaHint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("Simulated", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(step.accent.opacity(0.32), lineWidth: 1)
        )
    }
}

private struct HighlightButton: View {
    let title: String
    let icon: String
    let accent: Color
    let emphasized: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(emphasized ? .white : accent)
        .background(
            Capsule(style: .continuous)
                .fill(emphasized ? accent : accent.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(accent.opacity(0.9), lineWidth: emphasized ? 0 : 1)
                .shadow(color: emphasized ? accent.opacity(0.45) : .clear, radius: 10, x: 0, y: 0)
        )
        .scaleEffect(emphasized ? 1.02 : 1)
    }
}

private struct FeatureSidebarRow: View {
    let item: FeatureTourStep
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.sidebarIcon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16)
            Text(item.sidebarTitle)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(isCurrent ? item.accent : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? item.accent.opacity(0.18) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isCurrent ? item.accent.opacity(0.9) : .clear, lineWidth: 1)
                .shadow(color: isCurrent ? item.accent.opacity(0.45) : .clear, radius: 10, x: 0, y: 0)
        )
        .scaleEffect(isCurrent ? 1.02 : 1)
        .accessibilityIdentifier(item.sidebarAccessibilityIdentifier)
        .accessibilityValue(isCurrent ? "Highlighted" : "Not highlighted")
    }
}

private struct WorkspaceHealthMockup: View {
    let step: FeatureTourStep
    let phase: Int

    var body: some View {
        MockupShell(step: step) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 20) {
                    ZStack {
                        SortyGradientCircularProgress(
                            progress: phase == 0 ? 0.35 : phase == 1 ? 0.58 : 0.84,
                            accent: step.accent,
                            size: 130,
                            lineWidth: 12
                        )

                        Text(phase == 0 ? "42" : phase == 1 ? "67" : "89")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        metricRow("Large files", value: phase == 0 ? "17" : "9")
                        metricRow("Stale files", value: phase == 0 ? "63" : "18")
                        metricRow("Duplicate risk", value: phase == 2 ? "Low" : "Medium")
                    }
                }

                HighlightButton(
                    title: "Scan Health",
                    icon: "heart.text.square.fill",
                    accent: step.accent,
                    emphasized: phase == 2
                )
            }
        }
    }

    private func metricRow(_ name: String, value: String) -> some View {
        HStack {
            Text(name)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

private struct DuplicatesMockup: View {
    let step: FeatureTourStep
    let phase: Int

    var body: some View {
        MockupShell(step: step) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    duplicateCard("Invoice.pdf", tone: .orange, active: phase != 0)
                    duplicateCard("Invoice (1).pdf", tone: .yellow, active: phase == 2)
                    duplicateCard("Invoice-final.pdf", tone: .pink, active: phase == 1 || phase == 2)
                }
                .frame(height: 76)

                HStack(spacing: 10) {
                    duplicateCard("Photo_2044.jpg", tone: .mint, active: phase == 2)
                    duplicateCard("Photo_2044-copy.jpg", tone: .teal, active: phase != 0)
                }
                .frame(height: 70)

                HStack {
                    Text("2 duplicate groups selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HighlightButton(
                        title: "Review Duplicates",
                        icon: "doc.on.doc.fill",
                        accent: step.accent,
                        emphasized: phase == 2
                    )
                }
            }
        }
    }

    private func duplicateCard(_ name: String, tone: Color, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(active ? "Matched" : "Analyzing")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tone.opacity(active ? 0.25 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tone.opacity(active ? 0.9 : 0.2), lineWidth: 1)
        )
    }
}

private struct HistoryMockup: View {
    let step: FeatureTourStep
    let phase: Int

    var body: some View {
        MockupShell(step: step) {
            VStack(alignment: .leading, spacing: 12) {
                historyEntry("Today 9:41 AM", detail: "Desktop cleanup", status: phase == 2 ? "Undo Ready" : "Completed", accent: step.accent)
                historyEntry("Yesterday 7:14 PM", detail: "Downloads organization", status: "Completed", accent: .cyan)
                historyEntry("Yesterday 9:02 AM", detail: "Project archive", status: "Completed", accent: .mint)

                Spacer(minLength: 0)

                HStack {
                    Text("All actions are reversible from here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HighlightButton(
                        title: "Undo Last Run",
                        icon: "arrow.uturn.backward.circle.fill",
                        accent: step.accent,
                        emphasized: phase == 2
                    )
                }
            }
        }
    }

    private func historyEntry(_ date: String, detail: String, status: String, accent: Color) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accent.opacity(0.8))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(detail)
                    .font(.subheadline.weight(.semibold))
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(status)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(accent.opacity(0.2))
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

private struct BatchMockup: View {
    let step: FeatureTourStep
    let phase: Int

    var body: some View {
        MockupShell(step: step) {
            VStack(alignment: .leading, spacing: 14) {
                batchRow("Design Assets", progress: phase == 0 ? 0.2 : phase == 1 ? 0.6 : 1.0, accent: step.accent)
                batchRow("Downloads", progress: phase == 0 ? 0.0 : phase == 1 ? 0.4 : 0.9, accent: .blue)
                batchRow("Client Archive", progress: phase == 0 ? 0.0 : phase == 1 ? 0.2 : 0.7, accent: .purple)

                Spacer(minLength: 0)

                HStack {
                    Text("Queue: 3 folders")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HighlightButton(
                        title: "Start Batch",
                        icon: "play.fill",
                        accent: step.accent,
                        emphasized: phase == 2
                    )
                }
            }
        }
    }

    private func batchRow(_ title: String, progress: Double, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            SortyGradientProgressBar(progress: progress, accent: accent, height: 8)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

private struct ExclusionMockup: View {
    let step: FeatureTourStep
    let phase: Int

    var body: some View {
        MockupShell(step: step) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ruleChip("*.tmp", active: phase != 0, accent: step.accent)
                    ruleChip(".DS_Store", active: phase == 2, accent: .orange)
                    ruleChip("node_modules", active: true, accent: .pink)
                }

                HStack(spacing: 10) {
                    ruleChip("Private/*", active: phase == 2, accent: .purple)
                    ruleChip("Screenshots/*", active: phase != 0, accent: .indigo)
                }

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .frame(height: 44)
                    .overlay(
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(.secondary)
                            Text("Path, extension, or wildcard")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                    )

                HStack {
                    Spacer()
                    HighlightButton(
                        title: "Add Rule",
                        icon: "plus",
                        accent: step.accent,
                        emphasized: phase == 2
                    )
                }
            }
        }
    }

    private func ruleChip(_ text: String, active: Bool, accent: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(active ? accent : Color.secondary)
            .background(
                Capsule(style: .continuous)
                    .fill(active ? accent.opacity(0.2) : .white.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(active ? accent.opacity(0.9) : .white.opacity(0.15), lineWidth: 1)
            )
    }
}

private struct WatchFolderMockup: View {
    let step: FeatureTourStep
    let phase: Int

    var body: some View {
        MockupShell(step: step) {
            VStack(alignment: .leading, spacing: 12) {
                folderStatus(name: "Downloads", event: phase == 0 ? "Idle" : "4 files detected", accent: step.accent)
                folderStatus(name: "Screenshots", event: phase == 2 ? "Auto-organized" : "Watching...", accent: .cyan)
                folderStatus(name: "Client Intake", event: phase == 1 ? "2 files queued" : "Watching...", accent: .mint)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.07))
                    .frame(height: 54)
                    .overlay(
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Live Event")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(phase == 2 ? "Moved 12 files into /Receipts" : "Detected 3 new files in Downloads")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                    )

                HStack {
                    Spacer()
                    HighlightButton(
                        title: "Auto-Organize",
                        icon: "bolt.fill",
                        accent: step.accent,
                        emphasized: phase == 2
                    )
                }
            }
        }
    }

    private func folderStatus(name: String, event: String, accent: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(event)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(accent)
                .frame(width: 9, height: 9)
                .shadow(color: accent.opacity(0.5), radius: 6, x: 0, y: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

private struct LearningsMockup: View {
    let step: FeatureTourStep
    let phase: Int

    var body: some View {
        MockupShell(step: step) {
            VStack(alignment: .leading, spacing: 12) {
                ruleCard(
                    title: "When filename contains 'Invoice'",
                    action: "Move to Finance/Receipts",
                    confidence: phase == 0 ? "72%" : "91%",
                    accent: step.accent
                )
                ruleCard(
                    title: "When source is Screenshots",
                    action: "Move to Visuals/Screenshots",
                    confidence: phase == 2 ? "88%" : "76%",
                    accent: .indigo
                )

                HStack {
                    buttonTag("Accept", icon: "hand.thumbsup.fill", accent: .green, active: phase == 2)
                    buttonTag("Reject", icon: "hand.thumbsdown.fill", accent: .red, active: phase == 0)
                    Spacer()
                    HighlightButton(
                        title: "Apply Suggestions",
                        icon: "brain.head.profile",
                        accent: step.accent,
                        emphasized: phase == 2
                    )
                }
            }
        }
    }

    private func ruleCard(title: String, action: String, confidence: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(action)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Confidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(confidence)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    private func buttonTag(_ text: String, icon: String, accent: Color, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(active ? .white : accent)
        .background(
            Capsule(style: .continuous)
                .fill(active ? accent : accent.opacity(0.16))
        )
    }
}

#Preview {
    FeatureTourView()
        .environmentObject(AppState())
}

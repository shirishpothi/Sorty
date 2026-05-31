//
//  FeatureTourView.swift
//  Sorty
//
//  Guided feature tour shown after onboarding or from Help menu.
//
//  Modeled on the TourKit slideshow card style (rampatra/TourKit):
//  a single rounded dark card with a 16:10 image area, page-indicator
//  pills, ←/✓ chrome, and a centered title/description + primary action
//  in the bottom panel. The "image" area hosts the existing live
//  SwiftUI mockup screens instead of pre-rendered artwork.
//

import SwiftUI

public struct FeatureTourView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isKeyboardFocused: Bool

    // Card geometry — TourKit's defaults adapted for Sorty's wider mockups.
    private let cardWidth: CGFloat = 760
    private let imageAspect: CGFloat = 16.0 / 10.0
    private var imageHeight: CGFloat { cardWidth / imageAspect }

    @State private var currentIndex = 0

    private var step: FeatureTourStep { FeatureTourStep.visible[currentIndex] }
    private var isLastStep: Bool { currentIndex == FeatureTourStep.visible.count - 1 }

    public init() {}

    public var body: some View {
        ZStack {
            // Subtle backdrop behind the card so the sheet feels grounded.
            Color(red: 0.05, green: 0.07, blue: 0.11)
                .ignoresSafeArea()

            card
                .frame(width: cardWidth)
                .shadow(color: .black.opacity(0.45), radius: 40, x: 0, y: 18)
                .padding(28)
        }
        .frame(minWidth: cardWidth + 56, minHeight: imageHeight + 320)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("FeatureTourView")
        .accessibilityLabel("Feature Tour")
        .focusable()
        .focused($isKeyboardFocused)
        .onAppear { isKeyboardFocused = true }
        .onMoveCommand(perform: handleMoveCommand)
        .onExitCommand { skipTour() }
        .animation(.easeInOut(duration: reduceMotion ? 0.01 : 0.25), value: currentIndex)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            imageSection
            bottomPanel
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Image section (mockup artwork + chrome)

    private var imageSection: some View {
        ZStack(alignment: .top) {
            // Per-step accent wash — fades between slides so each step
            // has a distinct mood while the transition feels cohesive.
            LinearGradient(
                colors: [
                    step.accent.opacity(0.28),
                    step.accent.opacity(0.10),
                    Color(white: 0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .id(step.id)
            .transition(.opacity)

            screenView
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(step.id)
                .transition(.opacity)

            // Deep multi-stop gradient that blends the mockup seamlessly
            // into the dark bottom panel — mirrors TourKit's signature blend.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(white: 0.10).opacity(0.15), location: 0.25),
                    .init(color: Color(white: 0.10).opacity(0.45), location: 0.50),
                    .init(color: Color(white: 0.10).opacity(0.80), location: 0.75),
                    .init(color: Color(white: 0.10), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)

            pageIndicator
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            topControls
        }
        .frame(width: cardWidth, height: imageHeight)
        .clipped()
    }

    private var topControls: some View {
        HStack {
            tourIconButton(systemName: "chevron.left", action: goBack)
                .opacity(currentIndex == 0 ? 0 : 1)
                .disabled(currentIndex == 0)
                .accessibilityLabel("Previous step")

            Spacer()

            tourIconButton(systemName: "checkmark", action: skipTour)
                .accessibilityLabel("Close tour")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Glass-style circle icon button matching TourKit's chrome.
    private func tourIconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 32, height: 32)
                .background {
                    if #available(macOS 26.0, *) {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                            }
                    } else {
                        Circle().fill(Color.white.opacity(0.15))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Page indicator (TourKit-style pills)

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(Array(FeatureTourStep.visible.enumerated()), id: \.offset) { index, _ in
                let isActive = index == currentIndex
                Capsule(style: .continuous)
                    .fill(.white.opacity(isActive ? 0.95 : 0.32))
                    .frame(width: isActive ? 24 : 8, height: 8)
                    .onTapGesture {
                        guard index != currentIndex else { return }
                        currentIndex = index
                        HapticFeedbackManager.shared.selection()
                    }
                    .accessibilityLabel("Go to \(FeatureTourStep.visible[index].title)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page \(currentIndex + 1) of \(max(FeatureTourStep.visible.count, 1))")
    }

    // MARK: - Bottom panel (title + description + primary button)

    private var bottomPanel: some View {
        VStack(spacing: 0) {
            Text(step.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(step.subtitle)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: cardWidth - 80)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Spacer(minLength: 24)

            Button(action: goNext) {
                Text(isLastStep ? "Get Started" : "Continue")
            }
            .buttonStyle(TourPrimaryButtonStyle(accent: step.accent))
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(
                isLastStep ? "FeatureTourFinishButton" : "FeatureTourContinueButton")
        }
        .id(step.id)
        .transition(.opacity)
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mockup dispatch

    @ViewBuilder
    private var screenView: some View {
        switch step.id {
        case .workspaceHealth:
            WorkspaceHealthScreenMockup(step: step)
        case .duplicates:
            DuplicatesScreenMockup(step: step)
        case .history:
            HistoryScreenMockup(step: step)
        case .exclusions:
            ExclusionScreenMockup(step: step)
        case .watchFolders:
            WatchFolderScreenMockup(step: step)
        case .learnings:
            LearningsScreenMockup(step: step)
        }
    }

    // MARK: - Navigation

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left: goBack()
        case .right: goNext()
        default: break
        }
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        HapticFeedbackManager.shared.selection()
    }

    private func goNext() {
        if currentIndex < FeatureTourStep.visible.count - 1 {
            currentIndex += 1
            HapticFeedbackManager.shared.tap()
        } else {
            finishTour()
        }
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
}

private enum FeatureTourStepID: String, CaseIterable, Identifiable {
    case workspaceHealth
    case duplicates
    case history
    case exclusions
    case watchFolders
    case learnings

    var id: String { rawValue }
}

private struct FeatureTourStep: Identifiable {
    let id: FeatureTourStepID
    let title: String
    let subtitle: String
    let accent: Color
    let icon: String

    static let all: [FeatureTourStep] = [
        FeatureTourStep(
            id: .workspaceHealth,
            title: "Workspace Health",
            subtitle:
                "Spot stale folders, duplicate pressure, and cleanup work before your workspace drifts.",
            accent: .mint,
            icon: "heart.text.square"
        ),
        FeatureTourStep(
            id: .duplicates,
            title: "Duplicates",
            subtitle:
                "Review matched files side by side and keep the strongest copy without guessing.",
            accent: .orange,
            icon: "doc.on.doc"
        ),
        FeatureTourStep(
            id: .history,
            title: "History",
            subtitle:
                "Reopen any run, inspect every move, and undo with context when you need to roll back.",
            accent: .blue,
            icon: "clock.arrow.circlepath"
        ),
        FeatureTourStep(
            id: .exclusions,
            title: "Exclusions",
            subtitle:
                "Protect folders, patterns, and extensions that should never be touched during organization.",
            accent: .red,
            icon: "eye.slash"
        ),
        FeatureTourStep(
            id: .watchFolders,
            title: "Watched Folders",
            subtitle: "Let Sorty monitor intake folders and launch workflows as new files land.",
            accent: .teal,
            icon: "eye"
        ),
        FeatureTourStep(
            id: .learnings,
            title: "Learnings",
            subtitle:
                "Turn your corrections into reusable rules that sharpen future organization runs.",
            accent: .purple,
            icon: "brain"
        ),
    ]

    @MainActor
    static var visible: [FeatureTourStep] {
        all.filter { step in
            step.id != .workspaceHealth || FeatureFlags.workspaceHealthEnabled
        }
    }
}

private struct WorkspaceHealthScreenMockup: View {
    let step: FeatureTourStep

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TourSectionHeader(
                eyebrow: "Health snapshot",
                title: "Projects / Client Archive",
                detail: "Three high-impact issues are pushing this workspace toward cleanup."
            )

            HStack(spacing: 18) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 16)
                        Circle()
                            .trim(from: 0, to: 0.79)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        step.accent.opacity(0.4), step.accent, .white.opacity(0.85),
                                    ], center: .center),
                                style: StrokeStyle(lineWidth: 16, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Text("79")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Healthy")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.62))
                        }
                    }
                    .frame(width: 170, height: 170)

                    TourGlassBadge(text: "25 GB reclaimed if resolved")
                }
                .frame(width: 220)

                VStack(spacing: 12) {
                    TourInsightCard(
                        color: .orange, title: "Old installer cache",
                        detail: "14.2 GB unused for 142 days", action: "Review cleanup")
                    TourInsightCard(
                        color: step.accent, title: "Duplicate exports",
                        detail: "7 matching file clusters in Design", action: "Open Duplicates")
                    TourInsightCard(
                        color: .blue, title: "Stale review folders",
                        detail: "11 folders untouched in the last quarter",
                        action: "Archive candidates")
                }
            }
        }
    }
}

private struct DuplicatesScreenMockup: View {
    let step: FeatureTourStep

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                TourSectionHeader(
                    eyebrow: "Matched groups",
                    title: "12 duplicate clusters",
                    detail:
                        "Sorty ranks the best version by quality, recency, and folder relevance."
                )

                VStack(spacing: 10) {
                    DuplicateClusterRow(
                        title: "Brand deck exports", files: "4 files",
                        note: "Best copy in Marketing / Decks", color: step.accent, selected: true)
                    DuplicateClusterRow(
                        title: "Invoice scans", files: "3 files", note: "2 exact, 1 near-duplicate",
                        color: .white, selected: false)
                    DuplicateClusterRow(
                        title: "Meeting recordings", files: "5 files",
                        note: "Two trimmed versions detected", color: .white, selected: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                    TourGlassBadge(text: "Keep original")
                }

                HStack(spacing: 12) {
                    DuplicatePreviewCard(
                        title: "Deck_v12.pdf", subtitle: "Latest edits · 18 MB", accent: step.accent
                    )
                    DuplicatePreviewCard(
                        title: "Deck_final.pdf", subtitle: "Approved copy · 18 MB",
                        accent: .white.opacity(0.18))
                }

                VStack(spacing: 10) {
                    DuplicateMetricRow(label: "Text content", value: "100% match")
                    DuplicateMetricRow(label: "Visual diff", value: "2 slides changed")
                    DuplicateMetricRow(label: "Recommended action", value: "Archive older export")
                }
                .padding(14)
                .background(
                    .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .frame(width: 280, alignment: .topLeading)
        }
    }
}

private struct HistoryScreenMockup: View {
    let step: FeatureTourStep

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                TourSectionHeader(
                    eyebrow: "Run timeline",
                    title: "Wednesday afternoon cleanup",
                    detail:
                        "Every session keeps its plan, applied moves, and undo entry points together."
                )

                VStack(spacing: 10) {
                    HistoryEntryRow(
                        title: "Downloads cleanup", time: "2:14 PM", status: "Applied",
                        detail: "48 files organized into 9 folders", color: step.accent)
                    HistoryEntryRow(
                        title: "Reference docs", time: "1:42 PM", status: "Preview only",
                        detail: "Kept for review before apply", color: .blue)
                    HistoryEntryRow(
                        title: "Client handoff", time: "Yesterday", status: "Undone",
                        detail: "Restored 16 files to original paths", color: .orange)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                TourGlassBadge(text: "Undo available")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Run summary")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    TimelineStatRow(label: "Folders created", value: "9")
                    TimelineStatRow(label: "Files moved", value: "48")
                    TimelineStatRow(label: "Renames applied", value: "6")
                    TimelineStatRow(label: "Warnings", value: "1 skipped alias")
                }
                .padding(16)
                .background(
                    .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Highlighted action")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                    TourActionPill(
                        title: "Undo run", systemImage: "arrow.uturn.backward", accent: step.accent)
                }
            }
            .frame(width: 260, alignment: .topLeading)
        }
    }
}

private struct ExclusionScreenMockup: View {
    let step: FeatureTourStep

    private let chips = [
        "*.photoslibrary",
        "Client Archive",
        "System Backups",
        "*.pkg",
        "Legal Holds",
        "Reference Models",
        "node_modules",
        "Finance / Taxes",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TourSectionHeader(
                eyebrow: "Protection rules",
                title: "Keep fragile areas out of Sorty runs",
                detail:
                    "Rules are readable, layered, and visible before a plan touches the file system."
            )

            TourFlowLayout(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(step.accent.opacity(0.16), in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(step.accent.opacity(0.32), lineWidth: 1)
                        )
                }
            }
            .padding(16)
            .background(
                .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 14) {
                TourRulePanel(
                    title: "Path rules",
                    detail: "Protect deep folders, archives, or synced volumes.",
                    accent: step.accent)
                TourRulePanel(
                    title: "Pattern rules",
                    detail: "Exclude file types and generated assets in one place.", accent: .blue)
                TourRulePanel(
                    title: "Review banner",
                    detail: "Plans surface matched exclusions before you apply.", accent: .orange)
            }
        }
    }
}

private struct WatchFolderScreenMockup: View {
    let step: FeatureTourStep

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                TourSectionHeader(
                    eyebrow: "Live automation",
                    title: "Watched folders are active",
                    detail:
                        "Incoming events stream in so you can see exactly what triggered a workflow."
                )

                VStack(spacing: 10) {
                    WatchFolderCard(
                        title: "Downloads / Intake", badge: "Auto-organize", accent: step.accent)
                    WatchFolderCard(title: "Scans", badge: "Needs review", accent: .orange)
                    WatchFolderCard(
                        title: "Team Handoff", badge: "Paused", accent: .white.opacity(0.16))
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Recent events")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(spacing: 10) {
                    WatchEventRow(
                        title: "New file detected", detail: "Receipt_0428.pdf arrived in Scans",
                        color: step.accent)
                    WatchEventRow(
                        title: "Plan ready", detail: "Downloads / Intake organized 7 items",
                        color: .blue)
                    WatchEventRow(
                        title: "Skipped by rule", detail: "Project build folder matched exclusion",
                        color: .orange)
                    WatchEventRow(
                        title: "Notification sent",
                        detail: "Batch summary delivered to Notification Center",
                        color: .white.opacity(0.4))
                }
                .padding(14)
                .background(
                    .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .frame(width: 310, alignment: .topLeading)
        }
    }
}

private struct LearningsScreenMockup: View {
    let step: FeatureTourStep

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TourSectionHeader(
                eyebrow: "Behavior signals",
                title: "Sorty is learning from your corrections",
                detail:
                    "Accepted edits, rejected moves, and refined rules stay visible so you can steer future runs."
            )

            HStack(spacing: 14) {
                LearningsMetricCard(title: "Sessions observed", value: "42", accent: step.accent)
                LearningsMetricCard(title: "Rules suggested", value: "7", accent: .blue)
                LearningsMetricCard(title: "Confidence", value: "High", accent: .green)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 12) {
                    LearningsRuleCard(
                        title: "Invoices stay grouped by month",
                        detail: "Derived from 13 accepted corrections in Finance.",
                        accent: step.accent,
                        status: "Ready to apply"
                    )
                    LearningsRuleCard(
                        title: "Screenshots move into dated subfolders",
                        detail: "Based on repeated manual edits in Downloads.",
                        accent: .blue,
                        status: "Watching for one more signal"
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Latest feedback")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    VStack(spacing: 10) {
                        WatchEventRow(
                            title: "Accepted",
                            detail: "Draft invoice matched Accounts / 2026 / April", color: .green)
                        WatchEventRow(
                            title: "Corrected",
                            detail: "Presentation moved from Archive back to Active",
                            color: step.accent)
                        WatchEventRow(
                            title: "New instruction",
                            detail: "Keep client deliverables flat after approval", color: .blue)
                    }
                    .padding(14)
                    .background(
                        .white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .frame(width: 300, alignment: .topLeading)
            }
        }
    }
}

private struct TourSectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TourInsightCard: View {
    let color: Color
    let title: String
    let detail: String
    let action: String

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            Text(action)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(14)
        .background(
            .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct DuplicateClusterRow: View {
    let title: String
    let files: String
    let note: String
    let color: Color
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(files)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? color : .white.opacity(0.48))
            }
            Text(note)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(14)
        .background(
            selected ? color.opacity(0.16) : .white.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? color.opacity(0.34) : .white.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct DuplicatePreviewCard: View {
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent)
                .frame(height: 124)
                .overlay {
                    VStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.black.opacity(0.12))
                            .frame(width: 92, height: 10)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.black.opacity(0.18))
                            .frame(width: 120, height: 58)
                    }
                }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(12)
        .background(
            .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct DuplicateMetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct HistoryEntryRow: View {
    let title: String
    let time: String
    let status: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(time)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.44))
                }
                Text(status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .padding(14)
        .background(
            .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TimelineStatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct TourActionPill: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(accent.opacity(0.24), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(accent.opacity(0.34), lineWidth: 1)
        )
    }
}

private struct TourRulePanel: View {
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct WatchFolderCard: View {
    let title: String
    let badge: String
    let accent: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Monitoring 24/7 for new arrivals")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
            }
            Spacer()
            TourGlassBadge(text: badge, accent: accent)
        }
        .padding(14)
        .background(
            .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WatchEventRow: View {
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LearningsMetricCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct LearningsRuleCard: View {
    let title: String
    let detail: String
    let accent: Color
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Spacer()
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(accent)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct TourGlassBadge: View {
    let text: String
    var accent: Color = .white.opacity(0.14)

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.86))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(accent, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct TourPrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minWidth: 220, minHeight: 42)
            .background(
                LinearGradient(
                    colors: [
                        accent.opacity(configuration.isPressed ? 0.82 : 1),
                        accent.opacity(configuration.isPressed ? 0.66 : 0.82),
                        .white.opacity(configuration.isPressed ? 0.14 : 0.2),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule(style: .continuous)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(
                color: accent.opacity(configuration.isPressed ? 0.18 : 0.34),
                radius: configuration.isPressed ? 12 : 24, x: 0, y: configuration.isPressed ? 8 : 14
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct TourFlowLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
        self.horizontalSpacing = horizontalSpacing
        self.verticalSpacing = verticalSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            let totalWidth = subviews.reduce(CGFloat.zero) { partialResult, subview in
                partialResult + subview.sizeThatFits(.unspecified).width
            }
            let maxHeight = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            return CGSize(width: totalWidth, height: maxHeight)
        }

        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                totalHeight += rowHeight + verticalSpacing
                x = 0
                rowHeight = 0
            }

            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }

        totalHeight += rowHeight
        return CGSize(width: maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    FeatureTourView()
        .environmentObject(AppState())
}

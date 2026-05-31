//
//  WorkflowContainer.swift
//  Sorty
//
//  Shared container for consistent workflow layouts
//

import SwiftUI

/// Workflow step enum for progress indicator
public enum WorkflowStep: Int, CaseIterable {
    case selectFolder = 0
    case configure = 1
    case analyze = 2
    case preview = 3
    case complete = 4
    
    var title: String {
        switch self {
        case .selectFolder: return "Select"
        case .configure: return "Configure"
        case .analyze: return "Analyze"
        case .preview: return "Preview"
        case .complete: return "Complete"
        }
    }
    
    var icon: String {
        switch self {
        case .selectFolder: return "folder"
        case .configure: return "slider.horizontal.3"
        case .analyze: return "brain.head.profile"
        case .preview: return "eye"
        case .complete: return "checkmark.circle"
        }
    }
}

/// Environment flag: when `true`, `WorkflowContainer` suppresses its own
/// gradient background. Use this when an ancestor view is rendering a single
/// persistent `WorkflowGradientBackground` to avoid double-mounting (which
/// causes the gradient to flicker as views transition).
private struct WorkflowGradientHiddenKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var workflowGradientHidden: Bool {
        get { self[WorkflowGradientHiddenKey.self] }
        set { self[WorkflowGradientHiddenKey.self] = newValue }
    }
}

/// Shared container for workflow screens with consistent layout
struct WorkflowContainer<Content: View>: View {
    let currentStep: WorkflowStep?
    let showStepIndicator: Bool
    @ViewBuilder var content: Content
    @Environment(\.workflowGradientHidden) private var gradientHidden

    init(
        currentStep: WorkflowStep? = nil,
        showStepIndicator: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.currentStep = currentStep
        self.showStepIndicator = showStepIndicator
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if showStepIndicator, let step = currentStep {
                WorkflowStepIndicator(currentStep: step)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
            }

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 24) {
                        content
                    }
                    .frame(maxWidth: 580)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
        .background {
            if !gradientHidden {
                WorkflowGradientBackground()
            }
        }
    }
}

struct WorkflowGradientBackground: View {
    var showsBaseColor = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.workflowGradientHidden) private var gradientHidden

    /// Drives the one-shot rise-from-bottom reveal (0 -> 1).
    /// We animate only `scaleEffect` (anchored to `.bottom`) and `opacity`:
    /// no blur, no `drawingGroup`, because those were the main flicker sources.
    @State private var gradientReveal: Double = 0

    /// Anchor for the continuous TimelineView clock so animation is phase
    /// stable across view rebuilds and never snaps when the system tick rate
    /// changes.
    @State private var startTime: Date = .now

    var body: some View {
        if !gradientHidden {
            backgroundLayer
                .task {
                    // Guarded against re-entry so it only plays once per mount even
                    // if `task` is re-fired by an upstream identity change.
                    guard gradientReveal == 0 else { return }
                    startTime = .now
                    withAnimation(.easeOut(duration: 0.7)) {
                        gradientReveal = 1
                    }
                }
        }
    }

    /// Light mode needs more saturation for the gradient to read against the
    /// near-white window background; dark mode looks better with a softer
    /// wash so it doesn't compete with the foreground content.
    private var topOpacity: Double {
        colorScheme == .dark ? 0.28 : 0.44
    }

    private var midOpacity: Double {
        colorScheme == .dark ? 0.11 : 0.18
    }

    /// Top-of-stack soft bloom: a radial highlight that drifts horizontally,
    /// giving the wash a sense of light catching on it rather than a flat
    /// pulse.
    private var bloomOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.30
    }

    /// The background is built once and `TimelineView` only mutates cheap GPU
    /// transforms (`scaleEffect`, `opacity`) plus the bloom's `UnitPoint`.
    /// SwiftUI never has to rebuild or rasterize the gradient itself.
    private var backgroundLayer: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSince(startTime)

            // Two detuned sine waves combined produce a slowly varying breath
            // that never repeats exactly, so the motion feels organic instead
            // of mechanically looping. Periods ~4.8s and ~7.3s are coprime
            // enough to give a long beat pattern.
            let breathA = sin(t * (2 * .pi / 4.8))
            let breathB = sin(t * (2 * .pi / 7.3) + 1.1)
            let breath = (breathA * 0.65 + breathB * 0.35) // -1 ... 1
            let breathNorm = (breath + 1) * 0.5             //  0 ... 1

            // Vertical scale stays inside [0.88, 1.04] so the gradient never
            // lifts off the bottom edge — no white gap can appear — while
            // still reading as a clear bloom.
            let scaleY = reduceMotion ? 1.0 : (0.88 + 0.16 * breathNorm)
            // Opacity breathes between ~0.78 and 1.0 of the resting value.
            let opacityBreath = reduceMotion ? 1.0 : (0.78 + 0.22 * breathNorm)
            // Lateral drift of the bloom highlight, very slow (~11s cycle),
            // travelling within the central 60% of the width.
            let drift = reduceMotion ? 0 : sin(t * (2 * .pi / 11.0))
            let bloomX = 0.5 + drift * 0.18
            // Bloom intensity breathes on its own offset cycle so it never
            // perfectly aligns with the scale breath.
            let bloomPulse = reduceMotion ? 0.55 : (0.45 + 0.30 * ((sin(t * (2 * .pi / 6.1) + 0.6) + 1) * 0.5))

            ZStack(alignment: .bottom) {
                if showsBaseColor {
                    Color(NSColor.windowBackgroundColor)
                }

                LinearGradient(
                    colors: [
                        SortyDesignSystem.Colors.resolvedAccent.opacity(topOpacity),
                        SortyDesignSystem.Colors.resolvedAccent.opacity(midOpacity),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .center
                )
                .scaleEffect(x: 1, y: gradientReveal * scaleY, anchor: .bottom)
                .opacity(gradientReveal * opacityBreath)

                // Soft drifting bloom layered on top. RadialGradient anchored
                // near the bottom edge so the highlight reads as a light source
                // glowing from below the window chrome.
                GeometryReader { proxy in
                    RadialGradient(
                        colors: [
                            SortyDesignSystem.Colors.resolvedAccent.opacity(bloomOpacity * bloomPulse),
                            SortyDesignSystem.Colors.resolvedAccent.opacity(bloomOpacity * bloomPulse * 0.35),
                            .clear
                        ],
                        center: UnitPoint(x: bloomX, y: 1.05),
                        startRadius: 0,
                        endRadius: max(proxy.size.width, proxy.size.height) * 0.62
                    )
                    .blendMode(.plusLighter)
                    .opacity(gradientReveal)
                }
                .allowsHitTesting(false)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct EmptyStateWorkflowGradientModifier: ViewModifier {
    let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                ZStack(alignment: .bottom) {
                    Color(NSColor.windowBackgroundColor)

                    WorkflowGradientBackground(showsBaseColor: false)
                        .opacity(isVisible ? 1 : 0)
                        .scaleEffect(
                            x: 1,
                            y: isVisible || reduceMotion ? 1 : 0.86,
                            anchor: .bottom
                        )
                        .animation(.easeInOut(duration: reduceMotion ? 0.01 : 0.45), value: isVisible)
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func emptyStateWorkflowGradient(isVisible: Bool) -> some View {
        modifier(EmptyStateWorkflowGradientModifier(isVisible: isVisible))
    }
}

/// Step indicator showing progress through workflow
struct WorkflowStepIndicator: View {
    let currentStep: WorkflowStep
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(WorkflowStep.allCases.enumerated()), id: \.element) { index, step in
                if step == .complete { EmptyView() } else {
                    HStack(spacing: 8) {
                        stepCircle(for: step)
                        
                        if step != .preview {
                            stepConnector(isCompleted: step.rawValue < currentStep.rawValue)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 40)
    }
    
    @ViewBuilder
    private func stepCircle(for step: WorkflowStep) -> some View {
        let isActive = step == currentStep
        let isCompleted = step.rawValue < currentStep.rawValue
        
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? SortyDesignSystem.Colors.resolvedAccent : (isCompleted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.2) : Color.secondary.opacity(0.1)))
                    .frame(width: 32, height: 32)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                } else {
                    Image(systemName: step.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isActive ? .white : .secondary)
                }
            }
            
            Text(step.title)
                .font(.caption2)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
    
    private func stepConnector(isCompleted: Bool) -> some View {
        Rectangle()
            .fill(isCompleted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.3) : Color.secondary.opacity(0.15))
            .frame(width: 40, height: 2)
            .padding(.bottom, 20)
    }
}

/// A styled card section for grouping related content
struct WorkflowCard<Content: View>: View {
    let title: String?
    let icon: String?
    @ViewBuilder var content: Content
    
    init(
        title: String? = nil,
        icon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                HStack(spacing: 6) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

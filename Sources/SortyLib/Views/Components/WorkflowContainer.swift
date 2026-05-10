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

/// Shared container for workflow screens with consistent layout
struct WorkflowContainer<Content: View>: View {
    let currentStep: WorkflowStep?
    let showStepIndicator: Bool
    @ViewBuilder var content: Content

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
        .background(WorkflowGradientBackground())
    }
}

struct WorkflowGradientBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Drives the one-shot rise-from-bottom reveal (0 -> 1).
    /// We animate only `scaleEffect` (anchored to `.bottom`) and `opacity`:
    /// no blur, no `drawingGroup`, because those were the main flicker sources.
    @State private var gradientReveal: Double = 0

    /// Drives a continuous, slow breath (0 -> 1, autoreverses).
    /// Modulates the gradient's vertical extent and brightness so it feels
    /// alive without ever lifting off the bottom edge.
    @State private var gradientBreath: Double = 0

    var body: some View {
        backgroundLayer
            .task {
                // Guarded against re-entry so it only plays once per mount even
                // if `task` is re-fired by an upstream identity change.
                guard gradientReveal == 0 else { return }
                withAnimation(.easeOut(duration: 0.7)) {
                    gradientReveal = 1
                }
                // Wait for the reveal to settle, then start the slow continuous
                // breath. Starting it before the reveal completes would compound
                // two scale animations on the same property and look jittery.
                try? await Task.sleep(nanoseconds: 750_000_000)
                withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                    gradientBreath = 1
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

    /// Combined vertical scale: the one-shot reveal multiplied by a visible
    /// breath modulation. The breath stays inside `[0.86, 1.02]` so the
    /// gradient never lifts off the bottom edge — no white gap can appear,
    /// while still being clearly perceptible.
    private var combinedScaleY: Double {
        let breath = 0.86 + 0.16 * gradientBreath
        return gradientReveal * breath
    }

    /// Combined opacity: the one-shot reveal multiplied by a perceptible
    /// breath in `[0.70, 1.0]` so the colour seems to bloom and recede.
    private var combinedOpacity: Double {
        let breath = 0.70 + 0.30 * gradientBreath
        return gradientReveal * breath
    }

    /// The background is built once. Only `scaleEffect` (anchored to
    /// `.bottom`) and `opacity` change — both cheap GPU transforms — so
    /// SwiftUI never has to rebuild or rasterize the gradient itself.
    private var backgroundLayer: some View {
        ZStack(alignment: .bottom) {
            Color(NSColor.windowBackgroundColor)

            LinearGradient(
                colors: [
                    SortyDesignSystem.Colors.resolvedAccent.opacity(topOpacity),
                    SortyDesignSystem.Colors.resolvedAccent.opacity(midOpacity),
                    Color.clear
                ],
                startPoint: .bottom,
                endPoint: .center
            )
            .scaleEffect(x: 1, y: combinedScaleY, anchor: .bottom)
            .opacity(combinedOpacity)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
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

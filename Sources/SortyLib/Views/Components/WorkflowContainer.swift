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
        .background(.background)
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
                    .fill(isActive ? Color.accentColor : (isCompleted ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1)))
                    .frame(width: 32, height: 32)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
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
            .fill(isCompleted ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
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

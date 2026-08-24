//
//  DemoStepView.swift
//  Sorty
//
//  Demo step of the onboarding flow
//

import SwiftUI

private struct DemoCompletionView: View {
    let plan: OrganizationPlan?
    @Binding var showPreviewTree: Bool
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            DemoCompletionCelebration(isVisible: showPreviewTree)

            VStack(spacing: 8) {
                Text("Organization Complete!")
                    .font(.title2.bold())

                Text("See how Sorty transformed chaos into order")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            DemoCompletionStats(plan: plan)
            DemoCompletionHighlights()

            Button(action: onComplete) {
                HStack(spacing: 8) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(.sortyPrimary)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                showPreviewTree = true
            }
        }
    }
}

private struct DemoCompletionCelebration: View {
    let isVisible: Bool

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                DemoCompletionRipple(index: index, isVisible: isVisible)
            }

            Circle()
                .fill(Color.green.opacity(0.1))
                .frame(width: 100, height: 100)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: isVisible)
        }
    }
}

private struct DemoCompletionRipple: View {
    let index: Int
    let isVisible: Bool

    private var diameter: CGFloat { CGFloat(100 + index * 20) }
    private var strokeOpacity: Double { 0.3 - Double(index) * 0.1 }
    private var delay: Double { Double(index) * 0.2 }

    var body: some View {
        Circle()
            .stroke(Color.green.opacity(strokeOpacity), lineWidth: 2)
            .frame(width: diameter, height: diameter)
            .scaleEffect(isVisible ? 1.1 : 0.9)
            .opacity(isVisible ? 0 : 1)
            .animation(
                .easeOut(duration: 1.2)
                    .repeatCount(3, autoreverses: false)
                    .delay(delay),
                value: isVisible
            )
    }
}

private struct DemoCompletionStats: View {
    let plan: OrganizationPlan?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                cards
            }

            VStack(spacing: 14) {
                cards
            }
        }
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private var cards: some View {
        if let plan {
            DemoStatCard(
                icon: "doc.fill",
                value: "\(plan.totalFiles)",
                label: "files organized",
                color: .blue
            )

            DemoStatCard(
                icon: "folder.fill",
                value: "\(plan.totalFolders)",
                label: "folders created",
                color: .orange
            )
        } else {
            DemoStatCard(icon: "doc.fill", value: "10", label: "files organized", color: .blue)
            DemoStatCard(icon: "folder.fill", value: "4", label: "folders created", color: .orange)
            DemoStatCard(icon: "bolt.fill", value: "<1s", label: "time taken", color: .purple)
        }
    }
}

private struct DemoCompletionHighlights: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("Sorty-Powered Organization")
                    .font(.subheadline.bold())
            }

            VStack(alignment: .leading, spacing: 8) {
                DemoHighlightRow(icon: "photo.stack", text: "Grouped photos by type", color: .blue)
                DemoHighlightRow(icon: "doc.text", text: "Organized documents intelligently", color: .green)
                DemoHighlightRow(icon: "dollarsign.circle", text: "Separated financial files", color: .orange)
                DemoHighlightRow(icon: "arrow.uturn.backward.circle", text: "100% reversible with one click", color: .purple)
            }
        }
        .padding(16)
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.05))
                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
        )
    }
}

public struct DemoStepView: View {
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runtimeController = DemoRuntimeController()
    @State private var organizerState: OrganizationState = .idle
    @State private var currentPlan: OrganizationPlan?
    @State private var hasAppeared = false
    @State private var selectedDirectory: URL?
    @State private var demoState: DemoState = .intro
    @State private var showPreviewTree = false
    @State private var isDropTargeted = false
    
    enum DemoState {
        case intro
        case simulatedDemo
        case selectDirectory
        case analyzing
        case organizing
        case complete
    }
    
    public init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let compactLayout = geometry.size.width < 1180
            let horizontalPadding: CGFloat = compactLayout ? 32 : 60
            let rightPanelVerticalPadding: CGFloat = compactLayout ? 28 : 40
            let sectionSpacing: CGFloat = compactLayout ? 24 : 32
            let leftContentMaxWidth: CGFloat = compactLayout ? 360 : 420

            HStack(spacing: 0) {
                // Left side - What to expect
                VStack(alignment: .leading, spacing: 24) {
                    Spacer()

                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: demoState == .simulatedDemo ? "sparkles" : "wand.and.stars")
                            .font(.system(size: 48))
                            .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                            .symbolReplaceTransition(animationValue: demoState)
                            .symbolEffect(
                                .pulse.byLayer,
                                options: .repeating,
                                isActive: demoState == .simulatedDemo && !reduceMotion
                            )

                        Text(demoState == .complete ? "That's Sorty!" : "See the Magic")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .numericTextTransition(animationValue: demoState)

                        Text(leftPanelDescription)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .numericTextTransition(animationValue: leftPanelDescription)

                        VStack(alignment: .leading, spacing: 12) {
                            OnboardingProgressRow(state: demoState == .simulatedDemo || demoState == .analyzing ? .active : .idle, circleSize: 26, activeFill: .green.opacity(0.15), title: "On-device privacy scanning", fillsWidth: true, style: .togglingSymbol(idle: "lock.shield", active: "lock.shield.fill", weight: .semibold))
                            OnboardingProgressRow(state: demoState == .simulatedDemo || demoState == .organizing ? .active : .idle, circleSize: 26, activeFill: .green.opacity(0.15), title: "Persona-aware planning", fillsWidth: true, style: .togglingSymbol(idle: "person.crop.circle.badge.checkmark", active: "person.crop.circle.badge.checkmark.fill", weight: .semibold))
                            OnboardingProgressRow(state: demoState == .complete ? .active : .idle, circleSize: 26, activeFill: .green.opacity(0.15), title: "Smart folder structure", fillsWidth: true, style: .togglingSymbol(idle: "folder.badge.gearshape", active: "folder.badge.gearshape.fill", weight: .semibold))
                            OnboardingProgressRow(state: demoState == .complete ? .active : .idle, circleSize: 26, activeFill: .green.opacity(0.15), title: "One-click undo safety", fillsWidth: true, style: .togglingSymbol(idle: "arrow.uturn.backward.circle", active: "arrow.uturn.backward.circle.fill", weight: .semibold))
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: leftContentMaxWidth)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(x: hasAppeared ? 0 : -20)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8).delay(0.1),
                        value: hasAppeared
                    )

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.10), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

                // Right side - Demo interaction
                VStack(spacing: sectionSpacing) {
                    Spacer()

                    switch demoState {
                    case .intro:
                        introView
                    case .simulatedDemo:
                        SimulatedDemoAnimationView(onComplete: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                demoState = .complete
                            }
                            HapticFeedbackManager.shared.success()
                        })
                    case .selectDirectory:
                        selectDirectoryView
                    case .analyzing, .organizing:
                        processingView
                    case .complete:
                        completeView
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, rightPanelVerticalPadding)
                .padding(.horizontal, horizontalPadding)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : 20)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8).delay(0.2),
                    value: hasAppeared
                )
            }
            .siriDropZone(
                cornerRadius: 22,
                isEnabled: demoState == .selectDirectory,
                glowPresentation: .window,
                glowLineWidth: 2.2,
                glowRadius: 16,
                isTargeted: $isDropTargeted
            ) { providers in
                handleDrop(providers: providers)
            }
            .onAppear {
                hasAppeared = true
            }
            .onChange(of: demoState) { _, newState in
                if newState != .selectDirectory {
                    isDropTargeted = false
                }
            }
            .background {
                DemoEnvironmentResolver { organizer, settingsViewModel, state, plan in
                    runtimeController.organizer = organizer
                    runtimeController.settingsViewModel = settingsViewModel
                    organizerState = state
                    currentPlan = plan
                    handleStateChange(state)
                }
                .frame(width: 0, height: 0)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Demo Step")
        }
    }
    
    @ViewBuilder
    private var introView: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.12))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                    .symbolEffect(
                        .pulse.byLayer,
                        options: .repeating,
                        isActive: !reduceMotion
                    )
            }
            
            VStack(spacing: 12) {
                Text("See Sorty in Action")
                    .font(.title2.bold())
                
                Text("Watch a live demo showing how Sorty transforms a messy folder into an organized structure.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            VStack(spacing: 16) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        demoState = .simulatedDemo
                    }
                    HapticFeedbackManager.shared.tap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Watch Demo")
                    }
                }
                .buttonStyle(.sortyPrimary)
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        demoState = .selectDirectory
                    }
                    HapticFeedbackManager.shared.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 12))
                        Text("Or try with your own folder")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var selectDirectoryView: some View {
        VStack(spacing: 24) {
            if let url = selectedDirectory {
                // Selected folder display
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "folder.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .minimumScaleFactor(0.85)
                            PrivacySensitivePathText(path: url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .minimumScaleFactor(0.8)
                        }
                        .layoutPriority(1)
                        
                        Spacer()
                        
                        Button {
                            selectedDirectory = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                    .frame(maxWidth: 440)
                    
                    HStack(spacing: 12) {
                        Button {
                            selectDirectory()
                        } label: {
                            Text("Change")
                        }
                        .buttonStyle(.sortyBordered)
                        
                        Button {
                            startDemo()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Organize Now")
                            }
                        }
                        .buttonStyle(.sortyPrimary)
                    }
                }
            } else {
                // Folder selection prompt
                VStack(spacing: 20) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [10]))
                            .foregroundStyle(isDropTargeted ? SortyDesignSystem.Colors.resolvedAccent : Color.secondary.opacity(0.3))
                            .frame(width: 200, height: 140)
                        
                        VStack(spacing: 12) {
                            Image(systemName: isDropTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(isDropTargeted ? SortyDesignSystem.Colors.resolvedAccent : Color.secondary)
                                .symbolReplaceTransition(animationValue: isDropTargeted)
                            
                            Text(isDropTargeted ? "Drop to select" : "Drop a folder here")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .numericTextTransition(animationValue: isDropTargeted)
                        }
                    }
                    
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    
                    Button {
                        selectDirectory()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                            Text("Browse...")
                        }
                        .frame(minWidth: 120)
                    }
                    .buttonStyle(.sortyBordered)
                }
            }
        }
    }
    
    @ViewBuilder
    private var processingView: some View {
        VStack(spacing: 32) {
            // Animated processing indicator
            ZStack {
                Circle()
                    .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                BouncingSpinner(size: 40, color: .accentColor)
            }
            
            VStack(spacing: 8) {
                Text(statusText)
                    .font(.title3.bold())
                    .numericTextTransition(animationValue: statusText)
                
                Text(statusDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .numericTextTransition(animationValue: statusDescription)
            }
            
            // Progress steps
            VStack(alignment: .leading, spacing: 12) {
                OnboardingProgressRow(state: demoState == .organizing || demoState == .complete ? .complete : (demoState == .analyzing ? .active : .idle), circleSize: 28, activeFill: SortyDesignSystem.Colors.resolvedAccent.opacity(0.1), title: "Scanning files...", style: .spinner(idleSymbol: "magnifyingglass", idleWeight: .regular))

                OnboardingProgressRow(state: demoState == .complete ? .complete : (demoState == .organizing ? .active : .idle), circleSize: 28, activeFill: SortyDesignSystem.Colors.resolvedAccent.opacity(0.1), title: "Sorty analyzing patterns...", style: .spinner(idleSymbol: "brain.head.profile", idleWeight: .regular))

                OnboardingProgressRow(state: .idle, circleSize: 28, activeFill: SortyDesignSystem.Colors.resolvedAccent.opacity(0.1), title: "Creating structure...", style: .spinner(idleSymbol: "folder.badge.gearshape", idleWeight: .regular))
            }
            .frame(maxWidth: 280)
        }
    }
    
    @ViewBuilder
    private var completeView: some View {
        DemoCompletionView(
            plan: currentPlan,
            showPreviewTree: $showPreviewTree,
            onComplete: onComplete
        )
    }
    
    private var leftPanelDescription: String {
        switch demoState {
        case .intro:
            return "Watch Sorty analyze your files and create an intelligent organization structure in real-time."
        case .simulatedDemo:
            return "Watch as Sorty scans, categorizes, and organizes files into a clean folder structure."
        case .selectDirectory, .analyzing, .organizing:
            return "Sorty is working on your files. Watch the magic happen!"
        case .complete:
            return "Your files are now beautifully organized. Ready to try it on your own folders?"
        }
    }

    private var statusText: String {
        switch organizerState {
        case .scanning: return "Analyzing Your Files"
        case .organizing: return "Creating Organization Plan"
        case .applying: return "Applying Changes"
        case .ready: return "Preview Ready"
        default: return "Processing"
        }
    }
    
    private var statusDescription: String {
        switch organizerState {
        case .scanning: return "Examining file names, types, and patterns..."
        case .organizing: return "Sorty is designing the perfect folder structure..."
        case .applying: return "Moving files to their new homes..."
        case .ready: return "Your organization plan is ready!"
        default: return "Working on your files..."
        }
    }
    
    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select"
        panel.message = "Choose a folder to organize"
        
        if panel.runModal() == .OK, let url = panel.url {
            HapticFeedbackManager.shared.success()
            selectedDirectory = url
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.hasDirectoryPath {
                DispatchQueue.main.async {
                    selectedDirectory = url
                    HapticFeedbackManager.shared.success()
                }
            }
        }
        return true
    }
    
    private func startDemo() {
        guard let directory = selectedDirectory,
              let organizer = runtimeController.organizer,
              let settingsViewModel = runtimeController.settingsViewModel else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            demoState = .analyzing
        }
        HapticFeedbackManager.shared.tap()
        
        Task {
            do {
                try await organizer.configure(with: settingsViewModel.config)
                try await organizer.organize(directory: directory)
                
                // Auto-apply after preview is ready
                if case .ready = organizer.state {
                    try await organizer.apply(at: directory, dryRun: false, enableTagging: settingsViewModel.config.enableFileTagging)
                }
            } catch {
                HapticFeedbackManager.shared.error()
                withAnimation {
                    demoState = .selectDirectory
                }
            }
        }
    }
    
    private func handleStateChange(_ state: OrganizationState) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            switch state {
            case .scanning:
                demoState = .analyzing
            case .organizing:
                demoState = .organizing
            case .completed:
                HapticFeedbackManager.shared.success()
                demoState = .complete
            case .error:
                HapticFeedbackManager.shared.error()
                demoState = .selectDirectory
            default:
                break
            }
        }
    }
}

@MainActor
private final class DemoRuntimeController {
    weak var organizer: FolderOrganizer?
    weak var settingsViewModel: SettingsViewModel?
}

/// Narrows the demo's broad environment subscriptions to the two values that
/// affect presentation. Streaming organizer progress still reaches this tiny
/// adapter, but no longer rebuilds both animated demo panes.
private struct DemoEnvironmentResolver: View {
    @EnvironmentObject private var organizer: FolderOrganizer
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    let onSnapshot: (FolderOrganizer, SettingsViewModel, OrganizationState, OrganizationPlan?) -> Void

    var body: some View {
        Color.clear
            .onAppear {
                onSnapshot(organizer, settingsViewModel, organizer.state, organizer.currentPlan)
            }
            .onChange(of: organizer.state) { _, state in
                onSnapshot(organizer, settingsViewModel, state, organizer.currentPlan)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Supporting Views

struct DemoStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.1))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
            }
            
            Text(value)
                .font(.title2.bold())
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DemoHighlightRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    DemoStepView(onComplete: {})
        .environmentObject(FolderOrganizer())
        .environmentObject(SettingsViewModel())
}

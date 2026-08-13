//
//  SimulatedDemoAnimationView.swift
//  Sorty
//
//  Animated demo simulation for the onboarding demo step
//

import AppKit
import QuartzCore
import SwiftUI

struct SimulatedDemoAnimationView: View {
    let onComplete: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    @State private var phase: DemoPhase = .messy
    @State private var scannedFileIndex = -1
    @State private var currentThought: String = ""
    @State private var thoughtOpacity: Double = 0
    @State private var files: [DemoFileNode] = []
    @State private var folders: [DemoFolderNode] = []
    @State private var organizedCount: Int = 0
    @State private var showStats: Bool = false
    @State private var particleEffect: Bool = false
    
    // New state for enhanced demo
    @State private var showPrivacyBadge: Bool = false
    @State private var showPersonaCard: Bool = false
    @State private var personaApplying: Bool = true
    @State private var selectedPlanIndex: Int = -1
    @State private var showPlanCheckmark: Bool = false
    @State private var showUndoBadge: Bool = false
    @State private var transitionParticles: Bool = false
    @State private var fileRotations: [Double] = []
    @State private var fileBobOffsets: [CGFloat] = []
    @State private var fileBobDurations: [Double] = []
    @State private var fileBobbing: Bool = false
    @State private var confettiActive: Bool = false
    @State private var displayedFileCount: Int = 0
    @State private var displayedFolderCount: Int = 0
    @State private var displayedPercent: Int = 0
    @State private var organizingTrailOpacities: [UUID: Bool] = [:]
    @State private var animationTask: Task<Void, Never>?
    @State private var scanHighlightTask: Task<Void, Never>?
    @State private var pendingWorkItems: [DispatchWorkItem] = []

    @StateObject private var audioManager = OnboardingAudioManager()

    enum DemoPhase: CaseIterable {
        case messy
        case scanning
        case thinking
        case comparing
        case organizing
        case complete
    }
    
    private let sampleFiles: [DemoFileNode] = [
        DemoFileNode(name: "IMG_2024.jpg", icon: "photo.fill", color: .blue, targetFolder: "Photos"),
        DemoFileNode(name: "receipt_amazon.pdf", icon: "doc.fill", color: .red, targetFolder: "Finances"),
        DemoFileNode(name: "project_notes.docx", icon: "doc.text.fill", color: .blue, targetFolder: "Documents"),
        DemoFileNode(name: "photo_vacation.png", icon: "photo.fill", color: .green, targetFolder: "Photos"),
        DemoFileNode(name: "budget_2024.xlsx", icon: "tablecells.fill", color: .green, targetFolder: "Documents"),
        DemoFileNode(name: "screenshot_123.png", icon: "photo.fill", color: .purple, targetFolder: "Other"),
        DemoFileNode(name: "meeting_notes.md", icon: "doc.text.fill", color: .orange, targetFolder: "Documents"),
        DemoFileNode(name: "invoice_client.pdf", icon: "doc.fill", color: .red, targetFolder: "Finances"),
        DemoFileNode(name: "family_photo.jpg", icon: "photo.fill", color: .pink, targetFolder: "Photos"),
        DemoFileNode(name: "code_backup.zip", icon: "doc.zipper", color: .gray, targetFolder: "Other")
    ]
    
    private let sampleFolders: [DemoFolderNode] = [
        DemoFolderNode(name: "Documents", icon: "folder.fill", color: .blue),
        DemoFolderNode(name: "Photos", icon: "folder.fill", color: .green),
        DemoFolderNode(name: "Finances", icon: "folder.fill", color: .orange),
        DemoFolderNode(name: "Other", icon: "folder.fill", color: .gray)
    ]
    
    // Enhanced AI thoughts with privacy and persona focus
    private let aiThoughts: [String] = [
        "Scanning file types...",
        "Files stay on your device",
        "Found photos, docs, and archives",
        "Detecting naming patterns",
        "Applying Minimal persona style",
        "Choosing fewer folders",
        "Comparing organization plans",
        "Plan A keeps things simpler",
        "Moving files into categories",
        "Creating one-click undo checkpoint"
    ]
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

            VStack(spacing: 24) {
                phaseIndicator

                ZStack {
                    // Transition particles overlay
                    if transitionParticles {
                        TransitionParticleView(isActive: transitionParticles, color: .purple, particleCount: 16)
                    }

                    switch phase {
                    case .messy:
                        messyFilesView
                    case .scanning:
                        scanningView
                    case .thinking:
                        thinkingView
                    case .comparing:
                        comparingView
                    case .organizing:
                        organizingView
                    case .complete:
                        completeAnimationView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if phase != .complete {
                    aiThoughtBubble
                        .frame(maxWidth: 460)
                }

                if phase == .complete {
                    Button {
                        onComplete()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(.onboardingPill)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        } // ZStack
        .onAppear {
            files = sampleFiles
            folders = sampleFolders
            fileRotations = (0..<sampleFiles.count).map { _ in Double.random(in: -15...15) }
            fileBobOffsets = (0..<sampleFiles.count).map { _ in CGFloat.random(in: -6...6) }
            fileBobDurations = (0..<sampleFiles.count).map { _ in Double.random(in: 1.5...2.5) }
            startAnimation()
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            scanHighlightTask?.cancel()
            scanHighlightTask = nil
            pendingWorkItems.forEach { $0.cancel() }
            pendingWorkItems.removeAll()
            audioManager.stopAll()
        }
    }
    
    private var phaseIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<6) { index in
                Circle()
                    .fill(phaseIndex >= index ? SortyDesignSystem.Colors.resolvedAccent : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phaseIndex == index ? 1.3 : 1.0)
                    .shadow(color: phaseIndex == index ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.4) : .clear, radius: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: phaseIndex)
            }
        }
    }
    
    private var phaseIndex: Int {
        switch phase {
        case .messy: return 0
        case .scanning: return 1
        case .thinking: return 2
        case .comparing: return 3
        case .organizing: return 4
        case .complete: return 5
        }
    }
    
    private var messyFilesView: some View {
        ZStack {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                fileIcon(for: file)
                    .offset(messyOffset(for: index))
                    .offset(y: fileBobbing && fileBobOffsets.indices.contains(index) ? fileBobOffsets[index] : 0)
                    .rotationEffect(.degrees(fileRotations.indices.contains(index) ? fileRotations[index] : 0))
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: fileBobDurations.indices.contains(index) ? fileBobDurations[index] : 2)
                                .repeatForever(autoreverses: true),
                        value: fileBobbing
                    )
            }
        }
        .transition(.opacity)
        .onAppear {
            fileBobbing = true
        }
    }
    
    private var scanningView: some View {
        ZStack {
            // Files with scanning effect
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                fileIcon(for: file)
                    .offset(messyOffset(for: index))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(SortyDesignSystem.Colors.resolvedAccent, lineWidth: 2)
                            .opacity(abs(scannedFileIndex - index) <= 1 ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: scannedFileIndex)
                    )
            }
            
            DemoScanningLine()
            
            // Privacy badge at bottom
            VStack {
                Spacer()
                PrivacyBadge(isVisible: showPrivacyBadge)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var thinkingView: some View {
        VStack(spacing: 20) {
            // Dimmed files in background
            ZStack {
                ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                    fileIcon(for: file)
                        .offset(messyOffset(for: index))
                        .opacity(0.3)
                        .scaleEffect(0.9)
                }
                
                BouncingSpinner(size: 50, color: .accentColor)
            }
            .frame(maxHeight: .infinity)
            
            // Persona card
            if showPersonaCard {
                DemoPersonaCard(
                    name: "Minimal",
                    description: "Clean, simple folder structure",
                    icon: "square.grid.2x2",
                    color: .accentColor,
                    isApplying: $personaApplying
                )
                .frame(width: 280)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
    }
    
    private var comparingView: some View {
        VStack(spacing: 16) {
            Text("Comparing Options")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                DemoOrganizationPlanCard(
                    title: "Plan A",
                    subtitle: "Group by type with minimal nesting",
                    folderCount: 4,
                    style: "Minimal",
                    isSelected: selectedPlanIndex == 0,
                    showCheckmark: selectedPlanIndex == 0 && showPlanCheckmark
                )
                .scaleEffect(selectedPlanIndex == 0 ? 1.02 : 0.98)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedPlanIndex)
                
                DemoOrganizationPlanCard(
                    title: "Plan B",
                    subtitle: "Organize by date and project",
                    folderCount: 7,
                    style: "Detailed",
                    isSelected: selectedPlanIndex == 1,
                    showCheckmark: false
                )
                .scaleEffect(selectedPlanIndex == 1 ? 1.02 : 0.98)
                .opacity(selectedPlanIndex == 0 && showPlanCheckmark ? 0.5 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedPlanIndex)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                Text("Sorty generates multiple options for you to choose")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .opacity(selectedPlanIndex < 0 ? 1 : 0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private var organizingView: some View {
        let unorganizedFiles = files.filter { !$0.isOrganized }
        let organizedCounts = Dictionary(
            grouping: files.lazy.filter(\.isOrganized),
            by: \.targetFolder
        ).mapValues(\.count)

        return HStack(spacing: 60) {
            VStack(spacing: 8) {
                ForEach(unorganizedFiles) { file in
                    fileIcon(for: file)
                        .background(
                            fileIcon(for: file)
                                .opacity(organizingTrailOpacities[file.id] == true ? 0.3 : 0)
                                .blur(radius: 4)
                                .offset(x: -8, y: -4)
                        )
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .offset(x: 60, y: -45).combined(with: .opacity).combined(with: .scale(scale: 0.6))
                        ))
                }
            }
            .frame(width: 180)
            
            VStack(spacing: 8) {
                // Animated sliver effect container
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(.title)
                        .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                        .symbolEffect(
                            .pulse.byLayer,
                            options: .repeating,
                            isActive: !reduceMotion
                        )
                    
                    // Sliver animation overlay
                    OrganizingSliverEffect()
                }
                
                // Small animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .offset(y: organizedCount % 3 == i ? -3 : 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5).delay(Double(i) * 0.1), value: organizedCount)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(folders) { folder in
                    if folder.isVisible {
                        folderRow(
                            for: folder,
                            organizedCount: organizedCounts[folder.name, default: 0]
                        )
                            .overlay(
                                FolderSliverEffect(isVisible: folder.isVisible)
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
            }
            .frame(width: 270)
        }
    }

    private var completeAnimationView: some View {
        VStack(spacing: 20) {
            ZStack {
                // Particle burst effect
                if particleEffect {
                    TransitionParticleView(isActive: particleEffect, color: .green, particleCount: 20)
                }
                
                // Confetti burst
                if confettiActive {
                    ConfettiBurstView(isActive: confettiActive)
                }
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: phase == .complete)
            }
            
            if showStats {
                HStack(spacing: 20) {
                    statBadge(value: "\(displayedFileCount)", label: "Files", icon: "doc.fill", color: .blue)
                    statBadge(value: "\(displayedFolderCount)", label: "Folders", icon: "folder.fill", color: .orange)
                    statBadge(value: "\(displayedPercent)%", label: "Organized", icon: "sparkles", color: .purple)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Undo safety badge - prominent feature highlight
            UndoSafetyBadge(isVisible: showUndoBadge)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
        }
    }
    
    private var aiThoughtBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: thoughtIcon)
                .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                .symbolReplaceTransition(animationValue: thoughtIcon)
            
            Text(currentThought)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
                .numericTextTransition(animationValue: currentThought)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.1))
                .stroke(SortyDesignSystem.Colors.resolvedAccent.opacity(0.2), lineWidth: 1)
        )
        .opacity(thoughtOpacity)
    }
    
    private var thoughtIcon: String {
        if currentThought.contains("never leave") || currentThought.contains("device") {
            return "lock.shield.fill"
        } else if currentThought.contains("persona") || currentThought.contains("Minimal") {
            return "person.fill"
        } else if currentThought.contains("undo") {
            return "arrow.uturn.backward"
        } else if currentThought.contains("Comparing") || currentThought.contains("Option") {
            return "square.2.layers.3d"
        } else {
            return "brain.head.profile"
        }
    }
    
    private func fileIcon(for file: DemoFileNode) -> some View {
        VStack(spacing: 4) {
            Image(systemName: file.icon)
                .font(.system(size: 28))
                .foregroundStyle(file.color)
                .shadow(color: file.color.opacity(0.3), radius: 3, y: 1)
            
            Text(file.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
        }
        .frame(width: 84, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .shadow(color: file.color.opacity(0.1), radius: 6, y: 2)
        )
    }
    
    private func folderRow(
        for folder: DemoFolderNode,
        organizedCount: Int
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: folder.icon)
                .foregroundStyle(folder.color)
            
            Text(folder.name)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            
            Spacer()
            
            if organizedCount > 0 {
                Text("\(organizedCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .numericTextTransition(animationValue: organizedCount)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(folder.color))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(folder.color.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func statBadge(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.bold())
                .monospacedDigit()
                .numericTextTransition(animationValue: value)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private func messyOffset(for index: Int) -> CGSize {
        let positions: [CGSize] = [
            CGSize(width: -120, height: -90),
            CGSize(width: 90, height: -120),
            CGSize(width: -60, height: 30),
            CGSize(width: 135, height: -30),
            CGSize(width: -150, height: 90),
            CGSize(width: 30, height: 120),
            CGSize(width: 105, height: 75),
            CGSize(width: -90, height: -150),
            CGSize(width: 150, height: 135),
            CGSize(width: -30, height: -60)
        ]
        return positions[index % positions.count]
    }
    
    private func startAnimation() {
        animationTask = Task { @MainActor in
            // Phase 1: Messy (let the user absorb the initial state)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }

            // Phase 2: Scanning with privacy callout
            withAnimation(.easeOut(duration: 0.5)) {
                transitionParticles = true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                phase = .scanning
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            transitionParticles = false
            audioManager.playPhaseSound(.scanning)
            audioManager.startAmbientPulse(interval: 0.8)
            showThought(aiThoughts[0]) // "Scanning file types..."

            startScanHighlights()

            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            // Show privacy badge during scan
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                showPrivacyBadge = true
            }
            showThought(aiThoughts[1]) // "Files never leave your device"

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            showThought(aiThoughts[2]) // "Found 4 image files"

            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            // Transition particles
            withAnimation(.easeOut(duration: 0.5)) {
                transitionParticles = true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            transitionParticles = false

            // Phase 3: Thinking with persona showcase
            withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                phase = .thinking
                showPrivacyBadge = false
            }
            audioManager.stopAmbientPulse()
            audioManager.playPhaseSound(.thinking)
            showThought(aiThoughts[3]) // "Detected document patterns"

            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            // Show persona card
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                showPersonaCard = true
            }
            showThought(aiThoughts[4]) // "Using 'Minimal' persona style..."

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }

            // Persona applied
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                personaApplying = false
            }
            showThought(aiThoughts[5]) // "Organizing with minimal folders"

            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            // Phase 4: Comparing options
            withAnimation(.easeOut(duration: 0.5)) {
                transitionParticles = true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                phase = .comparing
                showPersonaCard = false
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            transitionParticles = false
            audioManager.playPhaseSound(.comparing)
            showThought(aiThoughts[6]) // "Comparing organization options..."

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }

            // Highlight each plan briefly
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                selectedPlanIndex = 1
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                selectedPlanIndex = 0
            }
            showThought(aiThoughts[7]) // "Option A uses fewer folders"

            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            // Show checkmark on selected plan
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                showPlanCheckmark = true
            }
            HapticFeedbackManager.shared.selection()

            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }

            // Phase 5: Organizing
            withAnimation(.easeOut(duration: 0.5)) {
                transitionParticles = true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.9)) {
                phase = .organizing
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            transitionParticles = false
            audioManager.playPhaseSound(.organizing)
            audioManager.startAmbientPulse(interval: 0.5)
            showThought(aiThoughts[8]) // "Moving files to categories"

            // Show folders appearing
            for i in 0..<folders.count {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    folders[i].isVisible = true
                }
            }

            // Animate files moving with trail effect
            for i in 0..<files.count {
                try? await Task.sleep(nanoseconds: 260_000_000)
                guard !Task.isCancelled else { return }
                let fileId = files[i].id
                withAnimation(.easeInOut(duration: 0.2)) {
                    organizingTrailOpacities[fileId] = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    files[i].isOrganized = true
                    organizedCount += 1
                }
                HapticFeedbackManager.shared.selection()
                scheduleWorkItem(delay: 0.4) {
                    organizingTrailOpacities[fileId] = false
                }
            }

            showThought(aiThoughts[9]) // "Creating undo checkpoint..."
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }

            // Phase 6: Complete with undo highlight
            withAnimation(.easeOut(duration: 0.5)) {
                transitionParticles = true
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                phase = .complete
                thoughtOpacity = 0
            }
            audioManager.stopAmbientPulse()
            audioManager.playCompletionFanfare()
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            transitionParticles = false

            withAnimation(.easeOut(duration: 0.8)) {
                particleEffect = true
                confettiActive = true
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                showStats = true
            }

            startCountingAnimation()

            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            // Show undo safety badge
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                showUndoBadge = true
            }
            HapticFeedbackManager.shared.success()
        }
    }

    private func startScanHighlights() {
        scanHighlightTask?.cancel()
        scannedFileIndex = -1
        scanHighlightTask = Task { @MainActor in
            for index in files.indices {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                scannedFileIndex = index
            }
        }
    }
    
    private func showThought(_ thought: String) {
        withAnimation(.easeInOut(duration: 0.4)) {
            thoughtOpacity = 0.3
        }

        scheduleWorkItem(delay: 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                currentThought = thought
                thoughtOpacity = 1
            }
        }
    }

    private func startCountingAnimation() {
        let totalFiles = 10
        let totalFolders = 4
        let totalPercent = 100
        let steps = 10
        let interval = 0.09

        for step in 1...steps {
            scheduleWorkItem(delay: interval * Double(step)) {
                withAnimation(.easeOut(duration: 0.05)) {
                    displayedFileCount = min(totalFiles, totalFiles * step / steps)
                    displayedFolderCount = min(totalFolders, totalFolders * step / steps)
                    displayedPercent = min(totalPercent, totalPercent * step / steps)
                }
            }
        }
    }

    /// Schedule a cancellable work item on the main queue
    private func scheduleWorkItem(delay: TimeInterval, action: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: action)
        pendingWorkItems.append(workItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

/// Owns the scan line's per-frame animation so it does not invalidate the
/// forty-state simulated-demo root for the full 2.5-second sweep.
private struct DemoScanningLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.accentColor.opacity(0), .accentColor.opacity(0.12), .accentColor.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 240, height: 480)
                .blur(radius: 8)
                .offset(x: -320 + progress * 600)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.accentColor.opacity(0), .accentColor.opacity(0.45), .accentColor.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 150, height: 480)
                .offset(x: -300 + progress * 600)
        }
        .onAppear {
            if reduceMotion {
                progress = 0.5
            } else {
                withAnimation(.easeInOut(duration: 2.5)) {
                    progress = 1
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Demo Models

struct DemoFileNode: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    let targetFolder: String
    var isOrganized: Bool = false
}

struct DemoFolderNode: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let color: Color
    var isVisible: Bool = false
    var files: [DemoFileNode] = []
}

// MARK: - Demo Organization Plan Card
struct DemoOrganizationPlanCard: View {
    let title: String
    let subtitle: String
    let folderCount: Int
    let style: String
    let isSelected: Bool
    let showCheckmark: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizedStringKey(title))
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showCheckmark)
                }
            }
            
            Text(LocalizedStringKey(subtitle))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
            
            HStack(spacing: 12) {
                Label("\(folderCount)", systemImage: "folder.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Text(style)
                    .font(.caption2.bold())
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.15))
                    )
            }
        }
        .padding(12)
        .frame(width: 172)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                .shadow(color: isSelected ? Color.purple.opacity(0.3) : Color.black.opacity(0.1), radius: isSelected ? 8 : 4, y: 2)
        )
    }
}

// MARK: - Demo Persona Card
struct DemoPersonaCard: View {
    let name: String
    let description: String
    let icon: String
    let color: Color
    @Binding var isApplying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .symbolEffect(
                        .pulse.byLayer,
                        options: .repeating,
                        isActive: isApplying && !reduceMotion
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.bold())
                    
                    Text("Persona")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(color))
                }
                
                Text(LocalizedStringKey(description))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if isApplying {
                SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Privacy Badge
struct PrivacyBadge: View {
    let isVisible: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
            Text("Local Processing")
                .font(.caption.bold())
        }
        .foregroundStyle(.green)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.15))
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
    }
}

// MARK: - Undo Safety Badge
struct UndoSafetyBadge: View {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 24))
                    .symbolEffect(
                        .pulse.byLayer,
                        options: .repeating,
                        isActive: isVisible && !reduceMotion
                    )
                
                Text("Undo Available")
                    .font(.headline.bold())
            }
            .foregroundStyle(.orange)
            
            Text("All changes can be reversed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
    }
}

// MARK: - Transition Particle Effect
struct TransitionParticleView: View {
    let isActive: Bool
    let color: Color
    let particleCount: Int
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                Circle()
                    .fill(color.opacity(0.6))
                    .frame(width: particleSize(for: index), height: particleSize(for: index))
                    .offset(particleOffset(for: index))
                    .opacity(isActive ? 0 : 0.8)
                    .blur(radius: isActive ? 2 : 0)
            }
        }
        .animation(.easeOut(duration: 0.8), value: isActive)
    }
    
    private func particleOffset(for index: Int) -> CGSize {
        let angle = Double(index) * (360.0 / Double(particleCount))
            + seededDemoValue(index: index, salt: 1, range: -10...10)
        let radius = isActive
            ? CGFloat(seededDemoValue(index: index, salt: 2, range: 60...100))
            : 0
        return CGSize(
            width: cos(angle * .pi / 180) * radius,
            height: sin(angle * .pi / 180) * radius
        )
    }

    private func particleSize(for index: Int) -> CGFloat {
        CGFloat(seededDemoValue(index: index, salt: 3, range: 4...8))
    }
}

// MARK: - Confetti Burst Effect
struct ConfettiBurstView: View {
    let isActive: Bool
    
    private let confettiColors: [Color] = [.green, .blue, .purple, .orange, .pink, .yellow, .red, .mint]
    private let particleCount = 24
    
    var body: some View {
        ZStack {
            ForEach(0..<particleCount, id: \.self) { index in
                Circle()
                    .fill(confettiColors[index % confettiColors.count].opacity(0.8))
                    .frame(width: particleSize(for: index), height: particleSize(for: index))
                    .offset(confettiOffset(for: index))
                    .opacity(isActive ? 0 : 1)
                    .scaleEffect(isActive ? 0.3 : 1)
            }
        }
        .animation(.easeOut(duration: 1.2), value: isActive)
    }
    
    private func confettiOffset(for index: Int) -> CGSize {
        let angle = Double(index) * (360.0 / Double(particleCount))
            + seededDemoValue(index: index, salt: 4, range: -20...20)
        let radius = isActive
            ? CGFloat(seededDemoValue(index: index, salt: 5, range: 80...160))
            : 0
        return CGSize(
            width: cos(angle * .pi / 180) * radius,
            height: sin(angle * .pi / 180) * radius
        )
    }

    private func particleSize(for index: Int) -> CGFloat {
        CGFloat(seededDemoValue(index: index, salt: 6, range: 4...10))
    }
}

private func seededDemoValue(index: Int, salt: Int, range: ClosedRange<Double>) -> Double {
    var value = UInt64(truncatingIfNeeded: index &* 1_103_515_245 &+ salt &* 12_345)
    value ^= value >> 16
    value &*= 0x7feb_352d
    value ^= value >> 15
    let unit = Double(value % 10_000) / 9_999
    return range.lowerBound + (range.upperBound - range.lowerBound) * unit
}

// MARK: - Organizing Sliver Effect
struct OrganizingSliverEffect: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        RetainedOrganizingSliver(
            shouldAnimate: !reduceMotion && controlActiveState != .inactive
        )
        .frame(width: 50, height: 30)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct OrganizingSliverGraphic: View {
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.4),
                        .purple.opacity(0.3),
                        .white.opacity(0.4),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 20, height: 30)
            .blur(radius: 2)
            .accessibilityHidden(true)
    }
}

private struct RetainedOrganizingSliver: NSViewRepresentable {
    let shouldAnimate: Bool

    func makeNSView(context: Context) -> RetainedOrganizingSliverView {
        RetainedOrganizingSliverView()
    }

    func updateNSView(_ nsView: RetainedOrganizingSliverView, context: Context) {
        nsView.setAnimating(shouldAnimate)
    }
}

@MainActor
private final class RetainedOrganizingSliverView: NSView {
    private let host = NSHostingView(rootView: OrganizingSliverGraphic())
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        host.wantsLayer = true
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        host.frame = CGRect(x: 0, y: 0, width: 20, height: bounds.height)
    }

    func setAnimating(_ shouldAnimate: Bool) {
        guard isAnimating != shouldAnimate else { return }
        isAnimating = shouldAnimate
        host.layer?.removeAnimation(forKey: "organizingSliverTravel")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.layer?.opacity = shouldAnimate ? 1 : 0
        host.layer?.setAffineTransform(.identity)
        CATransaction.commit()

        guard shouldAnimate else { return }
        let travel = CABasicAnimation(keyPath: "transform.translation.x")
        travel.fromValue = -30
        travel.toValue = 80
        travel.duration = 1.2
        travel.repeatCount = .infinity
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        host.layer?.add(travel, forKey: "organizingSliverTravel")
    }
}

// MARK: - Folder Sliver Effect
struct FolderSliverEffect: View {
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sliverPhase: CGFloat = 0
    @State private var hasAnimated = false

    private let sliverDuration: TimeInterval = 0.6
    
    var body: some View {
        GeometryReader { geometry in
            if !hasAnimated {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.5),
                                .purple.opacity(0.2),
                                .white.opacity(0.5),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 30)
                    .offset(x: -40 + sliverPhase * (geometry.size.width + 80))
                    .blur(radius: 1)
            }
        }
        .clipped()
        .onAppear {
            guard isVisible else { return }
            guard !reduceMotion else {
                hasAnimated = true
                return
            }
            HapticSequenceManager.shared.playShimmerWave(
                duration: sliverDuration,
                minimumInterval: sliverDuration
            )
            withAnimation(.easeInOut(duration: sliverDuration)) {
                sliverPhase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + sliverDuration + 0.1) {
                hasAnimated = true
            }
        }
    }
}

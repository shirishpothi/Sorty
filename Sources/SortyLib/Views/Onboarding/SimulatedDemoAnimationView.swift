//
//  SimulatedDemoAnimationView.swift
//  Sorty
//
//  Animated demo simulation for the onboarding demo step
//

import SwiftUI

struct SimulatedDemoAnimationView: View {
    let onComplete: () -> Void
    
    @State private var phase: DemoPhase = .messy
    @State private var scanProgress: CGFloat = 0
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
    @State private var fileBobbing: Bool = false
    @State private var confettiActive: Bool = false
    @State private var displayedFileCount: Int = 0
    @State private var displayedFolderCount: Int = 0
    @State private var displayedPercent: Int = 0
    @State private var organizingTrailOpacities: [UUID: Bool] = [:]
    @State private var animationTask: Task<Void, Never>?
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
        "Files never leave your device",
        "Found 4 image files",
        "Detected document patterns",
        "Using 'Minimal' persona style...",
        "Organizing with minimal folders",
        "Comparing organization options...",
        "Option A uses fewer folders",
        "Moving files to categories",
        "Creating undo checkpoint..."
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
        } // ZStack
        .onAppear {
            files = sampleFiles
            folders = sampleFolders
            fileRotations = (0..<sampleFiles.count).map { _ in Double.random(in: -15...15) }
            startAnimation()
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
            pendingWorkItems.forEach { $0.cancel() }
            pendingWorkItems.removeAll()
            audioManager.stopAll()
        }
    }
    
    private var phaseIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<6) { index in
                Circle()
                    .fill(phaseIndex >= index ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phaseIndex == index ? 1.3 : 1.0)
                    .shadow(color: phaseIndex == index ? Color.accentColor.opacity(0.4) : .clear, radius: 4)
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
                    .offset(y: fileBobbing ? CGFloat.random(in: -6...6) : 0)
                    .rotationEffect(.degrees(fileRotations.indices.contains(index) ? fileRotations[index] : 0))
                    .animation(
                        .easeInOut(duration: Double.random(in: 1.5...2.5))
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
                            .stroke(Color.accentColor, lineWidth: 2)
                            .opacity(scanLinePosition(for: index) ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: scanLinePosition(for: index))
                    )
            }
            
            // Scanning line with glow trail
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
                    .offset(x: -300 + scanProgress * 600 - 20)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.accentColor.opacity(0), .accentColor.opacity(0.45), .accentColor.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 150, height: 480)
                    .offset(x: -300 + scanProgress * 600)
            }
            
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
                Text("AI generates multiple options for you to choose")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .opacity(selectedPlanIndex < 0 ? 1 : 0)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private var organizingView: some View {
        HStack(spacing: 60) {
            VStack(spacing: 8) {
                ForEach(files.filter { !$0.isOrganized }) { file in
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
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.pulse.byLayer, options: .repeating)
                    
                    // Sliver animation overlay
                    OrganizingSliverEffect()
                }
                
                // Small animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .offset(y: organizedCount % 3 == i ? -3 : 0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5).delay(Double(i) * 0.1), value: organizedCount)
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(folders) { folder in
                    if folder.isVisible {
                        folderRow(for: folder)
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
                .foregroundStyle(Color.accentColor)
                .contentTransition(.interpolate)
            
            Text(currentThought)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.1))
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
        .opacity(thoughtOpacity)
        .animation(.easeInOut(duration: 0.3), value: currentThought)
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
        }
        .frame(width: 76, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .shadow(color: file.color.opacity(0.1), radius: 6, y: 2)
        )
    }
    
    private func folderRow(for folder: DemoFolderNode) -> some View {
        HStack(spacing: 8) {
            Image(systemName: folder.icon)
                .foregroundStyle(folder.color)
            
            Text(folder.name)
                .font(.subheadline.bold())
            
            Spacer()
            
            let count = files.filter { $0.targetFolder == folder.name && $0.isOrganized }.count
            if count > 0 {
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
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
    
    private func scanLinePosition(for index: Int) -> Bool {
        let normalizedProgress = scanProgress
        let fileProgress = CGFloat(index) / CGFloat(files.count)
        return abs(normalizedProgress - fileProgress) < 0.15
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

            withAnimation(.easeInOut(duration: 2.5)) {
                scanProgress = 1.0
            }

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

// MARK: - Demo Floating Particle

private struct DemoFloatingParticle: View {
    let index: Int
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0

    private var particleSize: CGFloat {
        CGFloat.random(in: 2...5)
    }

    var body: some View {
        Circle()
            .fill(Color.white.opacity(opacity))
            .frame(width: particleSize, height: particleSize)
            .offset(offset)
            .onAppear {
                let randomX = CGFloat.random(in: -300...300)
                let randomY = CGFloat.random(in: -300...300)
                offset = CGSize(width: randomX, height: randomY)

                withAnimation(
                    .easeInOut(duration: Double.random(in: 3...6))
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.2)
                ) {
                    offset = CGSize(
                        width: randomX + CGFloat.random(in: -120...120),
                        height: randomY + CGFloat.random(in: -120...120)
                    )
                    opacity = Double.random(in: 0.1...0.3)
                }
            }
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
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                if showCheckmark {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: showCheckmark)
                }
            }
            
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            
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
        .frame(width: 160)
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
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: isApplying)
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
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isApplying {
                ProgressView()
                    .scaleEffect(0.7)
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
    @State private var isPulsing = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 24))
                    .symbolEffect(.pulse.byLayer, options: .repeating, value: isPulsing)
                
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
        .onAppear {
            if isVisible {
                isPulsing = true
            }
        }
        .onChange(of: isVisible) { _, newValue in
            isPulsing = newValue
        }
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
                    .frame(width: CGFloat.random(in: 4...8), height: CGFloat.random(in: 4...8))
                    .offset(particleOffset(for: index))
                    .opacity(isActive ? 0 : 0.8)
                    .blur(radius: isActive ? 2 : 0)
            }
        }
        .animation(.easeOut(duration: 0.8), value: isActive)
    }
    
    private func particleOffset(for index: Int) -> CGSize {
        let angle = Double(index) * (360.0 / Double(particleCount)) + Double.random(in: -10...10)
        let radius: CGFloat = isActive ? CGFloat.random(in: 60...100) : 0
        return CGSize(
            width: cos(angle * .pi / 180) * radius,
            height: sin(angle * .pi / 180) * radius
        )
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
                    .frame(width: CGFloat.random(in: 4...10), height: CGFloat.random(in: 4...10))
                    .offset(confettiOffset(for: index))
                    .opacity(isActive ? 0 : 1)
                    .scaleEffect(isActive ? 0.3 : 1)
            }
        }
        .animation(.easeOut(duration: 1.2), value: isActive)
    }
    
    private func confettiOffset(for index: Int) -> CGSize {
        let angle = Double(index) * (360.0 / Double(particleCount)) + Double.random(in: -20...20)
        let radius: CGFloat = isActive ? CGFloat.random(in: 80...160) : 0
        return CGSize(
            width: cos(angle * .pi / 180) * radius,
            height: sin(angle * .pi / 180) * radius
        )
    }
}

// MARK: - Organizing Sliver Effect
struct OrganizingSliverEffect: View {
    @State private var sliverPhase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
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
                .frame(width: 20)
                .offset(x: -30 + sliverPhase * (geometry.size.width + 60))
                .blur(radius: 2)
        }
        .frame(width: 50, height: 30)
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                sliverPhase = 1
            }
        }
    }
}

// MARK: - Folder Sliver Effect
struct FolderSliverEffect: View {
    let isVisible: Bool
    @State private var sliverPhase: CGFloat = 0
    @State private var hasAnimated = false
    
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
            withAnimation(.easeInOut(duration: 0.6)) {
                sliverPhase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                hasAnimated = true
            }
        }
    }
}

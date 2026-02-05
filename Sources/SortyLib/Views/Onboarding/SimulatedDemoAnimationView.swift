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
            .frame(height: 320)
            
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
        .onAppear {
            files = sampleFiles
            folders = sampleFolders
            fileRotations = (0..<sampleFiles.count).map { _ in Double.random(in: -15...15) }
            startAnimation()
        }
    }
    
    private var phaseIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<6) { index in
                Circle()
                    .fill(phaseIndex >= index ? Color.purple : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phaseIndex == index ? 1.2 : 1.0)
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
                    .rotationEffect(.degrees(fileRotations.indices.contains(index) ? fileRotations[index] : 0))
            }
        }
        .transition(.opacity)
    }
    
    private var scanningView: some View {
        ZStack {
            // Files with scanning effect
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                fileIcon(for: file)
                    .offset(messyOffset(for: index))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple, lineWidth: 2)
                            .opacity(scanLinePosition(for: index) ? 1 : 0)
                            .animation(.easeInOut(duration: 0.2), value: scanLinePosition(for: index))
                    )
            }
            
            // Scanning line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0), .purple.opacity(0.5), .purple.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 100, height: 320)
                .offset(x: -200 + scanProgress * 400)
            
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
                
                BouncingSpinner(size: 50, color: .purple)
            }
            .frame(height: 200)
            
            // Persona card
            if showPersonaCard {
                DemoPersonaCard(
                    name: "Minimal",
                    description: "Clean, simple folder structure",
                    icon: "square.grid.2x2",
                    color: .purple,
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
        HStack(spacing: 40) {
            VStack(spacing: 8) {
                ForEach(files.filter { !$0.isOrganized }) { file in
                    fileIcon(for: file)
                        .transition(.asymmetric(
                            insertion: .identity,
                            removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.8))
                        ))
                }
            }
            .frame(width: 120)
            
            VStack(spacing: 8) {
                // Animated sliver effect container
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(.title)
                        .foregroundStyle(.purple)
                        .symbolEffect(.pulse.byLayer, options: .repeating)
                    
                    // Sliver animation overlay
                    OrganizingSliverEffect()
                }
                
                // Small animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.purple.opacity(0.5))
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
            .frame(width: 180)
        }
    }
    
    private var completeAnimationView: some View {
        VStack(spacing: 20) {
            ZStack {
                // Particle burst effect
                if particleEffect {
                    TransitionParticleView(isActive: particleEffect, color: .green, particleCount: 20)
                }
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: phase == .complete)
            }
            
            if showStats {
                HStack(spacing: 20) {
                    statBadge(value: "10", label: "Files", icon: "doc.fill", color: .blue)
                    statBadge(value: "4", label: "Folders", icon: "folder.fill", color: .orange)
                    statBadge(value: "100%", label: "Organized", icon: "sparkles", color: .purple)
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
                .foregroundStyle(.purple)
            
            Text(currentThought)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.1))
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
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
                .font(.system(size: 24))
                .foregroundStyle(file.color)
            
            Text(file.name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 70, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
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
            CGSize(width: -80, height: -60),
            CGSize(width: 60, height: -80),
            CGSize(width: -40, height: 20),
            CGSize(width: 90, height: -20),
            CGSize(width: -100, height: 60),
            CGSize(width: 20, height: 80),
            CGSize(width: 70, height: 50),
            CGSize(width: -60, height: -100),
            CGSize(width: 100, height: 90),
            CGSize(width: -20, height: -40)
        ]
        return positions[index % positions.count]
    }
    
    private func scanLinePosition(for index: Int) -> Bool {
        let normalizedProgress = scanProgress
        let fileProgress = CGFloat(index) / CGFloat(files.count)
        return abs(normalizedProgress - fileProgress) < 0.15
    }
    
    private func startAnimation() {
        Task { @MainActor in
            // Phase 1: Messy (brief pause to show initial state)
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Phase 2: Scanning with privacy callout
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .scanning
            }
            showThought(aiThoughts[0]) // "Scanning file types..."
            
            withAnimation(.linear(duration: 1.5)) {
                scanProgress = 1.0
            }
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Show privacy badge during scan
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPrivacyBadge = true
            }
            showThought(aiThoughts[1]) // "Files never leave your device"
            
            try? await Task.sleep(nanoseconds: 800_000_000)
            showThought(aiThoughts[2]) // "Found 4 image files"
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Transition particles
            withAnimation(.easeOut(duration: 0.3)) {
                transitionParticles = true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            transitionParticles = false
            
            // Phase 3: Thinking with persona showcase
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .thinking
                showPrivacyBadge = false
            }
            showThought(aiThoughts[3]) // "Detected document patterns"
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Show persona card
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showPersonaCard = true
            }
            showThought(aiThoughts[4]) // "Using 'Minimal' persona style..."
            
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            // Persona applied
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                personaApplying = false
            }
            showThought(aiThoughts[5]) // "Organizing with minimal folders"
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Phase 4: Comparing options (NEW)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .comparing
                showPersonaCard = false
            }
            showThought(aiThoughts[6]) // "Comparing organization options..."
            
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            // Highlight each plan briefly
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedPlanIndex = 1
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedPlanIndex = 0
            }
            showThought(aiThoughts[7]) // "Option A uses fewer folders"
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Show checkmark on selected plan
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPlanCheckmark = true
            }
            HapticFeedbackManager.shared.selection()
            
            try? await Task.sleep(nanoseconds: 600_000_000)
            
            // Phase 5: Organizing
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                phase = .organizing
            }
            showThought(aiThoughts[8]) // "Moving files to categories"
            
            // Show folders appearing
            for i in 0..<folders.count {
                try? await Task.sleep(nanoseconds: 250_000_000)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    folders[i].isVisible = true
                }
            }
            
            // Animate files moving
            for i in 0..<files.count {
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    files[i].isOrganized = true
                    organizedCount += 1
                }
                HapticFeedbackManager.shared.selection()
            }
            
            showThought(aiThoughts[9]) // "Creating undo checkpoint..."
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Phase 6: Complete with undo highlight
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                phase = .complete
                thoughtOpacity = 0
            }
            
            withAnimation(.easeOut(duration: 0.6)) {
                particleEffect = true
            }
            
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showStats = true
            }
            
            try? await Task.sleep(nanoseconds: 400_000_000)
            
            // Show undo safety badge prominently
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showUndoBadge = true
            }
            HapticFeedbackManager.shared.success()
        }
    }
    
    private func showThought(_ thought: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            thoughtOpacity = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            currentThought = thought
            withAnimation(.easeIn(duration: 0.2)) {
                thoughtOpacity = 1
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

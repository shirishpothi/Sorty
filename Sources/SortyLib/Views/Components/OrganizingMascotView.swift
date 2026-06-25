//
//  OrganizingMascotView.swift
//  Sorty
//

import SwiftUI
import UniformTypeIdentifiers

struct OrganizingMascotView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SortyPetAssetProvider.animatedMascotEnabledKey) private var animatedMascotEnabled = true
    @State private var isAnimating = false
    @State private var orbitingURLs: [URL] = []
    @State private var cachedOrbitingURLs: [URL] = []
    @State private var isHovered = false
    
    enum MascotEmotion {
        case idle
        case happy
        case working
        case excited
    }
    
    @State private var currentEmotion: MascotEmotion = .idle
    
    @State private var eyeBlinkPhase: Double = 0
    @State private var headTilt: Double = 0
    @State private var antennaWiggle: Double = 0
    @State private var lookAroundOffset: CGSize = .zero
    @State private var breathScale: CGFloat = 1.0
    @State private var bounceOffset: CGFloat = 0
    @State private var excitementScale: CGFloat = 1.0
    @State private var eyeSquint: CGFloat = 1.0
    @State private var antennaGlow: Double = 0.3
    
    @State private var orbitGlowIntensity: Double = 0.5
    @State private var sparklePhase: Double = 0
    
    @State private var lastBlinkTime: TimeInterval = 0
    @State private var lastLookAroundTime: TimeInterval = 0
    @State private var lastEmotionTime: TimeInterval = 0
    @State private var lastOrbitSampleTime: TimeInterval = 0
    @State private var timelineStarted = false
    
    private let orbitSize: CGFloat = 72
    private let iconSize: CGFloat = 12
    
    private var isOrganizing: Bool {
        switch organizer.state {
        case .scanning, .organizing, .applying:
            return true
        default:
            return false
        }
    }
    
    private var maxOrbitItems: Int {
        isOrganizing ? 3 : 2
    }
    
    private var frameInterval: TimeInterval {
        isOrganizing ? 1.0 / 6.0 : 1.0 / 10.0
    }

    private var shouldUseAnimatedPet: Bool {
        animatedMascotEnabled &&
            !reduceMotion &&
            SortyPetAssetProvider.shared.manifest != nil &&
            SortyPetAssetProvider.shared.spriteSheet != nil
    }

    private var petState: SortyPetAnimationState {
        switch organizer.state {
        case .idle:
            return organizer.scannedFiles.isEmpty ? .idle : .ready
        case .scanning:
            return .scanning
        case .organizing:
            return organizer.organizationStage.localizedCaseInsensitiveContains("rename") ? .renaming : .organizing
        case .ready:
            return .reviewing
        case .applying:
            return .applying
        case .completed:
            return .completed
        case .error:
            return .failed
        }
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: frameInterval)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            
            ZStack {
                ambientGlow(time: time)
                
                orbitRingPath
                
                mascotShadow
                
                ForEach(Array(orbitingURLs.prefix(maxOrbitItems).enumerated()), id: \.offset) { index, url in
                    orbitingIcon(url: url, index: index, time: time)
                }
                
                if isOrganizing || isHovered {
                    sparkleParticles(time: time)
                }
                
                mascotView(time: time)
            }
            .frame(width: orbitSize, height: orbitSize)
            .drawingGroup(opaque: false)
            .clipShape(Circle())
            .contentShape(Circle())
            .onChange(of: time) { _, newTime in
                handleTimelineTick(time: newTime)
            }
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
                if hovering {
                    currentEmotion = .happy
                    triggerHappyEyes()
                } else if !isOrganizing {
                    currentEmotion = .idle
                    resetEyes()
                }
            }
        }
        .onAppear {
            rebuildCachedURLs()
            orbitingURLs = cachedOrbitingURLs
            startAnimations()
        }
        .onChange(of: organizer.scannedFiles) { _, _ in
            rebuildCachedURLs()
            orbitingURLs = cachedOrbitingURLs
        }
        .onChange(of: organizer.currentPlan?.suggestions.count) { _, _ in
            rebuildCachedURLs()
            orbitingURLs = cachedOrbitingURLs
        }
        .onChange(of: isOrganizing) { _, newValue in
            if newValue {
                currentEmotion = .working
                triggerExcitement()
            } else {
                currentEmotion = .idle
            }
        }
    }
    
    // MARK: - Timeline-driven periodic actions
    
    private func handleTimelineTick(time: TimeInterval) {
        if !timelineStarted {
            timelineStarted = true
            lastBlinkTime = time + 1.0
            lastLookAroundTime = time
            lastEmotionTime = time
            lastOrbitSampleTime = time
            return
        }
        
        if time - lastBlinkTime >= 3.5 {
            lastBlinkTime = time
            triggerBlink()
        }
        
        if time - lastLookAroundTime >= 4.0 {
            lastLookAroundTime = time
            triggerLookAround()
        }
        
        if time - lastEmotionTime >= 2.0 {
            lastEmotionTime = time
            updateEmotion()
        }
        
        if time - lastOrbitSampleTime >= 2.6 {
            lastOrbitSampleTime = time
            orbitingURLs = cachedOrbitingURLs
        }
    }
    
    // MARK: - Ambient Glow
    
    @ViewBuilder
    private func ambientGlow(time: TimeInterval) -> some View {
        let pulseIntensity = 0.15 + sin(time * 2) * 0.05
        
        if isOrganizing || isHovered {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(pulseIntensity),
                            Color.blue.opacity(pulseIntensity * 0.5),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 30
                    )
                )
                .frame(width: 50, height: 50)
                .blur(radius: 4)
        }
    }
    
    // MARK: - Orbit Ring Path
    
    private var orbitRingPath: some View {
        ZStack {
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.2),
                            Color.blue.opacity(0.15),
                            Color.cyan.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 38, height: 22)
                .blur(radius: 0.5)
            
            if isOrganizing {
                Ellipse()
                    .stroke(
                        Color.cyan.opacity(orbitGlowIntensity * 0.5),
                        lineWidth: 2.5
                    )
                    .frame(width: 38, height: 22)
                    .blur(radius: 2)
            }
        }
    }
    
    // MARK: - Mascot Shadow
    
    private var mascotShadow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color.black.opacity(0.25),
                        Color.black.opacity(0.08),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 14
                )
            )
            .frame(width: 22, height: 7)
            .offset(y: 15 + bounceOffset * 0.4)
            .scaleEffect(x: 1.0 - bounceOffset * 0.02)
    }
    
    // MARK: - Sparkle Particles
    
    @ViewBuilder
    private func sparkleParticles(time: TimeInterval) -> some View {
        ForEach(0..<4, id: \.self) { index in
            let angle = time * 1.8 + Double(index) * (.pi * 2 / 4)
            let radius: CGFloat = 20 + CGFloat(sin(time * 2.5 + Double(index))) * 5
            let x = cos(angle) * radius
            let y = sin(angle * 0.7) * radius * 0.5
            let sparkleSize: CGFloat = CGFloat(2.5 + sin(time * 3.5 + Double(index) * 0.7) * 1.5)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white,
                            Color.cyan.opacity(0.9),
                            Color.blue.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: sparkleSize
                    )
                )
                .frame(width: sparkleSize * 2, height: sparkleSize * 2)
                .offset(x: x, y: y)
                .opacity(0.7 + sin(time * 4.5 + Double(index)) * 0.3)
        }
    }
    
    // MARK: - Mascot View with Life-like Animations
    
    @ViewBuilder
    private func mascotView(time: TimeInterval) -> some View {
        ZStack {
            if isOrganizing || isHovered {
                antennaGlowEffect(time: time)
            }
            
            if isOrganizing {
                mascotImage
                    .blur(radius: 8)
                    .opacity(0.6)
                    .scaleEffect(1.25 * excitementScale)
            }
            
            mascotImage
            
            if !shouldUseAnimatedPet {
                metallicSheen(time: time)

                eyeOverlay

                ledIndicators(time: time)
            }
        }
        .scaleEffect(breathScale * excitementScale * (isHovered ? 1.1 : 1.0))
        .offset(
            x: lookAroundOffset.width + (isHovered ? 0 : sin(time * 0.8) * 0.6),
            y: bounceOffset + lookAroundOffset.height
        )
        .rotationEffect(.degrees(headTilt + (isHovered ? -6 : 0)))
        .rotation3DEffect(
            .degrees(antennaWiggle),
            axis: (x: 0, y: 1, z: 0.2)
        )
    }
    
    // MARK: - Metallic Sheen
    
    @ViewBuilder
    private func metallicSheen(time: TimeInterval) -> some View {
        let sweepPosition = (sin(time * 0.6) + 1) / 2
        
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: max(0, sweepPosition - 0.25)),
                        .init(color: Color.white.opacity(0.15), location: sweepPosition),
                        .init(color: Color(white: 0.85).opacity(0.1), location: min(1, sweepPosition + 0.08)),
                        .init(color: Color.clear, location: min(1, sweepPosition + 0.25))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 26, height: 26)
            .blendMode(.screen)
    }
    
    // MARK: - Antenna Glow Effect
    
    @ViewBuilder
    private func antennaGlowEffect(time: TimeInterval) -> some View {
        let glowPulse = 0.6 + sin(time * 4) * 0.4
        
        ZStack {
            Circle()
                .fill(Color.cyan.opacity(antennaGlow * glowPulse * 0.5))
                .frame(width: 12, height: 12)
                .blur(radius: 5)
                .offset(y: -12)
            
            Circle()
                .fill(Color.cyan.opacity(antennaGlow * glowPulse))
                .frame(width: 4, height: 4)
                .shadow(color: Color.cyan.opacity(0.9), radius: 3)
                .offset(y: -12)
        }
    }
    
    @ViewBuilder
    private var mascotImage: some View {
        if shouldUseAnimatedPet {
            SortyPetView(
                state: petState,
                size: CGSize(width: 34, height: 36)
            )
        } else if let nsImage = SortyResources.image(named: "SortyMascot") {
            Image(nsImage: nsImage)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
        } else if let nsImage = SortyResources.image(named: "SortyMascotTemplate") {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
        } else {
            Image(systemName: "sparkles")
                .foregroundStyle(.cyan)
        }
    }
    
    // MARK: - Robot Eyes
    
    @ViewBuilder
    private var eyeOverlay: some View {
        if eyeBlinkPhase > 0.1 {
            ZStack {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5 * eyeBlinkPhase)
                    .shadow(color: Color.cyan.opacity(0.8), radius: 2)
                    .offset(x: -3.5, y: -2)
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5 * eyeBlinkPhase)
                    .shadow(color: Color.cyan.opacity(0.8), radius: 2)
                    .offset(x: 3.5, y: -2)
            }
            .opacity(eyeBlinkPhase)
        }
    }
    
    // MARK: - LED Indicators
    
    @ViewBuilder
    private func ledIndicators(time: TimeInterval) -> some View {
        let ledPulse = 0.5 + sin(time * 3.0) * 0.5
        
        Circle()
            .fill(Color.cyan.opacity(0.7 * ledPulse))
            .frame(width: 2.5, height: 2.5)
            .shadow(color: Color.cyan.opacity(0.6 * ledPulse), radius: 2)
            .offset(x: -11, y: 1)
        
        Circle()
            .fill(Color.cyan.opacity(0.7 * ledPulse))
            .frame(width: 2.5, height: 2.5)
            .shadow(color: Color.cyan.opacity(0.6 * ledPulse), radius: 2)
            .offset(x: 11, y: 1)
    }
    
    // MARK: - Enhanced Orbiting Icon
    
    private func orbitingIcon(url: URL, index: Int, time: TimeInterval) -> some View {
        let orbitSpeed = isOrganizing ? 2.0 : 1.0
        let baseRadius: CGFloat = 17 + CGFloat(index % 2) * 4
        let verticalRadius: CGFloat = 10 + CGFloat(index % 2) * 2
        let depth: CGFloat = 10
        let basePhase = Double(index) * (.pi * 0.5)
        let angle = time * orbitSpeed + basePhase
        let x = cos(angle) * baseRadius
        let y = sin(angle * 1.1) * verticalRadius
        let z = cos(angle + .pi / 2) * depth
        let depthProgress = (z + depth) / (2 * depth)
        let scale = 0.6 + depthProgress * 0.6
        let opacity = 0.35 + depthProgress * 0.65
        
        let trailAngle1 = angle - 0.18
        let trailAngle2 = angle - 0.36
        
        return ZStack {
            if isOrganizing {
                Circle()
                    .fill(Color.cyan.opacity(0.15))
                    .frame(width: iconSize * 0.5, height: iconSize * 0.5)
                    .offset(x: cos(trailAngle2) * baseRadius, y: sin(trailAngle2 * 1.1) * verticalRadius)
                    .blur(radius: 2)
                
                Circle()
                    .fill(Color.cyan.opacity(0.25))
                    .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                    .offset(x: cos(trailAngle1) * baseRadius, y: sin(trailAngle1 * 1.1) * verticalRadius)
                    .blur(radius: 1.5)
            }
            
            AppKitImageView(
                image: orbitIconImage(for: url),
                size: CGSize(width: iconSize, height: iconSize)
            )
            .frame(width: iconSize, height: iconSize)
            .shadow(color: Color.cyan.opacity(isOrganizing ? 0.6 : 0.25), radius: isOrganizing ? 5 : 2)
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .rotationEffect(.degrees(angle * 8))
        }
        .zIndex(Double(z))
    }
    
    // MARK: - Animation Triggers
    
    private func startAnimations() {
        withAnimation(
            .easeInOut(duration: 2.2)
            .repeatForever(autoreverses: true)
        ) {
            breathScale = 1.04
        }
        
        withAnimation(
            .easeInOut(duration: 1.6)
            .repeatForever(autoreverses: true)
        ) {
            bounceOffset = -2.0
        }
        
        withAnimation(
            .easeInOut(duration: 0.9)
            .repeatForever(autoreverses: true)
        ) {
            antennaWiggle = 4
        }
        
        withAnimation(
            .easeInOut(duration: 1.3)
            .repeatForever(autoreverses: true)
        ) {
            orbitGlowIntensity = 1.0
        }
        
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            antennaGlow = 0.8
        }
    }
    
    private func triggerBlink() {
        guard currentEmotion != .happy else { return }
        
        withAnimation(.easeIn(duration: 0.06)) {
            eyeBlinkPhase = 1.0
        }
        withAnimation(.easeOut(duration: 0.06).delay(0.08)) {
            eyeBlinkPhase = 0.0
        }
    }
    
    private func triggerHappyEyes() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            eyeSquint = 0.7
        }
    }
    
    private func resetEyes() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            eyeSquint = 1.0
        }
    }
    
    private func triggerLookAround() {
        let randomX = CGFloat.random(in: -2.0...2.0)
        let randomY = CGFloat.random(in: -1.0...1.0)
        let randomTilt = Double.random(in: -5...5)
        
        withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) {
            lookAroundOffset = CGSize(width: randomX, height: randomY)
            headTilt = randomTilt
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(1.8)) {
            lookAroundOffset = .zero
            headTilt = 0
        }
    }
    
    private func triggerExcitement() {
        withAnimation(
            .spring(response: 0.2, dampingFraction: 0.35)
            .repeatCount(2, autoreverses: true)
        ) {
            excitementScale = 1.18
        }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.4)) {
            excitementScale = 1.0
        }
    }
    
    private func updateEmotion() {
        guard !isHovered else { return }
        
        if isOrganizing {
            currentEmotion = .working
        } else if organizer.scannedFiles.count > 50 {
            currentEmotion = Bool.random() ? .excited : .idle
            if currentEmotion == .excited {
                triggerExcitement()
            }
        }
    }
    
    private func rebuildCachedURLs() {
        var urls: [URL] = []
        
        let files = organizer.scannedFiles
        if !files.isEmpty {
            let sample = Array(files.prefix(20)).shuffled().prefix(4)
            urls = sample.map { URL(fileURLWithPath: $0.path) }
        }
        
        if urls.isEmpty, let plan = organizer.currentPlan {
            var planFiles: [FileItem] = []
            func collectFiles(from suggestions: [FolderSuggestion]) {
                for suggestion in suggestions {
                    planFiles.append(contentsOf: suggestion.files)
                    collectFiles(from: suggestion.subfolders)
                }
            }
            collectFiles(from: plan.suggestions)
            planFiles.append(contentsOf: plan.unorganizedFiles)
            let sample = Array(planFiles.prefix(20)).shuffled().prefix(4)
            urls = sample.compactMap { URL(fileURLWithPath: $0.path) }
        }
        
        if urls.isEmpty, let dir = organizer.currentDirectory {
            let fallbackNames = ["Documents", "Images", "Projects"]
            urls = fallbackNames.map { dir.appendingPathComponent($0, isDirectory: true) }
        }
        
        cachedOrbitingURLs = urls
    }

    private func orbitIconImage(for url: URL) -> NSImage {
        if url.hasDirectoryPath {
            return AnalysisIconProvider.icon(for: .folder)
        }

        let ext = url.pathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !ext.isEmpty {
            return AnalysisIconProvider.icon(forFileExtension: ext)
        }

        return AnalysisIconProvider.icon(for: .data)
    }
}

#Preview {
    OrganizingMascotView()
        .environmentObject(FolderOrganizer())
        .frame(width: 80, height: 80)
        .padding()
}

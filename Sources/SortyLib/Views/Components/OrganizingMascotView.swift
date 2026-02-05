//
//  OrganizingMascotView.swift
//  Sorty
//

import SwiftUI

struct OrganizingMascotView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @State private var isAnimating = false
    @State private var orbitingURLs: [URL] = []
    @State private var isHovered = false
    
    // Mascot life-like animation states
    @State private var eyeBlinkPhase: Double = 0
    @State private var headTilt: Double = 0
    @State private var antennaWiggle: Double = 0
    @State private var lookAroundOffset: CGSize = .zero
    @State private var breathScale: CGFloat = 1.0
    @State private var bounceOffset: CGFloat = 0
    @State private var excitementScale: CGFloat = 1.0
    
    // Orbit enhancement states
    @State private var orbitGlowIntensity: Double = 0.5
    @State private var sparklePhase: Double = 0
    
    private let orbitTimer = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()
    private let blinkTimer = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()
    private let lookAroundTimer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()
    private let orbitSize: CGFloat = 60
    private let iconSize: CGFloat = 12
    
    private var isOrganizing: Bool {
        switch organizer.state {
        case .scanning, .organizing, .applying:
            return true
        default:
            return false
        }
    }
    
    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            
            ZStack {
                // Subtle orbit ring path
                orbitRingPath
                
                // Shadow under mascot
                mascotShadow
                
                // Orbiting items with enhanced effects
                ForEach(Array(orbitingURLs.enumerated()), id: \.offset) { index, url in
                    orbitingIcon(url: url, index: index, time: time)
                }
                
                // Sparkle particles
                sparkleParticles(time: time)
                
                // Main mascot with life-like animations
                mascotView(time: time)
            }
            .frame(width: orbitSize, height: orbitSize)
            .mask(Circle().inset(by: 1))
            .contentShape(Circle())
            .compositingGroup()
        }
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isHovered = hovering
            }
        }
        .onAppear {
            orbitingURLs = sampleOrbitingFiles()
            startAnimations()
        }
        .onReceive(orbitTimer) { _ in
            orbitingURLs = sampleOrbitingFiles()
        }
        .onReceive(blinkTimer) { _ in
            triggerBlink()
        }
        .onReceive(lookAroundTimer) { _ in
            triggerLookAround()
        }
        .onChange(of: organizer.scannedFiles) { _, _ in
            orbitingURLs = sampleOrbitingFiles()
        }
        .onChange(of: isOrganizing) { _, newValue in
            if newValue {
                triggerExcitement()
            }
        }
    }
    
    // MARK: - Orbit Ring Path
    
    private var orbitRingPath: some View {
        ZStack {
            // Outer subtle ring
            Ellipse()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.15),
                            Color.blue.opacity(0.1),
                            Color.purple.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 38, height: 22)
                .blur(radius: 0.5)
            
            // Inner glow ring during organizing
            if isOrganizing {
                Ellipse()
                    .stroke(
                        Color.purple.opacity(orbitGlowIntensity * 0.4),
                        lineWidth: 2
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
                        Color.black.opacity(0.2),
                        Color.black.opacity(0.05),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 12
                )
            )
            .frame(width: 20, height: 6)
            .offset(y: 14 + bounceOffset * 0.3)
            .scaleEffect(x: 1.0 - bounceOffset * 0.02)
    }
    
    // MARK: - Sparkle Particles
    
    @ViewBuilder
    private func sparkleParticles(time: TimeInterval) -> some View {
        if isOrganizing || isHovered {
            ForEach(0..<6, id: \.self) { index in
                let angle = time * 1.5 + Double(index) * (.pi / 3)
                let radius: CGFloat = 22 + CGFloat(sin(time * 2 + Double(index))) * 4
                let x = cos(angle) * radius
                let y = sin(angle * 0.7) * radius * 0.5
                let sparkleSize: CGFloat = CGFloat(2 + sin(time * 3 + Double(index) * 0.5) * 1.5)
                
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white,
                                Color.purple.opacity(0.8),
                                Color.purple.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: sparkleSize
                        )
                    )
                    .frame(width: sparkleSize * 2, height: sparkleSize * 2)
                    .offset(x: x, y: y)
                    .opacity(0.6 + sin(time * 4 + Double(index)) * 0.4)
            }
        }
    }
    
    // MARK: - Mascot View with Life-like Animations
    
    @ViewBuilder
    private func mascotView(time: TimeInterval) -> some View {
        ZStack {
            // Glow effect during organizing
            if isOrganizing {
                mascotImage
                    .blur(radius: 6)
                    .opacity(0.5)
                    .scaleEffect(1.2 * excitementScale)
            }
            
            mascotImage
        }
        .scaleEffect(breathScale * excitementScale * (isHovered ? 1.08 : 1.0))
        .offset(
            x: lookAroundOffset.width + (isHovered ? 0 : sin(time * 0.8) * 0.5),
            y: bounceOffset + lookAroundOffset.height
        )
        .rotationEffect(.degrees(headTilt + (isHovered ? -5 : 0)))
        .rotation3DEffect(
            .degrees(antennaWiggle),
            axis: (x: 0, y: 1, z: 0.2)
        )
    }
    
    @ViewBuilder
    private var mascotImage: some View {
        if let nsImage = SortyResources.image(named: "SortyMascot") {
            Image(nsImage: nsImage)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        } else if let nsImage = SortyResources.image(named: "SortyMascotTemplate") {
            Image(nsImage: nsImage)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
        }
    }
    
    // MARK: - Enhanced Orbiting Icon
    
    private func orbitingIcon(url: URL, index: Int, time: TimeInterval) -> some View {
        let orbitSpeed = isOrganizing ? 1.4 : 0.9
        let baseRadius: CGFloat = 16 + CGFloat(index % 2) * 4
        let verticalRadius: CGFloat = 9 + CGFloat(index % 2) * 2
        let depth: CGFloat = 10
        let basePhase = Double(index) * (.pi * 0.5)
        let angle = time * orbitSpeed + basePhase
        let x = cos(angle) * baseRadius
        let y = sin(angle * 1.1) * verticalRadius
        let z = cos(angle + .pi / 2) * depth
        let depthProgress = (z + depth) / (2 * depth)
        let scale = 0.65 + depthProgress * 0.55
        let opacity = 0.4 + depthProgress * 0.6
        
        // Trail effect positions
        let trailAngle1 = angle - 0.15
        let trailAngle2 = angle - 0.3
        
        return ZStack {
            // Particle trails
            if isOrganizing {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: iconSize * 0.5, height: iconSize * 0.5)
                    .offset(x: cos(trailAngle2) * baseRadius, y: sin(trailAngle2 * 1.1) * verticalRadius)
                    .blur(radius: 2)
                
                Circle()
                    .fill(Color.purple.opacity(0.3))
                    .frame(width: iconSize * 0.7, height: iconSize * 0.7)
                    .offset(x: cos(trailAngle1) * baseRadius, y: sin(trailAngle1 * 1.1) * verticalRadius)
                    .blur(radius: 1.5)
            }
            
            // Main icon with glow
            Group {
                if url.hasDirectoryPath {
                    FolderThumbnailView(url: url, size: CGSize(width: iconSize, height: iconSize))
                } else {
                    FileThumbnailView(url: url, size: CGSize(width: iconSize, height: iconSize))
                }
            }
            .frame(width: iconSize, height: iconSize)
            .shadow(color: Color.purple.opacity(isOrganizing ? 0.5 : 0.2), radius: isOrganizing ? 4 : 2)
            .opacity(opacity)
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .rotationEffect(.degrees(angle * 8))
        }
        .zIndex(Double(z))
    }
    
    // MARK: - Animation Triggers
    
    private func startAnimations() {
        // Breathing animation
        withAnimation(
            .easeInOut(duration: 2.0)
            .repeatForever(autoreverses: true)
        ) {
            breathScale = 1.03
        }
        
        // Subtle bounce
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            bounceOffset = -1.5
        }
        
        // Antenna wiggle
        withAnimation(
            .easeInOut(duration: 0.8)
            .repeatForever(autoreverses: true)
        ) {
            antennaWiggle = 3
        }
        
        // Orbit glow pulsing
        withAnimation(
            .easeInOut(duration: 1.2)
            .repeatForever(autoreverses: true)
        ) {
            orbitGlowIntensity = 1.0
        }
        
        // Initial blink after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            triggerBlink()
        }
    }
    
    private func triggerBlink() {
        withAnimation(.easeIn(duration: 0.08)) {
            eyeBlinkPhase = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.08)) {
                eyeBlinkPhase = 0.0
            }
        }
    }
    
    private func triggerLookAround() {
        let randomX = CGFloat.random(in: -1.5...1.5)
        let randomY = CGFloat.random(in: -0.8...0.8)
        let randomTilt = Double.random(in: -4...4)
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            lookAroundOffset = CGSize(width: randomX, height: randomY)
            headTilt = randomTilt
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                lookAroundOffset = .zero
                headTilt = 0
            }
        }
    }
    
    private func triggerExcitement() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            excitementScale = 1.15
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                excitementScale = 1.0
            }
        }
        
        // Repeat excitement bounce while organizing
        if isOrganizing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if isOrganizing {
                    triggerExcitement()
                }
            }
        }
    }
    
    private func sampleOrbitingFiles() -> [URL] {
        let files = organizer.scannedFiles
        guard !files.isEmpty else { return [] }
        let sample = files.shuffled().prefix(4)
        return sample.map { URL(fileURLWithPath: $0.path) }
    }
}

#Preview {
    OrganizingMascotView()
        .environmentObject(FolderOrganizer())
        .frame(width: 80, height: 80)
        .padding()
}

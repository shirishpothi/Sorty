//
//  AIPortalView.swift
//  Sorty
//

import SwiftUI

struct AIPortalView: View {
    var isProcessing: Bool
    var fileReceivedPulse: Bool
    var portalSize: CGFloat = 140

    @State private var rotationPhase: Double = 0
    @State private var pulseScales: [CGFloat] = [0.3, 0.6, 0.9]
    @State private var pulseOpacities: [Double] = [0.6, 0.4, 0.2]
    @State private var coreGlow: Double = 0.6
    @State private var fileFlashOpacity: Double = 0
    @State private var particlePhase: Double = 0

    private let particleCount = 8
    private let pulseCount = 3

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            ZStack {
                outerGlow(time: time)
                pulseRings(time: time)
                concentricRings(time: time)
                orbitingParticles(time: time)
                innerCore(time: time)
                fileReceivedFlash
            }
            .frame(width: portalSize, height: portalSize)
        }
        .onChange(of: fileReceivedPulse) { _, _ in
            triggerFileFlash()
        }
    }

    // MARK: - Outer Glow

    @ViewBuilder
    private func outerGlow(time: TimeInterval) -> some View {
        let breathe = 0.12 + sin(time * 1.5) * 0.04
        let processingBoost: Double = isProcessing ? 0.08 : 0

        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.cyan.opacity(breathe + processingBoost),
                        Color.blue.opacity((breathe + processingBoost) * 0.5),
                        Color.purple.opacity((breathe + processingBoost) * 0.25),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: portalSize * 0.15,
                    endRadius: portalSize * 0.52
                )
            )
            .frame(width: portalSize, height: portalSize)
            .blur(radius: 8)
    }

    // MARK: - Pulse Rings

    @ViewBuilder
    private func pulseRings(time: TimeInterval) -> some View {
        ForEach(0..<pulseCount, id: \.self) { index in
            let cycleTime = 2.4
            let offset = Double(index) * (cycleTime / Double(pulseCount))
            let progress = ((time + offset).truncatingRemainder(dividingBy: cycleTime)) / cycleTime
            let scale = 0.3 + progress * 0.7
            let opacity = (1.0 - progress) * (isProcessing ? 0.5 : 0.25)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(opacity),
                            Color.blue.opacity(opacity * 0.7),
                            Color.purple.opacity(opacity * 0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
                .frame(
                    width: portalSize * scale,
                    height: portalSize * scale
                )
                .shadow(color: Color.cyan.opacity(opacity * 0.5), radius: 3)
        }
    }

    // MARK: - Concentric Rings

    @ViewBuilder
    private func concentricRings(time: TimeInterval) -> some View {
        let ringCount = 3
        ForEach(0..<ringCount, id: \.self) { index in
            let radiusFraction = 0.28 + Double(index) * 0.1
            let speed = (Double(index) + 1) * 0.6
            let direction: Double = index.isMultiple(of: 2) ? 1.0 : -1.0
            let rotation = time * speed * direction * 30
            let baseOpacity = 0.15 + sin(time * 2.0 + Double(index) * 1.2) * 0.08
            let processingOpacity = isProcessing ? baseOpacity + 0.1 : baseOpacity

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            Color.cyan.opacity(processingOpacity),
                            Color.blue.opacity(processingOpacity * 0.6),
                            Color.purple.opacity(processingOpacity * 0.3),
                            Color.clear,
                            Color.cyan.opacity(processingOpacity)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])
                )
                .frame(
                    width: portalSize * radiusFraction * 2,
                    height: portalSize * radiusFraction * 2
                )
                .rotationEffect(.degrees(rotation))
        }
    }

    // MARK: - Orbiting Particles

    @ViewBuilder
    private func orbitingParticles(time: TimeInterval) -> some View {
        let orbitRadius = portalSize * 0.3
        ForEach(0..<particleCount, id: \.self) { index in
            let baseAngle = (Double(index) / Double(particleCount)) * .pi * 2
            let speed = isProcessing ? 1.8 : 0.8
            let angle = baseAngle + time * speed
            let wobble = sin(time * 3.0 + Double(index) * 0.9) * 4
            let x = cos(angle) * (orbitRadius + wobble)
            let y = sin(angle) * (orbitRadius + wobble) * 0.85
            let particleSize: CGFloat = CGFloat(2.0 + sin(time * 2.5 + Double(index) * 1.3) * 1.0)
            let opacity = 0.4 + sin(time * 3.0 + Double(index) * 0.7) * 0.3

            Circle()
                .fill(
                    index.isMultiple(of: 3)
                        ? Color.purple.opacity(opacity)
                        : index.isMultiple(of: 2)
                            ? Color.blue.opacity(opacity)
                            : Color.cyan.opacity(opacity)
                )
                .frame(width: particleSize, height: particleSize)
                .shadow(
                    color: Color.cyan.opacity(opacity * 0.6),
                    radius: 3
                )
                .offset(x: x, y: y)
        }
    }

    // MARK: - Inner Core

    @ViewBuilder
    private func innerCore(time: TimeInterval) -> some View {
        let corePulse = isProcessing
            ? 0.9 + sin(time * 3.0) * 0.1
            : 0.85 + sin(time * 1.5) * 0.05
        let glowIntensity = isProcessing
            ? 0.7 + sin(time * 2.5) * 0.2
            : 0.4 + sin(time * 1.2) * 0.1

        ZStack {
            // Core glow halo
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(glowIntensity * 0.5),
                            Color.blue.opacity(glowIntensity * 0.25),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: portalSize * 0.04,
                        endRadius: portalSize * 0.18
                    )
                )
                .frame(
                    width: portalSize * 0.36,
                    height: portalSize * 0.36
                )
                .blur(radius: 4)

            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.cyan.opacity(0.8),
                            Color.blue.opacity(0.6),
                            Color.purple.opacity(0.3)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: portalSize * 0.1
                    )
                )
                .frame(
                    width: portalSize * 0.16,
                    height: portalSize * 0.16
                )
                .shadow(color: Color.cyan.opacity(glowIntensity), radius: 8)
                .shadow(color: Color.blue.opacity(glowIntensity * 0.5), radius: 14)
                .scaleEffect(corePulse)

            // Inner bright point
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(
                    width: portalSize * 0.04,
                    height: portalSize * 0.04
                )
                .blur(radius: 1)
                .scaleEffect(corePulse)
        }
    }

    // MARK: - File Received Flash

    private var fileReceivedFlash: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(fileFlashOpacity * 0.8),
                        Color.cyan.opacity(fileFlashOpacity * 0.5),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: portalSize * 0.35
                )
            )
            .frame(width: portalSize * 0.7, height: portalSize * 0.7)
            .blur(radius: 6)
    }

    // MARK: - Animation Triggers

    private func triggerFileFlash() {
        withAnimation(.easeIn(duration: 0.1)) {
            fileFlashOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
            fileFlashOpacity = 0
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        AIPortalView(isProcessing: false, fileReceivedPulse: false)
        AIPortalView(isProcessing: true, fileReceivedPulse: false, portalSize: 180)
    }
    .padding(40)
    .background(Color.black)
}

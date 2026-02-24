//
//  LabGridBackground.swift
//  Sorty
//
//  Animated grid background for the Sorting Lab experience.
//

import SwiftUI

struct LabGridBackground: View {
    let isActive: Bool
    var mouseLocation: CGPoint? = nil

    private let gridSpacing: CGFloat = 48
    private let lineWidth: CGFloat = 0.5

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            GeometryReader { geo in
                let size = geo.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let pulse = (sin(time * 2.0) + 1) * 0.5
                let parallaxOffset = parallaxOffset(for: size)

                Canvas { ctx, canvasSize in
                    // Radial glow at center
                    let glowOpacity = isActive ? 0.18 + pulse * 0.1 : 0.06
                    let glowRadius = min(canvasSize.width, canvasSize.height) * (isActive ? 0.5 : 0.35)
                    let glowCenter = CGPoint(
                        x: center.x + parallaxOffset.x * 0.3,
                        y: center.y + parallaxOffset.y * 0.3
                    )
                    ctx.drawLayer { inner in
                        let gradient = Gradient(colors: [
                            Color.cyan.opacity(glowOpacity),
                            Color.blue.opacity(glowOpacity * 0.4),
                            Color.clear
                        ])
                        inner.fill(
                            Path(ellipseIn: CGRect(
                                x: glowCenter.x - glowRadius,
                                y: glowCenter.y - glowRadius,
                                width: glowRadius * 2,
                                height: glowRadius * 2
                            )),
                            with: .radialGradient(
                                gradient,
                                center: glowCenter,
                                startRadius: 0,
                                endRadius: glowRadius
                            )
                        )
                    }

                    // Grid lines
                    let baseOpacity = isActive ? 0.12 + pulse * 0.06 : 0.07
                    let lineColor = Color.cyan.opacity(baseOpacity)

                    // Vertical lines
                    let cols = Int(canvasSize.width / gridSpacing) + 2
                    let startX = parallaxOffset.x.truncatingRemainder(dividingBy: gridSpacing)
                    for i in 0..<cols {
                        let x = startX + CGFloat(i) * gridSpacing
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: canvasSize.height))
                        ctx.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
                    }

                    // Horizontal lines
                    let rows = Int(canvasSize.height / gridSpacing) + 2
                    let startY = parallaxOffset.y.truncatingRemainder(dividingBy: gridSpacing)
                    for i in 0..<rows {
                        let y = startY + CGFloat(i) * gridSpacing
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: canvasSize.width, y: y))
                        ctx.stroke(path, with: .color(lineColor), lineWidth: lineWidth)
                    }

                    // Shimmer highlight along a sweeping line when active
                    if isActive {
                        let sweepX = canvasSize.width * CGFloat((time * 0.15).truncatingRemainder(dividingBy: 1.0))
                        let shimmerGradient = Gradient(colors: [
                            Color.clear,
                            Color.cyan.opacity(0.08 + pulse * 0.06),
                            Color.clear
                        ])
                        let band: CGFloat = 60
                        ctx.fill(
                            Path(CGRect(x: sweepX - band / 2, y: 0, width: band, height: canvasSize.height)),
                            with: .linearGradient(
                                shimmerGradient,
                                startPoint: CGPoint(x: sweepX - band / 2, y: 0),
                                endPoint: CGPoint(x: sweepX + band / 2, y: 0)
                            )
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func parallaxOffset(for size: CGSize) -> CGPoint {
        guard let mouse = mouseLocation else { return .zero }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxShift: CGFloat = 12
        let dx = ((mouse.x - center.x) / center.x) * maxShift
        let dy = ((mouse.y - center.y) / center.y) * maxShift
        return CGPoint(x: dx, y: dy)
    }
}

#Preview("Lab Grid Background") {
    ZStack {
        Color.black

        LabGridBackground(isActive: true)
    }
    .frame(width: 600, height: 400)
}

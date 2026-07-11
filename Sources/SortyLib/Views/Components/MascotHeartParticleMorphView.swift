//
//  MascotHeartParticleMorphView.swift
//  Sorty
//
//  Particle morph from Sorty's mascot outline into a beating heart.
//

import SwiftUI

struct MascotHeartParticleMorphView: View {
    private enum Timing {
        static let mascotHold: TimeInterval = 0.7
        static let morphDuration: TimeInterval = 1.35
        static let heartbeatDuration: TimeInterval = 1.35
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()

    let color: Color

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: reduceMotion)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(animationStart)

            ParticleMorphCanvas(
                progress: reduceMotion ? 1 : morphProgress(at: elapsed),
                heartbeatScale: reduceMotion ? 1 : heartbeatScale(at: elapsed),
                color: color
            )
        }
        .onAppear {
            animationStart = Date()
        }
        .onChange(of: reduceMotion) {
            animationStart = Date()
        }
        .accessibilityHidden(true)
    }

    private func morphProgress(at elapsed: TimeInterval) -> Double {
        let rawProgress = min(max((elapsed - Timing.mascotHold) / Timing.morphDuration, 0), 1)
        return rawProgress * rawProgress * (3 - 2 * rawProgress)
    }

    private func heartbeatScale(at elapsed: TimeInterval) -> CGFloat {
        let heartStart = Timing.mascotHold + Timing.morphDuration
        guard elapsed >= heartStart else { return 1 }

        let time = (elapsed - heartStart).truncatingRemainder(dividingBy: Timing.heartbeatDuration)
        switch time {
        case 0..<0.12:
            return 1 + 0.09 * easedPulse(time / 0.12)
        case 0.12..<0.26:
            return 1.09 - 0.09 * easedPulse((time - 0.12) / 0.14)
        case 0.32..<0.43:
            return 1 + 0.055 * easedPulse((time - 0.32) / 0.11)
        case 0.43..<0.58:
            return 1.055 - 0.055 * easedPulse((time - 0.43) / 0.15)
        default:
            return 1
        }
    }

    private func easedPulse(_ progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        return CGFloat(1 - pow(1 - clamped, 3))
    }
}

private struct ParticleMorphCanvas: View {
    let progress: Double
    let heartbeatScale: CGFloat
    let color: Color

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            let side = min(size.width, size.height)
            let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
            let morph = CGFloat(progress)
            let scatterEnvelope = CGFloat(sin(.pi * progress))

            for index in MascotHeartParticleTargets.mascot.indices {
                let mascot = MascotHeartParticleTargets.mascot[index]
                let heart = MascotHeartParticleTargets.heart[index]
                let seed = Self.seed(for: index)
                let angle = Double(seed * 2 * .pi + morph * .pi)
                let scatter = scatterEnvelope * (0.012 + seed * 0.016)

                var x = mascot.x + (heart.x - mascot.x) * morph
                var y = mascot.y + (heart.y - mascot.y) * morph
                x += CGFloat(cos(angle)) * scatter
                y += CGFloat(sin(angle)) * scatter
                x = 0.5 + (x - 0.5) * heartbeatScale
                y = 0.5 + (y - 0.5) * heartbeatScale

                let diameter = 1.7 + seed * 1.5
                let center = CGPoint(x: origin.x + x * side, y: origin.y + y * side)
                let rect = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(0.68 + Double(seed) * 0.32))
                )
            }
        }
    }

    private static func seed(for index: Int) -> CGFloat {
        let mixed = UInt64(index &* 73_856_093) ^ UInt64(index &* 19_349_663)
        return CGFloat(mixed % 1_000) / 1_000
    }
}

private enum MascotHeartParticleTargets {
    private static let viewBoxSize: CGFloat = 22
    private static let heartVertexCount = 2_000

    static let mascot: [CGPoint] = orderedByAngle(makeMascotPoints())
    static let heart: [CGPoint] = orderedByAngle(makeHeartPoints(count: mascot.count))

    private static func makeMascotPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        points += roundedRectangleOutline(
            rect: CGRect(x: 3, y: 6, width: 16, height: 13),
            radius: 5.5,
            count: 200
        )
        points += circle(center: CGPoint(x: 2, y: 12.5), radius: 2.2, count: 50)
        points += circle(center: CGPoint(x: 20, y: 12.5), radius: 2.2, count: 50)
        points += quadraticCurve(
            from: CGPoint(x: 10.5, y: 6),
            control: CGPoint(x: 10.5, y: 4),
            to: CGPoint(x: 11, y: 2),
            count: 32
        )
        points += circle(center: CGPoint(x: 11, y: 1.8), radius: 1.8, count: 36)
        points += circle(center: CGPoint(x: 8, y: 11.5), radius: 2.3, count: 48)
        points += circle(center: CGPoint(x: 14, y: 11.5), radius: 2.3, count: 48)
        points += quadraticCurve(
            from: CGPoint(x: 8, y: 15.5),
            control: CGPoint(x: 11, y: 17.5),
            to: CGPoint(x: 14, y: 15.5),
            count: 56
        )

        return points.map(normalizeMascotPoint)
    }

    private static func makeHeartPoints(count: Int) -> [CGPoint] {
        let vertices = (0..<heartVertexCount).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(heartVertexCount)
            let x = 16 * pow(sin(angle), 3)
            let y = 13 * cos(angle) - 5 * cos(2 * angle) - 2 * cos(3 * angle) - cos(4 * angle)
            return CGPoint(x: 0.5 + x / 42, y: 0.5 - y / 42)
        }
        let outline = resampleClosedPolyline(vertices, count: count)
        let center = CGPoint(x: 0.5, y: 0.54)

        return outline.enumerated().map { index, edge in
            let radialScale: CGFloat
            if index.isMultiple(of: 4) {
                radialScale = 1
            } else {
                let fraction = (Double(index) * 0.618_033_988_75).truncatingRemainder(dividingBy: 1)
                radialScale = CGFloat(sqrt(fraction))
            }
            return CGPoint(
                x: center.x + (edge.x - center.x) * radialScale,
                y: center.y + (edge.y - center.y) * radialScale
            )
        }
    }

    private static func normalizeMascotPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: 0.05 + (point.x / viewBoxSize) * 0.9,
            y: 0.04 + (point.y / viewBoxSize) * 0.9
        )
    }

    private static func orderedByAngle(_ points: [CGPoint]) -> [CGPoint] {
        points.sorted { lhs, rhs in
            let lhsAngle = atan2(lhs.y - 0.5, lhs.x - 0.5)
            let rhsAngle = atan2(rhs.y - 0.5, rhs.x - 0.5)
            if lhsAngle == rhsAngle {
                return hypot(lhs.x - 0.5, lhs.y - 0.5) < hypot(rhs.x - 0.5, rhs.y - 0.5)
            }
            return lhsAngle < rhsAngle
        }
    }

    private static func circle(center: CGPoint, radius: CGFloat, count: Int) -> [CGPoint] {
        (0..<count).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(count) - .pi / 2
            return CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }
    }

    private static func quadraticCurve(
        from start: CGPoint,
        control: CGPoint,
        to end: CGPoint,
        count: Int
    ) -> [CGPoint] {
        guard count > 0 else { return [] }

        let denominator = CGFloat(max(count - 1, 1))
        var points: [CGPoint] = []
        points.reserveCapacity(count)

        for index in 0..<count {
            let progress = CGFloat(index) / denominator
            let inverse = 1 - progress
            let startWeight = inverse * inverse
            let controlWeight = 2 * inverse * progress
            let endWeight = progress * progress
            let x = startWeight * start.x + controlWeight * control.x + endWeight * end.x
            let y = startWeight * start.y + controlWeight * control.y + endWeight * end.y
            points.append(CGPoint(x: x, y: y))
        }

        return points
    }

    private static func roundedRectangleOutline(rect: CGRect, radius: CGFloat, count: Int) -> [CGPoint] {
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let arcSteps = 24
        var vertices = [
            CGPoint(x: left + radius, y: top),
            CGPoint(x: right - radius, y: top)
        ]

        vertices += arc(
            center: CGPoint(x: right - radius, y: top + radius),
            radius: radius,
            from: -.pi / 2,
            to: 0,
            steps: arcSteps
        )
        vertices.append(CGPoint(x: right, y: bottom - radius))
        vertices += arc(
            center: CGPoint(x: right - radius, y: bottom - radius),
            radius: radius,
            from: 0,
            to: .pi / 2,
            steps: arcSteps
        )
        vertices.append(CGPoint(x: left + radius, y: bottom))
        vertices += arc(
            center: CGPoint(x: left + radius, y: bottom - radius),
            radius: radius,
            from: .pi / 2,
            to: .pi,
            steps: arcSteps
        )
        vertices.append(CGPoint(x: left, y: top + radius))
        vertices += arc(
            center: CGPoint(x: left + radius, y: top + radius),
            radius: radius,
            from: .pi,
            to: .pi * 1.5,
            steps: arcSteps
        )

        return resampleClosedPolyline(vertices, count: count)
    }

    private static func arc(
        center: CGPoint,
        radius: CGFloat,
        from startAngle: Double,
        to endAngle: Double,
        steps: Int
    ) -> [CGPoint] {
        (1...steps).map { step in
            let progress = Double(step) / Double(steps)
            let angle = startAngle + (endAngle - startAngle) * progress
            return CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }
    }

    private static func resampleClosedPolyline(_ vertices: [CGPoint], count: Int) -> [CGPoint] {
        guard vertices.count > 1, count > 0 else { return [] }

        let segments = vertices.indices.map { index in
            let nextIndex = (index + 1) % vertices.count
            return hypot(vertices[nextIndex].x - vertices[index].x, vertices[nextIndex].y - vertices[index].y)
        }
        let totalLength = segments.reduce(0, +)
        guard totalLength > 0 else { return Array(repeating: vertices[0], count: count) }

        var points: [CGPoint] = []
        points.reserveCapacity(count)
        var segmentIndex = 0
        var segmentStartDistance: CGFloat = 0

        for sampleIndex in 0..<count {
            let targetDistance = totalLength * CGFloat(sampleIndex) / CGFloat(count)
            while segmentIndex < segments.count - 1,
                  segmentStartDistance + segments[segmentIndex] < targetDistance {
                segmentStartDistance += segments[segmentIndex]
                segmentIndex += 1
            }

            let start = vertices[segmentIndex]
            let end = vertices[(segmentIndex + 1) % vertices.count]
            let segmentLength = max(segments[segmentIndex], .leastNonzeroMagnitude)
            let progress = (targetDistance - segmentStartDistance) / segmentLength
            points.append(
                CGPoint(
                    x: start.x + (end.x - start.x) * progress,
                    y: start.y + (end.y - start.y) * progress
                )
            )
        }

        return points
    }
}

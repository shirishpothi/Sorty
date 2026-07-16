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
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
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

                var x = mascot.point.x + (heart.x - mascot.point.x) * morph
                var y = mascot.point.y + (heart.y - mascot.point.y) * morph
                x += CGFloat(cos(angle)) * scatter
                y += CGFloat(sin(angle)) * scatter
                x = 0.5 + (x - 0.5) * heartbeatScale
                y = 0.5 + (y - 0.5) * heartbeatScale

                let diameter = 1.15 + seed * 1.15
                let center = CGPoint(x: origin.x + x * side, y: origin.y + y * side)
                let rect = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )

                let shadowRect = rect.offsetBy(dx: 0, dy: 1.2)
                context.fill(
                    Path(ellipseIn: shadowRect),
                    with: .color(.black.opacity(0.08 + Double(seed) * 0.08))
                )

                let mascotOpacity = max(0, 1 - progress * 1.35)
                if mascotOpacity > 0 {
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(mascotColor(for: mascot.role, seed: seed).opacity(mascotOpacity))
                    )
                }

                let heartOpacity = max(0, (progress - 0.18) / 0.82)
                if heartOpacity > 0 {
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(heartColor(at: heart, seed: seed).opacity(heartOpacity))
                    )
                }
            }
        }
    }

    private func mascotColor(for role: MascotParticleRole, seed: CGFloat) -> Color {
        switch role {
        case .shell:
            return color.opacity(0.76 + Double(seed) * 0.24)
        case .face:
            return Color(red: 0.40, green: 0.88, blue: 0.98).opacity(0.82 + Double(seed) * 0.18)
        case .edge:
            return Color(red: 0.05, green: 0.24, blue: 0.55).opacity(0.86 + Double(seed) * 0.14)
        case .eye:
            return Color(red: 0.02, green: 0.07, blue: 0.18)
        case .highlight:
            return .white.opacity(0.82 + Double(seed) * 0.18)
        }
    }

    private func heartColor(at point: CGPoint, seed: CGFloat) -> Color {
        let highlightDistance = hypot(point.x - 0.38, point.y - 0.34)
        if highlightDistance < 0.09, seed > 0.28 {
            return .white.opacity(0.82 + Double(seed) * 0.18)
        }

        let verticalShade = min(max((point.y - 0.24) / 0.62, 0), 1)
        let red = 1 - Double(verticalShade) * 0.34
        let green = 0.08 + (1 - Double(verticalShade)) * 0.19
        let blue = 0.14 + (1 - Double(verticalShade)) * 0.14
        return Color(red: red, green: green, blue: blue)
    }

    private static func seed(for index: Int) -> CGFloat {
        let mixed = UInt64(index &* 73_856_093) ^ UInt64(index &* 19_349_663)
        return CGFloat(mixed % 1_000) / 1_000
    }
}

private enum MascotParticleRole {
    case shell
    case face
    case edge
    case eye
    case highlight
}

private struct MascotParticle {
    let point: CGPoint
    let role: MascotParticleRole
}

private enum MascotHeartParticleTargets {
    private static let viewBoxSize: CGFloat = 22
    private static let heartVertexCount = 2_000

    static let mascot: [MascotParticle] = orderedByAngle(makeMascotParticles())
    static let heart: [CGPoint] = orderedByAngle(makeHeartPoints(count: mascot.count))

    private static func makeMascotParticles() -> [MascotParticle] {
        let shellRect = CGRect(x: 3, y: 6, width: 16, height: 13)
        let faceRect = CGRect(x: 4.3, y: 8, width: 13.4, height: 8.7)
        let leftEar = CGPoint(x: 2.1, y: 12.6)
        let rightEar = CGPoint(x: 19.9, y: 12.6)

        var particles: [MascotParticle] = []
        particles += makeParticles(
            filledRoundedRectangle(rect: shellRect, radius: 5.5, count: 320),
            role: .shell
        )
        particles += makeParticles(
            roundedRectangleOutline(rect: shellRect, radius: 5.5, count: 160),
            role: .edge
        )
        particles += makeParticles(
            filledRoundedRectangle(rect: faceRect, radius: 3.8, count: 280),
            role: .face
        )
        particles += makeParticles(filledCircle(center: leftEar, radius: 2.2, count: 50), role: .shell)
        particles += makeParticles(filledCircle(center: rightEar, radius: 2.2, count: 50), role: .shell)
        particles += makeParticles(circle(center: leftEar, radius: 2.2, count: 24), role: .edge)
        particles += makeParticles(circle(center: rightEar, radius: 2.2, count: 24), role: .edge)
        particles += makeParticles(
            quadraticCurve(
                from: CGPoint(x: 10.6, y: 6.1),
                control: CGPoint(x: 10.6, y: 4),
                to: CGPoint(x: 11, y: 2),
                count: 32
            ),
            role: .edge
        )
        particles += makeParticles(filledCircle(center: CGPoint(x: 11, y: 1.8), radius: 1.65, count: 50), role: .shell)
        particles += makeParticles(circle(center: CGPoint(x: 11, y: 1.8), radius: 1.65, count: 24), role: .edge)
        particles += makeParticles(
            filledRoundedRectangle(rect: CGRect(x: 8.1, y: 5.5, width: 5.8, height: 2.5), radius: 1.1, count: 45),
            role: .shell
        )
        particles += makeParticles(
            roundedRectangleOutline(rect: CGRect(x: 8.1, y: 5.5, width: 5.8, height: 2.5), radius: 1.1, count: 30),
            role: .highlight
        )
        particles += makeParticles(filledCircle(center: CGPoint(x: 8, y: 11.6), radius: 1.75, count: 60), role: .eye)
        particles += makeParticles(filledCircle(center: CGPoint(x: 14, y: 11.6), radius: 1.75, count: 60), role: .eye)
        particles += makeParticles(filledCircle(center: CGPoint(x: 7.55, y: 11.1), radius: 0.55, count: 18), role: .highlight)
        particles += makeParticles(filledCircle(center: CGPoint(x: 13.55, y: 11.1), radius: 0.55, count: 18), role: .highlight)
        particles += makeParticles(
            quadraticCurve(
                from: CGPoint(x: 8.1, y: 14.6),
                control: CGPoint(x: 11, y: 17.1),
                to: CGPoint(x: 13.9, y: 14.6),
                count: 70
            ),
            role: .edge
        )

        return particles
    }

    private static func makeParticles(_ points: [CGPoint], role: MascotParticleRole) -> [MascotParticle] {
        points.map { MascotParticle(point: normalizeMascotPoint($0), role: role) }
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

    private static func orderedByAngle(_ particles: [MascotParticle]) -> [MascotParticle] {
        particles.sorted { lhs, rhs in
            let lhsAngle = atan2(lhs.point.y - 0.5, lhs.point.x - 0.5)
            let rhsAngle = atan2(rhs.point.y - 0.5, rhs.point.x - 0.5)
            if lhsAngle == rhsAngle {
                return hypot(lhs.point.x - 0.5, lhs.point.y - 0.5)
                    < hypot(rhs.point.x - 0.5, rhs.point.y - 0.5)
            }
            return lhsAngle < rhsAngle
        }
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

    private static func filledRoundedRectangle(rect: CGRect, radius: CGFloat, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }

        var points: [CGPoint] = []
        points.reserveCapacity(count)
        var sampleIndex = 1

        while points.count < count {
            let point = CGPoint(
                x: rect.minX + halton(sampleIndex, base: 2) * rect.width,
                y: rect.minY + halton(sampleIndex, base: 3) * rect.height
            )
            if isInsideRoundedRectangle(point, rect: rect, radius: radius) {
                points.append(point)
            }
            sampleIndex += 1
        }

        return points
    }

    private static func isInsideRoundedRectangle(_ point: CGPoint, rect: CGRect, radius: CGFloat) -> Bool {
        if point.x >= rect.minX + radius, point.x <= rect.maxX - radius {
            return true
        }
        if point.y >= rect.minY + radius, point.y <= rect.maxY - radius {
            return true
        }

        let corner = CGPoint(
            x: point.x < rect.midX ? rect.minX + radius : rect.maxX - radius,
            y: point.y < rect.midY ? rect.minY + radius : rect.maxY - radius
        )
        return hypot(point.x - corner.x, point.y - corner.y) <= radius
    }

    private static func halton(_ index: Int, base: Int) -> CGFloat {
        var result: CGFloat = 0
        var fraction: CGFloat = 1
        var value = index

        while value > 0 {
            fraction /= CGFloat(base)
            result += fraction * CGFloat(value % base)
            value /= base
        }

        return result
    }

    private static func filledCircle(center: CGPoint, radius: CGFloat, count: Int) -> [CGPoint] {
        let goldenAngle = Double.pi * (3 - sqrt(5))
        return (0..<count).map { index in
            let distance = radius * sqrt((CGFloat(index) + 0.5) / CGFloat(count))
            let angle = Double(index) * goldenAngle
            return CGPoint(
                x: center.x + CGFloat(cos(angle)) * distance,
                y: center.y + CGFloat(sin(angle)) * distance
            )
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

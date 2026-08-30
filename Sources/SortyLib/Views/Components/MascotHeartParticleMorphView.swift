//
//  MascotHeartParticleMorphView.swift
//  Sorty
//
//  Particle morph from Sorty's mascot into a solid heart.

import Foundation
import SwiftUI

struct MascotHeartParticleMorphView: View {
    private enum Timing {
        static let mascotHold: TimeInterval = 0.5
        static let morphDuration: TimeInterval = 1.15
        static let heartbeatDuration: TimeInterval = 0.90
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart: Date?

    // `color` kept for API compat but mascot uses its true palette, not the accent.
    let color: Color

    var body: some View {
        SwiftUI.TimelineView(
            .animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || animationStart == nil)
        ) { timeline in
            let elapsed = animationStart.map { timeline.date.timeIntervalSince($0) } ?? 0

            ParticleMorphCanvas(
                progress: reduceMotion ? 1 : morphProgress(at: elapsed),
                heartbeatScale: reduceMotion ? 1 : heartbeatScale(at: elapsed)
            )
        }
        .task(id: reduceMotion) {
            animationStart = nil
            guard !reduceMotion else { return }

            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            animationStart = Date()
        }
        .accessibilityHidden(true)
    }

    private func morphProgress(at elapsed: TimeInterval) -> Double {
        let raw = min(max((elapsed - Timing.mascotHold) / Timing.morphDuration, 0), 1)
        // easeInOutCubic
        if raw < 0.5 { return 4 * raw * raw * raw }
        let p = 2 * raw - 2
        return 0.5 * p * p * p + 1
    }

    private func heartbeatScale(at elapsed: TimeInterval) -> CGFloat {
        let heartStart = Timing.mascotHold + Timing.morphDuration
        guard elapsed >= heartStart else {
            return 1
        }

        let t = (elapsed - heartStart).truncatingRemainder(dividingBy: Timing.heartbeatDuration)
        switch t {
        case 0..<0.11: return 1 + 0.075 * eased(t / 0.11)
        case 0.11..<0.20: return 1.075 - 0.075 * eased((t - 0.11) / 0.09)
        case 0.24..<0.32: return 1 + 0.038 * eased((t - 0.24) / 0.08)
        case 0.32..<0.44: return 1.038 - 0.038 * eased((t - 0.32) / 0.12)
        default: return 1
        }
    }

    private func eased(_ p: Double) -> CGFloat {
        let c = min(max(p, 0), 1)
        return CGFloat(1 - pow(1 - c, 3))
    }
}

private struct ParticleMorphCanvas: View {
    let progress: Double
    let heartbeatScale: CGFloat

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
            drawParticles(in: &context, size: size)
        }
    }

    private func drawParticles(in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        drawParticlesOnly(in: &context, origin: origin, side: side)
    }

    private func drawParticlesOnly(
        in context: inout GraphicsContext,
        origin: CGPoint,
        side: CGFloat
    ) {
        for index in MascotHeartParticleTargets.mascot.indices {
            let mascot = MascotHeartParticleTargets.mascot[index]
            let heart = MascotHeartParticleTargets.heart[index]
            let seed = Self.seed(for: index)
            let angle = atan2(mascot.point.y - 0.5, mascot.point.x - 0.5)

            let rect = particleRect(
                mascot: mascot.point,
                heart: heart,
                seed: seed,
                angle: angle,
                origin: origin,
                side: side
            )
            drawParticle(
                in: &context,
                rect: rect,
                mascot: mascot,
                seed: seed,
                angle: angle
            )
        }
    }

    private func particleRect(
        mascot: CGPoint,
        heart: CGPoint,
        seed: CGFloat,
        angle: CGFloat,
        origin: CGPoint,
        side: CGFloat
    ) -> CGRect {
        // tiny stagger (max 80ms) prevents pop-in glitch while keeping motion coherent
        let angleNorm = abs(angle) / .pi // 0...1
        let delay = seed * 0.06 + angleNorm * 0.04
        let raw = max(0, min((CGFloat(progress) - delay) / (1 - delay), 1))
        // match global cubic easing per-particle with same curve
        let p: CGFloat
        if raw < 0.5 {
            p = 4 * raw * raw * raw
        } else {
            let pp = 2 * raw - 2
            p = 0.5 * pp * pp * pp + 1
        }

        // gentle arc: perpendicular offset peaks at mid-flight, scaled by travel distance
        let dx = heart.x - mascot.x
        let dy = heart.y - mascot.y
        let len = max(hypot(dx, dy), 0.001)
        let perpX = -dy / len
        let perpY = dx / len
        let sideSign: CGFloat = seed > 0.5 ? 1 : -1
        let arc = CGFloat(sin(.pi * Double(p))) * (0.012 + seed * 0.012) * min(len * 1.5, 1) * sideSign
        let cx = (mascot.x + heart.x) * 0.5 + perpX * arc
        let cy = (mascot.y + heart.y) * 0.5 + perpY * arc

        let ipf = 1 - p
        var x = ipf * ipf * mascot.x + 2 * ipf * p * cx + p * p * heart.x
        var y = ipf * ipf * mascot.y + 2 * ipf * p * cy + p * p * heart.y

        x = 0.5 + (x - 0.5) * heartbeatScale
        y = 0.5 + (y - 0.5) * heartbeatScale

        let diameter: CGFloat = 1.45
        let center = CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        return CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    private func drawParticle(
        in context: inout GraphicsContext,
        rect: CGRect,
        mascot: MascotParticle,
        seed: CGFloat,
        angle: CGFloat
    ) {
        let angleNorm = abs(angle) / .pi
        let delay = seed * 0.06 + angleNorm * 0.04
        let raw = max(0, min((CGFloat(progress) - delay) / (1 - delay), 1))
        let p: Double
        if raw < 0.5 {
            p = 4 * Double(raw) * Double(raw) * Double(raw)
        } else {
            let pp = 2 * Double(raw) - 2
            p = 0.5 * pp * pp * pp + 1
        }

        // crossfade with brief overlap — avoids muddy gray mid-morph
        let mascotOpacity = max(0, 1 - p * 1.9)
        let heartOpacity = max(0, (p - 0.18) / 0.82)
        let heartEased = heartOpacity * heartOpacity * (3 - 2 * heartOpacity)

        if mascotOpacity > 0.015 {
            context.fill(
                Path(ellipseIn: rect),
                with: .color(mascot.color.opacity(mascotOpacity))
            )
        }
        if heartEased > 0.015 {
            context.fill(
                Path(ellipseIn: rect),
                with: .color(heartColor.opacity(heartEased))
            )
        }
    }

    private var heartColor: Color {
        Color(red: 0.96, green: 0.19, blue: 0.26)
    }

    private static func seed(for index: Int) -> CGFloat {
        let mixed = UInt64(index &* 73_856_093) ^ UInt64(index &* 19_349_663)
        return CGFloat(mixed % 1_000) / 1_000
    }
}

private struct MascotParticle {
    let point: CGPoint
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

private enum MascotHeartParticleTargets {
    private static let heartVertexCount = 2_000

    static let mascot: [MascotParticle] = orderedByAngle(makeMascotParticles())
    static let heart: [CGPoint] = orderedByAngle(makeHeartPoints(count: mascot.count))

    private static func makeMascotParticles() -> [MascotParticle] {
        guard let data = Data(base64Encoded: mascotParticleData) else {
            return []
        }

        let bytes = [UInt8](data)
        return stride(from: 0, to: bytes.count, by: 5).map { index in
            MascotParticle(
                point: CGPoint(
                    x: CGFloat(bytes[index]) / 255,
                    y: CGFloat(bytes[index + 1]) / 255
                ),
                red: Double(bytes[index + 2]) / 255,
                green: Double(bytes[index + 3]) / 255,
                blue: Double(bytes[index + 4]) / 255
            )
        }
    }

    // Quantized particle positions and colors sampled from Sol Light's artwork.
    // The animation renders only these particles, never the source image.
    private static let mascotParticleData = """
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
"""

    // MARK: Heart — uniform interior via point-in-polygon + Halton

    private static func makeHeartPoints(count: Int) -> [CGPoint] {
        let outline = makeHeartOutline()
        let outlineCount = min(220, count / 6)
        var points = resampleClosedPolyline(outline, count: outlineCount)
        points.reserveCapacity(count)
        var haltonIndex = 1
        // tight bounding box of heart in normalized 0…1 space (from outline)
        let minX: CGFloat = 0.12, maxX: CGFloat = 0.88
        let minY: CGFloat = 0.18, maxY: CGFloat = 0.95
        while points.count < count {
            let x = minX + halton(haltonIndex, base: 2) * (maxX - minX)
            let y = minY + halton(haltonIndex, base: 3) * (maxY - minY)
            let p = CGPoint(x: x, y: y)
            if isInsidePolygon(p, polygon: outline) {
                points.append(p)
            }
            haltonIndex += 1
            // safety: prevent infinite loop if count unreasonably large
            if haltonIndex > 60_000 { break }
        }
        if points.count < count {
            let needed = count - points.count
            let fallback = resampleClosedPolyline(outline, count: needed)
            points.append(contentsOf: fallback)
        }
        return points
    }

    private static func makeHeartOutline() -> [CGPoint] {
        (0..<heartVertexCount).map { i in
            let a = 2 * Double.pi * Double(i) / Double(heartVertexCount)
            let x = 16 * pow(sin(a), 3)
            let y = 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a)
            return CGPoint(x: 0.5 + x / 42, y: 0.5 - y / 42)
        }
    }

    private static func isInsidePolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            let intersect = ((yi > point.y) != (yj > point.y))
                && (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func orderedByAngle(_ particles: [MascotParticle]) -> [MascotParticle] {
        particles.sorted { lhs, rhs in
            let la = atan2(lhs.point.y - 0.5, lhs.point.x - 0.5)
            let ra = atan2(rhs.point.y - 0.5, rhs.point.x - 0.5)
            if la == ra { return hypot(lhs.point.x - 0.5, lhs.point.y - 0.5) < hypot(rhs.point.x - 0.5, rhs.point.y - 0.5) }
            return la < ra
        }
    }

    private static func orderedByAngle(_ points: [CGPoint]) -> [CGPoint] {
        points.sorted { lhs, rhs in
            let la = atan2(lhs.y - 0.5, lhs.x - 0.5)
            let ra = atan2(rhs.y - 0.5, rhs.x - 0.5)
            if la == ra { return hypot(lhs.x - 0.5, lhs.y - 0.5) < hypot(rhs.x - 0.5, rhs.y - 0.5) }
            return la < ra
        }
    }

    private static func halton(_ index: Int, base: Int) -> CGFloat {
        var r: CGFloat = 0, f: CGFloat = 1, v = index
        while v > 0 { f /= CGFloat(base); r += f * CGFloat(v % base); v /= base }
        return r
    }

    private static func resampleClosedPolyline(_ vertices: [CGPoint], count: Int) -> [CGPoint] {
        guard vertices.count > 1, count > 0 else { return [] }
        let segs = vertices.indices.map { i in
            let n = (i + 1) % vertices.count
            return hypot(vertices[n].x - vertices[i].x, vertices[n].y - vertices[i].y)
        }
        let total = segs.reduce(0, +)
        guard total > 0 else { return Array(repeating: vertices[0], count: count) }
        var pts: [CGPoint] = []
        pts.reserveCapacity(count)
        var segIdx = 0
        var segStart: CGFloat = 0
        for s in 0..<count {
            let target = total * CGFloat(s) / CGFloat(count)
            while segIdx < segs.count - 1, segStart + segs[segIdx] < target {
                segStart += segs[segIdx]; segIdx += 1
            }
            let a = vertices[segIdx], b = vertices[(segIdx + 1) % vertices.count]
            let len = max(segs[segIdx], .leastNonzeroMagnitude)
            let p = (target - segStart) / len
            pts.append(CGPoint(x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p))
        }
        return pts
    }
}

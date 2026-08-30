//
//  MascotHeartParticleMorphView.swift
//  Sorty
//
//  Particle morph from Sorty's mascot into a solid heart.

import SwiftUI

struct MascotHeartParticleMorphView: View {
    private enum Timing {
        static let mascotHold: TimeInterval = 0.5
        static let morphDuration: TimeInterval = 1.15
        static let heartbeatDuration: TimeInterval = 0.44

        static var totalDuration: TimeInterval {
            mascotHold + morphDuration + heartbeatDuration
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStart = Date()
    @State private var animationComplete = false

    // `color` kept for API compat but mascot uses its true palette, not the accent.
    let color: Color

    var body: some View {
        SwiftUI.TimelineView(
            .animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || animationComplete)
        ) { timeline in
            let elapsed = timeline.date.timeIntervalSince(animationStart)
            let progress = reduceMotion || animationComplete ? 1 : morphProgress(at: elapsed)

            ZStack {
                Image(nsImage: SortyResources.menuBarLabelNSImage())
                    .resizable()
                    .scaledToFit()
                    .padding(6)
                    .opacity(mascotOpacity(for: progress))

                ParticleMorphCanvas(
                    progress: progress,
                    heartbeatScale: reduceMotion || animationComplete ? 1 : heartbeatScale(at: elapsed),
                    color: color
                )
                .opacity(particleLayerOpacity(for: progress))
            }
        }
        .task(id: reduceMotion) {
            animationStart = Date()
            animationComplete = reduceMotion
            guard !reduceMotion else { return }

            try? await Task.sleep(for: .seconds(Timing.totalDuration))
            guard !Task.isCancelled else { return }
            animationComplete = true
        }
        .accessibilityHidden(true)
    }

    private func mascotOpacity(for progress: Double) -> Double {
        let fade = min(max(progress / 0.22, 0), 1)
        return 1 - fade * fade * (3 - 2 * fade)
    }

    private func particleLayerOpacity(for progress: Double) -> Double {
        min(max(progress / 0.12, 0), 1)
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

        let t = elapsed - heartStart
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
    let color: Color

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            drawParticles(in: &context, size: size)
        }
    }

    private func drawParticles(in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)

        // Replace the particles with one heart at rest. Drawing both at full
        // opacity made the final color and edges shift as the heart pulsed.
        if progress > 0.82 {
            let t = (progress - 0.82) / 0.18
            let eased = t * t * (3 - 2 * t)
            var particleContext = context
            particleContext.opacity = 1 - eased
            drawParticlesOnly(in: &particleContext, origin: origin, side: side)
            drawSolidHeart(in: &context, size: size, opacity: eased)
        } else {
            drawParticlesOnly(in: &context, origin: origin, side: side)
        }
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
                heart: heart,
                seed: seed,
                angle: angle
            )
        }
    }

    private func drawSolidHeart(in context: inout GraphicsContext, size: CGSize, opacity: Double) {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        // Heart outline in 0…1 space
        var path = Path()
        let count = 400
        for i in 0..<count {
            let a = 2 * Double.pi * Double(i) / Double(count)
            let x = 16 * pow(sin(a), 3)
            let y = 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a)
            var px = 0.5 + x / 42
            var py = 0.5 - y / 42
            px = 0.5 + (px - 0.5) * heartbeatScale
            py = 0.5 + (py - 0.5) * heartbeatScale
            let p = CGPoint(x: origin.x + px * side, y: origin.y + py * side)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 0.96, green: 0.19, blue: 0.26).opacity(opacity)))
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

        let diameter = 1.4 + seed * 1.0
        let center = CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        return CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
    }

    private func drawParticle(
        in context: inout GraphicsContext,
        rect: CGRect,
        mascot: MascotParticle,
        heart: CGPoint,
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
                with: .color(mascotColor(for: mascot.role, seed: seed).opacity(mascotOpacity))
            )
        }
        if heartEased > 0.015 {
            context.fill(
                Path(ellipseIn: rect),
                with: .color(heartColor(at: heart, seed: seed).opacity(heartEased))
            )
        }
    }

    private func mascotColor(for role: MascotParticleRole, seed: CGFloat) -> Color {
        switch role {
        case .shell:
            // sampled Sorty shell mid-blue
            return Color(red: 0.42, green: 0.76, blue: 0.94).opacity(0.92 + Double(seed) * 0.08)
        case .face:
            // visor / inner face — near-white cyan
            return Color(red: 0.78, green: 0.96, blue: 0.99).opacity(0.96)
        case .edge:
            return Color(red: 0.06, green: 0.14, blue: 0.28).opacity(0.95)
        case .eye:
            return Color(red: 0.04, green: 0.09, blue: 0.18)
        case .highlight:
            return .white.opacity(0.92)
        }
    }

    private func heartColor(at point: CGPoint, seed: CGFloat) -> Color {
        // Uniform filled red — no white speckles. Slight vertical depth for richness.
        let t = min(max((point.y - 0.20) / 0.68, 0), 1)
        let r = 0.96 - Double(t) * 0.12
        let g = 0.17 + (1 - Double(t)) * 0.03
        let b = 0.23 + (1 - Double(t)) * 0.02
        _ = seed // keep param for API compat
        _ = point
        return Color(red: r, green: g, blue: b)
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
        particles += makeParticles(filledRoundedRectangle(rect: shellRect, radius: 5.5, count: 340), role: .shell)
        particles += makeParticles(roundedRectangleOutline(rect: shellRect, radius: 5.5, count: 140), role: .edge)
        particles += makeParticles(filledRoundedRectangle(rect: faceRect, radius: 3.8, count: 260), role: .face)
        particles += makeParticles(filledCircle(center: leftEar, radius: 2.2, count: 48), role: .shell)
        particles += makeParticles(filledCircle(center: rightEar, radius: 2.2, count: 48), role: .shell)
        particles += makeParticles(circle(center: leftEar, radius: 2.2, count: 22), role: .edge)
        particles += makeParticles(circle(center: rightEar, radius: 2.2, count: 22), role: .edge)
        particles += makeParticles(quadraticCurve(from: CGPoint(x: 10.6, y: 6.1), control: CGPoint(x: 10.6, y: 4), to: CGPoint(x: 11, y: 2), count: 28), role: .edge)
        particles += makeParticles(filledCircle(center: CGPoint(x: 11, y: 1.8), radius: 1.65, count: 44), role: .shell)
        particles += makeParticles(circle(center: CGPoint(x: 11, y: 1.8), radius: 1.65, count: 20), role: .edge)
        particles += makeParticles(filledRoundedRectangle(rect: CGRect(x: 8.1, y: 5.5, width: 5.8, height: 2.5), radius: 1.1, count: 40), role: .shell)
        particles += makeParticles(roundedRectangleOutline(rect: CGRect(x: 8.1, y: 5.5, width: 5.8, height: 2.5), radius: 1.1, count: 24), role: .highlight)
        particles += makeParticles(filledCircle(center: CGPoint(x: 8, y: 11.6), radius: 1.75, count: 54), role: .eye)
        particles += makeParticles(filledCircle(center: CGPoint(x: 14, y: 11.6), radius: 1.75, count: 54), role: .eye)
        particles += makeParticles(filledCircle(center: CGPoint(x: 7.55, y: 11.1), radius: 0.55, count: 14), role: .highlight)
        particles += makeParticles(filledCircle(center: CGPoint(x: 13.55, y: 11.1), radius: 0.55, count: 14), role: .highlight)
        particles += makeParticles(quadraticCurve(from: CGPoint(x: 8.1, y: 14.6), control: CGPoint(x: 11, y: 17.1), to: CGPoint(x: 13.9, y: 14.6), count: 64), role: .edge)
        return particles
    }

    private static func makeParticles(_ points: [CGPoint], role: MascotParticleRole) -> [MascotParticle] {
        points.map { MascotParticle(point: normalizeMascotPoint($0), role: role) }
    }

    // MARK: Heart — uniform interior via point-in-polygon + Halton

    private static func makeHeartPoints(count: Int) -> [CGPoint] {
        let outline = makeHeartOutline()
        var points: [CGPoint] = []
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
        // fill remainder with outline resample if sampling fell short (should not happen)
        if points.count < count {
            let needed = count - points.count
            let fallback = resampleClosedPolyline(outline, count: needed)
            points.append(contentsOf: fallback.map { CGPoint(x: $0.x, y: $0.y) })
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

    private static func normalizeMascotPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 0.05 + (point.x / viewBoxSize) * 0.9, y: 0.04 + (point.y / viewBoxSize) * 0.9)
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

    private static func filledRoundedRectangle(rect: CGRect, radius: CGFloat, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        var idx = 1
        while points.count < count {
            let p = CGPoint(x: rect.minX + halton(idx, base: 2) * rect.width, y: rect.minY + halton(idx, base: 3) * rect.height)
            if isInsideRoundedRectangle(p, rect: rect, radius: radius) { points.append(p) }
            idx += 1
        }
        return points
    }

    private static func isInsideRoundedRectangle(_ point: CGPoint, rect: CGRect, radius: CGFloat) -> Bool {
        if point.x >= rect.minX + radius, point.x <= rect.maxX - radius { return true }
        if point.y >= rect.minY + radius, point.y <= rect.maxY - radius { return true }
        let corner = CGPoint(x: point.x < rect.midX ? rect.minX + radius : rect.maxX - radius, y: point.y < rect.midY ? rect.minY + radius : rect.maxY - radius)
        return hypot(point.x - corner.x, point.y - corner.y) <= radius
    }

    private static func halton(_ index: Int, base: Int) -> CGFloat {
        var r: CGFloat = 0, f: CGFloat = 1, v = index
        while v > 0 { f /= CGFloat(base); r += f * CGFloat(v % base); v /= base }
        return r
    }

    private static func filledCircle(center: CGPoint, radius: CGFloat, count: Int) -> [CGPoint] {
        let golden = Double.pi * (3 - sqrt(5))
        return (0..<count).map { i in
            let d = radius * sqrt((CGFloat(i) + 0.5) / CGFloat(count))
            let a = Double(i) * golden
            return CGPoint(x: center.x + CGFloat(cos(a)) * d, y: center.y + CGFloat(sin(a)) * d)
        }
    }

    private static func circle(center: CGPoint, radius: CGFloat, count: Int) -> [CGPoint] {
        (0..<count).map { i in
            let a = 2 * Double.pi * Double(i) / Double(count) - .pi / 2
            return CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
        }
    }

    private static func quadraticCurve(from s: CGPoint, control c: CGPoint, to e: CGPoint, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let d = CGFloat(max(count - 1, 1))
        return (0..<count).map { i in
            let t = CGFloat(i) / d, u = 1 - t
            return CGPoint(x: u*u*s.x + 2*u*t*c.x + t*t*e.x, y: u*u*s.y + 2*u*t*c.y + t*t*e.y)
        }
    }

    private static func roundedRectangleOutline(rect: CGRect, radius: CGFloat, count: Int) -> [CGPoint] {
        let l = rect.minX, r = rect.maxX, t = rect.minY, b = rect.maxY
        let steps = 20
        var v: [CGPoint] = [CGPoint(x: l + radius, y: t), CGPoint(x: r - radius, y: t)]
        v += arc(center: CGPoint(x: r - radius, y: t + radius), radius: radius, from: -.pi/2, to: 0, steps: steps)
        v.append(CGPoint(x: r, y: b - radius))
        v += arc(center: CGPoint(x: r - radius, y: b - radius), radius: radius, from: 0, to: .pi/2, steps: steps)
        v.append(CGPoint(x: l + radius, y: b))
        v += arc(center: CGPoint(x: l + radius, y: b - radius), radius: radius, from: .pi/2, to: .pi, steps: steps)
        v.append(CGPoint(x: l, y: t + radius))
        v += arc(center: CGPoint(x: l + radius, y: t + radius), radius: radius, from: .pi, to: .pi*1.5, steps: steps)
        return resampleClosedPolyline(v, count: count)
    }

    private static func arc(center: CGPoint, radius: CGFloat, from s: Double, to e: Double, steps: Int) -> [CGPoint] {
        (1...steps).map { st in
            let p = Double(st) / Double(steps)
            let a = s + (e - s) * p
            return CGPoint(x: center.x + CGFloat(cos(a)) * radius, y: center.y + CGFloat(sin(a)) * radius)
        }
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

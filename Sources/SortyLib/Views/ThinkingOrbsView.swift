import SwiftUI

// MARK: - Model

private enum ThinkingOrbState: String, CaseIterable, Identifiable {
    case working
    case searching
    case solving
    case listening
    case composing
    case shaping

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var summary: String {
        switch self {
        case .working: "Particles on tilted orbits"
        case .searching: "A scan meridian sweeps a dotted globe"
        case .solving: "Bands scramble, then settle back into place"
        case .listening: "A waveform rolls through the rings"
        case .composing: "An undulating multi-band sash"
        case .shaping: "Circle, triangle, and square morph together"
        }
    }
}

private struct OrbDot {
    let point: CGPoint
    let depth: CGFloat
    let radius: CGFloat
    var opacity: Double = 1
}

// MARK: - Main View

public struct ThinkingOrbsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thinking Orbs")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Six dotted activity states, rendered natively in SwiftUI.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())],
                    spacing: 16
                ) {
                    ForEach(ThinkingOrbState.allCases) { state in
                        orbCard(state)
                    }
                }

                Link(destination: URL(string: "https://github.com/Jakubantalik/thinking-orbs")!) {
                    Label("Inspired by Jakub Antalik’s thinking-orbs", systemImage: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 680, minHeight: 520)
    }

    private func orbCard(_ state: ThinkingOrbState) -> some View {
        HStack(spacing: 20) {
            ThinkingOrb(state: state, isDark: colorScheme == .dark, reduceMotion: reduceMotion)
                .frame(width: 96, height: 96)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(state.title) activity indicator")

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.headline)
                Text(state.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.08))
        )
    }
}

/// Faithful port of the dotted-globe orb from Jakub Antalik's thinking-orbs
/// (`drawGlobe`, the "searching" state): a tilted, spinning sphere of dots with
/// a Gaussian scan meridian sweeping the front hemisphere. Renders at actual
/// size with the upstream sub-linear radius scaling, so it stays crisp small.
public struct ThinkingOrbLoaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
            let raw = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
            let isDark = colorScheme == .dark
            Canvas(rendersAsynchronously: true) { context, size in
                Self.drawGlobe(context: &context, size: size, rawTime: raw, dark: isDark)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Thinking activity indicator")
    }

    private static func drawGlobe(
        context: inout GraphicsContext,
        size: CGSize,
        rawTime: TimeInterval,
        dark: Bool
    ) {
        let s = min(size.width, size.height)
        guard s > 0 else { return }

        // Interpolate between the upstream 20px and 64px preset constants
        // so density and dot size track the rendered size like the original.
        let f = min(1, max(0, (s - 20) / 44))
        // 0.65× the upstream preset speed; full speed felt frantic inline.
        let speed: CGFloat = (2.665 + f * (2.015 - 2.665)) * 0.65
        let latRings = Int((6 + f * (11 - 6)).rounded())
        let lonDensity: CGFloat = 14 + f * (29 - 14)
        let rBase: CGFloat = 1.05 + f * (0.69 - 1.05)
        let rDepth: CGFloat = 2.975 + f * (1.955 - 2.975)
        let scanMul: CGFloat = 4.335 + f * (4.08 - 4.335)
        let dimBase: CGFloat = 0.45
        let inkFar: CGFloat = 0.62
        let inkSpan: CGFloat = 0.54
        let rMin: CGFloat = 0.3

        let t = CGFloat(rawTime) * speed
        let spin: CGFloat = 0.5
        let cx = size.width / 2
        let cy = size.height / 2
        let radius = (s / 2) * 0.82
        let tilt = 0.4 + 0.06 * sin(t * 0.35)
        let scan = t * (spin + (1.7 - spin) * scanMul)
        let rs = pow(s / 300, 0.6)

        let st = sin(tilt), ct = cos(tilt)
        let sy = sin(t * spin), cyw = cos(t * spin)

        struct Dot {
            let x, y, z, r: CGFloat
            let white: CGFloat
            let alpha: CGFloat
        }
        var dots: [Dot] = []

        for li in 0...latRings {
            let lat = -CGFloat.pi / 2 + CGFloat(li) / CGFloat(latRings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = CGFloat(lj) / CGFloat(lonCount) * 2 * .pi
                let x = cosLat * cos(lon)
                let y = sinLat
                let z = cosLat * sin(lon)

                // Yaw around Y, then tilt around X, orthographic projection.
                let x1 = x * cyw + z * sy
                let z1 = -x * sy + z * cyw
                let y1 = y * ct - z1 * st
                let z2 = y * st + z1 * ct

                let depth = (z2 + 1) / 2

                // Scan meridian: Gaussian in shortest angular distance,
                // limited to the front hemisphere.
                let a = lon + t * spin - scan
                let d = atan2(sin(a), cos(a))
                let boost = exp(-(d * d) / 0.18) * max(0, z2)

                dots.append(
                    Dot(
                        x: cx + x1 * radius,
                        y: cy - y1 * radius,
                        z: z2,
                        r: max(rMin, (rBase + rDepth * depth + boost) * rs),
                        white: inkFar - inkSpan * depth,
                        alpha: dimBase + (1 - dimBase) * min(1, boost)
                    )
                )
            }
        }

        dots.sort { $0.z < $1.z }
        for dot in dots where dot.alpha >= 0.02 {
            let w = min(1, max(0, dot.white))
            let gray = dark ? 1 - w : w
            let rect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .color(Color(white: gray).opacity(dot.alpha))
            )
        }
    }
}

private struct ThinkingOrb: View {
    let state: ThinkingOrbState
    let isDark: Bool
    let reduceMotion: Bool

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 1.25 : timeline.date.timeIntervalSinceReferenceDate
            Canvas(rendersAsynchronously: true) { context, size in
                let dots = OrbRenderer.dots(for: state, size: size, time: time)
                    .sorted { $0.depth < $1.depth }
                for dot in dots {
                    let depthOpacity = 0.34 + Double(dot.depth) * 0.66
                    let color = isDark ? Color.white : Color.black
                    let rect = CGRect(
                        x: dot.point.x - dot.radius,
                        y: dot.point.y - dot.radius,
                        width: dot.radius * 2,
                        height: dot.radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(color.opacity(dot.opacity * depthOpacity))
                    )
                }
            }
        }
    }
}

// MARK: - Supporting Shapes

private enum OrbRenderer {
    static func dots(for state: ThinkingOrbState, size: CGSize, time: TimeInterval) -> [OrbDot] {
        let side = min(size.width, size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let t = CGFloat(time)
        return switch state {
        case .working: working(center: center, radius: side * 0.39, time: t)
        case .searching: lattice(center: center, radius: side * 0.39, time: t, mode: .searching)
        case .solving: lattice(center: center, radius: side * 0.39, time: t, mode: .solving)
        case .listening: lattice(center: center, radius: side * 0.39, time: t, mode: .listening)
        case .composing: composing(center: center, radius: side * 0.38, time: t)
        case .shaping: shaping(center: center, radius: side * 0.42, time: t)
        }
    }

    private enum LatticeMode { case searching, solving, listening }

    private static func working(center: CGPoint, radius: CGFloat, time: CGFloat) -> [OrbDot] {
        var dots: [OrbDot] = []
        for orbit in 0..<7 {
            let seed = CGFloat(orbit)
            let tilt = 0.28 + seed * 0.19
            let orbitRadius = radius * (0.52 + hash(seed * 2.7) * 0.42)
            for index in 0..<24 {
                let angle = CGFloat(index) / 24 * .pi * 2
                let point = projectedCircle(angle: angle, radius: orbitRadius, tilt: tilt, rotation: seed * 0.7, center: center)
                dots.append(OrbDot(point: point.point, depth: point.depth, radius: 0.75, opacity: 0.22))
            }
            for particle in 0..<2 {
                let direction: CGFloat = orbit.isMultiple(of: 2) ? 1 : -1
                let angle = time * (0.65 + hash(seed) * 0.65) * direction + CGFloat(particle) * .pi + seed
                let point = projectedCircle(angle: angle, radius: orbitRadius, tilt: tilt, rotation: seed * 0.7, center: center)
                dots.append(OrbDot(point: point.point, depth: point.depth, radius: 1.5 + point.depth * 1.25))
            }
        }
        return dots
    }

    private static func lattice(
        center: CGPoint,
        radius: CGFloat,
        time: CGFloat,
        mode: LatticeMode
    ) -> [OrbDot] {
        var dots: [OrbDot] = []
        let ringCount = 11
        for ring in 0...ringCount {
            let latitude = -.pi / 2 + CGFloat(ring) / CGFloat(ringCount) * .pi
            let wave: CGFloat = mode == .listening
                ? sin(time * 2.1 - CGFloat(ring) * 0.62) * 0.10
                : 0
            let ringRadius = cos(latitude) * radius * (1 + wave)
            let y = sin(latitude) * radius * (1 + wave)
            let count = max(4, Int(abs(cos(latitude)) * 30))
            for index in 0..<count {
                var longitude = CGFloat(index) / CGFloat(count) * .pi * 2 + time * 0.22
                if mode == .solving {
                    let phase = (time * 0.7).truncatingRemainder(dividingBy: 4)
                    let band = CGFloat(ring / 3)
                    longitude += sin(phase * .pi) * band * 0.15
                }
                let x = cos(longitude) * ringRadius
                let z = sin(longitude) * ringRadius
                let depth = (z / radius + 1) / 2
                let scan = abs(wrappedAngle(longitude - time * 1.8))
                let scanBoost = mode == .searching ? exp(-scan * scan / 0.08) : 0
                dots.append(
                    OrbDot(
                        point: CGPoint(x: center.x + x, y: center.y + y),
                        depth: depth,
                        radius: 0.7 + depth * 1.25 + scanBoost * 1.1,
                        opacity: mode == .searching ? 0.45 + Double(scanBoost) * 0.55 : 1
                    )
                )
            }
        }
        return dots
    }

    private static func composing(center: CGPoint, radius: CGFloat, time: CGFloat) -> [OrbDot] {
        var dots: [OrbDot] = []
        for lane in 0..<9 {
            let laneOffset = (CGFloat(lane) - 4) * radius * 0.035
            for index in 0..<38 {
                let angle = CGFloat(index) / 38 * .pi * 2
                let wobble = sin(angle * 3 - time * 1.7 + CGFloat(lane) * 0.22) * radius * 0.12
                let x = cos(angle) * radius
                let y = sin(angle) * radius * 0.55 + laneOffset + wobble
                let depth = (sin(angle) + 1) / 2
                dots.append(OrbDot(point: CGPoint(x: center.x + x, y: center.y + y), depth: depth, radius: 0.8 + depth * 1.25))
            }
        }
        return dots
    }

    private static func shaping(center: CGPoint, radius: CGFloat, time: CGFloat) -> [OrbDot] {
        let segmentDuration: CGFloat = 2.3
        let phase = time.truncatingRemainder(dividingBy: segmentDuration * 3) / segmentDuration
        let shapeIndex = Int(phase.rounded(.down))
        let local = phase - CGFloat(shapeIndex)
        let progress = local < 0.6 ? 0 : smooth((local - 0.6) / 0.4)
        return (0..<34).map { index in
            let fraction = CGFloat(index) / 34
            let first = shapePoint(index: shapeIndex, fraction: fraction)
            let second = shapePoint(index: (shapeIndex + 1) % 3, fraction: fraction)
            let point = CGPoint(
                x: center.x + (first.x + (second.x - first.x) * progress) * radius,
                y: center.y + (first.y + (second.y - first.y) * progress) * radius
            )
            return OrbDot(point: point, depth: 0.75, radius: 1.55)
        }
    }

    private static func shapePoint(index: Int, fraction: CGFloat) -> CGPoint {
        switch index {
        case 0:
            let angle = -.pi / 2 + fraction * .pi * 2
            return CGPoint(x: cos(angle) * 0.72, y: sin(angle) * 0.72)
        case 1:
            return polygonPoint(vertices: [CGPoint(x: 0, y: -0.82), CGPoint(x: 0.72, y: 0.55), CGPoint(x: -0.72, y: 0.55)], fraction: fraction)
        default:
            return polygonPoint(vertices: [CGPoint(x: 0, y: -0.68), CGPoint(x: 0.68, y: -0.68), CGPoint(x: 0.68, y: 0.68), CGPoint(x: -0.68, y: 0.68), CGPoint(x: -0.68, y: -0.68)], fraction: fraction)
        }
    }

    private static func polygonPoint(vertices: [CGPoint], fraction: CGFloat) -> CGPoint {
        let scaled = fraction * CGFloat(vertices.count)
        let index = min(Int(scaled), vertices.count - 1)
        let next = (index + 1) % vertices.count
        let local = scaled - CGFloat(index)
        return CGPoint(
            x: vertices[index].x + (vertices[next].x - vertices[index].x) * local,
            y: vertices[index].y + (vertices[next].y - vertices[index].y) * local
        )
    }

    private static func projectedCircle(
        angle: CGFloat,
        radius: CGFloat,
        tilt: CGFloat,
        rotation: CGFloat,
        center: CGPoint
    ) -> (point: CGPoint, depth: CGFloat) {
        let x = cos(angle) * radius
        let y = sin(angle) * radius * sin(tilt)
        let z = sin(angle) * cos(tilt)
        let rotatedX = x * cos(rotation) - y * sin(rotation)
        let rotatedY = x * sin(rotation) + y * cos(rotation)
        return (CGPoint(x: center.x + rotatedX, y: center.y + rotatedY), (z + 1) / 2)
    }

    private static func hash(_ value: CGFloat) -> CGFloat {
        abs(sin(value * 127.1) * 43758.5453).truncatingRemainder(dividingBy: 1)
    }

    private static func wrappedAngle(_ angle: CGFloat) -> CGFloat {
        atan2(sin(angle), cos(angle))
    }

    private static func smooth(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

// MARK: - Preview

#Preview("Thinking Orbs") {
    ThinkingOrbsView()
        .frame(width: 760, height: 600)
}

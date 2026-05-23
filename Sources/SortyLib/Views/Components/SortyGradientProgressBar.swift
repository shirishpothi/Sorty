//
//  SortyGradientProgressBar.swift
//  Sorty
//
//  Reusable progress indicators with gradient fills.
//

import SwiftUI

// MARK: - Private helpers

private struct SortyGradientRingSegment: View {
    let accent: Color
    let lineWidth: CGFloat
    let start: Double
    let end: Double

    var body: some View {
        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: start, to: end)
            .stroke(
                SortyBeamPalette.arcGradient,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: accent.opacity(0.24), radius: lineWidth * 1.25)
    }
}

private enum SortyBeamPalette {
    static let primary = Color(red: 0.20, green: 0.78, blue: 0.38)
    static let warm = primary
    static let cool = primary

    static var trackFill: some ShapeStyle {
        Color.white.opacity(0.055)
    }

    static var trackStroke: some ShapeStyle {
        LinearGradient(
            colors: [.white.opacity(0.18), .white.opacity(0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var barGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: primary.opacity(0.88), location: 0.0),
                .init(color: primary.opacity(0.98), location: 0.48),
                .init(color: primary.opacity(0.90), location: 1.0),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    static var arcGradient: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: primary.opacity(0.24), location: 0.48),
                .init(color: primary.opacity(0.70), location: 0.76),
                .init(color: primary.opacity(0.94), location: 0.92),
                .init(color: primary.opacity(0.98), location: 1.0),
            ],
            center: .center
        )
    }
}

// MARK: - SortyGradientProgressBar

struct SortyGradientProgressBar: View {
    let progress: Double
    var accent: Color = SortyDesignSystem.Colors.resolvedAccent
    var height: CGFloat = 10
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(SortyBeamPalette.trackFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(SortyBeamPalette.trackStroke, lineWidth: 1)
                    )

                if clampedProgress > 0 {
                    let fillWidth = max(height, geo.size.width * clampedProgress)

                    Capsule(style: .continuous)
                        .fill(SortyBeamPalette.barGradient)
                        .overlay(
                            Capsule(style: .continuous)
                                .inset(by: max(1, height * 0.14))
                                .fill(.white.opacity(0.18))
                                .frame(height: max(1.5, height * 0.20)),
                            alignment: .top
                        )
                        .frame(width: fillWidth)
                        .shadow(color: SortyBeamPalette.primary.opacity(0.22), radius: height * 0.65, x: 0, y: 0)
                        .shadow(color: SortyBeamPalette.primary.opacity(0.16), radius: height * 1.05, x: 0, y: 0)
                }
            }
            .clipShape(Capsule(style: .continuous))
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.25), value: clampedProgress)
    }
}

// MARK: - SortyGradientLoadingBar

struct SortyGradientLoadingBar: View {
    var accent: Color = SortyDesignSystem.Colors.resolvedAccent
    var width: CGFloat = 150
    var height: CGFloat = 10
    var segmentWidthRatio: CGFloat = 0.34

    @State private var travelPhase: CGFloat = 0

    private var clampedSegmentRatio: CGFloat {
        min(max(segmentWidthRatio, 0.15), 0.75)
    }

    var body: some View {
        GeometryReader { geo in
            let segmentWidth = geo.size.width * clampedSegmentRatio
            let travelDistance = geo.size.width + segmentWidth

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(SortyBeamPalette.trackFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(SortyBeamPalette.trackStroke, lineWidth: 1)
                    )

                Capsule(style: .continuous)
                    .fill(SortyBeamPalette.barGradient)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(SortyBeamPalette.primary.opacity(0.16))
                    )
                    .frame(width: segmentWidth)
                    .offset(x: (travelPhase * travelDistance) - segmentWidth)
                    .shadow(color: SortyBeamPalette.cool.opacity(0.42), radius: 7, x: 0, y: 0)
            }
            .clipShape(Capsule(style: .continuous))
        }
        .frame(width: width, height: height)
        .onAppear {
            travelPhase = 0
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                travelPhase = 1
            }
        }
    }
}

// MARK: - SortyGradientCircularProgress

struct SortyGradientCircularProgress: View {
    let progress: Double
    var accent: Color = SortyDesignSystem.Colors.resolvedAccent
    var size: CGFloat = 80
    var lineWidth: CGFloat = 8
    var showsShimmer: Bool = false

    @State private var animatedProgress: Double = 0

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(SortyBeamPalette.trackFill, lineWidth: lineWidth)

            if animatedProgress > 0 {
                SortyGradientRingSegment(
                    accent: accent,
                    lineWidth: lineWidth,
                    start: 0,
                    end: animatedProgress
                )
            }

            if showsShimmer {
                SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let elapsed = context.date.timeIntervalSinceReferenceDate
                    let arcSpan = animatedProgress * 360
                    let phase = (elapsed * 120).truncatingRemainder(
                        dividingBy: arcSpan.isZero ? 360 : arcSpan)
                    let shimmerCenter = phase / max(arcSpan, 1)
                    let pulse = (sin(elapsed * 1.8) + 1) * 0.5
                    let peakOpacity = 0.35 + (pulse * 0.25)
                    let glowOpacity = 0.10 + (pulse * 0.10)
                    let highlightWidth: Double = 0.12

                    let trimStart = max(shimmerCenter - highlightWidth, 0) * animatedProgress
                    let trimEnd = min(shimmerCenter + highlightWidth, 1) * animatedProgress

                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: trimStart, to: trimEnd)
                        .stroke(
                            SortyBeamPalette.primary.opacity(peakOpacity),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 2)
                        .blendMode(.plusLighter)

                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0, to: animatedProgress)
                        .stroke(
                            accent.opacity(glowOpacity),
                            style: StrokeStyle(lineWidth: lineWidth + 4, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .blur(radius: lineWidth * 0.8)
                        .blendMode(.plusLighter)
                }
                .drawingGroup(opaque: false)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                animatedProgress = clampedProgress
            }
        }
        .onChange(of: clampedProgress) { _, newValue in
            withAnimation(.easeOut(duration: 0.25)) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - SortyGradientCircularTrackProgress

/// Large circular progress ring with a gradient arc that fades from near-invisible
/// at the tail to a bright, glowing tip at the leading edge.
///
/// Key design notes:
///  - The arc starts at 12 o'clock and sweeps CW, achieved via `.rotationEffect(-90°)`.
///  - `AngularGradient` stop *locations* map directly to fractional positions around
///    the full circle (0 = 12 o'clock after rotation, 1 = full revolution back to 12).
///    Setting `location: animatedProgress` targets the exact arc tip, so the bright
///    colour always sits at the leading edge regardless of the current value.
///  - The head-dot orbits from 12 o'clock using `rotationEffect(.degrees(p * 360))`.
///    The old formula `(p * 360) - 90` was off by 90° and placed the dot at the tail.
struct SortyGradientCircularTrackProgress: View {
    let progress: Double
    var accent: Color = SortyDesignSystem.Colors.resolvedAccent
    var size: CGFloat = 120
    var lineWidth: CGFloat = 10
    var isIndeterminate: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let segmentSpan = 0.24
            let phase =
                (elapsed * 0.68).truncatingRemainder(dividingBy: 1.0 + segmentSpan) - segmentSpan
            let segments = wrappedSegments(from: phase, to: phase + segmentSpan)

            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(SortyBeamPalette.trackFill, lineWidth: lineWidth)

                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(SortyBeamPalette.trackStroke, lineWidth: 1)

                if isIndeterminate {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        cometArc(from: seg.lowerBound, to: seg.upperBound)
                    }
                } else if animatedProgress > 0 {
                    progressLayer(p: animatedProgress)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { animatedProgress = clampedProgress }
        .onChange(of: clampedProgress) { _, newValue in
            withAnimation(.easeInOut(duration: 0.28)) {
                animatedProgress = newValue
            }
        }
    }

    // MARK: Determinate arc

    @ViewBuilder
    private func progressLayer(p: Double) -> some View {
        let safeP = max(p, 0.005)
        // As progress nears 1.0, the transparent tail fills in so the ring visually closes completely.
        let tailFill = max(0.0, (safeP - 0.9) / 0.1)
        let baseOpacity = 0.20 + (tailFill * 0.14)
        let highlightSpan = min(max(0.18, safeP * 0.48), safeP)
        let highlightStart = max(0, safeP - highlightSpan)
        let highlightStops: [Gradient.Stop] = [
            .init(color: .clear, location: highlightStart),
            .init(color: SortyBeamPalette.primary.opacity(0.28), location: highlightStart + (highlightSpan * 0.34)),
            .init(color: SortyBeamPalette.primary.opacity(0.72), location: highlightStart + (highlightSpan * 0.70)),
            .init(color: SortyBeamPalette.primary.opacity(0.94), location: highlightStart + (highlightSpan * 0.90)),
            .init(color: SortyBeamPalette.primary.opacity(0.98), location: safeP),
        ]

        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: safeP)
            .stroke(
                SortyBeamPalette.primary.opacity(baseOpacity),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
            .rotationEffect(.degrees(-90))

        Circle()
            .inset(by: lineWidth / 2)
            .trim(from: highlightStart, to: safeP)
            .stroke(
                AngularGradient(stops: highlightStops, center: .center),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
            .rotationEffect(.degrees(-90))

        progressHead(progress: safeP)
    }

    @ViewBuilder
    private func progressHead(progress p: Double) -> some View {
        let d = lineWidth * 1.3
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        SortyBeamPalette.primary.opacity(0.98),
                        SortyBeamPalette.primary.opacity(0.62),
                        SortyBeamPalette.primary.opacity(0.18),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: d * 0.60
                )
            )
            .frame(width: d, height: d)
            // Layered shadows build a soft circular glow with no arc artefacts.
            // Shadows render outside the view frame, so they're never hard-clipped.
            .shadow(color: SortyBeamPalette.primary.opacity(0.56), radius: lineWidth * 0.25)
            .shadow(color: SortyBeamPalette.cool.opacity(0.90), radius: lineWidth * 0.70)
            .shadow(color: SortyBeamPalette.warm.opacity(0.65), radius: lineWidth * 1.60)
            .shadow(color: SortyBeamPalette.warm.opacity(0.28), radius: lineWidth * 3.50)
            .offset(y: -(size / 2) + (lineWidth / 2))
            .rotationEffect(.degrees(p * 360))
    }

    // MARK: Indeterminate comet

    @ViewBuilder
    private func cometArc(from start: Double, to end: Double) -> some View {
        if end > start {
            let arcLen = end - start
            let stops: [Gradient.Stop] = [
                .init(color: .clear, location: start),
                .init(color: SortyBeamPalette.primary.opacity(0.34), location: start + arcLen * 0.50),
                .init(color: SortyBeamPalette.primary.opacity(0.78), location: start + arcLen * 0.84),
                .init(color: SortyBeamPalette.primary.opacity(0.98), location: end),
            ]

            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: start, to: end)
                .stroke(
                    AngularGradient(stops: stops, center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            let d = lineWidth * 1.2
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            SortyBeamPalette.primary.opacity(0.98),
                            SortyBeamPalette.primary.opacity(0.62),
                            SortyBeamPalette.primary.opacity(0.18),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: d * 0.60
                    )
                )
                .frame(width: d, height: d)
                .shadow(color: SortyBeamPalette.primary.opacity(0.56), radius: lineWidth * 0.25)
                .shadow(color: SortyBeamPalette.cool.opacity(0.90), radius: lineWidth * 0.70)
                .shadow(color: SortyBeamPalette.warm.opacity(0.65), radius: lineWidth * 1.60)
                .shadow(color: SortyBeamPalette.warm.opacity(0.28), radius: lineWidth * 3.50)
                .offset(y: -(size / 2) + (lineWidth / 2))
                .rotationEffect(.degrees(end * 360))
        }
    }

    // MARK: Helpers

    private func wrappedSegments(from start: Double, to end: Double) -> [ClosedRange<Double>] {
        if start >= 0, end <= 1 { return [max(start, 0)...min(end, 1)] }
        if start < 0 { return [0...min(end, 1), max(0, 1 + start)...1] }
        if end > 1 { return [max(start, 0)...1, 0...(end - 1)] }
        return []
    }
}

// MARK: - SortyGradientCircularLoader

/// Compact spinning loader. Uses the same tail-to-tip gradient strategy as
/// `SortyGradientCircularTrackProgress` so both components share a consistent look.
struct SortyGradientCircularLoader: View {
    var accent: Color = SortyDesignSystem.Colors.resolvedAccent
    var size: CGFloat = 18
    var lineWidth: CGFloat = 3

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let rotation = reduceMotion ? 0 : (time * 280).truncatingRemainder(dividingBy: 360)
            let pulse = (sin(time * 2.2) + 1) * 0.5
            let sweep = 0.24 + (0.34 * pulse)
            let trailEnd = 0.06 + ((1 - pulse) * 0.08)
            let leadEnd = min(trailEnd + sweep, 0.97)
            let arcLen = leadEnd - trailEnd

            let stops: [Gradient.Stop] = [
                .init(color: .clear, location: trailEnd),
                .init(color: SortyBeamPalette.primary.opacity(0.34), location: trailEnd + arcLen * 0.50),
                .init(color: SortyBeamPalette.primary.opacity(0.78), location: trailEnd + arcLen * 0.84),
                .init(color: SortyBeamPalette.primary.opacity(0.98), location: leadEnd),
            ]

            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(SortyBeamPalette.trackFill, lineWidth: lineWidth)

                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: trailEnd, to: leadEnd)
                    .stroke(
                        AngularGradient(stops: stops, center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation - 90))
                    .shadow(color: SortyBeamPalette.cool.opacity(0.48), radius: lineWidth * 1.2, x: 0, y: 0)
            }
        }
        .frame(width: size, height: size)
        .drawingGroup(opaque: false)
    }
}

// MARK: - Previews

#Preview("Gradient Progress Bar") {
    VStack(spacing: 20) {
        Group {
            SortyGradientProgressBar(progress: 0.78, accent: .indigo)
            SortyGradientProgressBar(progress: 0.45, accent: .blue)
            SortyGradientProgressBar(progress: 0.2, accent: .pink)
            SortyGradientLoadingBar()
        }

        Divider().opacity(0.3)

        HStack(spacing: 32) {
            VStack(spacing: 8) {
                SortyGradientCircularProgress(progress: 0.74)
                Text("Simple").font(.caption2).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ZStack {
                    SortyGradientCircularTrackProgress(
                        progress: 0.22,
                        accent: .accentColor,
                        size: 120,
                        lineWidth: 10
                    )
                    VStack(spacing: 2) {
                        Text("22%")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                        Text("2s")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Track").font(.caption2).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ZStack {
                    SortyGradientCircularTrackProgress(
                        progress: 0,
                        accent: .accentColor,
                        size: 80,
                        lineWidth: 8,
                        isIndeterminate: true
                    )
                }
                Text("Indeterminate").font(.caption2).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                SortyGradientCircularLoader(size: 32, lineWidth: 4)
                Text("Loader").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
    .padding(28)
    .background(
        LinearGradient(
            colors: [.black, Color(red: 0.08, green: 0.10, blue: 0.16)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .frame(width: 480)
}

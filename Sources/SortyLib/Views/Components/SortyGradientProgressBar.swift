//
//  SortyGradientProgressBar.swift
//  Sorty
//
//  Reusable linear progress bar with a glossy gradient fill.
//

import SwiftUI

struct SortyGradientProgressBar: View {
    let progress: Double
    var accent: Color = .accentColor
    var height: CGFloat = 10

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.65),
                                accent,
                                accent.opacity(0.86)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: geo.size.width * clampedProgress)
                    .shadow(color: accent.opacity(0.35), radius: 8, x: 0, y: 2)
            }
        }
        .frame(height: height)
        .animation(.easeInOut(duration: 0.25), value: clampedProgress)
    }
}

struct SortyGradientLoadingBar: View {
    var accent: Color = .accentColor
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
                    .fill(.white.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.55),
                                accent,
                                accent.opacity(0.72)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: segmentWidth)
                    .offset(x: (travelPhase * travelDistance) - segmentWidth)
                    .shadow(color: accent.opacity(0.28), radius: 6, x: 0, y: 2)
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

struct SortyGradientCircularProgress: View {
    let progress: Double
    var accent: Color = .accentColor
    var size: CGFloat = 80
    var lineWidth: CGFloat = 8

    @State private var animatedProgress: Double = 0

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(accent.opacity(0.18), lineWidth: lineWidth)

            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [
                            accent.opacity(0.55),
                            accent,
                            accent.opacity(0.78),
                            accent.opacity(0.55)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.28), radius: lineWidth * 0.6, x: 0, y: 1)
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

struct SortyGradientCircularLoader: View {
    var accent: Color = .accentColor
    var size: CGFloat = 18
    var lineWidth: CGFloat = 3

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let rotation = (time * 280).truncatingRemainder(dividingBy: 360)
            let pulse = (sin(time * 2.2) + 1) * 0.5
            let sweep = 0.24 + (0.34 * pulse)
            let head = 0.06 + ((1 - pulse) * 0.08)
            let tail = min(head + sweep, 0.97)

            ZStack {
                Circle()
                    .inset(by: lineWidth / 2)
                    .stroke(accent.opacity(0.18), lineWidth: lineWidth)

                Circle()
                    .inset(by: lineWidth / 2)
                    .trim(from: head, to: tail)
                    .stroke(
                        AngularGradient(
                            colors: [
                                accent.opacity(0.28),
                                accent.opacity(0.95),
                                accent,
                                accent.opacity(0.45)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(rotation - 90))
                    .shadow(color: accent.opacity(0.3), radius: lineWidth, x: 0, y: 1)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview("Gradient Progress Bar") {
    VStack(spacing: 16) {
        SortyGradientProgressBar(progress: 0.78, accent: .indigo)
        SortyGradientProgressBar(progress: 0.45, accent: .blue)
        SortyGradientProgressBar(progress: 0.2, accent: .pink)
        SortyGradientLoadingBar()
        SortyGradientCircularProgress(progress: 0.74)
        SortyGradientCircularLoader()
    }
    .padding(20)
    .background(
        LinearGradient(
            colors: [.black, Color(red: 0.1, green: 0.12, blue: 0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .frame(width: 420)
}

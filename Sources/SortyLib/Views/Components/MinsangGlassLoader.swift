import SwiftUI

/// A compact orbit of glass bubbles for indeterminate progress surfaces.
struct MinsangGlassLoader: View {
    let textChangeTrigger: String
    var size: CGFloat = 54
    var isActive = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let bubbleCount = 6

    private var shouldAnimate: Bool {
        isActive && !reduceMotion
    }

    var body: some View {
        SwiftUI.TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: !shouldAnimate)
        ) { timeline in
            Canvas { context, canvasSize in
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0
                let minimumLength = min(canvasSize.width, canvasSize.height)
                let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let lineWidth = max(minimumLength * 0.018, 0.9)

                for index in 0 ..< Self.bubbleCount {
                    let indexPhase = Double(index) * (2 * Double.pi / Double(Self.bubbleCount))
                    let angle = time * 1.25 + indexPhase
                    let pulse = (sin(time * 2.1 + Double(index) * 0.8) + 1) / 2
                    let drift = CGFloat(sin(time * 1.7 + Double(index) * 1.15)) * minimumLength * 0.02
                    let orbitRadius = minimumLength * 0.27 + drift
                    let diameter = minimumLength * CGFloat(0.105 + 0.035 * pulse)
                    let bubbleCenter = CGPoint(
                        x: canvasCenter.x + CGFloat(cos(angle)) * orbitRadius,
                        y: canvasCenter.y + CGFloat(sin(angle)) * orbitRadius
                    )
                    let bubbleRect = CGRect(
                        x: bubbleCenter.x - diameter / 2,
                        y: bubbleCenter.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    let bubble = Path(ellipseIn: bubbleRect)

                    context.fill(
                        bubble,
                        with: .color(Color.primary.opacity(0.04 + 0.03 * pulse))
                    )
                    context.stroke(
                        bubble,
                        with: .color(Color.primary.opacity(0.30 + 0.22 * pulse)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    context.stroke(
                        bubble.trimmedPath(from: 0.56, to: 0.80),
                        with: .color(Color.primary.opacity(0.72)),
                        style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round)
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

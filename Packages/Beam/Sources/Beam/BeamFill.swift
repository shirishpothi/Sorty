import SwiftUI

// MARK: - Public API

public extension View {
  /// Paints the receiver's rendered shape with a dedicated glyph-fill
  /// shader: a corner-anchored palette blend with a soft diagonal light
  /// sweep running through it. Use on `Text`, `Image` (SF Symbol), or any
  /// `Shape` — the receiver's silhouette masks the output so only the
  /// glyph / symbol / shape pixels show the fill.
  ///
  /// ```swift
  /// Text("GENERATE")
  ///     .font(.system(size: 56, weight: .black, design: .rounded))
  ///     .beamFill(palette: .colorful)
  ///
  /// Image(systemName: "sparkles")
  ///     .font(.system(size: 72))
  ///     .beamFill(palette: .sunset)
  ///
  /// Circle()
  ///     .frame(width: 120, height: 120)
  ///     .beamFill(palette: .ocean)
  /// ```
  ///
  /// Distinct from `.beam(...)`, which overlays a traveling beam
  /// around the view's edge. This modifier fills the view itself.
  ///
  /// - Parameters:
  ///   - palette: one of `.colorful`, `.mono`, `.ocean`, `.sunset`.
  ///   - active: fade in/out. Matches `.beam` semantics (0.6 s in,
  ///     0.5 s out). Reduce Motion snaps without easing.
  ///   - duration: seconds per light-sweep pass. Defaults to `2.4`.
  ///   - strength: overall intensity multiplier in `0...1`.
  func beamFill(
    palette: BeamPalette = .colorful,
    active: Bool = true,
    duration: Double = 2.4,
    strength: Double = 1.0
  ) -> some View {
    modifier(BeamFillModifier(
      palette: palette,
      duration: duration,
      strength: strength,
      active: active
    ))
  }
}

// MARK: - ViewModifier

/// Implementation of `.beamFill(...)`. Applies the dedicated glyph-fill
/// shader via `foregroundStyle` — SwiftUI masks the shader's output by
/// the receiver view's own silhouette (text glyphs, symbol path, Shape
/// outline), so the fill shows only where the view would have rendered
/// its foreground.
private struct BeamFillModifier: ViewModifier {
  let palette: BeamPalette
  let duration: Double
  let strength: Double
  let active: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pixelSize: CGSize = .zero
  @State private var visualOpacity: Double = 0

  func body(content: Content) -> some View {
    TimelineView(.animation(paused: reduceMotion)) { timeline in
      let t = timeline.date.timeIntervalSinceReferenceDate
        .truncatingRemainder(dividingBy: 1000)
      content
        .foregroundStyle(makeShader(pixelSize: pixelSize, time: t))
        .opacity(visualOpacity)
        .background {
          GeometryReader { proxy in
            Color.clear
              .task(id: proxy.size) { pixelSize = proxy.size }
          }
        }
    }
    .onAppear {
      guard active else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) {
        visualOpacity = 1.0
      }
    }
    .onChange(of: active) { _, isActive in
      withAnimation(reduceMotion ? nil : (isActive ? .easeOut(duration: 0.6) : .easeIn(duration: 0.5))) {
        visualOpacity = isActive ? 1.0 : 0.0
      }
    }
  }

  private func makeShader(pixelSize: CGSize, time: TimeInterval) -> Shader {
    let hueShiftDeg = -30.0 * cos((time / 12.0) * 2.0 * .pi)
    let hueShiftRad = hueShiftDeg * .pi / 180.0
    let hueCos = cos(hueShiftRad)
    let hueSin = sin(hueShiftRad)

    return ShaderDispatch.glyphFillShader(
      pixelSize: pixelSize,
      time: time,
      duration: duration,
      strength: strength,
      brightness: 1.10,
      saturation: 1.15,
      variant: Float(palette.rawValue),
      hueCos: hueCos,
      hueSin: hueSin
    )
  }
}

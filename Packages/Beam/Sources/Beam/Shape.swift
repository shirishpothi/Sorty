import CoreGraphics

/// Geometric shape the beam traces. Only applies to `.medium` and `.small`
/// sizes — `.line` is inherently a bottom-edge traveling beam.
///
/// ```swift
/// RoundedRectangle(cornerRadius: 22)
///     .fill(.regularMaterial)
///     .beam(shape: .roundedRect(cornerRadius: 22))
///
/// Capsule()
///     .fill(.regularMaterial)
///     .beam(shape: .capsule)
///
/// Circle()
///     .fill(.regularMaterial)
///     .frame(width: 120, height: 120)
///     .beam(.small, shape: .circle)
/// ```
///
/// `.circle` traces the inscribed circle of the view's bounds, so the view
/// should be square. On non-square frames the beam still traces the largest
/// circle that fits and the non-circle area stays unlit.
public enum BeamShape: Equatable, Sendable {
  case roundedRect(cornerRadius: CGFloat)
  case capsule
  case circle
}

extension BeamShape {
  /// Integer id matching the shader's `shapeType` uniform.
  var shaderID: Int {
    switch self {
    case .roundedRect: return 0
    case .capsule:     return 1
    case .circle:      return 2
    }
  }

  /// The cornerRadius lane the shader reads. For capsule/circle the shader
  /// computes its own radius from `min(halfSize)` and ignores this value, but
  /// we still pass a sensible number so the uniform is never garbage.
  func cornerRadiusUniform(fallback: CGFloat) -> CGFloat {
    switch self {
    case .roundedRect(let r): return r
    case .capsule, .circle:   return fallback
    }
  }
}

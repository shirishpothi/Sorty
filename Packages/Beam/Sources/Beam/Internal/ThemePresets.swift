import Foundation

/// Resolved shader uniform values for a given `(size, theme)` combination.
///
/// Each beam instance bundles these seven numbers into a single struct at
/// construction time and the modifier forwards them verbatim to the Metal
/// shader. Keeping every tunable in one place means contributors can adjust
/// a theme's look without hunting through the modifier or shader.
///
/// Two of the fields don't describe opacity or color directly and are worth
/// flagging:
///
/// - `inkLuma`: the luminance of the highlight color blended into the beam
///   at its peak. `1.0` in `.dark` (white ink on colored spots), `0.0` in
///   `.light` (black ink on colored spots). Passing it as a uniform lets the
///   shader use a single `mix(color, ink, alpha)` codepath without branches.
///
/// - `inkAlphaScale`: a scalar pre-multiplier for the shared conic highlight
///   table. `1.0` in `.dark`, `0.73` in `.light` — chosen so the same table
///   produces visually matched intensities for both themes without needing
///   a second copy of the table in the shader.
struct ThemePresets {
  let strokeOpacity: Double
  let innerOpacity: Double
  let bloomOpacity: Double
  let innerShadowAlpha: Double
  let saturation: Double
  let inkLuma: Double
  let inkAlphaScale: Double

  static func resolve(size: BeamSize, theme: BeamTheme) -> ThemePresets {
    let isDark = theme == .dark

    let strokeOp: Double = {
      switch size {
      case .line: return 0.72
      case .medium, .small: return isDark ? 0.48 : 0.33
      // Comet's head is a small bright point — push stroke opacity
      // higher so the core pops against the dim trail.
      case .comet: return isDark ? 0.62 : 0.42
      }
    }()

    let shadow: Double = {
      switch size {
      case .medium: return isDark ? 0.27 : 0.14
      case .small:  return isDark ? 0.30 : 0.15
      case .line:   return 0.10
      case .comet:  return isDark ? 0.22 : 0.12
      }
    }()

    return ThemePresets(
      strokeOpacity: strokeOp,
      innerOpacity: isDark ? 0.70 : 0.46,
      bloomOpacity: isDark ? 0.80 : 0.54,
      innerShadowAlpha: shadow,
      saturation: isDark ? 1.20 : 0.96,
      inkLuma: isDark ? 1.0 : 0.0,
      inkAlphaScale: isDark ? 1.0 : 0.73
    )
  }
}

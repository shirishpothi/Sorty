import Foundation

/// Ambient appearance the beam is rendered for. Controls opacity stops,
/// saturation, and which ink color (white vs. black) is blended into the
/// conic highlight.
public enum BeamTheme: Sendable {
  /// Full-saturation colors with white conic highlights at the beam head.
  /// Higher default opacities (stroke 0.48, bloom 0.80). Best on dark surfaces.
  case dark

  /// Muted pastel beam with the black-ink overlay disabled — colors are
  /// gated by intensity so weak-color areas stay transparent rather than
  /// rendering as gray smudges on white surfaces. Lower default opacities
  /// (stroke 0.33, bloom 0.54).
  case light
}

import Foundation

/// Color palette used by the border beam. Each palette defines nine radial
/// color spots arranged around the edges of the beam; the shader sums them
/// into a traveling multi-hue gradient.
///
/// The raw values are part of the shader's ABI — don't renumber these cases
/// without updating the corresponding palette indices in `Beam.metal`.
public enum BeamPalette: Int, CaseIterable, Sendable {
  /// Full-spectrum multi-hue beam: pink, blue, green, purple, orange, magenta.
  case colorful = 0

  /// Desaturated grayscale beam — subtler, suitable for dense or utilitarian UIs.
  case mono = 1

  /// Cool blues and purples.
  case ocean = 2

  /// Warm reds, oranges, and yellows.
  case sunset = 3
}

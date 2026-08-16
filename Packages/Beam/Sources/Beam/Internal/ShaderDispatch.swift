import Foundation
import SwiftUI

/// Builds a Metal `Shader` from the packaged Metal library, selecting the
/// correct entry point for the given size and packing the uniform arguments
/// in the order the shader expects.
///
/// ### Uniform contract
///
/// Uniforms are passed as four `float4` bundles plus a `float2` for the hue
/// sin/cos, rather than as 18 individual scalars. The packing reduces the
/// number of positional arguments both sides have to agree on — each bundle
/// groups values that change together — and each layout is documented at
/// both the Swift packing site (below) and the shader unpacking site (the
/// prologue of each `[[ stitchable ]]` entry point in `Shaders/`).
///
/// If you add a new uniform, extend one of the existing `float4`s into an
/// unused lane or introduce a new bundle at BOTH ends — Metal doesn't
/// name-match uniforms, so a mismatch silently reads garbage.
enum ShaderDispatch {
  private static let libraryBundle: Bundle = {
    if let resourceURL = Bundle.main.resourceURL,
       let embeddedBundle = Bundle(
         url: resourceURL.appendingPathComponent("Beam_Beam.bundle")
       ) {
      return embeddedBundle
    }
    return .module
  }()

  static func shader(
    size: BeamSize,
    pixelSize: CGSize,
    cornerRadius: CGFloat,
    borderWidth: CGFloat,
    time: TimeInterval,
    duration: Double,
    strokeOpacity: Double,
    innerOpacity: Double,
    bloomOpacity: Double,
    strength: Double,
    brightness: Double,
    saturation: Double,
    variant: Float,
    inkLuma: Double,
    innerShadowAlpha: Double,
    inkAlphaScale: Double,
    hueCos: Double,
    hueSin: Double,
    paletteScale: Double,
    shapeType: Int
  ) -> Shader {
    let function = ShaderFunction(
      library: .bundle(libraryBundle),
      name: entryPointName(for: size)
    )

    let args: [Shader.Argument] = [
      // rect:       sizeW, sizeH, cornerRadius, borderWidth
      .float4(
        Float(pixelSize.width),
        Float(pixelSize.height),
        Float(cornerRadius),
        Float(borderWidth)
      ),
      // timing:     time, duration, brightness, saturation
      .float4(
        Float(time),
        Float(duration),
        Float(brightness),
        Float(saturation)
      ),
      // opacities:  stroke, inner, bloom, strength
      .float4(
        Float(strokeOpacity),
        Float(innerOpacity),
        Float(bloomOpacity),
        Float(strength)
      ),
      // theme:      variant, inkLuma, innerShadowAlpha, inkAlphaScale
      .float4(
        variant,
        Float(inkLuma),
        Float(innerShadowAlpha),
        Float(inkAlphaScale)
      ),
      // hueAndScale: cos, sin, paletteScale, shapeType
      .float4(
        Float(hueCos),
        Float(hueSin),
        Float(paletteScale),
        Float(shapeType)
      ),
    ]
    return Shader(function: function, arguments: args)
  }

  private static func entryPointName(for size: BeamSize) -> String {
    switch size {
    case .medium: return "beam"
    case .small:  return "beamSmall"
    case .line:   return "beamLine"
    case .comet:  return "beamComet"
    }
  }

  /// Builds the glyph-fill shader used by `.beamFill(...)`. Unlike the
  /// border shaders this one fills the whole bounding box — the receiver
  /// view's own silhouette provides the mask.
  static func glyphFillShader(
    pixelSize: CGSize,
    time: TimeInterval,
    duration: Double,
    strength: Double,
    brightness: Double,
    saturation: Double,
    variant: Float,
    hueCos: Double,
    hueSin: Double
  ) -> Shader {
    let function = ShaderFunction(library: .bundle(libraryBundle), name: "beamGlyphFill")
    let args: [Shader.Argument] = [
      .float4(Float(pixelSize.width), Float(pixelSize.height), 0, 0),
      .float4(Float(time), Float(duration), Float(brightness), Float(saturation)),
      .float4(0, 0, 0, Float(strength)),
      .float4(variant, 0, 0, 0),
      .float4(Float(hueCos), Float(hueSin), 0, 0),
    ]
    return Shader(function: function, arguments: args)
  }

  /// Builds the distortion shader used by `.beamLens` / `lensStrength:`.
  /// Uses its own tiny uniform bundle — the lens doesn't need palette,
  /// theme, or opacity inputs, so we don't force it to share the main
  /// shader's ABI.
  static func lensShader(
    pixelSize: CGSize,
    time: TimeInterval,
    duration: Double,
    strength: Double
  ) -> Shader {
    let function = ShaderFunction(library: .bundle(libraryBundle), name: "beamLens")
    let args: [Shader.Argument] = [
      .float4(
        Float(pixelSize.width),
        Float(pixelSize.height),
        Float(strength),
        0
      ),
      .float4(
        Float(time),
        Float(duration),
        0,
        0
      ),
    ]
    return Shader(function: function, arguments: args)
  }
}

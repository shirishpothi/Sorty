#include "Common.h"

// MARK: - Glyph fill shader
//
// Unlike the border/beam shaders, this one paints the entire bounding
// box. It's intended for use as `foregroundStyle(...)` over text, SF
// Symbols, or any Shape — the receiver's own silhouette masks the output
// so the fill only shows inside the glyphs.
//
// Design:
//   • 4-corner palette blend — each palette has four anchor colors pinned
//     to the corners, bilinearly interpolated across the box.
//   • Moving diagonal sweep — a soft bright band travels corner to corner
//     once per `duration`, giving the glyphs a sense of light running
//     through them.
//   • Alpha always 1 at the shader level — SwiftUI composites that
//     against the glyph's own alpha, so invisible-outside-glyph is
//     handled for free.

// GENERATED-BEGIN: glyphFillColors
// 4 palettes × 4 anchor colors. Indexed as `variant * 4 + corner`
// (corner: 0 = top-left, 1 = top-right, 2 = bottom-left, 3 = bottom-right).
constant float3 glyphFillColors[16] = {
  // colorful
  float3(255.0,  50.0, 100.0) / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  float3(255.0, 140.0,  40.0) / 255.0,
  float3(180.0,  40.0, 240.0) / 255.0,
  // mono
  float3(220.0, 220.0, 220.0) / 255.0,
  float3(170.0, 170.0, 170.0) / 255.0,
  float3(150.0, 150.0, 150.0) / 255.0,
  float3(200.0, 200.0, 200.0) / 255.0,
  // ocean
  float3(120.0,  90.0, 255.0) / 255.0,
  float3( 60.0, 140.0, 230.0) / 255.0,
  float3( 80.0, 100.0, 200.0) / 255.0,
  float3(140.0, 100.0, 240.0) / 255.0,
  // sunset
  float3(255.0,  80.0,  50.0) / 255.0,
  float3(255.0, 160.0,  40.0) / 255.0,
  float3(255.0, 100.0,  80.0) / 255.0,
  float3(255.0, 200.0,  60.0) / 255.0,
};
// GENERATED-END: glyphFillColors

static inline float3 sampleGlyphPalette(float2 uv, int variant) {
  int base = variant * 4;
  float2 w = saturate(uv);
  float wTL = (1.0 - w.x) * (1.0 - w.y);
  float wTR =        w.x  * (1.0 - w.y);
  float wBL = (1.0 - w.x) *        w.y;
  float wBR =        w.x  *        w.y;
  return glyphFillColors[base + 0] * wTL
       + glyphFillColors[base + 1] * wTR
       + glyphFillColors[base + 2] * wBL
       + glyphFillColors[base + 3] * wBR;
}

// MARK: - Entry point

[[ stitchable ]] half4 beamGlyphFill(
  float2 position,
  float4 rect,       // (sizeW, sizeH, _, _)
  float4 timing,     // (time, duration, brightness, saturation)
  float4 opacities,  // (_, _, _, strength)
  float4 theme,      // (variant, _, _, _)
  float4 hueAndScale // (cos, sin, _, _)
) {
  float sizeW = rect.x, sizeH = rect.y;
  float time = timing.x, duration = timing.y;
  float brightness = timing.z, saturation = timing.w;
  float strength = opacities.w;
  int variant = int(theme.x);
  float hueCos = hueAndScale.x, hueSin = hueAndScale.y;

  float2 size = float2(max(sizeW, 1.0), max(sizeH, 1.0));
  float2 uv = position / size;

  float3 base = sampleGlyphPalette(uv, variant);

  // Diagonal sweep: a soft bright band travels from the top-left corner
  // to the bottom-right corner once per cycle, wrapping back to the
  // start via `fract`. Diagonal rather than horizontal so the motion
  // reads obviously even on short words like "GEN" or a single SF Symbol.
  float t = fract(time / max(duration, 0.0001));
  float diag = (uv.x + uv.y) * 0.5; // 0 at top-left, 1 at bottom-right
  // Travel from -0.3 to 1.3 so the sweep eases in from off-screen and
  // exits off-screen — avoids a visible "pop" at cycle boundaries.
  float sweepCenter = mix(-0.3, 1.3, t);
  float sweepWidth = 0.22;
  float d = (diag - sweepCenter) / sweepWidth;
  float sweep = exp(-d * d);

  // Add the sweep on top of the base palette. Clamp so fully saturated
  // channels don't overflow beyond 1.0 before premultiply.
  float3 rgb = saturate(base + float3(sweep * 0.35));

  // Glyph fill is opaque where it paints — SwiftUI composites it
  // against the glyph's own alpha, so transparency is handled for us.
  return finalize(half3(rgb), 1.0h, brightness, saturation, strength, hueCos, hueSin);
}

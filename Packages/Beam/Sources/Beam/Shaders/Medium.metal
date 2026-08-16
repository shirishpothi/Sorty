#include "Common.h"

// MARK: - Palette
//
// Nine radial spots arranged around the edges of a card-sized rectangle.
// Position (posU, posV) and ellipse radii (ellipseW, ellipseH) are shared
// across every palette; only the colors differ.

/// Nine spots ringing the card — three across the top, two on each side at
/// mid-height, two across the bottom. The side pairs mirror each other at
/// y=0.683 so the lit beam reads as continuous color all the way around the
/// card rather than leaving a visible gap on the right middle.
constant float4 spotPosSize[9] = {
  float4(0.330, -0.074,  70.0, 40.0), // top
  float4(0.120, -0.050,  60.0, 35.0), // top
  float4(0.021,  0.683,  40.0, 70.0), // left-middle
  float4(0.021,  0.683,  20.0, 35.0), // left-middle
  float4(0.744,  1.000, 180.0, 32.0), // bottom
  float4(0.550,  1.000,  85.0, 26.0), // bottom
  float4(0.939,  0.000,  74.0, 32.0), // top-right
  float4(1.000,  0.271,  26.0, 42.0), // right-upper
  float4(1.000,  0.683,  52.0, 48.0), // right-middle (mirrors left)
};

/// Four palettes concatenated in the order defined by `BeamPalette`:
/// `[colorful, mono, ocean, sunset]`. Indexed by `variant * 9 + spot`.
///
/// Regenerate via `swift Scripts/GeneratePalettes.swift` after editing the
/// palette data in that script.
// GENERATED-BEGIN: paletteColors
constant float3 paletteColors[36] = {
  // colorful
  float3(255.0,  50.0, 100.0) / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  float3( 50.0, 200.0,  80.0) / 255.0,
  float3( 30.0, 185.0, 170.0) / 255.0,
  float3(100.0,  70.0, 255.0) / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  float3(255.0, 120.0,  40.0) / 255.0,
  float3(240.0,  50.0, 180.0) / 255.0,
  float3(180.0,  40.0, 240.0) / 255.0,
  // mono
  float3(180.0, 180.0, 180.0) / 255.0,
  float3(140.0, 140.0, 140.0) / 255.0,
  float3(160.0, 160.0, 160.0) / 255.0,
  float3(130.0, 130.0, 130.0) / 255.0,
  float3(170.0, 170.0, 170.0) / 255.0,
  float3(150.0, 150.0, 150.0) / 255.0,
  float3(190.0, 190.0, 190.0) / 255.0,
  float3(145.0, 145.0, 145.0) / 255.0,
  float3(165.0, 165.0, 165.0) / 255.0,
  // ocean
  float3(100.0,  80.0, 220.0) / 255.0,
  float3( 60.0, 120.0, 255.0) / 255.0,
  float3( 80.0, 100.0, 200.0) / 255.0,
  float3( 50.0, 140.0, 220.0) / 255.0,
  float3(120.0,  80.0, 255.0) / 255.0,
  float3( 70.0, 130.0, 255.0) / 255.0,
  float3(140.0, 100.0, 240.0) / 255.0,
  float3( 90.0, 110.0, 230.0) / 255.0,
  float3(130.0,  70.0, 255.0) / 255.0,
  // sunset
  float3(255.0,  80.0,  50.0) / 255.0,
  float3(255.0, 160.0,  40.0) / 255.0,
  float3(255.0, 120.0,  60.0) / 255.0,
  float3(255.0, 200.0,  50.0) / 255.0,
  float3(255.0, 100.0,  80.0) / 255.0,
  float3(255.0, 180.0,  60.0) / 255.0,
  float3(255.0,  60.0,  60.0) / 255.0,
  float3(255.0, 140.0,  50.0) / 255.0,
  float3(255.0,  90.0,  70.0) / 255.0,
};
// GENERATED-END: paletteColors

static float3 samplePalette(float2 p, float2 size, float sizeScale, float alphaScale, int variant) {
  float3 c = float3(0.0);
  int base = variant * 9;
  for (int i = 0; i < 9; i++) {
    float4 ps = spotPosSize[i];
    c += radialSpot(p, size, ps.xy, ps.zw * sizeScale, paletteColors[base + i] * alphaScale);
  }
  return c;
}

// MARK: - Entry point
//
// Single-pass rendering of three composited layers:
//   • inner glow — 28pt color wash along all edges, conic-masked
//   • stroke    — crisp 1pt ring with white-ink highlight at the beam head
//   • bloom     — gaussian halo inward from the edge, tinted by the color field

[[ stitchable ]] half4 beam(
  float2 position,
  float4 rect,       // (sizeW, sizeH, cornerRadius, borderWidth)
  float4 timing,     // (time, duration, brightness, saturation)
  float4 opacities,  // (stroke, inner, bloom, strength)
  float4 theme,      // (variant, inkLuma, innerShadowAlpha, inkAlphaScale)
  float4 hueAndScale // (cos, sin, paletteScale, reserved)
) {
  float sizeW = rect.x, sizeH = rect.y;
  float cornerRadius = rect.z, borderWidth = rect.w;
  float time = timing.x, duration = timing.y;
  float brightness = timing.z, saturation = timing.w;
  float strokeOpacity = opacities.x, innerOpacity = opacities.y;
  float bloomOpacity = opacities.z, strength = opacities.w;
  int variant = int(theme.x);
  float inkLuma = theme.y, innerShadowAlpha = theme.z, inkAlphaScale = theme.w;
  float hueCos = hueAndScale.x, hueSin = hueAndScale.y;
  float paletteScale = hueAndScale.z;
  int shapeType = int(hueAndScale.w);

  float2 size = float2(sizeW, sizeH);
  float2 center = size * 0.5;

  float sdfOuter = sdBeamShape(position, center, size * 0.5, cornerRadius, shapeType);
  if (sdfOuter > 0.0) return half4(0.0);
  float distFromEdge = -sdfOuter;

  const float bloomSigma = 8.0;
  const float bloomReach = 24.0;
  const float innerReach = 28.0;
  if (distFromEdge > max(bloomReach, innerReach)) return half4(0.0);

  float a = beamAngleFract(position, size, time, duration);

  // Inner glow
  half3 innerPrem = half3(0.0);
  half  innerA = 0.0h;
  {
    float m = strokeConicMask(a);
    if (m > 0.0) {
      float vFade = saturate(1.0 - min(position.y, size.y - position.y) / innerReach);
      float hFade = saturate(1.0 - min(position.x, size.x - position.x) / innerReach);
      float edgeFade = max(vFade, hFade);

      if (edgeFade > 0.0) {
        // paletteScale grows the palette ellipses with the card's smallest
        // dimension so spots overlap at the same relative density regardless
        // of card size. Fixes "gap" artifacts on iPad-sized cards.
        float3 spots = samplePalette(position, size, 0.9 * paletteScale, 0.45, variant);
        float shadowFactor = exp(-(distFromEdge * distFromEdge) / 81.0) * innerShadowAlpha * inkLuma;
        // saturate() enforces the premul invariant: overlapping palette spots
        // can push a channel > 1, which would leak rgb > alpha after scaling.
        float3 rgb = saturate(mix(spots, float3(inkLuma), shadowFactor));
        // Gate alpha by the FINAL rgb brightness (post shadow-mix) so we only
        // paint coverage proportional to the layer's own luminance. In dark
        // mode `inkLuma=1`, which made the old `colorGate(spots,…)` return 1.0
        // and pushed full alpha into dim between-spot regions — that painted
        // near-black over the card and produced a visible dark trail behind
        // the beam. Gating on `rgb` keeps glow-positive pixels bright and lets
        // dim pixels fade to zero coverage.
        float rgbMax = max(max(rgb.r, rgb.g), rgb.b);
        float alpha = m * edgeFade * innerOpacity * rgbMax;
        innerPrem = half3(rgb * alpha);
        innerA = half(alpha);
      }
    }
  }

  // Stroke and bloom share the same 9-spot palette sample, so evaluate it
  // once per pixel (lazily — only when a layer actually needs it).
  bool strokeMaybe = (distFromEdge <= borderWidth);
  float mStroke = strokeMaybe ? strokeConicMask(a) : 0.0;
  float mBloom  = bloomConicMask(a);
  bool needFullSpots = (strokeMaybe && mStroke > 0.0) || (mBloom > 0.0);
  float3 fullSpots = needFullSpots
    ? samplePalette(position, size, paletteScale, 1.0, variant)
    : float3(0.0);
  float fullGate = needFullSpots ? colorGate(fullSpots, inkLuma) : 0.0;

  // Stroke
  half3 strokePrem = half3(0.0);
  half  strokeA = 0.0h;
  if (strokeMaybe && mStroke > 0.0) {
    float w = whiteConic(a) * inkAlphaScale * inkLuma;
    float3 rgb = saturate(mix(fullSpots, float3(inkLuma), w));
    float alpha = mStroke * strokeOpacity * fullGate;
    strokePrem = half3(rgb * alpha);
    strokeA = half(alpha);
  }

  // Bloom
  half3 bloomPrem = half3(0.0);
  half  bloomA = 0.0h;
  const float bloomNorm = 0.0498;
  if (mBloom > 0.0) {
    float falloff = exp(-(distFromEdge * distFromEdge) / (bloomSigma * bloomSigma));
    float alpha = mBloom * falloff * bloomOpacity * bloomNorm * 1.3 * inkAlphaScale * fullGate;
    float3 rgb = saturate(mix(fullSpots, float3(inkLuma), 0.35 * inkLuma));
    bloomPrem = half3(rgb * alpha);
    bloomA = half(alpha);
  }

  // Composite inner < stroke < bloom (source-over on premultiplied output)
  half3 rgb = innerPrem;
  half  aout = innerA;
  rgb  = strokePrem + rgb * (1.0h - strokeA);
  aout = strokeA    + aout * (1.0h - strokeA);
  rgb  = bloomPrem  + rgb * (1.0h - bloomA);
  aout = bloomA     + aout * (1.0h - bloomA);

  return finalize(rgb, aout, brightness, saturation, strength, hueCos, hueSin);
}

#include "Common.h"

// MARK: - Palette
//
// Reuses the `.medium` 9-spot layout verbatim. The comet is visually
// different from the medium arc, but the underlying palette geometry works
// fine for both — the difference is in the angular masks below.

constant float4 cometSpotPosSize[9] = {
  float4(0.330, -0.074,  70.0, 40.0),
  float4(0.120, -0.050,  60.0, 35.0),
  float4(0.021,  0.683,  40.0, 70.0),
  float4(0.021,  0.683,  20.0, 35.0),
  float4(0.744,  1.000, 180.0, 32.0),
  float4(0.550,  1.000,  85.0, 26.0),
  float4(0.939,  0.000,  74.0, 32.0),
  float4(1.000,  0.271,  26.0, 42.0),
  float4(1.000,  0.683,  52.0, 48.0),
};

// GENERATED-BEGIN: cometPaletteColors
constant float3 cometPaletteColors[36] = {
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
// GENERATED-END: cometPaletteColors

static float3 sampleCometPalette(float2 p, float2 size, float sizeScale, float alphaScale, int variant) {
  float3 c = float3(0.0);
  int base = variant * 9;
  for (int i = 0; i < 9; i++) {
    float4 ps = cometSpotPosSize[i];
    c += radialSpot(p, size, ps.xy, ps.zw * sizeScale, cometPaletteColors[base + i] * alphaScale);
  }
  return c;
}

// MARK: - Comet conic masks
//
// The comet "head" sits at a ≈ 0.67 — the same peak position as the medium
// beam's white highlight — so spinning a comet and a beam in parallel
// keeps them phase-aligned. Everything AHEAD of the head (a > 0.70) is
// dark: a comet can't light up pixels it hasn't reached yet. Behind the
// head (a < 0.67), coverage tapers off over a long trail that fades to
// zero around a = 0.20. The trail on the comet variant is intentionally
// longer than the medium beam's ramp-up so the tail reads as motion blur
// rather than just a short arc.

static inline float cometStrokeMask(float a) {
  // Nothing ahead of the head.
  if (a > 0.72) return 0.0;
  // Sharp head peak — the comet's bright core.
  if (a > 0.68) return mix(0.0,  1.00, (0.72 - a) / 0.04);
  if (a > 0.66) return 1.0;
  // Trail — long, gradual falloff.
  if (a > 0.60) return mix(0.75, 1.00, (a - 0.60) / 0.06);
  if (a > 0.50) return mix(0.45, 0.75, (a - 0.50) / 0.10);
  if (a > 0.35) return mix(0.15, 0.45, (a - 0.35) / 0.15);
  if (a > 0.20) return mix(0.00, 0.15, (a - 0.20) / 0.15);
  return 0.0;
}

static inline float cometWhiteConic(float a) {
  // White highlight concentrated AT the head only (narrower than medium's
  // wider whiteConic). No highlight trails behind — the trail is color,
  // not ink.
  if (a > 0.72) return 0.0;
  if (a > 0.70) return mix(0.0,  0.75, (0.72 - a) / 0.02);
  if (a > 0.67) return mix(0.75, 0.30, (0.70 - a) / 0.03);
  if (a > 0.64) return mix(0.30, 0.00, (0.67 - a) / 0.03);
  return 0.0;
}

static inline float cometBloomMask(float a) {
  // Bloom halo is tight around the head with a brief glow behind. Much
  // shorter than the stroke's trail so the comet reads as "one spark,
  // moving", not "a wide lit arc".
  if (a > 0.73) return 0.0;
  if (a > 0.705) return mix(0.00, 0.85, (0.73 - a) / 0.025);
  if (a > 0.69) return mix(0.85, 0.60, (0.705 - a) / 0.015);
  if (a > 0.65) return mix(0.60, 0.20, (0.69 - a) / 0.04);
  if (a > 0.58) return mix(0.20, 0.06, (0.65 - a) / 0.07);
  if (a > 0.50) return mix(0.06, 0.00, (0.58 - a) / 0.08);
  return 0.0;
}

// MARK: - Entry point
//
// Same three-layer composition as `.medium`: inner glow + stroke + bloom,
// all gated by comet-specific angular masks. The trail uses the same
// palette evaluation as the head, so as the comet travels it picks up
// whichever palette cluster it's currently over.

[[ stitchable ]] half4 beamComet(
  float2 position,
  float4 rect,
  float4 timing,
  float4 opacities,
  float4 theme,
  float4 hueAndScale
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

  // Inner glow — uses the comet's long stroke mask so the color trail
  // spreads inward from the edge just behind the head.
  half3 innerPrem = half3(0.0);
  half  innerA = 0.0h;
  {
    float m = cometStrokeMask(a);
    if (m > 0.0) {
      float vFade = saturate(1.0 - min(position.y, size.y - position.y) / innerReach);
      float hFade = saturate(1.0 - min(position.x, size.x - position.x) / innerReach);
      float edgeFade = max(vFade, hFade);

      if (edgeFade > 0.0) {
        float3 spots = sampleCometPalette(position, size, 0.9 * paletteScale, 0.45, variant);
        float shadowFactor = exp(-(distFromEdge * distFromEdge) / 81.0) * innerShadowAlpha * inkLuma;
        float3 rgb = saturate(mix(spots, float3(inkLuma), shadowFactor));
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
  float mStroke = strokeMaybe ? cometStrokeMask(a) : 0.0;
  float mBloom  = cometBloomMask(a);
  bool needFullSpots = (strokeMaybe && mStroke > 0.0) || (mBloom > 0.0);
  float3 fullSpots = needFullSpots
    ? sampleCometPalette(position, size, paletteScale, 1.0, variant)
    : float3(0.0);
  float fullGate = needFullSpots ? colorGate(fullSpots, inkLuma) : 0.0;

  // Stroke — crisp 1pt ring with a bright white core at the head.
  half3 strokePrem = half3(0.0);
  half  strokeA = 0.0h;
  if (strokeMaybe && mStroke > 0.0) {
    float w = cometWhiteConic(a) * inkAlphaScale * inkLuma;
    float3 rgb = saturate(mix(fullSpots, float3(inkLuma), w));
    float alpha = mStroke * strokeOpacity * fullGate;
    strokePrem = half3(rgb * alpha);
    strokeA = half(alpha);
  }

  // Bloom — halo around the head, tighter than medium's bloom.
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

  half3 rgb = innerPrem;
  half  aout = innerA;
  rgb  = strokePrem + rgb * (1.0h - strokeA);
  aout = strokeA    + aout * (1.0h - strokeA);
  rgb  = bloomPrem  + rgb * (1.0h - bloomA);
  aout = bloomA     + aout * (1.0h - bloomA);

  return finalize(rgb, aout, brightness, saturation, strength, hueCos, hueSin);
}

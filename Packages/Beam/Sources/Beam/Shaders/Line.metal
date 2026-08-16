#include "Common.h"

// MARK: - Animation curves

/// Piecewise-linear wrap-around through four values at t = 0 / 0.25 / 0.50 / 0.75.
static float curve4(float t, float v0, float v1, float v2, float v3) {
  if (t < 0.25) return mix(v0, v1, t * 4.0);
  if (t < 0.50) return mix(v1, v2, (t - 0.25) * 4.0);
  if (t < 0.75) return mix(v2, v3, (t - 0.50) * 4.0);
  return              mix(v3, v0, (t - 0.75) * 4.0);
}

/// Breathing height modulation. Ramps: 0.80 → 1.25 @25% → 0.85 @55% → 1.30 @80% → 0.80.
/// Irregular stops break up any perceptible periodicity when paired with travel.
static float lineBreatheH(float t) {
  if (t < 0.25) return mix(0.80, 1.25, t / 0.25);
  if (t < 0.55) return mix(1.25, 0.85, (t - 0.25) / 0.30);
  if (t < 0.80) return mix(0.85, 1.30, (t - 0.55) / 0.25);
  return              mix(1.30, 0.80, (t - 0.80) / 0.20);
}

/// Gates the beam to a centered window. Invisible during the first/last 12.5% of
/// the travel cycle, ramping in/out over 20%. Prevents the beam from appearing
/// to "teleport" at cycle boundaries.
static float lineEdgeFade(float t) {
  if (t < 0.125) return 0.0;
  if (t < 0.325) return (t - 0.125) / 0.20;
  if (t < 0.675) return 1.0;
  if (t < 0.875) return 1.0 - (t - 0.675) / 0.20;
  return 0.0;
}

// MARK: - Spots & masks

/// Elliptical radial spot whose axes scale with the beam's current width and
/// height. `geom` packs `(sizeW, sizeH, offsetX, offsetY)`.
static float3 lineSpot(float2 p, float2 size, float beamX, float w, float h, float4 geom, float3 color) {
  float2 center = float2(beamX * size.x + geom.z, size.y + geom.w);
  float2 ellipse = float2(geom.x * w, geom.y * h);
  float2 local = (p - center) / ellipse;
  float dist = length(local);
  return color * saturate(1.0 - dist);
}

static float lineStrokeRadialMask(float2 p, float2 size, float beamX, float w, float h) {
  float2 center = float2(beamX * size.x, size.y);
  float2 ellipse = float2(78.0 * w, 60.0 * h);
  float2 local = (p - center) / ellipse;
  float d = length(local);
  if (d >= 1.0) return 0.0;
  if (d < 0.45) return mix(1.0, 0.5, d / 0.45);
  return mix(0.5, 0.0, (d - 0.45) / 0.55);
}

/// Vertical radius 60 keeps the bloom concentrated at the bottom of typical
/// `.line` elements (~40pt search bars). Horizontal 84 spreads it along the edge.
static float lineBloomRadialMask(float2 p, float2 size, float beamX, float w, float h) {
  float2 center = float2(beamX * size.x, size.y);
  float2 ellipse = float2(84.0 * w, 60.0 * h);
  float2 local = (p - center) / ellipse;
  float d = length(local);
  if (d >= 1.0) return 0.0;
  if (d < 0.35) return mix(1.0, 0.5, d / 0.35);
  return mix(0.5, 0.0, (d - 0.35) / 0.65);
}

// MARK: - Border / inner palettes (dark theme)

constant float4 lineBorderGeom[9] = {
  float4(36.0, 36.0,   0.0,  2.0),
  float4(30.0, 32.0,  39.0,  0.0),
  float4(33.0, 28.0, -36.0,  2.0),
  float4(29.0, 34.0, -54.0,  0.0),
  float4(27.0, 30.0,  51.0, -1.0),
  float4(36.0, 24.0,  21.0,  1.0),
  float4(30.0, 22.0, -21.0,  0.0),
  float4(25.0, 28.0,  66.0,  1.0),
  float4(23.0, 30.0, -66.0, -1.0),
};

// GENERATED-BEGIN: lineBorderColors
constant float3 lineBorderColors[36] = {
  // colorful
  float3(255.0,  50.0, 100.0) / 255.0,
  float3( 40.0, 180.0, 220.0) / 255.0,
  float3( 50.0, 200.0,  80.0) / 255.0,
  float3(180.0,  40.0, 240.0) / 255.0,
  float3(255.0, 160.0,  30.0) / 255.0,
  float3(100.0,  70.0, 255.0) / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  float3(240.0,  50.0, 180.0) / 255.0,
  float3( 30.0, 185.0, 170.0) / 255.0,
  // mono
  float3(200.0, 200.0, 200.0) / 255.0,
  float3(170.0, 170.0, 170.0) / 255.0,
  float3(155.0, 155.0, 155.0) / 255.0,
  float3(185.0, 185.0, 185.0) / 255.0,
  float3(165.0, 165.0, 165.0) / 255.0,
  float3(180.0, 180.0, 180.0) / 255.0,
  float3(160.0, 160.0, 160.0) / 255.0,
  float3(175.0, 175.0, 175.0) / 255.0,
  float3(190.0, 190.0, 190.0) / 255.0,
  // ocean
  float3(100.0,  80.0, 220.0) / 255.0,
  float3( 60.0, 120.0, 255.0) / 255.0,
  float3( 80.0, 100.0, 200.0) / 255.0,
  float3(130.0,  70.0, 255.0) / 255.0,
  float3( 70.0, 130.0, 255.0) / 255.0,
  float3(120.0,  80.0, 255.0) / 255.0,
  float3( 90.0, 110.0, 230.0) / 255.0,
  float3(110.0,  90.0, 240.0) / 255.0,
  float3(140.0, 100.0, 255.0) / 255.0,
  // sunset
  float3(255.0, 100.0,  60.0) / 255.0,
  float3(255.0, 180.0,  50.0) / 255.0,
  float3(255.0, 140.0,  70.0) / 255.0,
  float3(255.0,  80.0,  80.0) / 255.0,
  float3(255.0, 200.0,  60.0) / 255.0,
  float3(255.0, 120.0,  50.0) / 255.0,
  float3(255.0, 160.0,  80.0) / 255.0,
  float3(255.0,  90.0,  60.0) / 255.0,
  float3(255.0,  70.0,  70.0) / 255.0,
};
// GENERATED-END: lineBorderColors

constant float4 lineInnerGeom[9] = {
  float4(33.0, 30.0,   0.0,  0.0),
  float4(24.0, 26.0,  39.0, -3.0),
  float4(27.0, 24.0, -36.0,  0.0),
  float4(23.0, 28.0, -54.0, -2.0),
  float4(24.0, 24.0,  51.0, -1.0),
  float4(30.0, 20.0,  21.0,  0.0),
  float4(25.0, 18.0, -21.0, -2.0),
  float4(21.0, 24.0,  66.0,  0.0),
  float4(18.0, 26.0, -66.0, -1.0),
};

/// Per-spot alpha pattern (shared across palettes):
/// 0.48, 0.42, 0.48, 0.42, 0.50, 0.45, 0.40, 0.45, 0.52
// GENERATED-BEGIN: lineInnerColors
constant float3 lineInnerColors[36] = {
  // colorful
  float3(255.0,  50.0, 100.0) * 0.48 / 255.0,
  float3( 40.0, 180.0, 220.0) * 0.42 / 255.0,
  float3( 50.0, 200.0,  80.0) * 0.48 / 255.0,
  float3(180.0,  40.0, 240.0) * 0.42 / 255.0,
  float3(255.0, 160.0,  30.0) * 0.5 / 255.0,
  float3(100.0,  70.0, 255.0) * 0.45 / 255.0,
  float3( 40.0, 140.0, 255.0) * 0.4 / 255.0,
  float3(240.0,  50.0, 180.0) * 0.45 / 255.0,
  float3( 30.0, 185.0, 170.0) * 0.52 / 255.0,
  // mono
  float3(200.0, 200.0, 200.0) * 0.48 / 255.0,
  float3(170.0, 170.0, 170.0) * 0.42 / 255.0,
  float3(155.0, 155.0, 155.0) * 0.48 / 255.0,
  float3(185.0, 185.0, 185.0) * 0.42 / 255.0,
  float3(165.0, 165.0, 165.0) * 0.5 / 255.0,
  float3(180.0, 180.0, 180.0) * 0.45 / 255.0,
  float3(160.0, 160.0, 160.0) * 0.4 / 255.0,
  float3(175.0, 175.0, 175.0) * 0.45 / 255.0,
  float3(190.0, 190.0, 190.0) * 0.52 / 255.0,
  // ocean
  float3(100.0,  80.0, 220.0) * 0.48 / 255.0,
  float3( 60.0, 120.0, 255.0) * 0.42 / 255.0,
  float3( 80.0, 100.0, 200.0) * 0.48 / 255.0,
  float3(130.0,  70.0, 255.0) * 0.42 / 255.0,
  float3( 70.0, 130.0, 255.0) * 0.5 / 255.0,
  float3(120.0,  80.0, 255.0) * 0.45 / 255.0,
  float3( 90.0, 110.0, 230.0) * 0.4 / 255.0,
  float3(110.0,  90.0, 240.0) * 0.45 / 255.0,
  float3(140.0, 100.0, 255.0) * 0.52 / 255.0,
  // sunset
  float3(255.0, 100.0,  60.0) * 0.48 / 255.0,
  float3(255.0, 180.0,  50.0) * 0.42 / 255.0,
  float3(255.0, 140.0,  70.0) * 0.48 / 255.0,
  float3(255.0,  80.0,  80.0) * 0.42 / 255.0,
  float3(255.0, 200.0,  60.0) * 0.5 / 255.0,
  float3(255.0, 120.0,  50.0) * 0.45 / 255.0,
  float3(255.0, 160.0,  80.0) * 0.4 / 255.0,
  float3(255.0,  90.0,  60.0) * 0.45 / 255.0,
  float3(255.0,  70.0,  70.0) * 0.52 / 255.0,
};
// GENERATED-END: lineInnerColors

// MARK: - Border palette (light theme)
//
// Wider spots (sizeW 45 vs 36) positioned further apart (offsetX ±110 vs ±66)
// so the beam reads as a broader, softer bar on white surfaces. Colors also
// shift toward slightly darker tones to hold contrast against white.
// The inner table is theme-agnostic.

constant float4 lineBorderGeomLight[9] = {
  float4(45.0, 36.0,    0.0,  2.0),
  float4(35.0, 32.0,   65.0,  0.0),
  float4(40.0, 28.0,  -60.0,  2.0),
  float4(35.0, 34.0,  -90.0,  0.0),
  float4(38.0, 30.0,   85.0, -1.0),
  float4(50.0, 24.0,   35.0,  1.0),
  float4(40.0, 22.0,  -35.0,  0.0),
  float4(35.0, 28.0,  110.0,  1.0),
  float4(30.0, 30.0, -110.0, -1.0),
};

// GENERATED-BEGIN: lineBorderColorsLight
constant float3 lineBorderColorsLight[36] = {
  // colorful
  float3(255.0,  50.0, 100.0) / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  float3( 50.0, 200.0,  80.0) / 255.0,
  float3(180.0,  40.0, 240.0) / 255.0,
  float3( 30.0, 185.0, 170.0) / 255.0,
  float3(100.0,  70.0, 255.0) / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  float3(255.0, 120.0,  40.0) / 255.0,
  float3(240.0,  50.0, 180.0) / 255.0,
  // mono
  float3(100.0, 100.0, 100.0) / 255.0,
  float3( 80.0,  80.0,  80.0) / 255.0,
  float3( 90.0,  90.0,  90.0) / 255.0,
  float3( 70.0,  70.0,  70.0) / 255.0,
  float3( 85.0,  85.0,  85.0) / 255.0,
  float3( 95.0,  95.0,  95.0) / 255.0,
  float3( 75.0,  75.0,  75.0) / 255.0,
  float3(105.0, 105.0, 105.0) / 255.0,
  float3( 65.0,  65.0,  65.0) / 255.0,
  // ocean
  float3( 80.0,  60.0, 200.0) / 255.0,
  float3( 50.0, 100.0, 220.0) / 255.0,
  float3( 70.0,  90.0, 190.0) / 255.0,
  float3(110.0,  60.0, 220.0) / 255.0,
  float3( 60.0, 110.0, 230.0) / 255.0,
  float3(100.0,  70.0, 240.0) / 255.0,
  float3( 80.0, 100.0, 210.0) / 255.0,
  float3( 90.0,  80.0, 225.0) / 255.0,
  float3(120.0,  90.0, 245.0) / 255.0,
  // sunset
  float3(220.0,  80.0,  40.0) / 255.0,
  float3(230.0, 150.0,  30.0) / 255.0,
  float3(210.0, 110.0,  50.0) / 255.0,
  float3(200.0,  60.0,  60.0) / 255.0,
  float3(220.0, 170.0,  40.0) / 255.0,
  float3(210.0, 100.0,  30.0) / 255.0,
  float3(230.0, 130.0,  60.0) / 255.0,
  float3(190.0,  70.0,  50.0) / 255.0,
  float3(180.0,  50.0,  50.0) / 255.0,
};
// GENERATED-END: lineBorderColorsLight

// Separate samplers for each (layer, theme) pair so the 9-iteration loop has
// no per-iteration branches — Metal can fully unroll each body. Callers pick
// the right function once and pass the result along.

static float3 sampleLineInnerSpots(
  float2 p, float2 size, float beamX, float beamW, float beamH, int variant
) {
  float3 c = float3(0.0);
  int base = variant * 9;
  for (int i = 0; i < 9; i++) {
    c += lineSpot(p, size, beamX, beamW, beamH, lineInnerGeom[i], lineInnerColors[base + i]);
  }
  return c;
}

static float3 sampleLineBorderSpotsDark(
  float2 p, float2 size, float beamX, float beamW, float beamH, int variant
) {
  float3 c = float3(0.0);
  int base = variant * 9;
  for (int i = 0; i < 9; i++) {
    c += lineSpot(p, size, beamX, beamW, beamH, lineBorderGeom[i], lineBorderColors[base + i]);
  }
  return c;
}

static float3 sampleLineBorderSpotsLight(
  float2 p, float2 size, float beamX, float beamW, float beamH, int variant
) {
  float3 c = float3(0.0);
  int base = variant * 9;
  for (int i = 0; i < 9; i++) {
    c += lineSpot(p, size, beamX, beamW, beamH, lineBorderGeomLight[i], lineBorderColorsLight[base + i]);
  }
  return c;
}

// MARK: - Spike geometry & colors
//
// Seven fixed-position vertical spikes sit along the bottom edge. Each has
// its own base width, height, gradient stops, and one of two spike-cycle
// multipliers. They only light up as the traveling bloom mask sweeps over
// their x position. Adjacent multiplier types alternate so the row
// shimmers out of phase rather than pulsing in lockstep.
//
// Minimum width is 8pt — narrower values would alias into sharp vertical
// lines because this shader has no separate gaussian-blur pass.

constant float4 lineSpikeGeom[7] = {
  // (xPercent, yOffsetPx, baseWidthPx, baseHeightPx)
  float4(0.08, 2.0, 10.0, 46.0),
  float4(0.22, 4.0, 12.0, 18.0),
  float4(0.36, 3.0, 10.0, 36.0),
  float4(0.50, 2.0, 16.0, 14.0),
  float4(0.64, 4.0, 10.0, 42.0),
  float4(0.78, 2.0, 10.0, 22.0),
  float4(0.92, 3.0,  8.0, 30.0),
};

/// Gradient fade breakpoints per spike: (midStop, outerStop).
constant float2 lineSpikeStops[7] = {
  float2(0.30, 0.88),
  float2(0.50, 0.95),
  float2(0.40, 0.90),
  float2(0.55, 0.96),
  float2(0.35, 0.89),
  float2(0.48, 0.94),
  float2(0.42, 0.91),
};

/// Multiplier type per spike: 0 = spike1, 1 = spike2, 2 = (2 − spike1), 3 = (2 − spike2).
constant int lineSpikeMultType[7] = {0, 1, 2, 1, 3, 0, 2};

/// 4 palettes × 7 spikes × 2 colors (center, mid) = 56 entries, indexed as
/// `variant * 14 + spike * 2 + (0=center | 1=mid)`. Colors are premultiplied
/// with their per-stop alphas baked in.
// GENERATED-BEGIN: lineSpikeColors
constant float3 lineSpikeColors[56] = {
  // colorful
  float3(255.0,  60.0,  80.0) / 255.0,
  float3(255.0,  60.0,  80.0) / 255.0,
  float3( 40.0, 190.0, 180.0) * 0.98 / 255.0,
  float3( 40.0, 190.0, 180.0) * 0.49 / 255.0,
  float3(100.0,  70.0, 255.0) / 255.0,
  float3(100.0,  70.0, 255.0) / 255.0,
  float3(255.0, 170.0,  40.0) * 0.59 / 255.0,
  float3(255.0, 170.0,  40.0) * 0.29 / 255.0,
  float3( 50.0, 200.0, 100.0) / 255.0,
  float3( 50.0, 200.0, 100.0) / 255.0,
  float3(200.0,  50.0, 240.0) * 0.91 / 255.0,
  float3(200.0,  50.0, 240.0) * 0.45 / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  float3( 40.0, 140.0, 255.0) / 255.0,
  // mono
  float3(200.0, 200.0, 200.0) * 0.14 / 255.0,
  float3(200.0, 200.0, 200.0) * 0.09 / 255.0,
  float3(170.0, 170.0, 170.0) * 0.12 / 255.0,
  float3(170.0, 170.0, 170.0) * 0.06 / 255.0,
  float3(200.0, 200.0, 200.0) * 0.14 / 255.0,
  float3(200.0, 200.0, 200.0) * 0.098 / 255.0,
  float3(180.0, 180.0, 180.0) * 0.0826 / 255.0,
  float3(180.0, 180.0, 180.0) * 0.0284 / 255.0,
  float3(190.0, 190.0, 190.0) * 0.14 / 255.0,
  float3(190.0, 190.0, 190.0) * 0.098 / 255.0,
  float3(170.0, 170.0, 170.0) * 0.1274 / 255.0,
  float3(170.0, 170.0, 170.0) * 0.0441 / 255.0,
  float3(185.0, 185.0, 185.0) * 0.14 / 255.0,
  float3(185.0, 185.0, 185.0) * 0.098 / 255.0,
  // ocean
  float3(100.0, 120.0, 255.0) / 255.0,
  float3(100.0, 120.0, 255.0) / 255.0,
  float3(130.0, 100.0, 220.0) * 0.98 / 255.0,
  float3(130.0, 100.0, 220.0) * 0.49 / 255.0,
  float3(100.0,  80.0, 255.0) / 255.0,
  float3(100.0,  80.0, 255.0) / 255.0,
  float3( 80.0, 130.0, 220.0) * 0.59 / 255.0,
  float3( 80.0, 130.0, 220.0) * 0.29 / 255.0,
  float3( 60.0, 100.0, 255.0) / 255.0,
  float3( 60.0, 100.0, 255.0) / 255.0,
  float3( 90.0, 120.0, 200.0) * 0.91 / 255.0,
  float3( 90.0, 120.0, 200.0) * 0.45 / 255.0,
  float3(120.0,  90.0, 255.0) / 255.0,
  float3(120.0,  90.0, 255.0) / 255.0,
  // sunset
  float3(255.0, 140.0,  80.0) / 255.0,
  float3(255.0, 140.0,  80.0) / 255.0,
  float3(255.0, 100.0,  60.0) * 0.98 / 255.0,
  float3(255.0, 100.0,  60.0) * 0.49 / 255.0,
  float3(255.0, 100.0,  80.0) / 255.0,
  float3(255.0, 100.0,  80.0) / 255.0,
  float3(255.0, 150.0,  80.0) * 0.59 / 255.0,
  float3(255.0, 150.0,  80.0) * 0.29 / 255.0,
  float3(255.0,  80.0,  60.0) / 255.0,
  float3(255.0,  80.0,  60.0) / 255.0,
  float3(255.0, 120.0,  50.0) * 0.91 / 255.0,
  float3(255.0, 120.0,  50.0) * 0.45 / 255.0,
  float3(255.0, 140.0,  70.0) / 255.0,
  float3(255.0, 140.0,  70.0) / 255.0,
};
// GENERATED-END: lineSpikeColors

/// Evaluates all seven spikes at `p` and returns their summed premultiplied RGB.
static float3 renderLineBloomSpikes(
  float2 p, float2 size, float beamH, float spike1, float spike2, int variant
) {
  float3 total = float3(0.0);
  int colorBase = variant * 14;

  for (int i = 0; i < 7; i++) {
    float4 geom = lineSpikeGeom[i];
    float2 stops = lineSpikeStops[i];
    int    mt   = lineSpikeMultType[i];

    float mult = (mt == 0) ? spike1
               : (mt == 1) ? spike2
               : (mt == 2) ? (2.0 - spike1)
                           : (2.0 - spike2);

    float2 center  = float2(geom.x * size.x, size.y - geom.y);
    float2 ellipse = float2(geom.z * mult,   geom.w * beamH);
    float2 local   = (p - center) / ellipse;
    float  d       = length(local);

    if (d >= stops.y) continue;

    float3 cCenter = lineSpikeColors[colorBase + i * 2];
    float3 cMid    = lineSpikeColors[colorBase + i * 2 + 1];
    float3 contribution;
    if (d < stops.x) {
      contribution = mix(cCenter, cMid, d / stops.x);
    } else {
      contribution = mix(cMid, float3(0.0), (d - stops.x) / (stops.y - stops.x));
    }
    total += contribution;
  }
  return total;
}

/// Traveling "comet head" at the beam center: a bright core dot plus a wider
/// soft ambient halo. Both ride with beamX and pulse with the spike cycles.
static float3 renderLineBloomCenter(
  float2 p, float2 size, float beamX, float beamW, float beamH,
  float spike1, float spike2, bool isMono, float inkLuma
) {
  float3 total = float3(0.0);
  float monoScale = isMono ? 0.5 : 1.0;
  float3 ink = float3(inkLuma);

  // Core dot
  {
    float2 center = float2(beamX * size.x, size.y + 1.0);
    float2 ellipse = float2(21.0 * spike1, 15.0 * spike2);
    float2 local = (p - center) / ellipse;
    float d = length(local);
    if (d < 1.0) {
      float a;
      if      (d < 0.20) a = mix(1.00, 0.90, d / 0.20);
      else if (d < 0.50) a = mix(0.90, 0.50, (d - 0.20) / 0.30);
      else               a = mix(0.50, 0.00, (d - 0.50) / 0.50);
      total += ink * a * monoScale;
    }
  }

  // Ambient halo
  {
    float2 center = float2(beamX * size.x, size.y);
    float2 ellipse = float2(42.0 * beamW, 40.0 * beamH);
    float2 local = (p - center) / ellipse;
    float d = length(local);
    if (d < 0.80) {
      float a;
      if      (d < 0.25) a = mix(0.30, 0.12, d / 0.25);
      else if (d < 0.55) a = mix(0.12, 0.03, (d - 0.25) / 0.30);
      else               a = mix(0.03, 0.00, (d - 0.55) / 0.25);
      total += ink * a * monoScale;
    }
  }
  return total;
}

// MARK: - Entry point
//
// Traveling beam along the bottom edge with three composited layers:
//   • inner  — 9 premultiplied color spots masked by a radial ellipse at beam center
//   • stroke — same mask intersected with the 1pt border band, full-color spots
//              plus a soft ink highlight
//   • bloom  — wider radial mask at beam center with colored spots, spike streaks,
//              and a central "hot dot" for the beam head

[[ stitchable ]] half4 beamLine(
  float2 position,
  float4 rect,       // (sizeW, sizeH, cornerRadius, borderWidth)
  float4 timing,     // (time, duration, brightness, saturation)
  float4 opacities,  // (stroke, inner, bloom, strength)
  float4 theme,      // (variant, inkLuma, innerShadowAlpha, inkAlphaScale)
  float4 hueAndScale // (cos, sin, paletteScale, reserved) — paletteScale unused for .line
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

  float2 size = float2(sizeW, sizeH);
  float2 center = size * 0.5;

  float sdfOuter = sdRoundedRect(position, center, size * 0.5, cornerRadius);
  if (sdfOuter > 0.0) return half4(0.0);
  float distFromEdge = -sdfOuter;

  // Four independent cycles at distinct periods so travel, breathe, and the
  // two spike multipliers never lock into a visible repeat pattern.
  float tTravel  = fract(time / max(duration,        0.0001));
  float tBreathe = fract(time / max(duration * 1.3,  0.0001));
  float tSpike1  = fract(time / max(duration * 1.33, 0.0001));
  float tSpike2  = fract(time / max(duration * 1.70, 0.0001));

  // Travel x is nearly linear; w peaks at the center (0.5 → 1.5 → 0.5),
  // which `1 − 0.5·cos(2πt)` approximates to four decimal places.
  float beamX  = mix(0.06, 0.94, tTravel);
  float beamW  = 1.0 - 0.5 * cos(2.0 * M_PI_F * tTravel);
  float beamH  = lineBreatheH(tBreathe);
  float ef     = lineEdgeFade(tTravel);
  float spike1 = curve4(tSpike1, 0.8, 1.3, 0.9, 1.4);
  float spike2 = curve4(tSpike2, 1.2, 0.7, 1.4, 0.8);

  if (ef <= 0.0) return half4(0.0);

  bool useLight = (inkLuma < 0.5);

  // Stroke and bloom masks are evaluated once; the stroke/inner radial mask
  // is shared. Stroke and bloom both sample the non-inner palette, so we
  // compute that once too.
  float mStrokeRadial = lineStrokeRadialMask(position, size, beamX, beamW, beamH);
  float mBloomRadial  = lineBloomRadialMask(position, size, beamX, beamW, beamH);

  bool needFullSpots = (mStrokeRadial > 0.0 || mBloomRadial > 0.0);
  float3 fullSpots = needFullSpots
    ? (useLight
       ? sampleLineBorderSpotsLight(position, size, beamX, beamW, beamH, variant)
       : sampleLineBorderSpotsDark(position, size, beamX, beamW, beamH, variant))
    : float3(0.0);
  float fullGate = needFullSpots ? colorGate(fullSpots, inkLuma) : 0.0;

  // Inner glow (uses the inner-geometry sample, which has its own per-spot alphas)
  half3 innerPrem = half3(0.0);
  half  innerA = 0.0h;
  if (mStrokeRadial > 0.0) {
    float3 spots = sampleLineInnerSpots(position, size, beamX, beamW, beamH, variant);
    float shadowFactor = exp(-(distFromEdge * distFromEdge) / 81.0) * innerShadowAlpha * inkLuma;
    float3 rgb = saturate(mix(spots, float3(inkLuma), shadowFactor));
    // Gate alpha by final rgb so dim between-spot pixels don't paint dark
    // over the card (see the matching comment in Medium.metal).
    float rgbMax = max(max(rgb.r, rgb.g), rgb.b);
    float alpha = mStrokeRadial * innerOpacity * ef * rgbMax;
    innerPrem = half3(rgb * alpha);
    innerA = half(alpha);
  }

  // Stroke (with soft ink highlight at the beam head)
  half3 strokePrem = half3(0.0);
  half  strokeA = 0.0h;
  if (distFromEdge <= borderWidth && mStrokeRadial > 0.0) {
    float2 hlCenter = float2(beamX * size.x, size.y + 2.0);
    float2 hlEllipse = float2(24.0 * beamW, 28.0 * beamH);
    float2 hlLocal = (position - hlCenter) / hlEllipse;
    float hlDist = length(hlLocal);
    float hl = (hlDist >= 1.0) ? 0.0 : (1.0 - hlDist) * 0.38 * inkAlphaScale * inkLuma;
    float3 rgb = saturate(mix(fullSpots, float3(inkLuma), hl));
    float alpha = mStrokeRadial * strokeOpacity * ef * fullGate;
    strokePrem = half3(rgb * alpha);
    strokeA = half(alpha);
  }

  // Bloom (colored spots + spikes + comet head), all gated by the wide radial mask.
  half3 bloomPrem = half3(0.0);
  half  bloomA = 0.0h;
  if (mBloomRadial > 0.0) {
    float3 rgb = saturate(mix(fullSpots, float3(inkLuma), 0.25 * inkLuma));
    rgb += renderLineBloomSpikes(position, size, beamH, spike1, spike2, variant) * 0.6;
    rgb += renderLineBloomCenter(position, size, beamX, beamW, beamH, spike1, spike2, variant == 1, inkLuma);

    float alpha = mBloomRadial * bloomOpacity * ef * 0.5 * inkAlphaScale * fullGate;
    bloomPrem = half3(saturate(rgb) * alpha);
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

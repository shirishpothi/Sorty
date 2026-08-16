#pragma once
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Geometry

/// Signed distance from `p` to a rounded rectangle centered at `center`, with
/// half-extents `b` and corner radius `r`. Negative inside, positive outside.
static inline float sdRoundedRect(float2 p, float2 center, float2 b, float r) {
  float2 q = abs(p - center) - b + r;
  return min(max(q.x, q.y), 0.0) + length(max(q, float2(0.0))) - r;
}

/// Shape-dispatching SDF. `shapeType`:
///   0 — rounded rect (uses `cornerRadius`)
///   1 — capsule       (ignores `cornerRadius`, uses `min(halfSize)`)
///   2 — circle        (inscribed circle; non-square frames get unlit padding)
static inline float sdBeamShape(float2 p, float2 center, float2 halfSize, float cornerRadius, int shapeType) {
  if (shapeType == 2) {
    float r = min(halfSize.x, halfSize.y);
    return length(p - center) - r;
  }
  if (shapeType == 1) {
    float r = min(halfSize.x, halfSize.y);
    return sdRoundedRect(p, center, halfSize, r);
  }
  return sdRoundedRect(p, center, halfSize, cornerRadius);
}

/// Fract-wrapped angle around the center of `size`, offset by the beam's
/// current position along its rotation cycle.
static inline float beamAngleFract(float2 position, float2 size, float time, float duration) {
  float2 d = position - size * 0.5;
  float raw = atan2(d.x, -d.y);
  float angle = raw / (2.0 * M_PI_F);
  if (angle < 0.0) angle += 1.0;
  float beamAngle = fract(time / max(duration, 0.0001));
  return fract(angle - beamAngle);
}

// MARK: - Conic masks
//
// Piecewise-linear LUTs that shape how the beam's angular window ramps in
// and out. The hand-tuned breakpoints are the product of side-by-side
// comparisons with the reference design — adjusting them changes the feel
// of the beam's leading / trailing edges.

static inline float strokeConicMask(float a) {
  if (a < 0.30) return 0.0;
  if (a < 0.36) return mix(0.0,  0.10, (a - 0.30) / 0.06);
  if (a < 0.44) return mix(0.10, 0.35, (a - 0.36) / 0.08);
  if (a < 0.52) return mix(0.35, 1.00, (a - 0.44) / 0.08);
  if (a < 0.80) return 1.0;
  if (a < 0.86) return mix(1.00, 0.35, (a - 0.80) / 0.06);
  if (a < 0.92) return mix(0.35, 0.10, (a - 0.86) / 0.06);
  if (a < 0.95) return mix(0.10, 0.0,  (a - 0.92) / 0.03);
  return 0.0;
}

static inline float whiteConic(float a) {
  if (a < 0.54) return 0.0;
  if (a < 0.57) return mix(0.00, 0.10, (a - 0.54) / 0.03);
  if (a < 0.60) return mix(0.10, 0.30, (a - 0.57) / 0.03);
  if (a < 0.63) return mix(0.30, 0.60, (a - 0.60) / 0.03);
  if (a < 0.66) return mix(0.60, 0.75, (a - 0.63) / 0.03);
  if (a < 0.69) return mix(0.75, 0.60, (a - 0.66) / 0.03);
  if (a < 0.72) return mix(0.60, 0.30, (a - 0.69) / 0.03);
  if (a < 0.75) return mix(0.30, 0.10, (a - 0.72) / 0.03);
  if (a < 0.78) return mix(0.10, 0.00, (a - 0.75) / 0.03);
  return 0.0;
}

static inline float bloomConicMask(float a) {
  if (a < 0.580) return 0.0;
  if (a < 0.620) return mix(0.00, 0.03, (a - 0.580) / 0.040);
  if (a < 0.650) return mix(0.03, 0.08, (a - 0.620) / 0.030);
  if (a < 0.670) return mix(0.08, 0.20, (a - 0.650) / 0.020);
  if (a < 0.690) return mix(0.20, 0.45, (a - 0.670) / 0.020);
  if (a < 0.700) return mix(0.45, 0.85, (a - 0.690) / 0.010);
  if (a < 0.705) return 0.85;
  if (a < 0.715) return mix(0.85, 0.45, (a - 0.705) / 0.010);
  if (a < 0.730) return mix(0.45, 0.20, (a - 0.715) / 0.015);
  if (a < 0.750) return mix(0.20, 0.08, (a - 0.730) / 0.020);
  if (a < 0.780) return mix(0.08, 0.03, (a - 0.750) / 0.030);
  if (a < 0.820) return mix(0.03, 0.00, (a - 0.780) / 0.040);
  return 0.0;
}

// MARK: - Color sampling

/// Premultiplied elliptical radial falloff. Returns `color * (1 - d)` where
/// `d` is normalized distance from the spot center in ellipse-local space.
static inline float3 radialSpot(float2 p, float2 size, float2 posUV, float2 ellipsePx, float3 color) {
  float2 center = posUV * size;
  float2 local = (p - center) / ellipsePx;
  float d = length(local);
  float w = saturate(1.0 - d);
  return color * w;
}

/// Scales a layer's alpha by the strongest channel of its color in light
/// mode. Without this, pixels where palette spots don't overlap would
/// render as `near-black * high_alpha`, producing visible gray smudges on
/// white backgrounds. In dark mode the factor is always 1.0.
///
/// The intensity is `saturate`d so the result can't exceed 1.0 when
/// overlapping palette spots push channels above 1.0 — keeping the
/// premultiplied invariant `rgb ≤ alpha` intact downstream.
static inline float colorGate(float3 spots, float inkLuma) {
  float intensity = saturate(max(max(spots.r, spots.g), spots.b));
  return mix(intensity, 1.0, inkLuma);
}

/// Hue rotation via the YIQ-based matrix from the SVG Filter Effects spec.
/// Linear in RGB, so it commutes with scalar alpha and can be applied
/// directly to premultiplied output without a pre-divide/re-multiply dance.
///
/// Takes `cos(angle)` / `sin(angle)` precomputed on the CPU — the rotation
/// angle is uniform across the entire draw, so running `cos`/`sin` per-pixel
/// would waste cycles on identical results.
static inline float3 hueRotate(float3 rgb, float c, float s) {
  float base = dot(rgb, float3(0.213, 0.715, 0.072));
  float3 cosPart = float3(
     rgb.r *  0.787 + rgb.g * -0.715 + rgb.b * -0.072,
     rgb.r * -0.213 + rgb.g *  0.285 + rgb.b * -0.072,
     rgb.r * -0.213 + rgb.g * -0.715 + rgb.b *  0.928
  );
  float3 sinPart = float3(
     rgb.r * -0.213 + rgb.g * -0.715 + rgb.b *  0.928,
     rgb.r *  0.143 + rgb.g *  0.140 + rgb.b * -0.283,
     rgb.r * -0.787 + rgb.g *  0.715 + rgb.b *  0.072
  );
  return float3(base) + c * cosPart + s * sinPart;
}

// MARK: - Post-processing

/// Shared tail of every entry point: brightness scale, saturation pivot
/// around rec709 luma, hue rotation, and strength multiply.
///
/// The brightness / saturation pair operates on premultiplied RGB: brightness
/// is a linear scale (alpha-preserving), saturation mixes against luma which
/// is also linear in premult — no pre-divide needed.
static inline half4 finalize(half3 rgb, half aout, float brightness, float saturation, float strength, float hueCos, float hueSin) {
  rgb *= half(brightness);
  half luma = dot(rgb, half3(0.2126, 0.7152, 0.0722));
  rgb = mix(half3(luma), rgb, half(saturation));

  float3 rotated = hueRotate(float3(rgb), hueCos, hueSin);
  rgb = half3(rotated);

  half s = half(strength);
  return half4(rgb * s, aout * s);
}

#include "Common.h"

// MARK: - Lens distortion
//
// `.distortionEffect(...)` shader that warps the receiver's pixels near
// the beam's current head position. The effect is tiny — just a few pixels
// of radial push — but it's enough to sell the illusion that the beam is
// a moving piece of liquid glass bending what's beneath it.
//
// The shader doesn't know anything about the beam's render passes; it
// just computes where the head currently is (from time + duration) and
// falls off with a gaussian around that point. Keep the falloff radius
// generous so the distortion reads as a soft lens rather than a sharp
// pinch.

[[ stitchable ]] float2 beamLens(
  float2 position,
  float4 rect,   // (sizeW, sizeH, strength, reserved)
  float4 timing  // (time, duration, _, _)
) {
  float sizeW = rect.x, sizeH = rect.y;
  float strength = rect.z;
  float time = timing.x, duration = timing.y;

  if (strength <= 0.0) return float2(0.0);

  float2 size = float2(sizeW, sizeH);
  float2 center = size * 0.5;

  // Beam head phase — matches the peak angle in `whiteConic` / the comet's
  // head so the lens moves exactly with the brightest pixel of the beam.
  float beamAngle = fract(time / max(duration, 0.0001));
  float headAngle = (0.67 + beamAngle) * 2.0 * M_PI_F;

  // atan2(x, -y) convention means angle 0 = up, 0.25 = right, etc.
  // Invert that to go from angle → direction vector: dir = (sin, -cos).
  float2 dir = float2(sin(headAngle), -cos(headAngle));

  // Project the direction ray from center to the bounding rect's edge —
  // that's roughly where the beam head sits at this moment. For capsule
  // and circle shapes the head sits on the inscribed perimeter, which is
  // close enough to this rect approximation that the lens still reads as
  // aligned with the beam.
  float2 halfSize = size * 0.5;
  float tx = halfSize.x / max(abs(dir.x), 1e-6);
  float ty = halfSize.y / max(abs(dir.y), 1e-6);
  float t = min(tx, ty);
  float2 headPos = center + dir * t;

  // Gaussian falloff around the head. Radius tuned so the lens is roughly
  // the same width as the beam's hot zone — visible but not distracting.
  float2 delta = position - headPos;
  float dist = length(delta);
  float radius = 42.0;
  float gain = exp(-dist * dist / (radius * radius)) * strength;

  // Push pixels radially outward from the head — the classic "glass bead
  // making a bump" look. Pull inward (negate) if we ever want a
  // "suction" aesthetic.
  float2 offset = (dist > 0.001) ? (delta / dist) * gain : float2(0.0);
  return offset;
}

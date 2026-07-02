'use client'

// Dia Browser's signature gradient — a self-contained drop-in.
//
// A row of N tall, heavily-blurred columns share one vertical rainbow gradient
// and are arranged in a symmetric bell curve (short at the edges, tallest in the
// middle). The whole field is anchored to the bottom and RISES UP FROM THE FLOOR
// the first time it scrolls into view via a one-shot scaleY(0) → 1 + opacity 0 → 1
// reveal (transform-origin: bottom), then stays put — it doesn't fade back out
// when you scroll up, so the bloom is always present at the footer. It's one
// inline <svg> — no canvas, no per-frame work.
//
// Usage:
//   <div className="absolute inset-x-0 bottom-0 h-[55vh] pointer-events-none">
//     <DiaGradient />
//   </div>

import { useEffect, useState } from 'react'

type Stop = { offset: number; color: string }

// Sorty's footer stops, bottom (0) → top (1): deep blue → cyan → ice → clear.
const DIA_STOPS: Stop[] = [
  { offset: 0, color: '#03111F' },
  { offset: 0.18, color: '#0647D8' },
  { offset: 0.34, color: '#0A84FF' },
  { offset: 0.52, color: '#4BB8FF' },
  { offset: 0.68, color: '#D8F3FF' },
  { offset: 0.84, color: '#7DD3FC80' },
  { offset: 1, color: '#E0F2FE00' },
]

const VBW = 1271
const VBH = 599

// Height curve fitted to the real Dia footer: a gentle power falloff (not a
// cosine bell), giving the flatter, pyramid-like rise of the original.
function bellHeights(n: number, peak: number, valley: number): number[] {
  const out: number[] = []
  const mid = (n - 1) / 2
  for (let i = 0; i < n; i++) {
    const t = mid === 0 ? 0 : Math.abs(i - mid) / mid // 0 center → 1 edge
    const eased = 1 - Math.pow(t, 1.24) // 1 at center → 0 at edge
    out.push(peak * VBH * (valley + (1 - valley) * eased))
  }
  return out
}

export function DiaGradient({
  bars = 9,
  blur = 15,
  peak = 0.98,
  valley = 0.55,
  stops = DIA_STOPS,
  riseMs = 1100,
  strength = 1,
}: {
  bars?: number
  blur?: number
  peak?: number
  valley?: number
  stops?: Stop[]
  riseMs?: number
  /** Peak opacity of the painted field (0..1). Applied to the <svg> so the
   *  wrapper's 0→1 rise opacity still animates independently on top of it. */
  strength?: number
}) {
  const [shown, setShown] = useState(false)

  useEffect(() => {
    const prefersReduced = window.matchMedia(
      '(prefers-reduced-motion: reduce)',
    ).matches
    if (prefersReduced) {
      setShown(true)
      return
    }
    // Double-rAF so the browser paints the flat (scaleY 0) state first, then
    // transitions up — otherwise the initial state is never painted and the
    // rise animation is skipped.
    const id = requestAnimationFrame(() =>
      requestAnimationFrame(() => setShown(true)),
    )
    return () => cancelAnimationFrame(id)
  }, [])

  const heights = bellHeights(bars, peak, valley)
  const colW = VBW / bars

  return (
    <div
      aria-hidden
      style={{
        height: '100%',
        width: '100%',
        transformOrigin: 'bottom',
        transform: shown ? 'scaleY(1)' : 'scaleY(0)',
        opacity: shown ? 1 : 0,
        transition: `transform ${riseMs}ms cubic-bezier(0.16, 1, 0.3, 1), opacity ${riseMs}ms cubic-bezier(0.16, 1, 0.3, 1)`,
        willChange: 'transform, opacity',
      }}
    >
      <svg
        style={{ height: '100%', width: '100%', opacity: strength }}
        viewBox={`0 0 ${VBW} ${VBH}`}
        preserveAspectRatio="none"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        <defs>
          {/* objectBoundingBox units (default): the gradient maps to each rect's
              own box, so every bar shows the full rainbow over its own height —
              a field of full-rainbow columns, the way the real Dia footer does it. */}
          <linearGradient id="dia-grad" x1="0" y1="1" x2="0" y2="0">
            {stops.map((s, i) => (
              <stop key={i} offset={s.offset} stopColor={s.color} />
            ))}
          </linearGradient>
          <filter id="dia-blur" x="-50%" y="-50%" width="200%" height="200%">
            <feGaussianBlur stdDeviation={blur} />
          </filter>
        </defs>
        {heights.map((h, i) => (
          <g key={i} filter="url(#dia-blur)">
            <rect
              x={i * colW}
              y={VBH - h}
              width={colW * 1.23}
              height={h}
              fill="url(#dia-grad)"
            />
          </g>
        ))}
      </svg>
    </div>
  )
}

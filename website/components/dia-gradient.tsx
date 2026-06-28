'use client'

// Dia Browser's signature gradient — a self-contained drop-in.
//
// A row of N tall, heavily-blurred columns share one vertical rainbow gradient
// and are arranged in a symmetric bell curve (short at the edges, tallest in the
// middle). The whole field is anchored to the bottom and RISES UP on mount via a
// scaleY(0) → 1 transform (transform-origin: bottom), so it unfurls from the
// floor like an aurora. It's one inline <svg> — no canvas, no per-frame work.
//
// Usage:
//   <div className="absolute inset-x-0 bottom-0 h-[55vh] pointer-events-none">
//     <DiaGradient />
//   </div>

import { useEffect, useState } from 'react'

type Stop = { offset: number; color: string }

// Dia's stops, bottom (0) → top (1): dark ember → blue → near-white → yellow →
// red-orange → magenta → transparent pink.
const DIA_STOPS: Stop[] = [
  { offset: 0, color: '#340B05' },
  { offset: 0.1827, color: '#0358F7' },
  { offset: 0.2837, color: '#5092C7' },
  { offset: 0.4135, color: '#E1ECFE' },
  { offset: 0.5866, color: '#FFD400' },
  { offset: 0.6827, color: '#FA3D1D' },
  { offset: 0.8029, color: '#FD02F5' },
  { offset: 1, color: '#FFC0FD00' },
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
}: {
  bars?: number
  blur?: number
  peak?: number
  valley?: number
  stops?: Stop[]
  riseMs?: number
}) {
  const prefersReduced =
    typeof window !== 'undefined' &&
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  const [shown, setShown] = useState(prefersReduced)

  useEffect(() => {
    if (prefersReduced) {
      setShown(true)
      return
    }
    const id = requestAnimationFrame(() =>
      requestAnimationFrame(() => setShown(true)),
    )
    return () => cancelAnimationFrame(id)
  }, [prefersReduced])

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
        transition: `transform ${riseMs}ms cubic-bezier(0.16, 1, 0.3, 1)`,
        willChange: 'transform',
      }}
    >
      <svg
        style={{ height: '100%', width: '100%' }}
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

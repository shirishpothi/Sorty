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

import { useEffect, useRef, useState } from 'react'

type Stop = { offset: number; color: string }

// Sorty's blue take on the Dia footer: same dark-to-bright-to-clear rhythm as
// the reference, mapped into navy, electric blue, ice, and transparent cyan.
const DIA_STOPS: Stop[] = [
  { offset: 0, color: '#020617' },
  { offset: 0.1827, color: '#0358F7' },
  { offset: 0.2837, color: '#38BDF8' },
  { offset: 0.4135, color: '#E1F4FF' },
  { offset: 0.5866, color: '#8BE8FF' },
  { offset: 0.6827, color: '#2563EB' },
  { offset: 0.8029, color: '#1D4ED8' },
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
  flattenOnScroll = true,
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
  flattenOnScroll?: boolean
}) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const scrollRef = useRef<HTMLDivElement>(null)
  const [shown, setShown] = useState(false)
  const [size, setSize] = useState<{ w: number; h: number } | null>(null)

  // Track the rendered size. preserveAspectRatio="none" stretches the viewBox
  // to fit, which distorts anything specified in viewBox units — most
  // noticeably the blur: on a phone the horizontal blur collapses to a few
  // pixels and the columns turn into hard-edged stripes. Knowing the real
  // size lets us compensate below.
  useEffect(() => {
    const el = wrapRef.current
    if (!el) return
    const observer = new ResizeObserver((entries) => {
      const entry = entries[0]
      if (!entry) return
      const { width, height } = entry.contentRect
      if (width > 0 && height > 0) setSize({ w: width, h: height })
    })
    observer.observe(el)
    return () => observer.disconnect()
  }, [])

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

  // Scroll flatten lives on its own inner element, driven imperatively by a
  // rAF loop that eases the current scale/opacity toward a scroll-derived
  // target each frame (exponential smoothing). No React state and no CSS
  // transition here: state-per-scroll-frame plus a restarting transition is
  // what made the old version feel stepped and abrupt.
  useEffect(() => {
    if (!flattenOnScroll) return

    const prefersReduced = window.matchMedia(
      '(prefers-reduced-motion: reduce)',
    ).matches
    if (prefersReduced) return

    const anim = { scale: 1, opacity: 1, targetScale: 1, targetOpacity: 1 }
    let frame = 0
    let lastTime = 0

    const computeTargets = () => {
      const el = wrapRef.current
      if (!el) return
      // rect.bottom is invariant under our bottom-origin scaleY, so measuring
      // the (possibly mid-animation) wrapper is safe — no feedback loop.
      const rect = el.getBoundingClientRect()
      const viewportHeight = window.innerHeight || 1
      const awayDistance = viewportHeight * 0.52
      const p = Math.max(
        0,
        Math.min(1, (rect.bottom - viewportHeight) / awayDistance),
      )
      // Smoothstep: zero slope at both ends, so the effect ramps in and out
      // gently instead of kicking in abruptly at the boundaries.
      const eased = p * p * (3 - 2 * p)
      anim.targetScale = 1 - eased * 0.34
      anim.targetOpacity = 1 - eased * 0.22
    }

    const apply = () => {
      const el = scrollRef.current
      if (!el) return
      el.style.transform = `scaleY(${anim.scale})`
      el.style.opacity = String(anim.opacity)
    }

    const step = (now: number) => {
      frame = 0
      const dt = lastTime ? Math.min(now - lastTime, 64) : 16
      lastTime = now
      // Exponential smoothing toward the target (time constant ~120ms):
      // frame-rate independent, always converging, never restarts.
      const k = 1 - Math.exp(-dt / 120)
      anim.scale += (anim.targetScale - anim.scale) * k
      anim.opacity += (anim.targetOpacity - anim.opacity) * k
      const settled =
        Math.abs(anim.targetScale - anim.scale) < 0.0005 &&
        Math.abs(anim.targetOpacity - anim.opacity) < 0.0005
      if (settled) {
        anim.scale = anim.targetScale
        anim.opacity = anim.targetOpacity
      }
      apply()
      if (!settled) {
        frame = requestAnimationFrame(step)
      } else {
        lastTime = 0
      }
    }

    const kick = () => {
      computeTargets()
      if (!frame) frame = requestAnimationFrame(step)
    }

    // Start at the current target so initial paint doesn't animate — the
    // one-shot rise on the outer wrapper owns the entrance.
    computeTargets()
    anim.scale = anim.targetScale
    anim.opacity = anim.targetOpacity
    apply()

    window.addEventListener('scroll', kick, { passive: true })
    window.addEventListener('resize', kick)
    return () => {
      if (frame) cancelAnimationFrame(frame)
      window.removeEventListener('scroll', kick)
      window.removeEventListener('resize', kick)
    }
  }, [flattenOnScroll])

  // On narrow screens, fewer columns keep the same chunky rhythm the field
  // has on desktop instead of squeezing all of them into skinny stripes.
  const effectiveBars = size && size.w < 640 ? Math.min(bars, 6) : bars
  // Anisotropic blur compensation: never let the on-screen blur drop below
  // what desktop gets. When the viewBox is squeezed (narrow/tall phone
  // layouts), scale the stdDeviation up per-axis so the bloom stays soft.
  const blurX = size ? blur * Math.max(1, Math.min(4, VBW / size.w)) : blur
  const blurY = size ? blur * Math.max(1, Math.min(4, VBH / size.h)) : blur

  const heights = bellHeights(effectiveBars, peak, valley)
  const colW = VBW / effectiveBars

  return (
    <div
      ref={wrapRef}
      aria-hidden
      style={{
        height: '100%',
        width: '100%',
        transformOrigin: 'bottom',
        transform: `scaleY(${shown ? 1 : 0})`,
        opacity: shown ? 1 : 0,
        transition: `transform ${riseMs}ms cubic-bezier(0.16, 1, 0.3, 1), opacity ${riseMs}ms cubic-bezier(0.16, 1, 0.3, 1)`,
      }}
    >
      <div
        ref={scrollRef}
        style={{
          height: '100%',
          width: '100%',
          transformOrigin: 'bottom',
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
            <feGaussianBlur stdDeviation={`${blurX} ${blurY}`} />
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
    </div>
  )
}

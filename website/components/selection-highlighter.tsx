'use client'

import { useEffect } from 'react'
import { highlightSelection, type HighlightOptions } from '@highlighters/core'

const SORTY_SELECTION_HIGHLIGHT: HighlightOptions = {
  color: '#4f8cff',
  opacity: 0.58,
  vivid: true,
  tip: {
    type: 'chisel',
    angle: 8,
    overshoot: 1,
    overshootJitter: 0.75,
  },
  ink: {
    flow: 0.5,
    viscosity: 0.5,
    feathering: 0.2,
    streakiness: 0.22,
    dryout: 0.04,
    startEndBuildup: 0.12,
    flowFade: 0.12,
  },
  edge: {
    waviness: 1,
    frequency: 22,
    roughness: 0.2,
    cap: 'round',
    radius: 4,
  },
  paper: {
    absorbency: 0.18,
  },
  glow: {
    enabled: true,
    intensity: 0.1,
    spread: 4,
    color: '#6ea2ff',
  },
  snap: 'none',
  fadeOnClear: true,
  animation: {
    draw: false,
  },
}

export function SelectionHighlighter() {
  useEffect(() => {
    const handle = highlightSelection(SORTY_SELECTION_HIGHLIGHT)
    return () => handle.remove()
  }, [])

  return null
}

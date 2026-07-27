'use client'

import type { ReactElement } from 'react'
import { SmoothCorners } from '@lisse/react'

type SquircleProps = {
  children: ReactElement
  radius?: number
  smoothing?: number
}

export function Squircle({
  children,
  radius = 24,
  smoothing = 0.8,
}: SquircleProps) {
  return (
    <SmoothCorners
      asChild
      corners={{ radius, smoothing, preserveSmoothing: true }}
    >
      {children}
    </SmoothCorners>
  )
}

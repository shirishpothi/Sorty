'use client'

import { useEffect } from 'react'

const SETTLE_DELAY_MS = 140
const SETTLE_DURATION_MS = 620
const SNAP_OFFSET_PX = 96
const MAX_SETTLE_DISTANCE_RATIO = 0.48

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function supportsDesktopSnapLayout() {
  return window.matchMedia('(min-width: 768px)').matches
}

function targetScrollY(section: Element) {
  const sectionTop = window.scrollY + section.getBoundingClientRect().top
  return Math.max(0, sectionTop - SNAP_OFFSET_PX)
}

function nearestSectionTarget() {
  const sections = Array.from(document.querySelectorAll('.snap-section'))
  if (sections.length < 2) return null

  let nearestTarget = targetScrollY(sections[0])
  let nearestDistance = Math.abs(window.scrollY - nearestTarget)

  sections.forEach((section) => {
    const target = targetScrollY(section)
    const distance = Math.abs(window.scrollY - target)
    if (distance < nearestDistance) {
      nearestDistance = distance
      nearestTarget = target
    }
  })

  return {
    distance: nearestDistance,
    y: nearestTarget,
  }
}

function easeInOutCubic(progress: number) {
  return progress < 0.5
    ? 4 * progress * progress * progress
    : 1 - Math.pow(-2 * progress + 2, 3) / 2
}

function animateScrollTo(targetY: number, onComplete: () => void) {
  const startY = window.scrollY
  const distance = targetY - startY
  const startTime = performance.now()
  let frameId = 0

  const step = (time: number) => {
    const progress = Math.min((time - startTime) / SETTLE_DURATION_MS, 1)
    window.scrollTo(0, startY + distance * easeInOutCubic(progress))

    if (progress < 1) {
      frameId = window.requestAnimationFrame(step)
      return
    }

    window.scrollTo(0, targetY)
    onComplete()
  }

  frameId = window.requestAnimationFrame(step)

  return () => window.cancelAnimationFrame(frameId)
}

function isEditableTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false
  return Boolean(target.closest('input, textarea, select, [contenteditable="true"]'))
}

export function SectionScrollController() {
  useEffect(() => {
    if (prefersReducedMotion()) return
    if (!supportsDesktopSnapLayout()) return

    let settleTimer: ReturnType<typeof window.setTimeout> | undefined
    let cancelScrollAnimation: (() => void) | undefined

    const cancelSettle = () => {
      window.clearTimeout(settleTimer)
      settleTimer = undefined
      cancelScrollAnimation?.()
      cancelScrollAnimation = undefined
    }

    const settleToNearestSection = () => {
      const nearest = nearestSectionTarget()
      if (!nearest) return
      if (nearest.distance < 8) return
      if (nearest.distance > window.innerHeight * MAX_SETTLE_DISTANCE_RATIO) return

      document.documentElement.dataset.snapScrolling = 'true'
      cancelScrollAnimation = animateScrollTo(nearest.y, () => {
        delete document.documentElement.dataset.snapScrolling
        cancelScrollAnimation = undefined
      })
    }

    const onWheel = (event: WheelEvent) => {
      if (event.defaultPrevented) return
      if (event.ctrlKey || event.metaKey || event.altKey) return
      if (isEditableTarget(event.target)) return
      if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) return

      cancelSettle()
      settleTimer = window.setTimeout(settleToNearestSection, SETTLE_DELAY_MS)
    }

    const onInterrupt = () => {
      cancelSettle()
      delete document.documentElement.dataset.snapScrolling
    }

    window.addEventListener('wheel', onWheel, { passive: true })
    window.addEventListener('keydown', onInterrupt)
    window.addEventListener('touchstart', onInterrupt, { passive: true })

    return () => {
      cancelSettle()
      delete document.documentElement.dataset.snapScrolling
      window.removeEventListener('wheel', onWheel)
      window.removeEventListener('keydown', onInterrupt)
      window.removeEventListener('touchstart', onInterrupt)
    }
  }, [])

  return null
}

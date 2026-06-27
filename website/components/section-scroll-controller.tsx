'use client'

import { useEffect } from 'react'

const SNAP_DURATION_MS = 1150
const SNAP_COOLDOWN_MS = SNAP_DURATION_MS + 120
const SNAP_DELTA_THRESHOLD = 52

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function supportsDesktopSnapLayout() {
  return window.matchMedia('(min-width: 768px)').matches
}

function sectionDistanceFromViewportCenter(section: Element) {
  const rect = section.getBoundingClientRect()
  const sectionCenter = rect.top + rect.height / 2
  return Math.abs(sectionCenter - window.innerHeight / 2)
}

function currentSectionIndex(sections: Element[]) {
  let nearestIndex = 0
  let nearestDistance = Number.POSITIVE_INFINITY

  sections.forEach((section, index) => {
    const distance = sectionDistanceFromViewportCenter(section)
    if (distance < nearestDistance) {
      nearestDistance = distance
      nearestIndex = index
    }
  })

  return nearestIndex
}

function easeInOutQuint(progress: number) {
  return progress < 0.5
    ? 16 * progress * progress * progress * progress * progress
    : 1 - Math.pow(-2 * progress + 2, 5) / 2
}

function scrollSectionIntoView(section: Element, onComplete: () => void) {
  const startY = window.scrollY
  const targetY = Math.max(0, startY + section.getBoundingClientRect().top)
  const distance = targetY - startY
  const startTime = performance.now()
  let frameId = 0

  const step = (time: number) => {
    const elapsed = time - startTime
    const progress = Math.min(elapsed / SNAP_DURATION_MS, 1)
    const eased = easeInOutQuint(progress)

    window.scrollTo(0, startY + distance * eased)

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

export function SectionScrollController() {
  useEffect(() => {
    if (prefersReducedMotion()) return
    if (!supportsDesktopSnapLayout()) return

    let accumulatedDelta = 0
    let lastSnapAt = 0
    let resetTimer: ReturnType<typeof window.setTimeout> | undefined
    let cancelScrollAnimation: (() => void) | undefined

    const snapToSection = (direction: 1 | -1) => {
      const sections = Array.from(document.querySelectorAll('.snap-section'))
      if (sections.length < 2) return

      const activeIndex = currentSectionIndex(sections)
      const targetIndex = Math.min(
        Math.max(activeIndex + direction, 0),
        sections.length - 1,
      )

      if (targetIndex === activeIndex) return

      document.documentElement.dataset.snapScrolling = 'true'
      cancelScrollAnimation?.()
      cancelScrollAnimation = scrollSectionIntoView(sections[targetIndex], () => {
        delete document.documentElement.dataset.snapScrolling
        cancelScrollAnimation = undefined
      })
    }

    const onWheel = (event: WheelEvent) => {
      if (event.defaultPrevented || Math.abs(event.deltaY) < 2) return
      if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) return

      const now = Date.now()
      if (now - lastSnapAt < SNAP_COOLDOWN_MS) {
        event.preventDefault()
        return
      }

      accumulatedDelta += event.deltaY
      window.clearTimeout(resetTimer)
      resetTimer = window.setTimeout(() => {
        accumulatedDelta = 0
      }, 140)

      if (Math.abs(accumulatedDelta) < SNAP_DELTA_THRESHOLD) return

      event.preventDefault()
      lastSnapAt = now
      const direction = accumulatedDelta > 0 ? 1 : -1
      accumulatedDelta = 0
      snapToSection(direction)
    }

    window.addEventListener('wheel', onWheel, { passive: false })
    return () => {
      window.clearTimeout(resetTimer)
      cancelScrollAnimation?.()
      delete document.documentElement.dataset.snapScrolling
      window.removeEventListener('wheel', onWheel)
    }
  }, [])

  return null
}

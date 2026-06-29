'use client'

import { useEffect } from 'react'

const MIN_DESKTOP_WIDTH_PX = 768
const NAV_OFFSET_PX = 96
const WHEEL_INTENT_THRESHOLD = 18
const TOUCH_INTENT_THRESHOLD = 48
const SCROLL_DURATION_MS = 980
const RELEASE_DELAY_MS = 90

type ScrollDirection = 1 | -1

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}

function supportsSectionScroll() {
  return window.matchMedia(`(min-width: ${MIN_DESKTOP_WIDTH_PX}px)`).matches
}

function sectionTargets() {
  return Array.from(
    document.querySelectorAll<HTMLElement>('.snap-section, footer'),
  ).map((section) => {
    const top = window.scrollY + section.getBoundingClientRect().top
    return Math.max(0, Math.round(top - NAV_OFFSET_PX))
  })
}

function nearestTargetIndex(targets: number[]) {
  let nearestIndex = 0
  let nearestDistance = Number.POSITIVE_INFINITY

  targets.forEach((target, index) => {
    const distance = Math.abs(window.scrollY - target)
    if (distance < nearestDistance) {
      nearestIndex = index
      nearestDistance = distance
    }
  })

  return nearestIndex
}

function targetIndexForDirection(direction: ScrollDirection) {
  const targets = sectionTargets()
  if (targets.length < 2) return null

  const currentIndex = nearestTargetIndex(targets)
  const targetIndex = Math.min(
    Math.max(currentIndex + direction, 0),
    targets.length - 1,
  )

  return {
    y: targets[targetIndex],
  }
}

function easeOutExpo(progress: number) {
  if (progress === 1) return 1
  return 1 - Math.pow(2, -10 * progress)
}

function animateScrollTo(targetY: number, onComplete: () => void) {
  const startY = window.scrollY
  const distance = targetY - startY
  const startTime = performance.now()
  let frameId = 0

  const step = (time: number) => {
    const progress = Math.min((time - startTime) / SCROLL_DURATION_MS, 1)
    const eased = easeOutExpo(progress)

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

function isEditableTarget(target: EventTarget | null) {
  if (!(target instanceof HTMLElement)) return false
  return Boolean(
    target.closest('input, textarea, select, [contenteditable="true"]'),
  )
}

function shouldIgnoreWheel(event: WheelEvent) {
  if (event.defaultPrevented) return true
  if (event.ctrlKey || event.metaKey || event.altKey) return true
  if (Math.abs(event.deltaX) > Math.abs(event.deltaY)) return true
  return isEditableTarget(event.target)
}

export function SectionScrollController() {
  useEffect(() => {
    if (prefersReducedMotion()) return
    if (!supportsSectionScroll()) return

    let wheelIntent = 0
    let touchStartY: number | undefined
    let releaseTimer: ReturnType<typeof window.setTimeout> | undefined
    let cancelScrollAnimation: (() => void) | undefined

    const release = () => {
      window.clearTimeout(releaseTimer)
      releaseTimer = undefined
      delete document.documentElement.dataset.sectionScrolling
      cancelScrollAnimation = undefined
    }

    const startSectionScroll = (direction: ScrollDirection) => {
      const target = targetIndexForDirection(direction)
      if (!target) return

      wheelIntent = 0

      if (Math.abs(window.scrollY - target.y) < 2) {
        release()
        return
      }

      cancelScrollAnimation?.()
      document.documentElement.dataset.sectionScrolling = 'true'

      cancelScrollAnimation = animateScrollTo(target.y, () => {
        releaseTimer = window.setTimeout(release, RELEASE_DELAY_MS)
      })
    }

    const interrupt = () => {
      window.clearTimeout(releaseTimer)
      releaseTimer = undefined
      cancelScrollAnimation?.()
      cancelScrollAnimation = undefined
      wheelIntent = 0
      delete document.documentElement.dataset.sectionScrolling
    }

    const onWheel = (event: WheelEvent) => {
      if (shouldIgnoreWheel(event)) return

      event.preventDefault()

      if (document.documentElement.dataset.sectionScrolling === 'true') return

      wheelIntent += event.deltaY
      if (Math.abs(wheelIntent) < WHEEL_INTENT_THRESHOLD) return

      startSectionScroll(wheelIntent > 0 ? 1 : -1)
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (isEditableTarget(event.target)) return

      const nextKeys = ['ArrowDown', 'PageDown', 'Space']
      const previousKeys = ['ArrowUp', 'PageUp']

      if (nextKeys.includes(event.code)) {
        event.preventDefault()
        if (document.documentElement.dataset.sectionScrolling !== 'true') {
          startSectionScroll(1)
        }
        return
      }

      if (previousKeys.includes(event.code)) {
        event.preventDefault()
        if (document.documentElement.dataset.sectionScrolling !== 'true') {
          startSectionScroll(-1)
        }
      }
    }

    const onTouchStart = (event: TouchEvent) => {
      if (event.touches.length !== 1) return
      touchStartY = event.touches[0].clientY
    }

    const onTouchMove = (event: TouchEvent) => {
      if (touchStartY === undefined || event.touches.length !== 1) return

      const deltaY = touchStartY - event.touches[0].clientY
      if (Math.abs(deltaY) < TOUCH_INTENT_THRESHOLD) return

      event.preventDefault()

      if (document.documentElement.dataset.sectionScrolling !== 'true') {
        startSectionScroll(deltaY > 0 ? 1 : -1)
      }

      touchStartY = undefined
    }

    const onResize = () => {
      if (!supportsSectionScroll()) interrupt()
    }

    window.addEventListener('wheel', onWheel, { passive: false })
    window.addEventListener('keydown', onKeyDown)
    window.addEventListener('touchstart', onTouchStart, { passive: true })
    window.addEventListener('touchmove', onTouchMove, { passive: false })
    window.addEventListener('resize', onResize)

    return () => {
      interrupt()
      window.removeEventListener('wheel', onWheel)
      window.removeEventListener('keydown', onKeyDown)
      window.removeEventListener('touchstart', onTouchStart)
      window.removeEventListener('touchmove', onTouchMove)
      window.removeEventListener('resize', onResize)
    }
  }, [])

  return null
}

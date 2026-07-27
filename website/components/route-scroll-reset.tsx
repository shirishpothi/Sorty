'use client'

import { useLayoutEffect } from 'react'
import { usePathname } from 'next/navigation'

export function RouteScrollReset() {
  const pathname = usePathname()

  useLayoutEffect(() => {
    const root = document.documentElement
    const previousScrollBehavior = root.style.scrollBehavior

    root.style.scrollBehavior = 'auto'
    window.scrollTo(0, 0)

    const restoreAnimation = window.requestAnimationFrame(() => {
      root.style.scrollBehavior = previousScrollBehavior
    })

    return () => {
      window.cancelAnimationFrame(restoreAnimation)
      root.style.scrollBehavior = previousScrollBehavior
    }
  }, [pathname])

  return null
}

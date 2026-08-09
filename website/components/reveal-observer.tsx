'use client'

import { useEffect } from 'react'
import { usePathname } from 'next/navigation'

export function RevealObserver() {
  const pathname = usePathname()

  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) {
            continue
          }

          entry.target.classList.add('is-visible')
          observer.unobserve(entry.target)
        }
      },
      { threshold: 0.15, rootMargin: '0px 0px -8% 0px' },
    )

    const frame = window.requestAnimationFrame(() => {
      document
        .querySelectorAll<HTMLElement>('.reveal:not(.is-visible)')
        .forEach((element) => observer.observe(element))
    })

    return () => {
      window.cancelAnimationFrame(frame)
      observer.disconnect()
    }
  }, [pathname])

  return null
}

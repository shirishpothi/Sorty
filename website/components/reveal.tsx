'use client'

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ElementType,
  type ReactNode,
} from 'react'
import { cn } from '@/lib/utils'

interface RevealProps {
  children: ReactNode
  className?: string
  /** Delay in ms before the element animates in. */
  delay?: number
  as?: ElementType
}

export function Reveal({ children, className, delay = 0, as }: RevealProps) {
  const Tag = (as ?? 'div') as ElementType
  const ref = useRef<HTMLElement>(null)
  const [visible, setVisible] = useState(false)

  useLayoutEffect(() => {
    const node = ref.current
    if (!node) return

    const bounds = node.getBoundingClientRect()
    if (bounds.top < window.innerHeight && bounds.bottom > 0) {
      setVisible(true)
    }
  }, [])

  useEffect(() => {
    if (visible) return

    const node = ref.current
    if (!node) return

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setVisible(true)
            observer.unobserve(entry.target)
          }
        })
      },
      { threshold: 0.15, rootMargin: '0px 0px -8% 0px' },
    )

    observer.observe(node)
    return () => observer.disconnect()
  }, [visible])

  return (
    <Tag
      ref={ref}
      className={cn('reveal', visible && 'is-visible', className)}
      style={delay ? { transitionDelay: `${delay}ms` } : undefined}
    >
      {children}
    </Tag>
  )
}

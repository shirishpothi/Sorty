import { type ElementType, type ReactNode } from 'react'
import { cn } from '@/lib/utils'

interface RevealProps {
  children: ReactNode
  className?: string
  /** Delay in ms before the element animates in. */
  delay?: number
  /** Render visible immediately for content already in the initial viewport. */
  immediate?: boolean
  /** Animate immediate content from its initial painted state without replaying. */
  animateOnEnter?: boolean
  as?: ElementType
}

export function Reveal({
  children,
  className,
  delay = 0,
  immediate = false,
  animateOnEnter = false,
  as,
}: RevealProps) {
  const Tag = (as ?? 'div') as ElementType

  return (
    <Tag
      className={cn(
        'reveal',
        immediate && 'is-visible',
        immediate && animateOnEnter && 'reveal-on-enter',
        className,
      )}
      style={delay ? { transitionDelay: `${delay}ms` } : undefined}
    >
      {children}
    </Tag>
  )
}

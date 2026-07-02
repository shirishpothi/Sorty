'use client'

import { BorderBeam } from 'border-beam'
import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/utils'

type DownloadButtonProps = Omit<
  AnchorHTMLAttributes<HTMLAnchorElement>,
  'children' | 'className' | 'href' | 'rel' | 'target'
> & {
  href: string
  children: ReactNode
  className?: string
}

export function DownloadButton({
  href,
  children,
  className,
  onClick,
  ...props
}: DownloadButtonProps) {
  const widthClassName = className
    ?.split(/\s+/)
    .filter((token) => /^(?:\w+:)*w-/.test(token))
    .join(' ')

  return (
    <BorderBeam
      size="sm"
      colorVariant="ocean"
      theme="dark"
      strength={0.92}
      duration={2.4}
      borderRadius={999}
      className={cn('download-beam', widthClassName)}
    >
      <a
        href={href}
        onClick={(event) => {
          onClick?.(event)

          if (!event.defaultPrevented) {
            window.alert(
              'Your Sorty download should start soon.\n\nAfter moving Sorty.app to Applications, run:\n\nxattr -cr /Applications/Sorty.app',
            )
          }
        }}
        className={cn('btn-download flex items-center rounded-full', className)}
        {...props}
      >
        {children}
      </a>
    </BorderBeam>
  )
}

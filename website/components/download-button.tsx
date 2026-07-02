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
        target="_blank"
        rel="noreferrer"
        className={cn('btn-download flex items-center rounded-full', className)}
        {...props}
      >
        <span className="finder-mark" aria-hidden="true">
          <span className="finder-mark-half finder-mark-left" />
          <span className="finder-mark-half finder-mark-right" />
          <span className="finder-mark-face finder-mark-face-left" />
          <span className="finder-mark-face finder-mark-face-right" />
          <span className="finder-mark-smile" />
        </span>
        <span className="download-label">{children}</span>
      </a>
    </BorderBeam>
  )
}

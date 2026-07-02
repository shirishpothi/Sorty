'use client'

import { BorderBeam } from 'border-beam'
import { X } from 'lucide-react'
import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { useEffect, useState } from 'react'
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
  const [showNotice, setShowNotice] = useState(false)

  const widthClassName = className
    ?.split(/\s+/)
    .filter((token) => /^(?:\w+:)*w-/.test(token))
    .join(' ')

  useEffect(() => {
    if (!showNotice) {
      return
    }

    const timeout = window.setTimeout(() => setShowNotice(false), 8000)
    return () => window.clearTimeout(timeout)
  }, [showNotice])

  return (
    <>
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
              setShowNotice(true)
            }
          }}
          className={cn('btn-download flex items-center rounded-full', className)}
          {...props}
        >
          {children}
        </a>
      </BorderBeam>

      {showNotice && (
        <div
          role="status"
          className="fixed bottom-5 left-1/2 z-[80] w-[calc(100vw-2rem)] max-w-sm -translate-x-1/2 rounded-2xl border border-border bg-background/95 p-4 text-left shadow-2xl shadow-black/40 backdrop-blur-xl"
        >
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1">
              <p className="text-sm font-medium text-foreground">
                Download should start soon
              </p>
              <p className="mt-1 text-xs leading-relaxed text-muted-foreground">
                After moving Sorty.app to Applications, run this in Terminal:
              </p>
              <code className="mt-3 block overflow-x-auto rounded-lg border border-border bg-secondary/70 px-3 py-2 text-xs text-foreground">
                xattr -cr /Applications/Sorty.app
              </code>
            </div>
            <button
              type="button"
              onClick={() => setShowNotice(false)}
              className="flex size-8 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
              aria-label="Dismiss download notice"
            >
              <X className="size-4" />
            </button>
          </div>
        </div>
      )}
    </>
  )
}

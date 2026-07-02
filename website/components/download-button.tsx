'use client'

import { BorderBeam } from 'border-beam'
import { Check, Copy, Download, Terminal, X } from 'lucide-react'
import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { useEffect, useState } from 'react'
import { cn } from '@/lib/utils'

const XATTR_COMMAND = 'xattr -cr /Applications/Sorty.app'

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
  const [copied, setCopied] = useState(false)

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

  useEffect(() => {
    if (!copied) {
      return
    }

    const timeout = window.setTimeout(() => setCopied(false), 1600)
    return () => window.clearTimeout(timeout)
  }, [copied])

  async function copyCommand() {
    try {
      await navigator.clipboard.writeText(XATTR_COMMAND)
      setCopied(true)
    } catch {
      setCopied(false)
    }
  }

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
          className="download-notice fixed bottom-4 left-1/2 z-[80] w-[calc(100vw-1.5rem)] max-w-[410px] -translate-x-1/2 overflow-hidden rounded-3xl border border-white/15 bg-background/90 text-left shadow-2xl shadow-black/45 backdrop-blur-2xl sm:bottom-5"
        >
          <div
            aria-hidden
            className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary/70 to-transparent"
          />
          <div
            aria-hidden
            className="absolute -right-16 -top-20 size-44 rounded-full bg-primary/25 blur-3xl"
          />

          <div className="relative p-3.5 sm:p-4">
            <div className="flex items-start gap-3.5">
              <div className="flex size-10 shrink-0 items-center justify-center rounded-2xl bg-brand text-white shadow-lg shadow-brand/30">
                <Download className="size-5" />
              </div>

              <div className="min-w-0 flex-1">
                <p className="text-sm font-semibold text-foreground">
                  Sorty is downloading
                </p>
                <p className="mt-1 max-w-[31ch] text-xs leading-snug text-muted-foreground">
                  Once it finishes, move Sorty.app to Applications and run the
                  Terminal command below.
                </p>
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

            <div className="mt-3 rounded-2xl border border-border bg-secondary/55 p-2 shadow-inner shadow-black/20">
              <div className="flex items-center gap-2 px-2 pb-2 pt-1 text-[11px] font-medium text-muted-foreground">
                <Terminal className="size-3.5" />
                Terminal
              </div>
              <div
                className={cn(
                  'copy-command-row flex flex-col gap-2 rounded-xl border border-white/10 bg-background/70 p-2 transition-[border-color,box-shadow] duration-300 sm:flex-row sm:items-center',
                  copied && 'is-copied border-brand/45 shadow-[0_0_0_1px_oklch(0.62_0.19_256_/_24%),0_0_26px_-12px_oklch(0.62_0.19_256_/_80%)]',
                )}
              >
                <code className="min-w-0 flex-1 break-all px-1 text-xs leading-relaxed text-foreground sm:overflow-x-auto sm:whitespace-nowrap">
                  {XATTR_COMMAND}
                </code>
                <button
                  type="button"
                  onClick={() => void copyCommand()}
                  className={cn(
                    'copy-command-button relative flex h-8 shrink-0 items-center justify-center overflow-hidden rounded-lg px-2.5 text-xs font-medium transition-[transform,background-color,color,box-shadow] duration-300 hover:scale-[1.03] active:scale-95',
                    copied
                      ? 'is-copied gap-1.5 bg-brand text-white shadow-lg shadow-brand/30'
                      : 'gap-1.5 bg-foreground text-background',
                  )}
                  aria-label="Copy Terminal command"
                >
                  <span className="copy-command-shine" aria-hidden />
                  {copied ? (
                    <span className="copy-command-label is-copied">
                      <Check className="copy-command-check size-3.5" />
                      Copied
                    </span>
                  ) : (
                    <span className="copy-command-label">
                      <Copy className="size-3.5" />
                      Copy
                    </span>
                  )}
                </button>
              </div>
            </div>

            <div className="mt-3 flex items-center gap-2 text-[11px] leading-relaxed text-muted-foreground">
              <span className="size-1.5 shrink-0 rounded-full bg-primary" />
              <p>
                This removes macOS quarantine after you place the app in
                Applications.
              </p>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

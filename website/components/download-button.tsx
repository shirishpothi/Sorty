'use client'

import { BorderBeam } from 'border-beam'
import { Check, Copy, Download, Terminal, X } from 'lucide-react'
import type { AnchorHTMLAttributes, ReactNode } from 'react'
import { useEffect, useId, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'

const XATTR_COMMAND = 'xattr -cr /Applications/Sorty.app'

type CopyFeedback = 'idle' | 'copied' | 'failed'

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
  const [copyFeedback, setCopyFeedback] = useState<CopyFeedback>('idle')
  const copyFeedbackTimeout = useRef<number | null>(null)
  const modalPanelRef = useRef<HTMLDivElement>(null)
  const titleId = useId()
  const descriptionId = useId()

  const widthClassName = className
    ?.split(/\s+/)
    .filter((token) => /^(?:\w+:)*w-/.test(token))
    .join(' ')

  useEffect(() => {
    if (!showNotice) {
      return
    }

    const previousOverflow = document.documentElement.style.overflow
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setShowNotice(false)
      }
    }

    document.documentElement.style.overflow = 'hidden'
    window.addEventListener('keydown', handleKeyDown)
    modalPanelRef.current?.focus({ preventScroll: true })

    return () => {
      document.documentElement.style.overflow = previousOverflow
      window.removeEventListener('keydown', handleKeyDown)
    }
  }, [showNotice])

  useEffect(() => {
    return () => {
      if (copyFeedbackTimeout.current !== null) {
        window.clearTimeout(copyFeedbackTimeout.current)
      }
    }
  }, [])

  function showCopyFeedback(nextFeedback: CopyFeedback) {
    if (copyFeedbackTimeout.current !== null) {
      window.clearTimeout(copyFeedbackTimeout.current)
    }

    setCopyFeedback('idle')
    window.requestAnimationFrame(() => {
      setCopyFeedback(nextFeedback)
      copyFeedbackTimeout.current = window.setTimeout(
        () => {
          setCopyFeedback('idle')
          copyFeedbackTimeout.current = null
        },
        nextFeedback === 'failed' ? 2400 : 1700,
      )
    })
  }

  async function writeClipboardText(text: string) {
    if (navigator.clipboard?.writeText && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text)
        return
      } catch {
        // Fall through to the textarea path for browsers that expose the API
        // but reject it because of permissions or focus quirks.
      }
    }

    const textarea = document.createElement('textarea')
    textarea.value = text
    textarea.setAttribute('readonly', '')
    textarea.style.position = 'fixed'
    textarea.style.left = '-9999px'
    textarea.style.top = '0'
    document.body.appendChild(textarea)
    textarea.focus()
    textarea.select()
    textarea.setSelectionRange(0, textarea.value.length)
    const didCopy = document.execCommand('copy')
    textarea.remove()

    if (!didCopy) {
      throw new Error('Copy command failed')
    }
  }

  async function copyCommand() {
    showCopyFeedback('copied')

    try {
      await writeClipboardText(XATTR_COMMAND)
    } catch {
      showCopyFeedback('failed')
    }
  }

  function showDownloadNotice() {
    if (copyFeedbackTimeout.current !== null) {
      window.clearTimeout(copyFeedbackTimeout.current)
      copyFeedbackTimeout.current = null
    }

    setCopyFeedback('idle')
    setShowNotice(true)
  }

  const copySucceeded = copyFeedback === 'copied'
  const copyFailed = copyFeedback === 'failed'

  const notice =
    showNotice &&
    typeof document !== 'undefined' &&
    createPortal(
      <div
        className="download-modal-backdrop fixed inset-0 z-[100] grid place-items-end bg-black/45 p-3 backdrop-blur-md sm:place-items-center sm:p-6"
        onMouseDown={(event) => {
          if (event.target === event.currentTarget) {
            setShowNotice(false)
          }
        }}
      >
        <div
          ref={modalPanelRef}
          role="dialog"
          aria-modal="true"
          aria-labelledby={titleId}
          aria-describedby={descriptionId}
          tabIndex={-1}
          className="download-modal-panel relative max-h-[calc(100dvh-1.5rem)] w-full max-w-[480px] overflow-y-auto rounded-[1.75rem] border border-white/15 bg-background/95 text-left shadow-2xl shadow-black/55 outline-none backdrop-blur-2xl sm:max-h-[calc(100dvh-3rem)]"
        >
          <div
            aria-hidden
            className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary/70 to-transparent"
          />
          <div
            aria-hidden
            className="absolute -right-20 -top-24 size-56 rounded-full bg-primary/20 blur-3xl"
          />

          <div className="relative p-4 sm:p-5">
            <div className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-3.5">
              <div className="flex size-11 shrink-0 items-center justify-center rounded-2xl bg-brand text-white shadow-lg shadow-brand/30">
                <Download className="size-5" />
              </div>

              <div className="min-w-0">
                <p
                  id={titleId}
                  className="text-base font-semibold text-foreground"
                >
                  Download started
                </p>
                <p
                  id={descriptionId}
                  className="mt-1 max-w-[36ch] text-sm leading-snug text-muted-foreground"
                >
                  Move Sorty.app to Applications after the zip opens, then run
                  this Terminal command if macOS blocks the app.
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

            <div className="mt-4 rounded-2xl border border-border bg-secondary/55 p-2 shadow-inner shadow-black/20">
              <div className="flex items-center gap-2 px-2 pb-2 pt-1 text-[11px] font-medium text-muted-foreground">
                <Terminal className="size-3.5" />
                Terminal
              </div>
              <div
                className={cn(
                  'copy-command-row grid gap-2 rounded-xl border border-white/10 bg-background/70 p-2 transition-[border-color,box-shadow] duration-300 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center',
                  copySucceeded && 'is-copied border-brand/45 shadow-[0_0_0_1px_oklch(0.62_0.19_256_/_24%),0_0_26px_-12px_oklch(0.62_0.19_256_/_80%)]',
                  copyFailed && 'border-destructive/55',
                )}
              >
                <code className="min-w-0 break-all px-1 text-xs leading-relaxed text-foreground">
                  {XATTR_COMMAND}
                </code>
                <button
                  type="button"
                  onClick={() => void copyCommand()}
                  className={cn(
                    'copy-command-button relative flex h-8 shrink-0 items-center justify-center overflow-hidden rounded-lg px-2.5 text-xs font-medium transition-[transform,background-color,color,box-shadow] duration-300 hover:scale-[1.03] active:scale-95',
                    copySucceeded &&
                      'is-copied gap-1.5 bg-brand text-white shadow-lg shadow-brand/30',
                    copyFailed && 'gap-1.5 bg-destructive text-white',
                    copyFeedback === 'idle' &&
                      'gap-1.5 bg-foreground text-background',
                  )}
                  aria-label={
                    copySucceeded
                      ? 'Terminal command copied'
                      : 'Copy Terminal command'
                  }
                >
                  <span className="copy-command-shine" aria-hidden />
                  {copySucceeded ? (
                    <span className="copy-command-label is-copied">
                      <Check className="copy-command-check size-3.5" />
                      Copied
                    </span>
                  ) : copyFailed ? (
                    <span className="copy-command-label">
                      <X className="size-3.5" />
                      Retry
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

            <div className="mt-4 grid gap-2 sm:grid-cols-[1fr_auto] sm:items-center">
              <p className="text-xs leading-relaxed text-muted-foreground">
                The command only removes the quarantine flag from the app you
                placed in Applications.
              </p>
              <button
                type="button"
                onClick={() => setShowNotice(false)}
                className="justify-self-start rounded-full border border-border bg-secondary/55 px-4 py-2 text-xs font-medium text-foreground transition-colors hover:bg-secondary sm:justify-self-end"
              >
                Done
              </button>
            </div>
          </div>
        </div>
      </div>,
      document.body,
    )

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
              showDownloadNotice()
            }
          }}
          className={cn('btn-download flex items-center rounded-full', className)}
          {...props}
        >
          {children}
        </a>
      </BorderBeam>

      {notice}
    </>
  )
}

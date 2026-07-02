'use client'

import { BorderBeam } from 'border-beam'
import { Check, Copy, Download, Terminal, X } from 'lucide-react'
import type {
  AnchorHTMLAttributes,
  CSSProperties,
  ReactNode,
} from 'react'
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { cn } from '@/lib/utils'

const XATTR_COMMAND = 'xattr -cr /Applications/Sorty.app'
const NOTICE_MAX_WIDTH = 410
const NOTICE_MARGIN = 12
const NOTICE_GAP = 12

type NoticePosition = {
  left: number
  top: number
  width: number
  arrowLeft: number
  placement: 'top' | 'bottom'
}

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
  const [noticePosition, setNoticePosition] = useState<NoticePosition | null>(
    null,
  )
  const anchorRef = useRef<HTMLAnchorElement>(null)
  const noticeRef = useRef<HTMLDivElement>(null)

  const widthClassName = className
    ?.split(/\s+/)
    .filter((token) => /^(?:\w+:)*w-/.test(token))
    .join(' ')

  const positionNotice = useCallback(() => {
    const anchorRect = anchorRef.current?.getBoundingClientRect()
    if (!anchorRect) {
      return
    }

    const width = Math.min(NOTICE_MAX_WIDTH, window.innerWidth - NOTICE_MARGIN * 2)
    const height = noticeRef.current?.offsetHeight ?? 270
    const centerX = anchorRect.left + anchorRect.width / 2
    const left = Math.min(
      Math.max(centerX - width / 2, NOTICE_MARGIN),
      window.innerWidth - width - NOTICE_MARGIN,
    )
    const fitsBelow =
      anchorRect.bottom + NOTICE_GAP + height <= window.innerHeight - NOTICE_MARGIN
    const placement = fitsBelow ? 'bottom' : 'top'
    const top =
      placement === 'bottom'
        ? anchorRect.bottom + NOTICE_GAP
        : Math.max(NOTICE_MARGIN, anchorRect.top - height - NOTICE_GAP)
    const arrowLeft = Math.min(Math.max(centerX - left, 22), width - 22)

    setNoticePosition({ left, top, width, arrowLeft, placement })
  }, [])

  useLayoutEffect(() => {
    if (showNotice) {
      positionNotice()
    }
  }, [positionNotice, showNotice])

  useEffect(() => {
    if (!showNotice) {
      return
    }

    const timeout = window.setTimeout(() => setShowNotice(false), 8000)
    const handleReposition = () => positionNotice()
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setShowNotice(false)
      }
    }
    const handlePointerDown = (event: PointerEvent) => {
      if (
        noticeRef.current &&
        event.target instanceof Node &&
        !noticeRef.current.contains(event.target)
      ) {
        setShowNotice(false)
      }
    }

    window.addEventListener('resize', handleReposition)
    window.addEventListener('scroll', handleReposition, true)
    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('pointerdown', handlePointerDown)

    return () => {
      window.clearTimeout(timeout)
      window.removeEventListener('resize', handleReposition)
      window.removeEventListener('scroll', handleReposition, true)
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('pointerdown', handlePointerDown)
    }
  }, [positionNotice, showNotice])

  useEffect(() => {
    if (!copied) {
      return
    }

    const timeout = window.setTimeout(() => setCopied(false), 1600)
    return () => window.clearTimeout(timeout)
  }, [copied])

  async function copyCommand() {
    try {
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(XATTR_COMMAND)
      } else {
        const textarea = document.createElement('textarea')
        textarea.value = XATTR_COMMAND
        textarea.setAttribute('readonly', '')
        textarea.style.position = 'fixed'
        textarea.style.left = '-9999px'
        document.body.appendChild(textarea)
        textarea.select()
        document.execCommand('copy')
        textarea.remove()
      }
      setCopied(true)
    } catch {
      setCopied(false)
    }
  }

  function showDownloadNotice() {
    setNoticePosition(null)
    setShowNotice(true)
  }

  const noticeStyle = noticePosition
    ? ({
        left: noticePosition.left,
        top: noticePosition.top,
        width: noticePosition.width,
        '--download-notice-arrow-left': `${noticePosition.arrowLeft}px`,
      } as CSSProperties)
    : undefined

  const notice =
    showNotice &&
    typeof document !== 'undefined' &&
    createPortal(
      <div
        ref={noticeRef}
        role="dialog"
        aria-label="Download instructions"
        aria-live="polite"
        data-placement={noticePosition?.placement ?? 'bottom'}
        style={noticeStyle}
        className={cn(
          'download-notice fixed isolate z-[80] rounded-3xl border border-white/15 bg-background/90 text-left shadow-2xl shadow-black/45 backdrop-blur-2xl',
          !noticePosition && 'opacity-0',
        )}
      >
        <span className="download-notice-arrow" aria-hidden />
        <div
          aria-hidden
          className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-primary/70 to-transparent"
        />
        <div
          aria-hidden
          className="absolute -right-16 -top-20 size-44 rounded-full bg-primary/25 blur-3xl"
        />

        <div className="relative p-3.5 sm:p-4">
          <div className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-3">
            <div className="flex size-10 shrink-0 items-center justify-center rounded-2xl bg-brand text-white shadow-lg shadow-brand/30">
              <Download className="size-5" />
            </div>

            <div className="min-w-0">
              <p className="text-sm font-semibold text-foreground">
                Sorty is downloading
              </p>
              <p className="mt-1 max-w-[34ch] text-xs leading-snug text-muted-foreground">
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
                'copy-command-row grid gap-2 rounded-xl border border-white/10 bg-background/70 p-2 transition-[border-color,box-shadow] duration-300 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-center',
                copied && 'is-copied border-brand/45 shadow-[0_0_0_1px_oklch(0.62_0.19_256_/_24%),0_0_26px_-12px_oklch(0.62_0.19_256_/_80%)]',
              )}
            >
              <code className="min-w-0 break-all px-1 text-xs leading-relaxed text-foreground sm:overflow-x-auto sm:whitespace-nowrap">
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

          <div className="mt-3 flex items-start gap-2 text-[11px] leading-relaxed text-muted-foreground">
            <span className="mt-1.5 size-1.5 shrink-0 rounded-full bg-primary" />
            <p>
              This removes macOS quarantine after you place the app in
              Applications.
            </p>
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
          ref={anchorRef}
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

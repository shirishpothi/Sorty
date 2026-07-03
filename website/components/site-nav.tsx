'use client'

import { useEffect, useState } from 'react'
import { Heart, Menu, X } from 'lucide-react'
import { cn } from '@/lib/utils'
import { SortyLogo } from '@/components/sorty-logo'
import { GithubIcon } from '@/components/github-icon'
import { DownloadButton } from '@/components/download-button'
import { sitePath } from '@/lib/site-paths'

const LINKS = [
  { label: 'Features', href: sitePath('/#features') },
  { label: 'Privacy', href: sitePath('/privacy-policy') },
  { label: 'Terms', href: sitePath('/terms') },
  { label: 'Pricing', href: sitePath('/#pricing') },
  { label: 'FAQ', href: sitePath('/#faq') },
]

const GITHUB_URL = 'https://github.com/sorty-organizer/Sorty'
const SPONSOR_URL = 'https://github.com/sponsors/shirishpothi'
const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Sorty-universal.zip`

export function SiteNav() {
  const [scrolled, setScrolled] = useState(false)
  const [open, setOpen] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 16)
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <header className="fixed inset-x-0 top-0 z-50 flex justify-center px-4 pt-4">
      <nav
        className={cn(
          'flex w-full max-w-3xl items-center justify-between gap-2 rounded-full border px-2 py-2 pl-4 transition-all duration-500',
          scrolled
            ? 'border-border bg-background/70 shadow-lg shadow-black/30 backdrop-blur-xl'
            : 'border-transparent bg-background/30 backdrop-blur-md',
        )}
      >
        <a href={sitePath('/#top')} className="shrink-0">
          <SortyLogo />
        </a>

        <div className="hidden items-center gap-1 md:flex">
          {LINKS.map((link) => (
            <a
              key={link.href}
              href={link.href}
              className="rounded-full px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground"
            >
              {link.label}
            </a>
          ))}
        </div>

        <div className="flex items-center gap-2">
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noreferrer"
            className="hidden items-center gap-1.5 rounded-full px-3 py-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground sm:flex"
          >
            <GithubIcon className="size-4" />
            GitHub
          </a>
          <a
            href={SPONSOR_URL}
            target="_blank"
            rel="noreferrer"
            className="btn-support hidden items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-medium lg:flex"
          >
            <Heart className="support-heart-icon size-4" />
            Donate
          </a>
          <DownloadButton
            href={DOWNLOAD_URL}
            className="gap-1.5 px-4 py-2 text-sm font-medium"
          >
            <span
              className="text-[16px] leading-none"
              aria-hidden="true"
            >
              
            </span>
            <span>Download</span>
          </DownloadButton>
          <button
            type="button"
            onClick={() => setOpen((v) => !v)}
            className="flex size-9 items-center justify-center rounded-full text-muted-foreground transition-colors hover:text-foreground md:hidden"
            aria-label={open ? 'Close menu' : 'Open menu'}
          >
            {open ? <X className="size-5" /> : <Menu className="size-5" />}
          </button>
        </div>
      </nav>

      {open && (
        <div className="absolute top-20 w-full max-w-3xl rounded-3xl border border-border bg-background/80 p-2 backdrop-blur-xl md:hidden">
          {LINKS.map((link) => (
            <a
              key={link.href}
              href={link.href}
              onClick={() => setOpen(false)}
              className="block rounded-2xl px-4 py-3 text-sm text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            >
              {link.label}
            </a>
          ))}
          <a
            href={GITHUB_URL}
            target="_blank"
            rel="noreferrer"
            className="flex items-center gap-2 rounded-2xl px-4 py-3 text-sm text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
          >
            <GithubIcon className="size-4" />
            View source on GitHub
          </a>
          <a
            href={SPONSOR_URL}
            target="_blank"
            rel="noreferrer"
            className="btn-support mt-2 flex items-center justify-center gap-2 rounded-full px-4 py-3 text-sm font-medium"
          >
            <Heart className="support-heart-icon size-4" />
            Donate to support Sorty
          </a>
        </div>
      )}
    </header>
  )
}

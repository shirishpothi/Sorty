'use client'

import Image from 'next/image'
import { useEffect, useRef } from 'react'
import { Highlight, type HighlightOptions } from '@highlighters/react'
import { Cpu, Heart, Monitor, Star, UserX } from 'lucide-react'
import { Reveal } from '@/components/reveal'
import { GithubIcon } from '@/components/github-icon'
import { DownloadButton } from '@/components/download-button'
import { sitePath } from '@/lib/site-paths'

const GITHUB_URL = 'https://github.com/sorty-organizer/Sorty'
const SPONSOR_URL = 'https://github.com/sponsors/shirishpothi'
const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Sorty.zip`

const TRUST_ITEMS = [
  { icon: Monitor, label: 'macOS 15+' },
  { icon: Cpu, label: 'Apple Silicon & Intel' },
  { icon: UserX, label: 'No account required' },
]

const SORTY_HIGHLIGHT: HighlightOptions = {
  markType: 'highlight',
  color: '#4f8cff',
  opacity: 0.52,
  vivid: true,
  tip: {
    type: 'chisel',
    angle: 8,
    overshoot: 4,
    overshootJitter: 1,
  },
  ink: {
    flow: 0.42,
    viscosity: 0.62,
    feathering: 0.08,
    streakiness: 0.18,
    dryout: 0.03,
    startEndBuildup: 0.08,
    flowFade: 0.24,
  },
  edge: {
    waviness: 0.6,
    frequency: 28,
    roughness: 0.08,
    cap: 'round',
    radius: 4,
  },
  paper: {
    absorbency: 0.05,
  },
  glow: {
    enabled: true,
    intensity: 0.16,
    spread: 5,
    color: '#6ea2ff',
  },
  snap: 'word',
  semantic: true,
  animation: {
    draw: true,
    duration: 620,
    easing: 'cubic-bezier(0.16, 1, 0.3, 1)',
    direction: 'left-to-right',
    trigger: 'immediate',
    repeat: false,
  },
}

export function Hero() {
  const screenshotRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const card = screenshotRef.current
    if (!card || window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      return
    }

    let frame = 0

    const updateTilt = () => {
      frame = 0
      const rect = card.getBoundingClientRect()
      const viewport = window.innerHeight || document.documentElement.clientHeight
      const start = viewport * 0.78
      const end = viewport * 0.28
      const rawProgress = Math.min(
        1,
        Math.max(0, (start - rect.top) / (start - end)),
      )
      const progress = rawProgress * rawProgress * (3 - 2 * rawProgress)
      const tilt = 16 - progress * 16
      const scale = 0.985 + progress * 0.015

      card.style.setProperty('--hero-screenshot-tilt', `${tilt.toFixed(2)}deg`)
      card.style.setProperty('--hero-screenshot-scale', scale.toFixed(4))
    }

    const scheduleTilt = () => {
      if (frame) {
        return
      }
      frame = window.requestAnimationFrame(updateTilt)
    }

    updateTilt()
    window.addEventListener('scroll', scheduleTilt, { passive: true })
    window.addEventListener('resize', scheduleTilt)

    return () => {
      if (frame) {
        window.cancelAnimationFrame(frame)
      }
      window.removeEventListener('scroll', scheduleTilt)
      window.removeEventListener('resize', scheduleTilt)
    }
  }, [])

  return (
    <section
      id="top"
      className="page-section isolate relative overflow-hidden px-4 pt-28 pb-10 sm:pt-36"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-30 bg-cover bg-center bg-no-repeat opacity-90"
        style={{
          backgroundImage: `url(${sitePath('/hero-local-background.png')})`,
          maskImage:
            'linear-gradient(to bottom, black 0%, black 68%, transparent 100%)',
          WebkitMaskImage:
            'linear-gradient(to bottom, black 0%, black 68%, transparent 100%)',
        }}
      />
      {/* layered ambient gradient backdrop */}
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 -z-20"
        style={{
          background:
            'radial-gradient(900px 480px at 50% 8%, color-mix(in oklch, var(--brand) 28%, transparent), transparent 70%), radial-gradient(700px 420px at 80% 30%, color-mix(in oklch, var(--brand-bright) 18%, transparent), transparent 70%), radial-gradient(700px 420px at 18% 24%, color-mix(in oklch, var(--brand) 14%, transparent), transparent 72%)',
        }}
      />
      <div
        aria-hidden
        className="animate-sorty-float pointer-events-none absolute left-1/2 top-24 -z-10 h-[420px] w-[680px] max-w-[90vw] -translate-x-1/2 rounded-full bg-primary/25 blur-[120px]"
      />

      <div className="mx-auto max-w-3xl text-center">
        <Reveal delay={80}>
          <h1 className="mt-6 text-balance text-5xl font-semibold leading-[0.95] tracking-tight text-foreground sm:text-7xl">
            AI folder{' '}
            <Highlight
              options={SORTY_HIGHLIGHT}
              className="relative inline-block px-1 text-white"
            >
              organization
            </Highlight>{' '}
            for your{' '}
            <span className="mac-heading-lockup highlight-in" aria-label="Mac">
              <Image
                src={sitePath('/macos-finder-40.webp')}
                alt=""
                width={512}
                height={512}
                className="mac-heading-icon"
                aria-hidden="true"
              />
            </span>{' '}
            Mac
          </h1>
        </Reveal>

        <Reveal delay={160}>
          <p className="mx-auto mt-6 max-w-xl text-pretty text-base leading-relaxed text-muted-foreground sm:text-lg">
            Point{' '}
            <Image
              src={sitePath('/sorty-icon-40.webp')}
              alt=""
              width={18}
              height={18}
              className="hero-copy-sorty-icon"
              aria-hidden="true"
            />{' '}
            Sorty at any messy folder and let AI suggest a clean structure.
            Preview every change, apply when ready, and undo anytime; your
            files never leave your Mac unless you say so.
          </p>
        </Reveal>

        <Reveal delay={240}>
          <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <DownloadButton
              id="download"
              href={DOWNLOAD_URL}
              className="w-full justify-center gap-2 px-6 py-3 text-sm font-medium sm:w-auto"
            >
              <span className="download-apple-mark" aria-hidden="true">
                
              </span>
              Download for Mac
            </DownloadButton>
            <a
              href={GITHUB_URL}
              target="_blank"
              rel="noreferrer"
              className="group flex w-full items-center justify-center gap-2 rounded-full border border-border bg-secondary/50 px-6 py-3 text-sm font-medium text-foreground backdrop-blur-md transition-colors hover:border-amber-300/50 hover:bg-amber-300/10 sm:w-auto"
            >
              <span className="relative size-4" aria-hidden="true">
                <GithubIcon className="absolute inset-0 size-4 transition-all duration-200 group-hover:scale-75 group-hover:opacity-0" />
                <Star className="absolute inset-0 size-4 scale-75 fill-amber-300 text-amber-300 opacity-0 drop-shadow-[0_0_8px_rgba(252,211,77,0.75)] transition-all duration-200 group-hover:scale-110 group-hover:opacity-100" />
              </span>
              Star on GitHub
            </a>
            <a
              href={SPONSOR_URL}
              target="_blank"
              rel="noreferrer"
              className="btn-support flex w-full items-center justify-center gap-2 rounded-full px-6 py-3 text-sm font-medium sm:w-auto"
            >
              <Heart className="support-heart-icon size-4" />
              Support the dev
            </a>
          </div>
        </Reveal>

        <Reveal delay={320}>
          <div className="mt-6 flex flex-wrap items-center justify-center gap-2">
            {TRUST_ITEMS.map(({ icon: Icon, label }) => (
              <span
                key={label}
                className="inline-flex items-center gap-1.5 rounded-full border border-border bg-secondary/45 px-3 py-1.5 text-xs text-muted-foreground backdrop-blur-md"
              >
                <Icon className="size-3.5 text-primary" />
                {label}
              </span>
            ))}
          </div>
        </Reveal>
      </div>

      {/* App screenshot */}
      <Reveal delay={120} className="mx-auto mt-12 max-w-5xl">
        <div
          ref={screenshotRef}
          className="hero-screenshot-card relative rounded-2xl border border-border bg-card/40 p-2 shadow-2xl shadow-black/50 backdrop-blur-xl sm:rounded-3xl sm:p-3"
        >
          <div
            aria-hidden
            className="pointer-events-none absolute inset-x-10 -top-px h-px bg-gradient-to-r from-transparent via-primary/60 to-transparent"
          />
          <Image
            src={sitePath('/sorty-app.webp?v=lossless-1')}
            alt="The Sorty app prompting the user to select a directory to organize."
            width={1102}
            height={754}
            className="w-full rounded-xl sm:rounded-2xl"
            priority
          />
        </div>
      </Reveal>
    </section>
  )
}

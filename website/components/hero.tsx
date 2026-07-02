import Image from 'next/image'
import { ArrowRight } from 'lucide-react'
import { Reveal } from '@/components/reveal'
import { GithubIcon } from '@/components/github-icon'
import { DownloadButton } from '@/components/download-button'

const GITHUB_URL = 'https://github.com/sorty-organizer/Sorty'
const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest`

export function Hero() {
  return (
    <section
      id="top"
      className="page-section relative overflow-hidden px-4 pt-36 pb-12 sm:pt-44"
    >
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
        <Reveal>
          <a
            href="#features"
            className="inline-flex items-center gap-2 rounded-full border border-border bg-secondary/60 px-3 py-1 text-xs text-muted-foreground backdrop-blur-md transition-colors hover:text-foreground"
          >
            <span className="rounded-full bg-primary/20 px-2 py-0.5 text-[11px] font-medium text-primary">
              Free &amp; Open Source
            </span>
            Licensed under GPL v3
            <ArrowRight className="size-3.5" />
          </a>
        </Reveal>

        <Reveal delay={80}>
          <h1 className="mt-6 text-balance bg-gradient-to-b from-foreground to-foreground/65 bg-clip-text text-5xl font-semibold leading-[0.95] tracking-tight text-transparent sm:text-7xl">
            AI folder{' '}
            <span className="highlight-pill highlight-in inline-block rounded-2xl px-3 py-1">
              organization
            </span>{' '}
            for your{' '}
            <span className="mac-heading-badge highlight-in" aria-label="Mac">
              <span className="finder-mark" aria-hidden="true">
                <span className="finder-mark-half finder-mark-left" />
                <span className="finder-mark-half finder-mark-right" />
                <span className="finder-mark-face finder-mark-face-left" />
                <span className="finder-mark-face finder-mark-face-right" />
                <span className="finder-mark-smile" />
              </span>
              <span className="mac-heading-text" aria-hidden="true">Mac</span>
            </span>
          </h1>
        </Reveal>

        <Reveal delay={160}>
          <p className="mx-auto mt-6 max-w-xl text-pretty text-base leading-relaxed text-muted-foreground sm:text-lg">
            Point Sorty at any messy folder and let AI suggest a clean structure.
            Preview every change, apply when ready, and undo anytime — your files
            never leave your Mac unless you say so.
          </p>
        </Reveal>

        <Reveal delay={240}>
          <div className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row">
            <DownloadButton
              id="download"
              href={DOWNLOAD_URL}
              className="w-full justify-center gap-2 px-6 py-3 text-sm font-medium sm:w-auto"
            >
              <span
                className="text-[17px] leading-none"
                aria-hidden="true"
              >
                
              </span>
              Download for Mac
            </DownloadButton>
            <a
              href={GITHUB_URL}
              target="_blank"
              rel="noreferrer"
              className="flex w-full items-center justify-center gap-2 rounded-full border border-border bg-secondary/50 px-6 py-3 text-sm font-medium text-foreground backdrop-blur-md transition-colors hover:bg-secondary sm:w-auto"
            >
              <GithubIcon className="size-4" />
              Star on GitHub
            </a>
          </div>
        </Reveal>

        <Reveal delay={320}>
          <p className="mt-6 text-xs text-muted-foreground">
            macOS 15+ · Apple Silicon &amp; Intel · No account required
          </p>
        </Reveal>
      </div>

      {/* App screenshot */}
      <Reveal delay={120} className="mx-auto mt-16 max-w-5xl">
        <div className="relative rounded-2xl border border-border bg-card/40 p-2 shadow-2xl shadow-black/50 backdrop-blur-xl sm:rounded-3xl sm:p-3">
          <div className="absolute -right-4 -top-4 z-10 hidden size-20 items-center justify-center rounded-3xl border border-border bg-background/75 p-2 shadow-xl shadow-black/35 backdrop-blur-xl sm:flex">
            <Image
              src="/sorty-mascot-head.png"
              alt=""
              width={96}
              height={96}
              className="size-full"
            />
          </div>
          <div
            aria-hidden
            className="pointer-events-none absolute inset-x-10 -top-px h-px bg-gradient-to-r from-transparent via-primary/60 to-transparent"
          />
          <Image
            src="/sorty-app.png"
            alt="The Sorty app showing an AI-generated organization plan for a Downloads folder, with files grouped into Images, Documents, Invoices and Archives."
            width={1600}
            height={1000}
            className="w-full rounded-xl sm:rounded-2xl"
            priority
          />
        </div>
      </Reveal>
    </section>
  )
}

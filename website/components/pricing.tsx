import Image from 'next/image'
import { Check } from 'lucide-react'
import { Reveal } from '@/components/reveal'
import { GithubIcon } from '@/components/github-icon'

const GITHUB_URL = 'https://github.com/sorty-organizer/Sorty'

const INCLUDED = [
  'Every feature, forever — no paid tiers',
  'Unlimited folders and organization runs',
  'Bring your own AI provider or run local',
  'Full source code under the GPL v3',
  'Community support on GitHub',
]

export function Pricing() {
  return (
    <section
      id="pricing"
      className="section-seam snap-section px-4 py-20 sm:py-28"
    >
      <div className="mx-auto max-w-3xl">
        <Reveal className="text-center">
          <p className="text-sm font-medium text-primary">Pricing &amp; availability</p>
          <h2 className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
            Free and open source. Genuinely.
          </h2>
          <p className="mt-4 text-pretty text-muted-foreground">
            Sorty is released under the GPL v3. No subscription, no activation code,
            no catch.
          </p>
        </Reveal>

        <Reveal delay={120} className="mt-12">
          <div className="relative overflow-hidden rounded-3xl border border-primary/30 bg-card/50 p-8 backdrop-blur-xl sm:p-10">
            <div
              aria-hidden
              className="pointer-events-none absolute -right-16 -top-16 h-48 w-48 rounded-full bg-primary/20 blur-3xl"
            />
            <div className="flex flex-col items-start gap-1">
              <span className="rounded-full bg-primary/15 px-3 py-1 text-xs font-medium text-primary">
                GPL v3 · macOS 15+
              </span>
              <div className="mt-5 flex items-end gap-2">
                <span className="text-5xl font-semibold tracking-tight">$0</span>
                <span className="pb-1.5 text-muted-foreground">forever</span>
              </div>
            </div>

            <ul className="mt-8 space-y-3">
              {INCLUDED.map((item) => (
                <li key={item} className="flex items-start gap-3 text-sm">
                  <span className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-primary/15 text-primary">
                    <Check className="size-3.5" />
                  </span>
                  <span className="text-muted-foreground">{item}</span>
                </li>
              ))}
            </ul>

            <div className="mt-9 flex flex-col gap-3 sm:flex-row">
              <a
                href="#top"
                className="btn-download flex w-full items-center justify-center gap-2 rounded-full px-6 py-3 text-sm font-medium"
              >
                <Image
                  src="/apple-icon.png"
                  alt=""
                  width={16}
                  height={16}
                  className="size-4"
                  aria-hidden="true"
                />
                Download for Mac
              </a>
              <a
                href={GITHUB_URL}
                target="_blank"
                rel="noreferrer"
                className="flex w-full items-center justify-center gap-2 rounded-full border border-border bg-secondary/50 px-6 py-3 text-sm font-medium text-foreground transition-colors hover:bg-secondary"
              >
                <GithubIcon className="size-4" />
                Build from source
              </a>
            </div>

            <p className="mt-5 text-center text-xs text-muted-foreground">
              Apple Silicon &amp; Intel · Works with iCloud Drive, Dropbox, and
              external drives
            </p>
          </div>
        </Reveal>
      </div>
    </section>
  )
}

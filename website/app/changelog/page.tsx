import type { Metadata } from 'next'
import Image from 'next/image'
import {
  ArrowUpRight,
  Eye,
  FolderGit2,
  ShieldCheck,
  Sparkles,
} from 'lucide-react'
import { DiaGradient } from '@/components/dia-gradient'
import { Reveal } from '@/components/reveal'
import { SiteFooter } from '@/components/site-footer'
import { SiteNav } from '@/components/site-nav'
import { sitePath } from '@/lib/site-paths'

export const metadata: Metadata = {
  title: 'Changelog',
  description:
    'See what changed in Sorty, with screenshots for visual updates starting with the unreleased Sorty 1.2.0 release.',
  alternates: {
    canonical: '/changelog',
  },
}

const RELEASES = [
  {
    version: 'Sorty 1.2.0',
    status: 'Unreleased',
    date: 'In progress',
    title: 'A faster, cleaner, more reliable Sorty',
    summary:
      'A rebuilt macOS experience with smarter Finder integration, smoother organization, stronger privacy controls, and a polished new design system.',
    image: '/sorty-1.2.0-changelog.png',
    imageAlt:
      'Sorty 1.2.0 promotional image showing the rebuilt macOS welcome screen and faster, cleaner, more reliable Sorty headline.',
    highlights: [
      {
        icon: Sparkles,
        title: 'Polished design system',
        body: 'Refined glass surfaces, tighter spacing, and clearer visual hierarchy across the main Sorty flows.',
      },
      {
        icon: FolderGit2,
        title: 'Smarter Finder integration',
        body: 'Finder handoff and workspace entry points have been rebuilt to feel faster and more native.',
      },
      {
        icon: Eye,
        title: 'Smoother organization',
        body: 'Preview, apply, and review flows are being tuned so the path from messy folder to organized workspace is easier to trust.',
      },
      {
        icon: ShieldCheck,
        title: 'Stronger privacy controls',
        body: 'Local-first boundaries and provider controls are clearer, with better guardrails around what Sorty can access.',
      },
    ],
  },
]

export default function ChangelogPage() {
  return (
    <main className="relative min-h-screen overflow-x-clip">
      <SiteNav />

      <section className="relative isolate overflow-hidden px-4 pb-16 pt-32 sm:pb-24 sm:pt-40">
        <div className="pointer-events-none absolute inset-x-[-25vw] top-[-18vh] -z-10 h-[68vh] opacity-80 [mask-image:radial-gradient(ellipse_at_top,black_0%,black_42%,transparent_72%)]">
          <DiaGradient
            blur={18}
            peak={0.92}
            valley={0.5}
            strength={0.62}
            flattenOnScroll={false}
          />
        </div>
        <div className="pointer-events-none absolute inset-0 -z-10 bg-[radial-gradient(circle_at_18%_24%,oklch(0.66_0.2_12_/_0.22),transparent_26%),radial-gradient(circle_at_82%_18%,oklch(0.68_0.16_250_/_0.18),transparent_30%),linear-gradient(180deg,transparent_0%,var(--background)_88%)]" />

        <div className="mx-auto max-w-5xl">
          <Reveal className="max-w-3xl">
            <p className="text-sm font-medium text-primary">Changelog</p>
            <h1 className="mt-4 text-balance text-5xl font-semibold tracking-tight sm:text-6xl lg:text-7xl">
              What changed in Sorty
            </h1>
            <p className="mt-6 max-w-2xl text-pretty text-lg leading-8 text-muted-foreground">
              Release notes for the Mac folder organizer, now with UI images so
              visual changes are easy to scan before you update.
            </p>
          </Reveal>
        </div>
      </section>

      <section className="px-4 pb-24">
        <div className="mx-auto max-w-5xl">
          <div className="relative space-y-8 before:absolute before:left-4 before:top-5 before:h-[calc(100%-2.5rem)] before:w-px before:bg-gradient-to-b before:from-primary/70 before:via-border before:to-transparent md:before:left-6">
            {RELEASES.map((release) => (
              <Reveal
                key={release.version}
                className="relative pl-12 md:pl-16"
              >
                <span
                  aria-hidden
                  className="absolute left-0 top-3 flex size-8 items-center justify-center rounded-full border border-primary/40 bg-background shadow-[0_0_30px_-8px_oklch(0.62_0.19_256_/_0.8)] md:size-12"
                >
                  <Sparkles className="size-4 text-primary md:size-5" />
                </span>

                <article className="overflow-hidden rounded-3xl border border-border bg-card/40 shadow-2xl shadow-black/30 backdrop-blur-xl">
                  <div className="grid gap-0 lg:grid-cols-[0.88fr_1.12fr]">
                    <div className="flex flex-col justify-between border-b border-border p-6 sm:p-8 lg:border-b-0 lg:border-r">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="rounded-full bg-primary/15 px-3 py-1 text-xs font-medium text-primary">
                            {release.status}
                          </span>
                          <span className="text-sm text-muted-foreground">
                            {release.date}
                          </span>
                        </div>
                        <h2 className="mt-5 text-3xl font-semibold tracking-tight sm:text-4xl">
                          {release.version}
                        </h2>
                        <p className="mt-3 text-xl font-medium text-foreground/90">
                          {release.title}
                        </p>
                        <p className="mt-4 text-sm leading-7 text-muted-foreground">
                          {release.summary}
                        </p>
                      </div>

                      <a
                        href="https://github.com/sorty-organizer/Sorty/releases"
                        target="_blank"
                        rel="noreferrer"
                        className="mt-8 inline-flex w-fit items-center gap-2 rounded-full border border-white/10 bg-background/65 px-4 py-2 text-sm font-medium text-foreground/85 transition-colors hover:border-primary/40 hover:text-foreground"
                      >
                        GitHub releases
                        <ArrowUpRight className="size-4" />
                      </a>
                    </div>

                    <div className="relative p-3 sm:p-4">
                      <div className="changelog-image-frame">
                        <Image
                          src={sitePath(release.image)}
                          alt={release.imageAlt}
                          width={1123}
                          height={896}
                          priority
                          className="w-full rounded-[1.35rem] border border-white/10 object-cover"
                        />
                      </div>
                    </div>
                  </div>

                  <div className="grid gap-px border-t border-border bg-border md:grid-cols-2">
                    {release.highlights.map((highlight) => (
                      <div
                        key={highlight.title}
                        className="bg-card/70 p-6 sm:p-7"
                      >
                        <div className="flex items-center gap-3">
                          <span className="flex size-10 shrink-0 items-center justify-center rounded-2xl bg-primary/15 text-primary">
                            <highlight.icon className="size-5" />
                          </span>
                          <h3 className="text-base font-medium">
                            {highlight.title}
                          </h3>
                        </div>
                        <p className="mt-3 text-sm leading-6 text-muted-foreground">
                          {highlight.body}
                        </p>
                      </div>
                    ))}
                  </div>
                </article>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      <SiteFooter />
    </main>
  )
}

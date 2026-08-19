import Image from 'next/image'
import Link from 'next/link'
import {
  ArrowRight,
  Check,
  Compass,
  Cpu,
  Download,
  FolderDown,
  FolderOpen,
  ListChecks,
  Scale,
  ScanSearch,
  ShieldCheck,
  Sparkles,
  WifiOff,
} from 'lucide-react'
import type { ComponentType } from 'react'
import type { DiscoveryPage as DiscoveryPageData } from '@/lib/discovery-pages'
import { DOWNLOAD_URL, GITHUB_URL, SITE_URL } from '@/lib/site-metadata'
import { sitePath } from '@/lib/site-paths'
import { GithubIcon } from '@/components/github-icon'
import { Reveal } from '@/components/reveal'
import { SiteFooter } from '@/components/site-footer'
import { SiteNav } from '@/components/site-nav'

const STEP_ICONS: Record<DiscoveryPageData['steps'][number]['icon'], ComponentType<{ className?: string }>> = {
  folder: FolderOpen,
  scan: ScanSearch,
  plan: Sparkles,
  review: ListChecks,
  local: Cpu,
  privacy: ShieldCheck,
}

const RELATED_LINKS = [
  {
    href: '/mac-folder-organizer/',
    icon: FolderOpen,
    label: 'Mac folder organizer',
  },
  {
    href: '/organize-downloads-folder/',
    icon: FolderDown,
    label: 'Organize Downloads',
  },
  {
    href: '/local-ai-file-organizer/',
    icon: ShieldCheck,
    label: 'Local AI privacy',
  },
  {
    href: '/compare/',
    icon: Scale,
    label: 'Compare Mac organizers',
  },
]

function HeroIconCluster({ slug }: { slug: string }) {
  if (slug === 'mac-folder-organizer') {
    return (
      <div className="flex items-center gap-2" aria-hidden="true">
        <span className="flex size-12 items-center justify-center rounded-2xl border border-white/20 bg-white/10 shadow-lg shadow-black/25">
          <Image
            src={sitePath('/macos-finder-40.webp')}
            alt=""
            width={34}
            height={34}
            className="size-8"
          />
        </span>
        <span className="flex size-10 items-center justify-center rounded-2xl border border-white/15 bg-white/8 text-white">
          <FolderOpen className="size-5" />
        </span>
        <span className="flex size-10 items-center justify-center rounded-2xl border border-border bg-card/50 text-muted-foreground">
          <ListChecks className="size-5" />
        </span>
      </div>
    )
  }

  if (slug === 'organize-downloads-folder') {
    return (
      <div className="flex items-center gap-2" aria-hidden="true">
        <span className="flex size-12 items-center justify-center rounded-2xl bg-white text-background shadow-lg shadow-white/10">
          <FolderDown className="size-6" />
        </span>
        <span className="flex size-10 items-center justify-center rounded-2xl border border-white/15 bg-white/8 text-white">
          <ScanSearch className="size-5" />
        </span>
        <span className="flex size-10 items-center justify-center rounded-2xl border border-border bg-card/50 text-muted-foreground">
          <ListChecks className="size-5" />
        </span>
      </div>
    )
  }

  return (
    <div className="flex items-center gap-2" aria-hidden="true">
      <span className="flex size-12 items-center justify-center rounded-2xl bg-white text-background shadow-lg shadow-white/10">
        <Cpu className="size-6" />
      </span>
      <span className="flex size-10 items-center justify-center rounded-2xl border border-white/15 bg-white/8 text-white">
        <ShieldCheck className="size-5" />
      </span>
      <span className="flex size-10 items-center justify-center rounded-2xl border border-border bg-card/50 text-muted-foreground">
        <WifiOff className="size-5" />
      </span>
    </div>
  )
}

function HeroTitle({ slug, title }: { slug: string; title: string }) {
  if (slug === 'mac-folder-organizer') {
    return (
      <>
        Organize your Mac.{' '}
        <span className="highlight-pill inline-block rounded-2xl px-2.5 py-1 align-[0.04em]">
          Review every move.
        </span>
      </>
    )
  }

  if (slug === 'organize-downloads-folder') {
    return (
      <>
        Turn a messy{' '}
        <span className="highlight-pill inline-block rounded-2xl px-2.5 py-1 align-[0.04em]">
          Downloads folder
        </span>{' '}
        <span className="text-muted-foreground">into a plan</span> you can approve
      </>
    )
  }

  if (slug === 'local-ai-file-organizer') {
    return (
      <>
        Organize files with{' '}
        <span className="highlight-pill inline-block rounded-2xl px-2.5 py-1 align-[0.04em]">
          local AI
        </span>{' '}
        <span className="text-muted-foreground">that can stay on</span> your Mac
      </>
    )
  }

  return title
}

export function DiscoveryPage({ page }: { page: DiscoveryPageData }) {
  const pageUrl = `${SITE_URL}/${page.slug}/`
  const relatedLinks = RELATED_LINKS.filter((link) => link.href !== `/${page.slug}/`)
  const structuredData = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        '@id': `${pageUrl}#webpage`,
        url: pageUrl,
        name: page.title,
        description: page.description,
        isPartOf: { '@id': `${SITE_URL}/#website` },
        about: { '@id': `${SITE_URL}/#app` },
        inLanguage: 'en-US',
        dateModified: '2026-08-10',
      },
      {
        '@type': 'BreadcrumbList',
        '@id': `${pageUrl}#breadcrumb`,
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'Sorty', item: `${SITE_URL}/` },
          { '@type': 'ListItem', position: 2, name: page.eyebrow, item: pageUrl },
        ],
      },
      {
        '@type': 'HowTo',
        '@id': `${pageUrl}#howto`,
        name: page.title,
        description: page.summary,
        step: page.steps.map((step, index) => ({
          '@type': 'HowToStep',
          position: index + 1,
          name: step.title,
          text: step.text,
          url: `${pageUrl}#step-${index + 1}`,
        })),
      },
    ],
  }

  return (
    <main className="relative min-h-screen overflow-x-clip">
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData) }}
      />
      <SiteNav />

      <section className="page-section relative isolate overflow-hidden px-4 pb-16 pt-32 sm:pb-24 sm:pt-44">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[34rem]"
          style={{
            background:
              'radial-gradient(800px 420px at 50% 0%, color-mix(in oklch, var(--brand) 24%, transparent), transparent 72%)',
          }}
        />
        <div className="mx-auto grid max-w-5xl items-center gap-12 lg:grid-cols-[0.9fr_1.1fr]">
          <Reveal immediate animateOnEnter>
            <HeroIconCluster slug={page.slug} />
            <p className="mt-5 text-sm font-medium text-primary">{page.eyebrow}</p>
            <h1 className="mt-4 text-balance text-4xl font-semibold leading-[1.04] tracking-tight sm:text-6xl">
              <HeroTitle slug={page.slug} title={page.title} />
            </h1>
            <p className="mt-6 text-pretty text-lg leading-8 text-muted-foreground">
              {page.summary}
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <a
                href={DOWNLOAD_URL}
                className="btn-download inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-sm font-medium"
              >
                <Download className="size-4" />
                Download Sorty free
              </a>
              <a
                href={GITHUB_URL}
                target="_blank"
                rel="noreferrer"
                className="group inline-flex items-center justify-center gap-2 rounded-full border border-border bg-secondary/50 px-6 py-3 text-sm font-medium transition-[transform,background-color,border-color,box-shadow] duration-300 ease-out hover:-translate-y-0.5 hover:border-white/25 hover:bg-secondary hover:shadow-lg hover:shadow-black/25"
              >
                <GithubIcon className="size-4 transition-transform duration-300 group-hover:scale-110" />
                View source
              </a>
            </div>
            <p className="mt-4 text-xs text-muted-foreground">
              Free · GPL v3 · macOS 15+ · Apple Silicon and Intel
            </p>
          </Reveal>

          <Reveal immediate animateOnEnter delay={100}>
            <div className="rounded-3xl border border-border bg-card/40 p-2 shadow-2xl shadow-black/40 backdrop-blur-xl">
              <Image
                src={sitePath(page.image)}
                alt={page.imageAlt}
                width={1102}
                height={754}
                className="w-full rounded-2xl"
                priority
              />
            </div>
          </Reveal>
        </div>
      </section>

      <section className="section-seam border-y border-border bg-card/20 px-4 py-20">
        <div className="mx-auto max-w-3xl">
          <Reveal>
            <p className="text-sm font-medium text-primary">How it works</p>
            <h2 className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
              From folder to reviewed plan in three steps
            </h2>
            <p className="mt-4 text-pretty text-muted-foreground">
              Follow the connected path. Each step appears as you reach it.
            </p>
          </Reveal>

          <ol className="relative mt-12" aria-label="Three-step Sorty workflow">
            <span
              aria-hidden
              className="absolute bottom-2 left-6 top-2 w-px bg-gradient-to-b from-primary via-primary/45 to-border"
            />

            {page.steps.map((step, index) => {
              const StepIcon = STEP_ICONS[step.icon]
              return (
                <Reveal
                  key={step.title}
                  delay={index * 110}
                  as="li"
                  className="relative flex scroll-mt-28 gap-5 pb-8 last:pb-0"
                >
                  <div className="relative z-10 shrink-0">
                    <span className="flex size-12 items-center justify-center rounded-2xl border border-primary/30 bg-card text-primary shadow-lg shadow-black/30 backdrop-blur-md">
                      <StepIcon className="size-5" />
                    </span>
                    <span className="absolute -right-1 -top-1 flex size-5 items-center justify-center rounded-full bg-primary text-[10px] font-semibold text-primary-foreground">
                      {index + 1}
                    </span>
                  </div>

                  <div
                    id={`step-${index + 1}`}
                    className={
                      page.slug === 'mac-folder-organizer'
                        ? 'min-w-0 flex-1'
                        : 'how-step-beam min-w-0 flex-1 rounded-3xl'
                    }
                  >
                    <div
                      className={
                        page.slug === 'mac-folder-organizer'
                          ? 'h-full rounded-2xl border border-border bg-card p-6'
                          : 'relative z-10 h-full rounded-3xl border border-border bg-background/65 p-6 backdrop-blur-md transition-colors hover:border-white/25'
                      }
                    >
                      <h3 className="text-lg font-medium">{step.title}</h3>
                      <p className="mt-3 text-sm leading-6 text-muted-foreground">
                        {step.text}
                      </p>
                    </div>
                  </div>
                </Reveal>
              )
            })}
          </ol>
        </div>
      </section>

      <section className="section-seam px-4 py-24">
        <div className="mx-auto max-w-3xl space-y-16">
          {page.sections.map((section, index) => (
            <Reveal as="article" key={section.title} delay={(index % 2) * 80}>
              <h2 className="text-balance text-3xl font-semibold tracking-tight">
                {section.title}
              </h2>
              <div className="mt-5 space-y-4 text-base leading-7 text-muted-foreground">
                {section.paragraphs.map((paragraph) => (
                  <p key={paragraph}>{paragraph}</p>
                ))}
              </div>
              {section.points && (
                <ul className="mt-6 grid auto-rows-fr gap-3 lg:grid-cols-2">
                  {section.points.map((point) => (
                    <li
                      key={point}
                      className="flex h-full items-start gap-3 rounded-2xl border border-border bg-card/35 p-4 text-left text-sm leading-6 text-foreground/90"
                    >
                      <Check className="mt-0.5 size-4 shrink-0 text-primary" />
                      <span className="min-w-0">{point}</span>
                    </li>
                  ))}
                </ul>
              )}
            </Reveal>
          ))}
        </div>
      </section>

      <section className="section-seam px-4 py-20 text-center">
        <Reveal>
          <div className="mx-auto flex max-w-3xl items-center justify-center gap-3">
            <span className="flex size-11 items-center justify-center rounded-2xl border border-primary/25 bg-primary/10 text-primary">
              <Compass className="size-5" />
            </span>
            <h2 className="text-3xl font-semibold tracking-tight">
              <span className="text-muted-foreground">Explore</span> more about{' '}
              <span className="text-primary">Sorty</span>
            </h2>
          </div>
          <div className="mx-auto mt-7 flex max-w-4xl flex-wrap justify-center gap-3">
            {relatedLinks.map(({ href, icon: Icon, label }) => (
              <Link
                key={href}
                href={href}
                className="group inline-flex items-center gap-2 rounded-full border border-border bg-card/20 px-5 py-2.5 text-sm transition-[transform,background-color,border-color,box-shadow] duration-300 ease-out hover:-translate-y-1 hover:border-primary/45 hover:bg-secondary/70 hover:shadow-xl hover:shadow-black/25 focus-visible:border-primary/60"
              >
                <Icon className="size-4 text-muted-foreground transition-colors duration-300 group-hover:text-primary" />
                {label}
                <ArrowRight className="size-4 transition-transform duration-300 group-hover:translate-x-1" />
              </Link>
            ))}
          </div>
        </Reveal>
      </section>

      <SiteFooter />
    </main>
  )
}

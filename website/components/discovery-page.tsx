import Image from 'next/image'
import Link from 'next/link'
import { ArrowRight, Check, Download, ShieldCheck } from 'lucide-react'
import type { DiscoveryPage as DiscoveryPageData } from '@/lib/discovery-pages'
import { DOWNLOAD_URL, GITHUB_URL, SITE_URL } from '@/lib/site-metadata'
import { sitePath } from '@/lib/site-paths'
import { GithubIcon } from '@/components/github-icon'
import { SiteFooter } from '@/components/site-footer'
import { SiteNav } from '@/components/site-nav'

export function DiscoveryPage({ page }: { page: DiscoveryPageData }) {
  const pageUrl = `${SITE_URL}/${page.slug}`
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
        dateModified: '2026-08-09',
      },
      {
        '@type': 'BreadcrumbList',
        '@id': `${pageUrl}#breadcrumb`,
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: 'Sorty', item: SITE_URL },
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
      {
        '@type': 'FAQPage',
        '@id': `${pageUrl}#faq`,
        mainEntity: page.faqs.map((faq) => ({
          '@type': 'Question',
          name: faq.question,
          acceptedAnswer: { '@type': 'Answer', text: faq.answer },
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

      <section className="relative isolate overflow-hidden px-4 pb-16 pt-32 sm:pb-24 sm:pt-44">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[34rem]"
          style={{
            background:
              'radial-gradient(800px 420px at 50% 0%, color-mix(in oklch, var(--brand) 24%, transparent), transparent 72%)',
          }}
        />
        <div className="mx-auto grid max-w-5xl items-center gap-12 lg:grid-cols-[0.9fr_1.1fr]">
          <div>
            <p className="text-sm font-medium text-primary">{page.eyebrow}</p>
            <h1 className="mt-4 text-balance text-4xl font-semibold tracking-tight sm:text-6xl">
              {page.title}
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
                className="inline-flex items-center justify-center gap-2 rounded-full border border-border bg-secondary/50 px-6 py-3 text-sm font-medium transition-colors hover:bg-secondary"
              >
                <GithubIcon className="size-4" />
                View source
              </a>
            </div>
            <p className="mt-4 text-xs text-muted-foreground">
              Free · GPL v3 · macOS 15+ · Apple Silicon and Intel
            </p>
          </div>

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
        </div>
      </section>

      <section className="border-y border-border bg-card/20 px-4 py-20">
        <div className="mx-auto max-w-5xl">
          <p className="text-sm font-medium text-primary">How it works</p>
          <h2 className="mt-3 text-3xl font-semibold tracking-tight sm:text-4xl">
            From folder to reviewed plan in three steps
          </h2>
          <ol className="mt-10 grid gap-4 md:grid-cols-3">
            {page.steps.map((step, index) => (
              <li
                id={`step-${index + 1}`}
                key={step.title}
                className="scroll-mt-28 rounded-3xl border border-border bg-background/60 p-6"
              >
                <span className="flex size-9 items-center justify-center rounded-full bg-primary/15 text-sm font-semibold text-primary">
                  {index + 1}
                </span>
                <h3 className="mt-5 text-lg font-medium">{step.title}</h3>
                <p className="mt-3 text-sm leading-6 text-muted-foreground">
                  {step.text}
                </p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="px-4 py-24">
        <div className="mx-auto max-w-3xl space-y-16">
          {page.sections.map((section) => (
            <article key={section.title}>
              <h2 className="text-balance text-3xl font-semibold tracking-tight">
                {section.title}
              </h2>
              <div className="mt-5 space-y-4 text-base leading-7 text-muted-foreground">
                {section.paragraphs.map((paragraph) => (
                  <p key={paragraph}>{paragraph}</p>
                ))}
              </div>
              {section.points && (
                <ul className="mt-6 grid gap-3 sm:grid-cols-2">
                  {section.points.map((point) => (
                    <li
                      key={point}
                      className="flex gap-3 rounded-2xl border border-border bg-card/35 p-4 text-sm leading-6 text-foreground/90"
                    >
                      <Check className="mt-0.5 size-4 shrink-0 text-primary" />
                      {point}
                    </li>
                  ))}
                </ul>
              )}
            </article>
          ))}
        </div>
      </section>

      <section id="faq" className="border-y border-border bg-card/20 px-4 py-20">
        <div className="mx-auto max-w-3xl">
          <div className="flex items-center gap-3">
            <ShieldCheck className="size-6 text-primary" />
            <h2 className="text-3xl font-semibold tracking-tight">Questions and answers</h2>
          </div>
          <dl className="mt-8 divide-y divide-border rounded-3xl border border-border bg-background/55 px-6">
            {page.faqs.map((faq) => (
              <div key={faq.question} className="py-6">
                <dt className="font-medium text-foreground">{faq.question}</dt>
                <dd className="mt-2 text-sm leading-6 text-muted-foreground">{faq.answer}</dd>
              </div>
            ))}
          </dl>
        </div>
      </section>

      <section className="px-4 py-20 text-center">
        <h2 className="text-3xl font-semibold tracking-tight">Explore more about Sorty</h2>
        <div className="mx-auto mt-6 flex max-w-3xl flex-wrap justify-center gap-3">
          <Link href="/mac-folder-organizer" className="inline-flex items-center gap-2 rounded-full border border-border px-5 py-2.5 text-sm hover:bg-secondary">
            Mac folder organizer <ArrowRight className="size-4" />
          </Link>
          <Link href="/organize-downloads-folder" className="inline-flex items-center gap-2 rounded-full border border-border px-5 py-2.5 text-sm hover:bg-secondary">
            Organize Downloads <ArrowRight className="size-4" />
          </Link>
          <Link href="/local-ai-file-organizer" className="inline-flex items-center gap-2 rounded-full border border-border px-5 py-2.5 text-sm hover:bg-secondary">
            Local AI privacy <ArrowRight className="size-4" />
          </Link>
        </div>
      </section>

      <SiteFooter />
    </main>
  )
}

import type { ReactNode } from 'react'
import { SiteNav } from '@/components/site-nav'
import { SiteFooter } from '@/components/site-footer'

interface LegalPageProps {
  title: string
  updated: string
  children: ReactNode
}

export function LegalPage({ title, updated, children }: LegalPageProps) {
  return (
    <main className="relative min-h-screen overflow-x-hidden">
      <SiteNav />
      <section className="relative px-4 pt-36 pb-12 sm:pt-44">
        <div
          aria-hidden
          className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-80"
          style={{
            background:
              'radial-gradient(700px 320px at 50% 0%, color-mix(in oklch, var(--brand) 22%, transparent), transparent 70%)',
          }}
        />
        <div className="mx-auto max-w-3xl">
          <a
            href="/"
            className="text-sm text-muted-foreground transition-colors hover:text-foreground"
          >
            ← Back to Sorty
          </a>
          <h1 className="mt-6 text-balance text-4xl font-semibold tracking-tight sm:text-5xl">
            {title}
          </h1>
          <p className="mt-3 text-sm text-muted-foreground">
            Last updated {updated}
          </p>

          <div className="legal-prose mt-12 space-y-8 text-sm leading-relaxed text-muted-foreground">
            {children}
          </div>
        </div>
      </section>
      <SiteFooter />
    </main>
  )
}

interface SectionProps {
  heading: string
  children: ReactNode
}

export function LegalSection({ heading, children }: SectionProps) {
  return (
    <div>
      <h2 className="text-lg font-medium text-foreground">{heading}</h2>
      <div className="mt-3 space-y-3">{children}</div>
    </div>
  )
}

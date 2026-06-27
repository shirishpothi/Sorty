import { Mail } from 'lucide-react'
import { SortyLogo } from '@/components/sorty-logo'
import { GithubIcon } from '@/components/github-icon'

const GITHUB_URL = 'https://github.com/sorty-app/sorty'

const COLUMNS = [
  {
    title: 'Product',
    links: [
      { label: 'How it works', href: '#how-it-works' },
      { label: 'Features', href: '#features' },
      { label: 'Privacy', href: '#privacy' },
      { label: 'Pricing', href: '#pricing' },
    ],
  },
  {
    title: 'Resources',
    links: [
      { label: 'Changelog', href: `${GITHUB_URL}/releases` },
      { label: 'Source code', href: GITHUB_URL },
      { label: 'Report an issue', href: `${GITHUB_URL}/issues` },
      { label: 'FAQ', href: '#faq' },
    ],
  },
  {
    title: 'Legal',
    links: [
      { label: 'GPL v3 License', href: `${GITHUB_URL}/blob/main/LICENSE` },
      { label: 'Privacy Policy', href: '/privacy-policy' },
      { label: 'Terms', href: '/terms' },
    ],
  },
]

export function SiteFooter() {
  return (
    <footer className="relative overflow-hidden border-t border-border px-4 pt-14">
      <div className="mx-auto grid max-w-5xl gap-10 md:grid-cols-[1.4fr_1fr_1fr_1fr]">
        <div>
          <SortyLogo />
          <p className="mt-4 max-w-xs text-sm leading-relaxed text-muted-foreground">
            AI folder organization for your Mac. Free, open source, and private
            by design.
          </p>
          <div className="mt-5 flex items-center gap-2">
            <a
              href={GITHUB_URL}
              target="_blank"
              rel="noreferrer"
              className="flex size-9 items-center justify-center rounded-full border border-border text-muted-foreground transition-colors hover:text-foreground"
              aria-label="GitHub"
            >
              <GithubIcon className="size-4" />
            </a>
            <a
              href="mailto:hello@sorty.app"
              className="flex size-9 items-center justify-center rounded-full border border-border text-muted-foreground transition-colors hover:text-foreground"
              aria-label="Email support"
            >
              <Mail className="size-4" />
            </a>
          </div>
        </div>

        {COLUMNS.map((col) => (
          <div key={col.title}>
            <h3 className="text-sm font-medium">{col.title}</h3>
            <ul className="mt-4 space-y-2.5">
              {col.links.map((link) => (
                <li key={link.label}>
                  <a
                    href={link.href}
                    className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                  >
                    {link.label}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div className="mx-auto mt-12 flex max-w-5xl flex-col items-center justify-between gap-3 border-t border-border pt-6 text-xs text-muted-foreground sm:flex-row">
        <p>© {new Date().getFullYear()} Sorty. Released under the GPL v3.</p>
        <p>Made for people with too many files.</p>
      </div>

      {/* Oversized faded brand wordmark */}
      <div
        aria-hidden
        className="pointer-events-none relative mt-8 select-none"
      >
        <span className="block bg-gradient-to-b from-foreground/[0.07] to-foreground/0 bg-clip-text text-center text-[24vw] font-semibold leading-[0.8] tracking-tighter text-transparent">
          Sorty
        </span>
      </div>
    </footer>
  )
}

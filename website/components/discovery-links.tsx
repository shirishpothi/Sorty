import Link from 'next/link'
import { ArrowRight, Bot, FolderOpen, Laptop } from 'lucide-react'

const LINKS = [
  {
    href: '/mac-folder-organizer',
    icon: Laptop,
    title: 'Mac folder organizer',
    description: 'See how Sorty compares with fixed-rule automation and keeps you in control of every move.',
  },
  {
    href: '/organize-downloads-folder',
    icon: FolderOpen,
    title: 'Organize Downloads',
    description: 'Clean up mixed downloads by meaning, then keep the folder organized with watched workflows.',
  },
  {
    href: '/local-ai-file-organizer',
    icon: Bot,
    title: 'Use local AI',
    description: 'Run organization with Ollama or supported Apple on-device models so analysis can stay local.',
  },
]

export function DiscoveryLinks() {
  return (
    <section className="px-4 py-20" aria-labelledby="discover-sorty">
      <div className="mx-auto max-w-5xl">
        <p className="text-sm font-medium text-primary">Guides and use cases</p>
        <h2 id="discover-sorty" className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
          Decide whether Sorty fits your workflow
        </h2>
        <p className="mt-4 max-w-2xl leading-7 text-muted-foreground">
          Explore the organization model, a practical Downloads workflow, and the privacy differences between local and cloud AI.
        </p>
        <div className="mt-9 grid gap-4 md:grid-cols-3">
          {LINKS.map(({ href, icon: Icon, title, description }) => (
            <Link
              key={href}
              href={href}
              className="group rounded-3xl border border-border bg-card/35 p-6 transition-colors hover:border-primary/40 hover:bg-card/60"
            >
              <Icon className="size-6 text-primary" />
              <h3 className="mt-5 text-lg font-medium">{title}</h3>
              <p className="mt-2 text-sm leading-6 text-muted-foreground">{description}</p>
              <span className="mt-5 inline-flex items-center gap-2 text-sm font-medium text-foreground">
                Read guide
                <ArrowRight className="size-4 transition-transform group-hover:translate-x-1" />
              </span>
            </Link>
          ))}
        </div>
      </div>
    </section>
  )
}

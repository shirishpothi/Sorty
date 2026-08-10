import Link from 'next/link'
import { ArrowRight, Bot, FolderOpen, Laptop, Scale } from 'lucide-react'
import { Reveal } from '@/components/reveal'

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
  {
    href: '/compare',
    icon: Scale,
    title: 'Compare Mac organizers',
    description: 'Compare Sorty with Hazel, Folder Tidy, and Declutter using sourced workflow details.',
  },
]

export function DiscoveryLinks() {
  return (
    <section className="px-4 py-20" aria-labelledby="discover-sorty">
      <div className="mx-auto max-w-5xl">
        <Reveal>
          <p className="text-sm font-medium text-primary">Guides and use cases</p>
          <h2 id="discover-sorty" className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
            Decide whether Sorty fits your workflow
          </h2>
          <p className="mt-4 max-w-2xl leading-7 text-muted-foreground">
            Explore the organization workflow, a practical Downloads cleanup, local AI privacy, and a sourced competitor comparison.
          </p>
        </Reveal>
        <div className="mt-9 grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {LINKS.map(({ href, icon: Icon, title, description }, index) => (
            <Reveal key={href} delay={(index % 2) * 70}>
              <Link
                href={href}
                className="group flex h-full flex-col rounded-3xl border border-border bg-card/35 p-6 transition-[transform,background-color,border-color,box-shadow] duration-300 ease-out hover:-translate-y-1 hover:border-primary/40 hover:bg-card/60 hover:shadow-xl hover:shadow-black/25"
              >
                <Icon className="size-6 text-primary" />
                <h3 className="mt-5 text-lg font-medium">{title}</h3>
                <p className="mt-2 flex-1 text-sm leading-6 text-muted-foreground">{description}</p>
                <span className="mt-5 inline-flex items-center gap-2 text-sm font-medium text-foreground">
                  Read guide
                  <ArrowRight className="size-4 transition-transform duration-300 group-hover:translate-x-1" />
                </span>
              </Link>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}

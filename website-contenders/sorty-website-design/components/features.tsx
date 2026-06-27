import Image from 'next/image'
import {
  FolderTree,
  PenLine,
  Brain,
  History,
  AppWindow,
  Cpu,
} from 'lucide-react'
import { Reveal } from '@/components/reveal'

const FEATURES = [
  {
    icon: FolderTree,
    title: 'Smart structure suggestions',
    body: 'Sorty suggests folder hierarchies that actually match how you work — by type, project, date, or topic.',
  },
  {
    icon: PenLine,
    title: 'Rename & move previews',
    body: 'See exactly which files will be renamed and where they will land before a single thing moves.',
  },
  {
    icon: Brain,
    title: 'Learns your preferences',
    body: 'Keep or reject suggestions and Sorty adapts to your naming and grouping style over time.',
  },
  {
    icon: History,
    title: 'History & undo',
    body: 'Every organization run is recorded. Roll back any change with a single click, even later.',
  },
  {
    icon: AppWindow,
    title: 'Finder integration',
    body: 'Right-click any folder in Finder and send it straight to Sorty to organize in seconds.',
  },
  {
    icon: Cpu,
    title: 'Bring your own AI',
    body: 'Use cloud providers or run a fully local model. You pick what powers the suggestions.',
  },
]

const SHOTS = [
  {
    src: '/sorty-settings.png',
    title: 'Choose your AI provider',
    body: 'Connect a cloud provider or run everything locally — your call.',
    alt: 'Sorty AI providers settings screen with toggles for OpenAI, Anthropic, Ollama, and Mistral.',
  },
  {
    src: '/sorty-history.png',
    title: 'Undo anything, anytime',
    body: 'A complete timeline of every change, each one reversible.',
    alt: 'Sorty history screen showing a timeline of organization actions, each with an undo button.',
  },
]

export function Features() {
  return (
    <section
      id="features"
      className="section-seam snap-section px-4 py-20 sm:py-28"
    >
      <div className="mx-auto max-w-5xl">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-medium text-primary">Features</p>
          <h2 className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
            Everything you need to tame your files
          </h2>
          <p className="mt-4 text-pretty text-muted-foreground">
            Powerful where it counts, careful where it matters.
          </p>
        </Reveal>

        <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map((f, i) => (
            <Reveal
              key={f.title}
              delay={(i % 3) * 80}
              className="rounded-3xl border border-border bg-card/40 p-6 backdrop-blur-md transition-colors hover:border-primary/40"
            >
              <span className="flex size-11 items-center justify-center rounded-2xl bg-primary/15 text-primary">
                <f.icon className="size-5" />
              </span>
              <h3 className="mt-5 text-lg font-medium">{f.title}</h3>
              <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                {f.body}
              </p>
            </Reveal>
          ))}
        </div>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          {SHOTS.map((shot, i) => (
            <Reveal
              key={shot.title}
              delay={i * 100}
              className="overflow-hidden rounded-3xl border border-border bg-card/40 backdrop-blur-md"
            >
              <div className="border-b border-border p-6">
                <h3 className="text-lg font-medium">{shot.title}</h3>
                <p className="mt-1.5 text-sm text-muted-foreground">{shot.body}</p>
              </div>
              <div className="p-3">
                <Image
                  src={shot.src || '/placeholder.svg'}
                  alt={shot.alt}
                  width={1200}
                  height={800}
                  className="w-full rounded-2xl border border-border"
                />
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}

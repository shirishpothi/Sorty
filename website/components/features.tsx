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
    src: '/sorty-apply.png',
    title: 'Preview every move',
    body: 'Review the apply step before Sorty touches a file.',
    alt: 'Sorty apply screen showing proposed file moves ready for review.',
  },
  {
    src: '/sorty-settings.png',
    title: 'Choose your AI provider',
    body: 'Connect a cloud provider or run everything locally with Ollama.',
    alt: 'Sorty AI provider settings screen showing configured model providers.',
  },
  {
    src: '/sorty-health.png',
    title: 'Keep workspaces healthy',
    body: 'See clutter, stale folders, and automation status in one place.',
    alt: 'Sorty workspace health screen showing folder health insights.',
  },
  {
    src: '/sorty-duplicates.png',
    title: 'Review duplicates clearly',
    body: 'Compare duplicate candidates before choosing what stays.',
    alt: 'Sorty duplicates screen showing duplicate file review controls.',
  },
]

const PROVIDERS = [
  { src: '/provider-chatgpt.png', name: 'OpenAI' },
  { src: '/provider-claude.png', name: 'Claude' },
  { src: '/provider-gemini.png', name: 'Gemini' },
  { src: '/provider-github-copilot.png', name: 'GitHub Copilot' },
  { src: '/provider-groq.png', name: 'Groq' },
  { src: '/provider-ollama.png', name: 'Ollama' },
  { src: '/provider-openrouter.png', name: 'OpenRouter' },
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

        <Reveal className="mt-8">
          <div className="flex flex-wrap items-center justify-center gap-x-2 gap-y-2.5 rounded-3xl border border-border bg-card/35 px-4 py-4 backdrop-blur-md sm:gap-3 sm:px-5">
            {PROVIDERS.map((provider) => (
              <span
                key={provider.name}
                className="flex min-h-10 items-center gap-2 rounded-full border border-white/10 bg-background/70 px-3.5 py-2 text-xs font-medium text-foreground/85 shadow-sm shadow-black/20"
              >
                <Image
                  src={provider.src}
                  alt=""
                  width={24}
                  height={24}
                  className="size-6 object-contain"
                />
                {provider.name}
              </span>
            ))}
          </div>
        </Reveal>

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
                  src={shot.src}
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

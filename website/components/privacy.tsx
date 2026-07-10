import { Lock, ShieldOff, Server, KeyRound, EyeOff } from 'lucide-react'
import { Reveal } from '@/components/reveal'

const GITHUB_URL = 'https://github.com/sorty-organizer/Sorty'

const POINTS = [
  {
    icon: ShieldOff,
    title: 'No servers. No accounts. No telemetry.',
    body: 'Sorty has no backend. There is nothing to sign up for and nothing phones home. The developers literally cannot see your files, your folder names, your activity, or anything else — because none of it is ever sent to us.',
  },
  {
    icon: EyeOff,
    title: 'Only your AI provider sees anything',
    body: 'To build a plan, Sorty sends file names and metadata to the AI provider you choose. File contents are only ever shared if you explicitly turn on Deep Scan — and even then, contents go directly to your provider, never through Sorty.',
  },
  {
    icon: Server,
    title: 'Or keep everything 100% on-device',
    body: 'Point Sorty through Ollama and absolutely nothing leaves your Mac — not even file names. Full organization, zero network.',
  },
  {
    icon: KeyRound,
    title: 'Strict, scoped folder access',
    body: 'Sorty uses macOS security-scoped bookmarks. It can only ever touch the specific folders you explicitly grant — nothing else on your disk.',
  },
]

export function Privacy() {
  return (
    <section
      id="privacy"
      className="section-seam page-section px-4 py-20 sm:py-28"
    >
      <div className="mx-auto max-w-5xl">
        <Reveal className="mx-auto max-w-2xl text-center">
          <p className="text-sm font-medium text-primary">Privacy, in plain language</p>
          <h2 className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
            Your files never reach us. Ever.
          </h2>
          <p className="mt-4 text-pretty text-muted-foreground">
            Sorty has no servers and no account system, so your files and folder
            data never touch the developers. The only party that ever sees
            anything is the AI provider you choose — and only file contents, only
            if you switch on Deep Scan.
          </p>
        </Reveal>

        {/* headline emphasis banner */}
        <Reveal delay={80} className="mt-12">
          <div className="relative overflow-hidden rounded-3xl border border-primary/30 bg-card/50 p-6 text-center backdrop-blur-xl sm:p-8">
            <div
              aria-hidden
              className="pointer-events-none absolute inset-0 -z-10"
              style={{
                background:
                  'radial-gradient(600px 220px at 50% 0%, color-mix(in oklch, var(--brand) 22%, transparent), transparent 70%)',
              }}
            />
            <span className="inline-flex items-center gap-2 rounded-full bg-primary/15 px-3 py-1 text-xs font-medium text-primary">
              <Lock className="size-3.5" />
              Private by architecture, not by promise
            </span>
            <p className="mx-auto mt-4 max-w-2xl text-balance text-lg font-medium leading-relaxed sm:text-xl">
              Sorty can&apos;t leak what it never receives. With no backend, the
              app and its developers have{' '}
              <span className="text-primary">zero visibility</span> into your
              files. Cloud AI providers only see contents when{' '}
              <span className="text-primary">Deep Scan</span> is on — your call,
              every time.
            </p>
          </div>
        </Reveal>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          {POINTS.map((p, i) => (
            <Reveal
              key={p.title}
              delay={(i % 2) * 80}
              className="rounded-3xl border border-border bg-card/40 p-6 backdrop-blur-md transition-colors hover:border-primary/40"
            >
              <div className="flex items-start gap-4">
                <span className="flex size-11 shrink-0 items-center justify-center rounded-2xl bg-primary/15 text-primary">
                  <p.icon className="size-5" />
                </span>
                <div>
                  <h3 className="text-lg font-medium">{p.title}</h3>
                  <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                    {p.body}
                  </p>
                </div>
              </div>
            </Reveal>
          ))}
        </div>

        <Reveal className="mt-6">
          <p className="rounded-3xl border border-border bg-card/30 p-5 text-center text-sm text-muted-foreground backdrop-blur-md">
            Because Sorty is{' '}
            <a
              href={GITHUB_URL}
              target="_blank"
              rel="noreferrer"
              className="font-medium text-primary underline-offset-4 transition-colors hover:text-primary/80 hover:underline"
            >
              open source
            </a>{' '}
            under the GPL v3, you can read every
            line of code yourself and verify all of this.
          </p>
        </Reveal>
      </div>
    </section>
  )
}

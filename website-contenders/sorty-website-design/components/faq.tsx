'use client'

import { useState } from 'react'
import { Plus } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Reveal } from '@/components/reveal'

const FAQS = [
  {
    q: 'Does Sorty delete my files?',
    a: 'No. Sorty only moves and renames files into folders — it never deletes anything. Nothing happens until you review the plan and click apply.',
  },
  {
    q: 'Can I undo changes?',
    a: 'Yes. Every organization run is recorded in History, and any run can be fully reversed with one click — even days later.',
  },
  {
    q: 'Are my files uploaded anywhere?',
    a: 'Never to us. Sorty has no servers and no accounts, so the developers can never see your files or anything about them. By default only lightweight metadata (file names, types, sizes, dates) is sent to the AI provider you choose. File contents are only ever shared if you turn on Deep Scan, and even then they go straight to your provider. Pick a local model and nothing leaves your Mac at all.',
  },
  {
    q: 'Which AI providers are supported?',
    a: 'Sorty works with major cloud providers like OpenAI, Anthropic, and Mistral, and with local models through Ollama. You bring your own key or run locally — Sorty does not resell AI usage.',
  },
  {
    q: 'What macOS version do I need?',
    a: 'macOS 15 or later, on both Apple Silicon and Intel Macs.',
  },
  {
    q: 'Does it work with external drives, iCloud Drive, or Dropbox?',
    a: 'Yes. Sorty works with any folder you can grant access to, including external drives and synced folders from iCloud Drive and Dropbox.',
  },
  {
    q: 'What happens if I cancel midway?',
    a: 'Applying changes is atomic and resumable. If you stop midway, only the moves already confirmed are kept, and you can undo the entire run from History.',
  },
]

function FaqItem({ q, a }: { q: string; a: string }) {
  const [open, setOpen] = useState(false)
  return (
    <div className="rounded-3xl border border-border bg-card/40 backdrop-blur-md transition-colors hover:border-primary/30">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center justify-between gap-4 px-6 py-5 text-left"
        aria-expanded={open}
      >
        <span className="text-base font-medium">{q}</span>
        <Plus
          className={cn(
            'size-5 shrink-0 text-primary transition-transform duration-300',
            open && 'rotate-45',
          )}
        />
      </button>
      <div
        className={cn(
          'grid transition-all duration-500 ease-[cubic-bezier(0.16,1,0.3,1)]',
          open ? 'grid-rows-[1fr] opacity-100 blur-0' : 'grid-rows-[0fr] opacity-0 blur-sm',
        )}
      >
        <div className="overflow-hidden">
          <p className="px-6 pb-5 text-sm leading-relaxed text-muted-foreground">
            {a}
          </p>
        </div>
      </div>
    </div>
  )
}

export function Faq() {
  return (
    <section
      id="faq"
      className="section-seam snap-section px-4 py-20 sm:py-28"
    >
      <div className="mx-auto max-w-3xl">
        <Reveal className="text-center">
          <p className="text-sm font-medium text-primary">FAQ</p>
          <h2 className="mt-3 text-balance text-3xl font-semibold tracking-tight sm:text-4xl">
            Questions, answered
          </h2>
        </Reveal>

        <div className="mt-12 space-y-3">
          {FAQS.map((item, i) => (
            <Reveal key={item.q} delay={(i % 4) * 60}>
              <FaqItem {...item} />
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}

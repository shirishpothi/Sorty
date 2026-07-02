'use client'

import { useState } from 'react'
import { Plus } from 'lucide-react'
import { cn } from '@/lib/utils'
import { Reveal } from '@/components/reveal'
import { FAQS } from '@/components/faq-data'

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
      className="section-seam page-section px-4 py-20 sm:py-28"
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

import { SiteNav } from '@/components/site-nav'
import { Hero } from '@/components/hero'
import { HowItWorks } from '@/components/how-it-works'
import { Features } from '@/components/features'
import { Privacy } from '@/components/privacy'
import { Pricing } from '@/components/pricing'
import { Faq } from '@/components/faq'
import { SiteFooter } from '@/components/site-footer'
import { StructuredData } from '@/components/structured-data'

export default function Page() {
  // overflow-x-clip (not -hidden): `hidden` would make <main> a scroll
  // container and capture the sections' snap points away from the root
  // scroller, silently breaking section snapping.
  return (
    <main data-snap-scroll className="relative min-h-screen overflow-x-clip">
      <StructuredData />
      <SiteNav />
      <Hero />
      <HowItWorks />
      <Features />
      <Privacy />
      <Pricing />
      <Faq />
      <SiteFooter />
    </main>
  )
}

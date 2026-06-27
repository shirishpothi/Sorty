import { SiteNav } from '@/components/site-nav'
import { Hero } from '@/components/hero'
import { TrustSafety } from '@/components/trust-safety'
import { HowItWorks } from '@/components/how-it-works'
import { Features } from '@/components/features'
import { Privacy } from '@/components/privacy'
import { Pricing } from '@/components/pricing'
import { Faq } from '@/components/faq'
import { SiteFooter } from '@/components/site-footer'
import { SectionScrollController } from '@/components/section-scroll-controller'

export default function Page() {
  return (
    <main className="relative min-h-screen overflow-x-hidden">
      <SectionScrollController />
      <SiteNav />
      <Hero />
      <TrustSafety />
      <HowItWorks />
      <Features />
      <Privacy />
      <Pricing />
      <Faq />
      <SiteFooter />
    </main>
  )
}

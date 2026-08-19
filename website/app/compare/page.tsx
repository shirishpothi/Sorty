import type { Metadata } from 'next'
import { ComparisonPage } from '@/components/comparison-page'
import { OG_IMAGE_PATH, SITE_NAME, SITE_URL } from '@/lib/site-metadata'

const title = 'Sorty vs Hazel vs Folder Tidy vs Sparkle'
const description =
  'Compare Mac file organizers by AI, rules, preview-before-apply, automation, undo, privacy, and open-source availability. See where Sorty, Hazel, Folder Tidy, and Sparkle differ.'

export const metadata: Metadata = {
  title,
  description,
  keywords: [
    'Sorty vs Hazel',
    'Hazel alternative Mac',
    'Folder Tidy alternative',
    'Sparkle alternative Mac',
    'best Mac file organizer',
    'AI file organizer comparison',
    'Mac folder automation comparison',
    'open source Hazel alternative',
  ],
  alternates: { canonical: '/compare' },
  openGraph: {
    type: 'website',
    siteName: SITE_NAME,
    title,
    description,
    url: `${SITE_URL}/compare/`,
    images: [
      {
        url: OG_IMAGE_PATH,
        width: 1102,
        height: 754,
        alt: 'Sorty showing a reviewable AI-generated folder organization plan on macOS.',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title,
    description,
    images: [OG_IMAGE_PATH],
  },
}

export default function CompareRoute() {
  return <ComparisonPage />
}

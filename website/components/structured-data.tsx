import { FAQS } from '@/components/faq-data'

const SITE_URL = 'https://sorty.app'
const GITHUB_URL = 'https://github.com/sorty-organizer/Sorty'

/**
 * JSON-LD structured data for rich results: the software application itself,
 * the publishing organization, and the FAQ shown on the home page.
 */
export function StructuredData() {
  const graph = {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'Organization',
        '@id': `${SITE_URL}/#organization`,
        name: 'Sorty',
        url: SITE_URL,
        logo: `${SITE_URL}/sorty-icon-96.webp`,
        sameAs: [GITHUB_URL],
      },
      {
        '@type': 'WebSite',
        '@id': `${SITE_URL}/#website`,
        url: SITE_URL,
        name: 'Sorty',
        description: 'AI folder organization for your Mac.',
        publisher: { '@id': `${SITE_URL}/#organization` },
        inLanguage: 'en-US',
      },
      {
        '@type': 'SoftwareApplication',
        '@id': `${SITE_URL}/#app`,
        name: 'Sorty',
        applicationCategory: 'UtilitiesApplication',
        operatingSystem: 'macOS 15+',
        description:
          'Sorty is a free and open source (GPL v3) Mac app that uses AI to organize your folders. Preview every change, undo anytime, and keep your files local.',
        url: SITE_URL,
        downloadUrl: `${GITHUB_URL}/releases/latest/download/Sorty-universal.zip`,
        softwareLicense: 'https://www.gnu.org/licenses/gpl-3.0.en.html',
        isAccessibleForFree: true,
        publisher: { '@id': `${SITE_URL}/#organization` },
        screenshot: `${SITE_URL}/sorty-app.webp`,
        offers: {
          '@type': 'Offer',
          price: '0',
          priceCurrency: 'USD',
        },
      },
      {
        '@type': 'FAQPage',
        '@id': `${SITE_URL}/#faq`,
        mainEntity: FAQS.map((item) => ({
          '@type': 'Question',
          name: item.q,
          acceptedAnswer: {
            '@type': 'Answer',
            text: item.a,
          },
        })),
      },
    ],
  }

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(graph) }}
    />
  )
}

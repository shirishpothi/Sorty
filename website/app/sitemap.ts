import type { MetadataRoute } from 'next'
import { DISCOVERY_PAGES } from '@/lib/discovery-pages'
import { LAST_MODIFIED, SITE_URL } from '@/lib/site-metadata'

export const dynamic = 'force-static'

export default function sitemap(): MetadataRoute.Sitemap {
  const primaryPages: MetadataRoute.Sitemap = [
    {
      url: SITE_URL,
      lastModified: LAST_MODIFIED,
      changeFrequency: 'weekly',
      priority: 1,
    },
    {
      url: `${SITE_URL}/changelog`,
      lastModified: LAST_MODIFIED,
      changeFrequency: 'monthly',
      priority: 0.7,
    },
    {
      url: `${SITE_URL}/press`,
      lastModified: LAST_MODIFIED,
      changeFrequency: 'monthly',
      priority: 0.6,
    },
  ]

  const discoveryPages: MetadataRoute.Sitemap = DISCOVERY_PAGES.map((page) => ({
    url: `${SITE_URL}/${page.slug}`,
    lastModified: LAST_MODIFIED,
    changeFrequency: 'monthly',
    priority: page.slug === 'mac-folder-organizer' ? 0.9 : 0.8,
  }))

  const legalPages: MetadataRoute.Sitemap = [
    {
      url: `${SITE_URL}/privacy-policy`,
      lastModified: LAST_MODIFIED,
      changeFrequency: 'yearly',
      priority: 0.5,
    },
    {
      url: `${SITE_URL}/terms`,
      lastModified: LAST_MODIFIED,
      changeFrequency: 'yearly',
      priority: 0.5,
    },
  ]

  return [...primaryPages, ...discoveryPages, ...legalPages]
}

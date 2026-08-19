import { SITE_NAME, SITE_URL } from '@/lib/site-metadata'

type BreadcrumbItem = {
  name: string
  path: string
}

type PageStructuredDataProps = {
  name: string
  description: string
  path: string
  breadcrumbs: BreadcrumbItem[]
  dateModified?: string
}

export function PageStructuredData({
  name,
  description,
  path,
  breadcrumbs,
  dateModified,
}: PageStructuredDataProps) {
  const canonicalPath = path === '/' || path.endsWith('/') ? path : `${path}/`
  const pageUrl = `${SITE_URL}${canonicalPath}`
  const graph = [
    {
      '@type': 'WebPage',
      '@id': `${pageUrl}#webpage`,
      url: pageUrl,
      name,
      description,
      isPartOf: { '@id': `${SITE_URL}/#website` },
      inLanguage: 'en-US',
      ...(dateModified ? { dateModified } : {}),
    },
    {
      '@type': 'BreadcrumbList',
      '@id': `${pageUrl}#breadcrumb`,
      itemListElement: breadcrumbs.map((item, index) => ({
        '@type': 'ListItem',
        position: index + 1,
        name: item.name,
        item: `${SITE_URL}${item.path === '/' || item.path.endsWith('/') ? item.path : `${item.path}/`}`,
      })),
    },
  ]

  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{
        __html: JSON.stringify({
          '@context': 'https://schema.org',
          '@graph': [
            {
              '@type': 'WebSite',
              '@id': `${SITE_URL}/#website`,
              url: `${SITE_URL}/`,
              name: SITE_NAME,
              inLanguage: 'en-US',
            },
            ...graph,
          ],
        }),
      }}
    />
  )
}

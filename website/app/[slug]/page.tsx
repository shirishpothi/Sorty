import type { Metadata } from 'next'
import { notFound } from 'next/navigation'
import { DiscoveryPage } from '@/components/discovery-page'
import { DISCOVERY_PAGES, getDiscoveryPage } from '@/lib/discovery-pages'
import { OG_IMAGE_PATH, SITE_NAME, SITE_URL } from '@/lib/site-metadata'

type PageProps = {
  params: Promise<{ slug: string }>
}

export function generateStaticParams() {
  return DISCOVERY_PAGES.map((page) => ({ slug: page.slug }))
}

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { slug } = await params
  const page = getDiscoveryPage(slug)

  if (!page) {
    return {}
  }

  return {
    title: page.eyebrow,
    description: page.description,
    keywords: page.keywords,
    alternates: { canonical: `/${page.slug}` },
    openGraph: {
      type: 'website',
      siteName: SITE_NAME,
      title: page.title,
      description: page.description,
      url: `${SITE_URL}/${page.slug}`,
      images: [{ url: OG_IMAGE_PATH, width: 1102, height: 754, alt: page.imageAlt }],
    },
    twitter: {
      card: 'summary_large_image',
      title: page.title,
      description: page.description,
      images: [OG_IMAGE_PATH],
    },
  }
}

export default async function DiscoveryRoute({ params }: PageProps) {
  const { slug } = await params
  const page = getDiscoveryPage(slug)

  if (!page) {
    notFound()
  }

  return <DiscoveryPage page={page} />
}

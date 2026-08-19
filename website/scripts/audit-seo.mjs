import { readFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDirectory = dirname(fileURLToPath(import.meta.url))
const outputDirectory = resolve(scriptDirectory, '..', 'out')
const siteUrl = 'https://sorty-organizer.github.io/Sorty'
const sitemap = await readFile(resolve(outputDirectory, 'sitemap.xml'), 'utf8')
const sitemapUrls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1])

if (sitemapUrls.length === 0) {
  throw new Error('The sitemap contains no URLs.')
}

for (const url of sitemapUrls) {
  const parsedUrl = new URL(url)
  const relativePath = parsedUrl.pathname.slice('/Sorty/'.length).replace(/\/$/, '')
  const htmlPath = relativePath
    ? resolve(outputDirectory, relativePath, 'index.html')
    : resolve(outputDirectory, 'index.html')
  const html = await readFile(htmlPath, 'utf8')
  const canonical = html.match(/<link rel="canonical" href="([^"]+)"\/>/)?.[1]

  if (!url.endsWith('/')) {
    throw new Error(`Sitemap URL is not canonical: ${url}`)
  }

  if (canonical !== url) {
    throw new Error(`Canonical mismatch for ${url}: found ${canonical ?? 'none'}`)
  }

  for (const match of html.matchAll(/href="(\/Sorty\/[^"#?]*)/g)) {
    const href = match[1]
    const finalSegment = href.split('/').at(-1) ?? ''
    const isFile = finalSegment.includes('.')

    if (!isFile && !href.endsWith('/')) {
      throw new Error(`Internal link redirects instead of using its canonical URL: ${href}`)
    }
  }
}

const robots = await readFile(resolve(outputDirectory, 'robots.txt'), 'utf8')
if (!robots.includes(`Sitemap: ${siteUrl}/sitemap.xml`)) {
  throw new Error('robots.txt does not advertise the production sitemap.')
}

console.log(`SEO audit passed for ${sitemapUrls.length} canonical pages.`)

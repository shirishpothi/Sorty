import type { Metadata, Viewport } from 'next'
import { Geist, Geist_Mono } from 'next/font/google'
import './globals.css'

const geistSans = Geist({ variable: '--font-geist-sans', subsets: ['latin'] })
const geistMono = Geist_Mono({
  variable: '--font-geist-mono',
  subsets: ['latin'],
})

const SITE_URL = 'https://sorty-organizer.github.io/Sorty'

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: 'Sorty — AI folder organization for your Mac',
    template: '%s — Sorty',
  },
  description:
    'Sorty is a free and open source (GPL v3) Mac app that uses AI to organize your folders. Preview every change, undo anytime, and keep your files local.',
  applicationName: 'Sorty',
  generator: 'Next.js',
  authors: [{ name: 'The Sorty open-source project' }],
  creator: 'The Sorty open-source project',
  publisher: 'The Sorty open-source project',
  category: 'productivity',
  keywords: [
    'Sorty',
    'AI folder organizer',
    'Mac file organization',
    'macOS file organizer',
    'organize Downloads folder',
    'AI file management Mac',
    'open source Mac app',
    'private file organizer',
    'local AI Mac',
    'Ollama file organizer',
    'GPL v3 macOS app',
  ],
  alternates: {
    canonical: '/',
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      'max-image-preview': 'large',
      'max-snippet': -1,
      'max-video-preview': -1,
    },
  },
  openGraph: {
    type: 'website',
    siteName: 'Sorty',
    title: 'Sorty — AI folder organization for your Mac',
    description:
      'A free and open source (GPL v3) Mac app that uses AI to organize your folders. Preview every change, undo anytime, and keep your files local.',
    url: SITE_URL,
    locale: 'en_US',
    images: [
      {
        url: '/sorty-app.webp',
        width: 1102,
        height: 754,
        alt: 'The Sorty app showing an AI-generated organization plan for a Downloads folder.',
      },
    ],
  },
  twitter: {
    card: 'summary_large_image',
    title: 'Sorty — AI folder organization for your Mac',
    description:
      'A free and open source (GPL v3) Mac app that uses AI to organize your folders. Preview every change, undo anytime, and keep your files local.',
    images: ['/sorty-app.webp'],
  },
  icons: {
    icon: [
      {
        url: `${SITE_URL}/icon-light-32x32.png`,
        media: '(prefers-color-scheme: light)',
      },
      {
        url: `${SITE_URL}/icon-dark-32x32.png`,
        media: '(prefers-color-scheme: dark)',
      },
    ],
    apple: `${SITE_URL}/apple-icon.png`,
  },
}

export const viewport: Viewport = {
  colorScheme: 'dark',
  themeColor: '#0b0c10',
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html
      lang="en"
      className={`dark ${geistSans.variable} ${geistMono.variable} bg-background`}
    >
      <body className="font-sans antialiased">
        {children}
      </body>
    </html>
  )
}

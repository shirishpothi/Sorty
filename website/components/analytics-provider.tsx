'use client'

import {
  createContext,
  useContext,
  useEffect,
  useId,
  useState,
} from 'react'
import { usePathname } from 'next/navigation'
import {
  applyWebsiteAnalyticsPreference,
  captureWebsiteException,
  isWebsiteAnalyticsEnabled,
  trackPageView,
  trackSectionView,
  trackWebInteraction,
  WEBSITE_ANALYTICS_PREFERENCE_KEY,
  type WebsiteAnalyticsPreference,
} from '@/lib/analytics'

type AnalyticsPreferencesContextValue = {
  openPreferences: () => void
}

const AnalyticsPreferencesContext =
  createContext<AnalyticsPreferencesContextValue | null>(null)

export function AnalyticsProvider({ children }: { children: React.ReactNode }) {
  const pathname = usePathname()
  const [isOpen, setIsOpen] = useState(false)
  const [preference, setPreference] =
    useState<WebsiteAnalyticsPreference | null>(() => {
      if (typeof window === 'undefined') {
        return null
      }
      const stored = window.localStorage.getItem(
        WEBSITE_ANALYTICS_PREFERENCE_KEY,
      )
      return stored === 'allowed' || stored === 'denied' ? stored : null
    })
  const titleId = useId()
  const descriptionId = useId()

  useEffect(() => {
    trackPageView(pathname)

    const seen = new Set<string>()
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting || entry.intersectionRatio < 0.35) {
            continue
          }

          const element = entry.target as HTMLElement
          const section =
            element.dataset.analyticsSection || element.getAttribute('id')
          if (!section || seen.has(section)) {
            continue
          }

          seen.add(section)
          trackSectionView(section, pathname)
          observer.unobserve(element)
        }
      },
      { threshold: [0.35] },
    )

    const elements = document.querySelectorAll<HTMLElement>(
      'section[id], [data-analytics-section]',
    )
    elements.forEach((element) => observer.observe(element))
    return () => observer.disconnect()
  }, [pathname])

  useEffect(() => {
    const handleError = (event: ErrorEvent) => {
      captureWebsiteException(event.error ?? new Error('Window error'), {
        surface: 'window',
        handled: false,
        cause: 'unhandled_error',
      })
    }
    const handleRejection = (event: PromiseRejectionEvent) => {
      captureWebsiteException(event.reason, {
        surface: 'promise',
        handled: false,
        cause: 'unhandled_rejection',
      })
    }

    window.addEventListener('error', handleError)
    window.addEventListener('unhandledrejection', handleRejection)
    return () => {
      window.removeEventListener('error', handleError)
      window.removeEventListener('unhandledrejection', handleRejection)
    }
  }, [])

  useEffect(() => {
    const handleClick = (event: MouseEvent) => {
      const target = event.target
      if (!(target instanceof Element)) {
        return
      }

      const trackedElement = target.closest<HTMLElement>(
        '[data-analytics-action]',
      )
      if (!trackedElement) {
        return
      }

      trackWebInteraction({
        action: trackedElement.dataset.analyticsAction ?? 'clicked',
        component: trackedElement.dataset.analyticsComponent ?? 'control',
        location: trackedElement.dataset.analyticsLocation ?? 'unknown',
        target: trackedElement.dataset.analyticsTarget,
      })
    }

    document.addEventListener('click', handleClick)
    return () => document.removeEventListener('click', handleClick)
  }, [])

  function setAnalyticsPreference(next: WebsiteAnalyticsPreference) {
    window.localStorage.setItem(WEBSITE_ANALYTICS_PREFERENCE_KEY, next)
    applyWebsiteAnalyticsPreference(next)
    setPreference(next)
    setIsOpen(false)

    if (next === 'allowed') {
      trackWebInteraction({
        action: 'analytics_allowed',
        component: 'analytics_preferences',
        location: 'footer',
        outcome: 'enabled',
      })
    }
  }

  function openAnalyticsPreferences() {
    setIsOpen(true)
    trackWebInteraction({
      action: 'analytics_preferences_opened',
      component: 'analytics_preferences',
      location: 'footer',
      outcome: isWebsiteAnalyticsEnabled() ? 'enabled' : 'disabled',
    })
  }

  function dismissAnalyticsPreferences() {
    setIsOpen(false)
    trackWebInteraction({
      action: 'analytics_preferences_dismissed',
      component: 'analytics_preferences',
      location: 'footer',
      target: 'backdrop',
    })
  }

  const isEnabled = isWebsiteAnalyticsEnabled()

  return (
    <AnalyticsPreferencesContext.Provider
      value={{ openPreferences: openAnalyticsPreferences }}
    >
      {children}
      {isOpen && (
        <div
          className="fixed inset-0 z-[120] grid place-items-end bg-black/50 p-3 backdrop-blur-md sm:place-items-center sm:p-6"
          onMouseDown={(event) => {
            if (event.target === event.currentTarget) {
              dismissAnalyticsPreferences()
            }
          }}
        >
          <section
            role="dialog"
            aria-modal="true"
            aria-labelledby={titleId}
            aria-describedby={descriptionId}
            className="w-full max-w-lg rounded-3xl border border-border bg-background/95 p-6 shadow-2xl shadow-black/60 backdrop-blur-2xl"
          >
            <p className="text-xs font-medium uppercase tracking-[0.16em] text-primary">
              Privacy controls
            </p>
            <h2 id={titleId} className="mt-2 text-xl font-semibold">
              Anonymous website analytics
            </h2>
            <p
              id={descriptionId}
              className="mt-3 text-sm leading-relaxed text-muted-foreground"
            >
              Sorty measures page and section visits, meaningful button use, and
              sanitized technical errors. It uses no analytics cookies, user
              profile, session recording, form text, file data, or full
              referrer URLs.
            </p>
            <p className="mt-3 text-xs text-muted-foreground">
              Current setting:{' '}
              <span className="font-medium text-foreground">
                {isEnabled ? 'Allowed' : 'Not allowed'}
              </span>
              {preference === null && isEnabled
                ? ' (privacy-preserving default)'
                : ''}
            </p>
            <div className="mt-6 grid gap-2 sm:grid-cols-2">
              <button
                type="button"
                onClick={() => setAnalyticsPreference('allowed')}
                className="rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90"
              >
                Allow anonymous analytics
              </button>
              <button
                type="button"
                onClick={() => setAnalyticsPreference('denied')}
                className="rounded-full border border-border bg-secondary/60 px-5 py-2.5 text-sm font-medium transition-colors hover:bg-secondary"
              >
                Don&apos;t allow
              </button>
            </div>
          </section>
        </div>
      )}
    </AnalyticsPreferencesContext.Provider>
  )
}

export function AnalyticsPreferencesButton({
  className,
}: {
  className?: string
}) {
  const context = useContext(AnalyticsPreferencesContext)
  if (!context) {
    return null
  }

  return (
    <button
      type="button"
      onClick={context.openPreferences}
      className={className}
    >
      Analytics preferences
    </button>
  )
}

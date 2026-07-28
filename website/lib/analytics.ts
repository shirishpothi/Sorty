'use client'

import posthog from 'posthog-js'
import type { CaptureResult, Properties } from 'posthog-js'

export const WEBSITE_ANALYTICS_PREFERENCE_KEY =
  'sorty.website.analytics.preference'

export type WebsiteAnalyticsPreference = 'allowed' | 'denied'

type InteractionProperties = {
  action: string
  component: string
  location: string
  target?: string
  outcome?: string
}

type ExceptionContext = {
  surface: string
  handled: boolean
  cause?: string
}

type WebPerformanceMetric = {
  name: string
  value: number
  rating: string
  navigationType: string
}

const POSTHOG_EVENT_ALLOWLIST = new Set([
  '$exception',
  '$pageview',
  'web:interaction',
  'web:not_found_viewed',
  'web:performance_measured',
  'web:scroll_depth_reached',
  'web:section_viewed',
])

const PAGE_NAMES: Record<string, string> = {
  '/': 'home',
  '/changelog': 'changelog',
  '/privacy-policy': 'privacy_policy',
  '/terms': 'terms',
}

const SECTION_NAMES = new Set([
  'top',
  'how-it-works',
  'features',
  'privacy',
  'pricing',
  'faq',
  'footer',
])

const PERFORMANCE_METRICS = new Set(['CLS', 'FCP', 'INP', 'LCP', 'TTFB'])

const WEBSITE_PROPERTY_ALLOWLIST = new Set([
  '$browser',
  '$browser_version',
  '$current_url',
  '$device_type',
  '$geoip_disable',
  '$lib',
  '$lib_version',
  '$os',
  '$os_version',
  '$process_person_profile',
  '$session_id',
  'action',
  'analytics_scope',
  'component',
  'depth_percent',
  'distinct_id',
  'error_category',
  'error_cause',
  'error_type',
  'handled',
  'location',
  'metric_name',
  'metric_unit',
  'metric_value',
  'navigation_type',
  'outcome',
  'page_name',
  'page_path',
  'platform_surface',
  'section',
  'surface',
  'target',
  'token',
  'traffic_source',
  'rating',
])

let isInitialized = false

function readPreference(): WebsiteAnalyticsPreference | null {
  if (typeof window === 'undefined') {
    return null
  }

  const value = window.localStorage.getItem(WEBSITE_ANALYTICS_PREFERENCE_KEY)
  return value === 'allowed' || value === 'denied' ? value : null
}

function hasGlobalPrivacySignal(): boolean {
  if (typeof window === 'undefined' || typeof navigator === 'undefined') {
    return false
  }

  const navigatorWithGpc = navigator as Navigator & {
    globalPrivacyControl?: boolean
  }
  const windowWithDnt = window as Window & { doNotTrack?: string }

  return (
    navigatorWithGpc.globalPrivacyControl === true ||
    navigator.doNotTrack === '1' ||
    windowWithDnt.doNotTrack === '1'
  )
}

export function isWebsiteAnalyticsEnabled(): boolean {
  const preference = readPreference()
  if (preference === 'denied' || hasGlobalPrivacySignal()) {
    return false
  }

  return preference === 'allowed' || preference === null
}

function stripBasePath(pathname: string): string {
  const configuredBasePath = process.env.NEXT_PUBLIC_BASE_PATH ?? ''
  const basePath = configuredBasePath.replace(/\/+$/, '')
  let normalized = pathname || '/'

  if (basePath && normalized.startsWith(basePath)) {
    normalized = normalized.slice(basePath.length) || '/'
  }

  if (normalized.length > 1) {
    normalized = normalized.replace(/\/+$/, '')
  }

  return normalized || '/'
}

function safePagePath(pathname = window.location.pathname): string {
  const normalized = stripBasePath(pathname)
  return PAGE_NAMES[normalized] ? normalized : '/not-found'
}

function trafficSource(): string {
  if (!document.referrer) {
    return 'direct'
  }

  try {
    const hostname = new URL(document.referrer).hostname.toLowerCase()
    if (hostname === window.location.hostname) return 'internal'
    if (hostname === 'github.com' || hostname.endsWith('.github.com')) return 'github'
    if (
      ['google.', 'bing.com', 'duckduckgo.com', 'search.brave.com'].some(
        (value) => hostname.includes(value),
      )
    ) {
      return 'search'
    }
    if (
      ['reddit.com', 'x.com', 'twitter.com', 'linkedin.com'].some(
        (value) => hostname === value || hostname.endsWith(`.${value}`),
      )
    ) {
      return 'social'
    }
    return 'referral'
  } catch {
    return 'unknown'
  }
}

function sanitizeUrl(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined
  }

  try {
    const url = new URL(value, window.location.origin)
    return `${url.origin}${url.pathname}`
  } catch {
    return undefined
  }
}

function sanitizeEvent(event: CaptureResult | null): CaptureResult | null {
  if (!event) {
    return null
  }
  if (!isWebsiteAnalyticsEnabled() || !POSTHOG_EVENT_ALLOWLIST.has(event.event)) {
    return null
  }

  const properties = event.properties ?? {}
  const currentUrl = sanitizeUrl(properties.$current_url)
  const safeProperties = Object.fromEntries(
    Object.entries(properties)
      .filter(
        ([key]) =>
          WEBSITE_PROPERTY_ALLOWLIST.has(key) ||
          key.startsWith('$exception'),
      )
      .map(([key, value]) => [key, sanitizeProperty(value)]),
  )

  if (currentUrl) {
    safeProperties.$current_url = currentUrl
  }
  safeProperties.$geoip_disable = true
  safeProperties.analytics_scope = 'anonymous_aggregate'
  safeProperties.platform_surface = 'website'
  event.properties = safeProperties
  return event
}

function sanitizeProperty(value: unknown): unknown {
  if (typeof value === 'string') {
    return value
      .slice(0, 500)
      .replace(/[?#][^\s)]+/g, '')
      .replace(
        /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi,
        '[redacted-email]',
      )
  }
  if (Array.isArray(value)) {
    return value.map(sanitizeProperty)
  }
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, nestedValue]) => [
        key,
        sanitizeProperty(nestedValue),
      ]),
    )
  }
  return value
}

export function initializeWebsiteAnalytics(): void {
  if (
    typeof window === 'undefined' ||
    isInitialized ||
    !isWebsiteAnalyticsEnabled()
  ) {
    return
  }

  const projectToken = process.env.NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN
  const host = process.env.NEXT_PUBLIC_POSTHOG_HOST

  if (!projectToken || !host) {
    if (process.env.NODE_ENV === 'development') {
      console.error(
        'NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN and NEXT_PUBLIC_POSTHOG_HOST variables required by PostHog are missing or un-configured, this causes events to be silently missed. This error stops appearing once both variables are configured',
      )
    }
    return
  }

  isInitialized = true
  posthog.init(projectToken, {
    api_host: host,
    ui_host: 'https://us.posthog.com',
    defaults: '2026-05-30',
    autocapture: false,
    capture_pageview: false,
    capture_pageleave: false,
    capture_exceptions: false,
    capture_performance: false,
    capture_dead_clicks: false,
    person_profiles: 'never',
    persistence: 'sessionStorage',
    disable_persistence: false,
    disable_session_recording: true,
    enable_heatmaps: false,
    disable_surveys: true,
    advanced_disable_feature_flags: true,
    disable_external_dependency_loading: true,
    respect_dnt: true,
    request_batching: false,
    before_send: sanitizeEvent,
  })
}

export function applyWebsiteAnalyticsPreference(
  preference: WebsiteAnalyticsPreference,
): void {
  if (preference === 'denied') {
    if (isInitialized) {
      posthog.opt_out_capturing()
    }
    return
  }

  if (!isWebsiteAnalyticsEnabled()) {
    return
  }

  initializeWebsiteAnalytics()
  if (isInitialized) {
    posthog.opt_in_capturing({ captureEventName: false })
  }
}

function capture(event: string, properties: Properties): void {
  initializeWebsiteAnalytics()
  if (!isInitialized || !isWebsiteAnalyticsEnabled()) {
    return
  }

  posthog.capture(event, {
    ...properties,
    platform_surface: 'website',
  })
}

export function trackPageView(pathname: string): void {
  const pagePath = safePagePath(pathname)
  const pageName = PAGE_NAMES[pagePath] ?? 'not_found'
  capture('$pageview', {
    $current_url: `${window.location.origin}${pagePath}`,
    page_name: pageName,
    page_path: pagePath,
    traffic_source: trafficSource(),
  })

  if (pageName === 'not_found') {
    capture('web:not_found_viewed', {
      page_name: pageName,
      page_path: pagePath,
    })
  }
}

export function trackSectionView(section: string, pagePath: string): void {
  if (!SECTION_NAMES.has(section)) {
    return
  }

  capture('web:section_viewed', {
    page_path: safePagePath(pagePath),
    section,
  })
}

export function trackScrollDepth(pathname: string, depthPercent: number): void {
  if (![25, 50, 75, 90, 100].includes(depthPercent)) {
    return
  }

  capture('web:scroll_depth_reached', {
    depth_percent: depthPercent,
    page_path: safePagePath(pathname),
  })
}

function safePropertyValue(value: string | undefined): string | undefined {
  if (!value) {
    return undefined
  }

  const normalized = value.toLowerCase().replace(/[^a-z0-9_:-]+/g, '_')
  return normalized.slice(0, 64)
}

export function trackWebInteraction({
  action,
  component,
  location,
  target,
  outcome,
}: InteractionProperties): void {
  capture('web:interaction', {
    action: safePropertyValue(action),
    component: safePropertyValue(component),
    location: safePropertyValue(location),
    target: safePropertyValue(target),
    outcome: safePropertyValue(outcome),
  })
}

export function trackWebPerformance({
  name,
  value,
  rating,
  navigationType,
}: WebPerformanceMetric): void {
  if (!PERFORMANCE_METRICS.has(name) || !Number.isFinite(value)) {
    return
  }

  const isLayoutShift = name === 'CLS'
  capture('web:performance_measured', {
    metric_name: name.toLowerCase(),
    metric_unit: isLayoutShift ? 'score' : 'milliseconds',
    metric_value: isLayoutShift
      ? Math.round(value * 1_000) / 1_000
      : Math.round(value),
    navigation_type: safePropertyValue(navigationType),
    rating: safePropertyValue(rating),
  })
}

function classifyError(error: unknown): {
  error: Error
  type: string
  category: string
  cause: string
} {
  const original =
    error instanceof Error ? error : new Error('A non-Error value was thrown')
  const type = safePropertyValue(original.name) ?? 'error'
  const lowerMessage = original.message.toLowerCase()

  let category = 'runtime'
  let cause = 'unexpected_state'

  if (
    original.name === 'NetworkError' ||
    lowerMessage.includes('network') ||
    lowerMessage.includes('fetch')
  ) {
    category = 'network'
    cause = 'request_failed'
  } else if (
    original.name === 'ChunkLoadError' ||
    lowerMessage.includes('loading chunk')
  ) {
    category = 'resource'
    cause = 'bundle_load_failed'
  } else if (original.name === 'SecurityError') {
    category = 'browser_security'
    cause = 'browser_policy'
  } else if (original.name === 'TypeError') {
    cause = 'invalid_value'
  }

  const safeError = new Error(`${category}:${cause}`)
  safeError.name = original.name || 'Error'
  if (original.stack) {
    safeError.stack = original.stack
      .replace(/^.*$/m, `${safeError.name}: ${safeError.message}`)
      .replace(/[?#][^\s)]+/g, '')
  }

  return { error: safeError, type, category, cause }
}

export function captureWebsiteException(
  error: unknown,
  context: ExceptionContext,
): void {
  initializeWebsiteAnalytics()
  if (!isInitialized || !isWebsiteAnalyticsEnabled()) {
    return
  }

  const classified = classifyError(error)
  posthog.captureException(classified.error, {
    error_type: classified.type,
    error_category: classified.category,
    error_cause: safePropertyValue(context.cause) ?? classified.cause,
    handled: context.handled,
    surface: safePropertyValue(context.surface),
    platform_surface: 'website',
  })
}

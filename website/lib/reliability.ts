'use client'

import * as Sentry from '@sentry/nextjs'
import { isWebsiteAnalyticsEnabled } from '@/lib/analytics'

type ExceptionContext = {
  surface: string
  handled: boolean
  cause?: string
}

const PRODUCTION_DSN =
  'https://1a279fd4e1ae3b869fa0f5ba78ccf173@o4511816291844096.ingest.us.sentry.io/4511816327954432'

let isInitialized = false

function safeIdentifier(value: string | undefined, fallback: string): string {
  if (!value) {
    return fallback
  }

  const normalized = value.toLowerCase().replace(/[^a-z0-9_.:-]+/g, '_')
  return normalized.slice(0, 64) || fallback
}

function configuredDsn(): string | undefined {
  const dsn =
    process.env.NEXT_PUBLIC_SENTRY_DSN ??
    (process.env.NODE_ENV === 'production' ? PRODUCTION_DSN : undefined)

  if (!dsn) {
    return undefined
  }

  try {
    const url = new URL(dsn)
    return url.protocol === 'https:' &&
      url.hostname === 'o4511816291844096.ingest.us.sentry.io'
      ? dsn
      : undefined
  } catch {
    return undefined
  }
}

function scrubStack(stack: string | undefined): string | undefined {
  return stack
    ?.replace(/[?#][^\s)]+/g, '')
    .replace(/https?:\/\/[^/\s)]+/g, '[origin]')
    .slice(0, 20_000)
}

function safeTransactionName(value: string | undefined): string {
  const basePath = (process.env.NEXT_PUBLIC_BASE_PATH ?? '').replace(/\/+$/, '')
  const withoutBase =
    basePath && value?.startsWith(basePath)
      ? value.slice(basePath.length) || '/'
      : value
  const path = withoutBase?.split(/[?#]/, 1)[0]?.replace(/\/+$/, '') || '/'
  return ['/', '/changelog', '/privacy-policy', '/terms'].includes(path)
    ? path
    : '/not-found'
}

function classifyError(error: unknown): {
  error: Error
  type: string
  category: string
  cause: string
} {
  const original =
    error instanceof Error ? error : new Error('A non-Error value was thrown')
  const type = safeIdentifier(original.name, 'error')
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

  const sanitizedError = new Error(`${category}:${cause}`)
  sanitizedError.name = safeIdentifier(original.name, 'Error')
  sanitizedError.stack = scrubStack(original.stack)
  return { error: sanitizedError, type, category, cause }
}

export function initializeWebsiteReliability(): void {
  if (
    typeof window === 'undefined' ||
    isInitialized ||
    !isWebsiteAnalyticsEnabled()
  ) {
    return
  }

  const dsn = configuredDsn()
  if (!dsn) {
    return
  }

  Sentry.init({
    dsn,
    environment:
      process.env.NODE_ENV === 'production' ? 'production' : 'development',
    release: process.env.NEXT_PUBLIC_SENTRY_RELEASE,
    dist: process.env.NEXT_PUBLIC_SENTRY_DIST,
    sendDefaultPii: false,
    attachStacktrace: true,
    enableLogs: false,
    tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.05 : 1,
    tracePropagationTargets: [],
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
    beforeBreadcrumb(breadcrumb) {
      return {
        ...breadcrumb,
        message: undefined,
        data: undefined,
      }
    },
    beforeSend(event) {
      delete event.user
      delete event.request
      if (event.message) {
        event.message = safeIdentifier(event.message, 'website_error')
      }
      return event
    },
    beforeSendTransaction(event) {
      delete event.user
      delete event.request
      event.transaction = safeTransactionName(event.transaction)
      return event
    },
  })
  isInitialized = true
}

export function applyWebsiteReliabilityPreference(
  preference: 'allowed' | 'denied',
): void {
  if (preference === 'denied') {
    if (isInitialized) {
      void Sentry.close(2_000)
      isInitialized = false
    }
    return
  }

  initializeWebsiteReliability()
}

export function captureWebsiteException(
  error: unknown,
  context: ExceptionContext,
): void {
  initializeWebsiteReliability()
  if (!isInitialized || !isWebsiteAnalyticsEnabled()) {
    return
  }

  const classified = classifyError(error)
  Sentry.withScope((scope) => {
    scope.setTag('platform_surface', 'website')
    scope.setTag('surface', safeIdentifier(context.surface, 'unknown'))
    scope.setTag('handled', context.handled ? 'true' : 'false')
    scope.setTag('error_type', classified.type)
    scope.setTag('error_category', classified.category)
    scope.setTag(
      'error_cause',
      safeIdentifier(context.cause, classified.cause),
    )
    Sentry.captureException(classified.error)
  })
}

export const onRouterTransitionStart = Sentry.captureRouterTransitionStart

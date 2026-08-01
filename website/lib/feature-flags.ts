'use client'

import {
  useActiveFeatureFlags,
  usePostHog,
} from 'posthog-js/react'
import type { JsonType } from 'posthog-js'
import { useMemo } from 'react'

import { isWebsiteAnalyticsEnabled } from '@/lib/analytics'

const LABS_FLAG_PREFIX = 'labs-'
const MAXIMUM_TITLE_LENGTH = 80
const MAXIMUM_DESCRIPTION_LENGTH = 280
const MAXIMUM_IDENTIFIER_LENGTH = 64

type LabsFeaturePayload = {
  title?: string
  description?: string
  system_image?: string
}

type LabsFeatureResult = {
  enabled: boolean
  variant?: string | boolean
  payload: LabsFeaturePayload | null
}

function isLabsFlag(key: string): boolean {
  return key.startsWith(LABS_FLAG_PREFIX)
}

function boundedText(value: unknown, maximumLength: number): string | undefined {
  if (typeof value !== 'string') {
    return undefined
  }

  const trimmed = value.trim()
  return trimmed ? trimmed.slice(0, maximumLength) : undefined
}

function boundedIdentifier(value: unknown): string | undefined {
  if (typeof value !== 'string') {
    return undefined
  }

  const normalized = value.toLowerCase().replace(/[^a-z0-9.-]+/g, '')
  return normalized ? normalized.slice(0, MAXIMUM_IDENTIFIER_LENGTH) : undefined
}

function sanitizeLabsPayload(payload: JsonType): LabsFeaturePayload | null {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return null
  }

  const record = payload as Record<string, unknown>
  const boundedPayload: LabsFeaturePayload = {}
  const title = boundedText(record.title, MAXIMUM_TITLE_LENGTH)
  const description = boundedText(record.description, MAXIMUM_DESCRIPTION_LENGTH)
  const systemImage = boundedIdentifier(record.system_image)

  if (title) boundedPayload.title = title
  if (description) boundedPayload.description = description
  if (systemImage) boundedPayload.system_image = systemImage

  return Object.keys(boundedPayload).length > 0 ? boundedPayload : null
}

function useLabsFeatureResult(key: `labs-${string}`): LabsFeatureResult | undefined {
  const activeFlags = useActiveFeatureFlags()
  const posthog = usePostHog()

  return useMemo(() => {
    if (!isLabsFlag(key) || !isWebsiteAnalyticsEnabled()) {
      return undefined
    }

    // Read the cached result without calling getFeatureFlag(), which would emit
    // a $feature_flag_called event and expose the flag response to analytics.
    void activeFlags
    const result = posthog
      .getAllFeatureFlags()
      .find((featureFlag) => featureFlag.key === key)
    if (!result) {
      return undefined
    }

    return {
      enabled: result.enabled,
      variant: result.variant,
      payload: sanitizeLabsPayload(result.payload),
    }
  }, [activeFlags, key, posthog])
}

export function useLabsFeatureEnabled(key: `labs-${string}`): boolean | undefined {
  const result = useLabsFeatureResult(key)
  return isLabsFlag(key) ? result?.enabled : false
}

export function useLabsFeatureVariant(
  key: `labs-${string}`,
): string | boolean | undefined {
  const result = useLabsFeatureResult(key)
  return isLabsFlag(key) ? result?.variant : false
}

export function useLabsFeaturePayload(key: `labs-${string}`): JsonType {
  const result = useLabsFeatureResult(key)
  return isLabsFlag(key) ? result?.payload : null
}

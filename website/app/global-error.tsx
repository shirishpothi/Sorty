'use client'

import { useEffect } from 'react'
import {
  captureWebsiteException,
  trackWebInteraction,
} from '@/lib/analytics'

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    captureWebsiteException(error, {
      surface: 'global_error_boundary',
      handled: true,
      cause: 'root_render_failed',
    })
  }, [error])

  return (
    <html lang="en" className="dark bg-background">
      <body className="grid min-h-screen place-items-center bg-background px-6 font-sans text-foreground">
        <div className="max-w-md text-center">
          <h1 className="text-3xl font-semibold">Sorty couldn&apos;t load.</h1>
          <p className="mt-4 text-sm text-muted-foreground">
            Try loading the site again.
          </p>
          <button
            type="button"
            onClick={() => {
              trackWebInteraction({
                action: 'error_retry_clicked',
                component: 'error_boundary',
                location: 'global_error',
                outcome: 'retrying',
              })
              reset()
            }}
            className="mt-6 rounded-full bg-primary px-6 py-3 text-sm font-medium text-primary-foreground"
          >
            Try again
          </button>
        </div>
      </body>
    </html>
  )
}

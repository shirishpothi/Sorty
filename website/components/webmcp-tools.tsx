'use client'

import { useEffect } from 'react'

type ModelContext = {
  registerTool(
    tool: {
      name: string
      description: string
      inputSchema: Record<string, unknown>
      execute: (input: Record<string, never>) => Promise<string>
    },
    options?: { signal?: AbortSignal },
  ): Promise<void>
}

function getModelContext() {
  return (document as Document & { modelContext?: ModelContext }).modelContext
}

export function WebMCPTools() {
  useEffect(() => {
    const modelContext = getModelContext()

    if (!modelContext) {
      return
    }

    const controller = new AbortController()

    void modelContext
      .registerTool(
        {
          name: 'download_sorty_for_macos',
          description:
            'Downloads the latest Sorty ZIP for macOS and shows the installation instructions.',
          inputSchema: {
            type: 'object',
            properties: {},
            additionalProperties: false,
          },
          execute: async () => {
            const downloadButton = document.querySelector<HTMLAnchorElement>(
              '[data-webmcp-download]',
            )

            if (!downloadButton) {
              throw new Error('The Sorty download control is unavailable.')
            }

            downloadButton.click()
            return 'Started the Sorty download and displayed installation instructions.'
          },
        },
        { signal: controller.signal },
      )
      .catch(() => {
        // WebMCP is an experimental progressive enhancement. Registration can
        // fail when Chrome's origin trial or local development flag is absent.
      })

    return () => controller.abort()
  }, [])

  return null
}

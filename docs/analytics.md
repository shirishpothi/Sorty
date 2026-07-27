# Sorty Analytics

Sorty uses one PostHog project for the public website and Mac app. The implementation is deliberately broad enough to answer product and reliability questions, but it keeps the event namespace small and excludes user content.

## Consent and privacy

The Mac app is opt-in. `AnalyticsManager` does not initialize PostHog until the user allows anonymous analytics after onboarding. Denial is persisted locally but never reported. Revoking consent, enabling **Block Internet Connections**, or deleting Sorty usage data closes the SDK and clears its local queue and anonymous identifier.

The website uses anonymous, cookieless aggregate measurement by default. The footer provides a persistent opt-out, and Global Privacy Control or Do Not Track disables capture automatically. It uses no person profiles, session replay, heatmaps, surveys, automatic click capture, full referrers, query strings, console logs, or form text.

Both clients instruct PostHog to discard IP addresses. Neither client may send file or folder names, paths, file contents, prompts, custom instructions, AI responses, API keys, user-entered text, or raw handled-error messages.

## Event taxonomy

| Event | Surface | Purpose |
|---|---|---|
| `$pageview` | Website | Visits to each public route, using a stable page name and sanitized path |
| `web:section_viewed` | Website | Meaningfully visible named homepage sections |
| `web:interaction` | Website | Important links, downloads, navigation, FAQ toggles, and bounded outcomes |
| `app:session_started` | Mac | An opted-in app analytics session |
| `app:screen_viewed` | Mac | Main screens and individual Settings sections |
| `app:feature_used` | Mac | Feature and sub-feature actions with stable outcomes |
| `app:workflow_progressed` | Mac | Organize, apply, regenerate, undo, duplicate-scan, and cleanup stages |
| `app:important_button_clicked` | Mac | A small allowlist of decision-critical buttons |
| `$exception` | Both | Sanitized handled errors and opted-in Mac crashes |

Do not create a new event for every button or state. Prefer an existing canonical event with low-cardinality `feature`, `subfeature`, `action`, `stage`, `outcome`, `screen`, or `button` properties. Counts and durations must use `AnalyticsManager.countBucket` and `durationBucket`; paths, identifiers, model names, and free text are not acceptable dimensions.

## Implementation map

- Mac SDK setup, consent, allowlists, bucketing, and error classification: `Sources/SortyLib/Analytics/AnalyticsManager.swift`
- Mac one-time permission UI: `Sources/SortyLib/Analytics/AnalyticsConsentView.swift`
- Website initialization, sanitization, route events, and error classification: `website/lib/analytics.ts`
- Website route/section/action listeners and preferences UI: `website/components/analytics-provider.tsx`
- Website client bootstrap: `website/instrumentation-client.ts`
- Completed PostHog project, dashboard, and release handoff: `posthog-setup-report.md`

## Configuration and releases

The website reads `NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN` and `NEXT_PUBLIC_POSTHOG_HOST`. GitHub repository variables provide both values to the Pages workflow. The Mac app contains the public project token and ingestion host, with `SORTY_POSTHOG_PROJECT_TOKEN` and `SORTY_POSTHOG_HOST` overrides for development builds.

`POSTHOG_CLI_API_KEY` is a GitHub Actions secret and `POSTHOG_CLI_PROJECT_ID` is a repository variable. The website workflow injects source-map identifiers, uploads source maps, and deletes maps before publishing the static artifact. Release and nightly Mac workflows build `dwarf-with-dsym` symbols and upload dSYMs without source files.

PostHog project settings keep automatic web capture, recordings, console capture, performance capture, heatmaps, surveys, and dead-click tracking disabled. IP anonymization and stateless cookieless mode are enabled. Exception capture is enabled project-side so the explicitly opted-in native crash reporter can submit on the next launch; browser exceptions remain locally controlled and manually sanitized.

## Adding instrumentation

1. Confirm the question cannot already be answered with an existing event and property.
2. Add only bounded, documented property values. Never pass a URL, file object, `Error.localizedDescription`, prompt, provider response, or user-entered string.
3. Capture intent at the important UI control and capture the outcome at the manager or workflow boundary.
4. Send expected cancellations as workflow outcomes, not exceptions.
5. Update the event catalog and this guide if the event namespace or privacy boundary changes.
6. Verify Swift compilation, website lint/type-check/build, and the relevant PostHog dashboard query.

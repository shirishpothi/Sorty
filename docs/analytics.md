# Sorty Analytics

Sorty uses PostHog for the same lightweight product and reliability telemetry that is normal for most apps: understanding which screens and features are useful, where workflows fail, and whether releases are reliable. It uses one project for the public website and Mac app, keeps the event namespace small, and never uses analytics to inspect user content.

## Consent and privacy

The Mac app is opt-in. `AnalyticsManager` does not initialize PostHog until the user allows anonymous analytics after onboarding. Denial is persisted locally but never reported. Revoking consent, enabling **Block Internet Connections**, or deleting Sorty usage data closes the SDK and clears its local queue and anonymous identifier.

The website uses anonymous, cookieless aggregate measurement by default. The footer provides a persistent opt-out, and Global Privacy Control or Do Not Track disables capture automatically. A random identifier lives in session storage only until the browser tab closes so page views can be grouped into one visit; it uses no person profiles, session replay, heatmaps, surveys, automatic click capture, full referrers, query strings, console logs, or form text.

Both clients instruct PostHog to discard IP addresses and never create a person profile. Analytics is anonymous: the Mac app uses a random installation identifier only to group its own events, and neither client sends a name, email address, account identifier, advertising identifier, or other information linked to a person. Neither client may send file or folder names, paths, file contents, prompts, custom instructions, AI responses, API keys, user-entered text, or raw handled-error messages. File contents are never transmitted to PostHog.

This boundary is separate from AI-provider requests. If a user explicitly enables Deep Scan with a cloud provider, content may be sent directly to that selected provider to produce an organization plan; it is never routed through Sorty or included in PostHog analytics.

## Event taxonomy

| Event | Surface | Purpose |
|---|---|---|
| `$pageview` | Website | Visits to each public route, using a stable page name and sanitized path |
| `$pageleave` | Website | Consent-gated page-exit timing for more accurate session duration |
| `web:section_viewed` | Website | Meaningfully visible named homepage sections |
| `web:scroll_depth_reached` | Website | Bounded 25%, 50%, 75%, 90%, and 100% scroll milestones for each sanitized page |
| `web:not_found_viewed` | Website | Explicit 404 visits without retaining the unknown requested path |
| `web:interaction` | Website | Important links, downloads, fixed-command copy outcomes, modal exits, navigation, stable FAQ opens and closes, menu toggles, preference controls, legal-section choices, and bounded recovery actions |
| `$web_vitals` | Website | Consent-gated PostHog Web Vitals for LCP, INP, and CLS |
| `app:session_started` | Mac | An opted-in app analytics session |
| `app:screen_viewed` | Mac | Main screens and individual Settings sections |
| `app:feature_used` | Mac | Feature and sub-feature actions, including settings changes and bucketed persona inventory, with stable outcomes |
| `app:workflow_progressed` | Mac | Organize, apply, regenerate, undo, duplicate-scan, and cleanup stages |
| `app:important_button_clicked` | Mac | A small allowlist of decision-critical buttons |
| `$exception` | Both | Sanitized handled errors and opted-in Mac crashes |

Do not create a new event for every button or state. Prefer an existing canonical event with low-cardinality `feature`, `subfeature`, `action`, `stage`, `outcome`, `screen`, `control`, `selection_kind`, or `button` properties. Counts and durations must use `AnalyticsManager.countBucket` and `durationBucket`; paths, identifiers, persona names or contents, model names, and free text are not acceptable dimensions.

## Implementation map

- Mac SDK setup, consent, allowlists, bucketing, and error classification: `Sources/SortyLib/Analytics/AnalyticsManager.swift`
- Mac settings toggles, notification previews, automation controls, and persona inventory: `Sources/SortyLib/Views/Settings/SettingsComponents.swift`, `Sources/SortyLib/Views/Settings/AutomationSettingsView.swift`, and `Sources/SortyLib/Views/PersonaPickerView.swift`
- Mac one-time permission UI: `Sources/SortyLib/Analytics/AnalyticsConsentView.swift`
- Website initialization, sanitization, route events, and error classification: `website/lib/analytics.ts`
- Website route/section/action listeners and preferences UI: `website/components/analytics-provider.tsx`
- Website client bootstrap: `website/instrumentation-client.ts`
- Completed PostHog project, dashboard, and release handoff: `posthog-setup-report.md`

## Configuration and releases

The website reads `NEXT_PUBLIC_POSTHOG_PROJECT_TOKEN` and `NEXT_PUBLIC_POSTHOG_HOST`. GitHub repository variables provide both values to the Pages workflow. The Mac app contains the public project token and ingestion host, with `SORTY_POSTHOG_PROJECT_TOKEN` and `SORTY_POSTHOG_HOST` overrides for development builds.

`POSTHOG_CLI_API_KEY` is a GitHub Actions secret and `POSTHOG_CLI_PROJECT_ID` is a repository variable. The website workflow injects source-map identifiers, uploads source maps, and deletes maps before publishing the static artifact. Release and nightly Mac workflows build `dwarf-with-dsym` symbols and upload dSYMs without source files.

PostHog project settings keep automatic click capture, recordings, console capture, performance attribution, heatmaps, surveys, and dead-click tracking disabled. The website uses consent-gated `$pageleave` events for session duration and PostHog's lightweight `$web_vitals` capture for the three Core Web Vitals—LCP, INP, and CLS—through its event and property allowlists. Bounce rate remains conservative because PostHog requires automatic DOM interaction capture for its complete bounce calculation, and Sorty deliberately does not collect it. IP anonymization and stateless cookieless mode are enabled. Exception capture is enabled project-side so the explicitly opted-in native crash reporter can submit on the next launch; browser exceptions remain locally controlled and manually sanitized.

The static GitHub Pages export cannot host a request-forwarding reverse proxy. PostHog requests continue to use `NEXT_PUBLIC_POSTHOG_HOST` directly until Sorty has a custom domain where a managed PostHog proxy can be provisioned with a neutral subdomain and DNS CNAME.

## Adding instrumentation

1. Confirm the question cannot already be answered with an existing event and property.
2. Add only bounded, documented property values. Never pass a URL, file object, `Error.localizedDescription`, prompt, provider response, or user-entered string.
3. Capture intent at the important UI control and capture the outcome at the manager or workflow boundary.
4. Send expected cancellations as workflow outcomes, not exceptions.
5. Update the event catalog and this guide if the event namespace or privacy boundary changes.
6. Verify Swift compilation, website lint/type-check/build, and the relevant PostHog dashboard query.

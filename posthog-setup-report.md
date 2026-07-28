# Sorty PostHog Setup Report

Completed July 28, 2026.

## Outcome

Sorty now uses one PostHog project for privacy-scoped website analytics and explicitly opted-in Mac app analytics. The implementation covers route and screen visits, meaningful feature and sub-feature use, decision-critical buttons, core workflow progress, sanitized handled errors, and opted-in native crashes without sending user content.

- PostHog project: `Sorty Product Analytics` (`405329`, US Cloud)
- Dashboard: [Analytics basics (wizard)](https://us.posthog.com/project/405329/dashboard/1912544)
- Website SDK: `posthog-js` `1.407.3`
- Mac SDK: `posthog-ios` `3.68.2`
- Release tooling: `@posthog/cli` `0.9.1`

## Consent and privacy boundary

The Mac app does not initialize PostHog while consent is undecided or denied. It asks once after onboarding, persists denial locally without reporting it, and allows the choice to be changed in Advanced Settings. Revoking consent, enabling **Block Internet Connections**, or deleting usage data closes the SDK and clears its queue and anonymous identifier. Tests, UI tests, and harness processes suppress analytics.

The website collects anonymous cookieless aggregate analytics by default. A persistent footer control allows visitors to opt out or back in, and Global Privacy Control or Do Not Track disables capture automatically.

Both clients disable person profiles and IP collection. Session replay, heatmaps, surveys, automatic click capture, console capture, performance attribution, and browser automatic exception capture are disabled. The website allows only PostHog's lightweight LCP, INP, and CLS `$web_vitals` measurements. Event and property allowlists reject unexpected telemetry, and sanitizers remove URLs with query strings, local paths, email addresses, raw handled-error text, and other high-cardinality data. File or folder names, paths, file contents, prompts, custom instructions, AI responses, API keys, form text, and user-entered text are prohibited.

## Event catalog

| Event | Scope | Key bounded properties |
|---|---|---|
| `$pageview` | Every public website route | `page_name`, `page_path`, `traffic_source` |
| `$pageleave` | Website exits while analytics is enabled | `$prev_pageview_duration`, `$prev_pageview_pathname` |
| `web:section_viewed` | Meaningfully visible homepage sections | `section`, `page_path` |
| `web:interaction` | Navigation, downloads, FAQ, source/support links, and analytics preferences | `action`, `component`, `location`, `target`, `outcome` |
| `app:session_started` | Each opted-in Mac analytics session | `launch_source` |
| `app:screen_viewed` | Main app screens and Settings sections | `screen`, `section`, `source` |
| `app:feature_used` | Features, settings controls, and bucketed persona inventory with outcomes | `feature`, `subfeature`, `action`, `outcome`, `control`, `selection_kind`, `count_bucket` |
| `app:workflow_progressed` | Organize, apply, regenerate, undo, duplicate scan, and cleanup stages | `workflow`, `stage`, `outcome`, `count_bucket`, `duration_bucket` |
| `app:important_button_clicked` | Small allowlist of decision-critical controls | `button`, `screen`, `feature` |
| `$exception` | Sanitized website errors and opted-in Mac errors/crashes | `platform_surface`, `feature`, `operation`, `error_type`, `error_category`, `error_cause`, `severity`, `recoverable` |

All events include `platform_surface` and `$geoip_disable`. The website additionally marks `analytics_scope=anonymous_aggregate`. Counts and durations use coarse buckets instead of raw values where cardinality would add noise.

## Product coverage

Website instrumentation covers `/`, `/changelog`, `/privacy-policy`, `/terms`, unknown routes, the main homepage sections, navigation and mobile-menu actions, downloads and download outcomes, fixed-command copy success or failure, download-notice exits, pricing/support/source links, FAQ toggles, analytics-preference opens, legal-page table-of-contents navigation, changelog release-history exits, 404 recovery, and sanitized handled and unhandled errors.

Mac instrumentation covers app sessions; main screens; individual Settings sections; shared settings toggles and notification previews; background automation controls; bucketed custom-persona inventory and built-in-versus-custom selection; directory selection and organization mode; watched-folder add, remove, toggle, and trigger actions; organize start, empty result, plan ready, cancellation, and failure; apply start, success, partial completion, and failure; regeneration variants; undo; duplicate scan and cleanup; and the most important preview and cleanup decision buttons. Persona names, IDs, descriptions, prompts, and instructions remain excluded.

## Dashboard

The pinned `Analytics basics (wizard)` dashboard contains exactly five low-noise insights:

1. **Website page visits by route** — daily `$pageview` volume split by `page_name`.
2. **Mac screen visits** — daily opted-in `app:screen_viewed` volume split by `screen`.
3. **Mac feature adoption** — daily opted-in `app:feature_used` volume split by `feature`.
4. **Organize workflow conversion** — `started` → `plan_ready` → `applied` within 24 hours.
5. **Errors and crashes by surface** — daily `$exception` volume split by `platform_surface`.

The insight short IDs are `zWy5neXL`, `344OWGEe`, `dawp7NuK`, `o0NmgL6f`, and `ev4Nr8nD`. Queries were validated successfully; results are currently empty because production traffic has not yet reached the new instrumentation.

## Project configuration

The project is set to the `Asia/Singapore` timezone with IP anonymization and stateless cookieless mode enabled. Automatic click capture, recordings, console capture, performance attribution, heatmaps, surveys, and dead-click tracking are disabled; consent-gated `$pageleave` timing and lightweight LCP, INP, and CLS `$web_vitals` capture are enabled. Bounce rate remains conservative without `$autocapture`, while session duration can use `$pageleave`. Project-side exception capture remains enabled only so the consent-gated native SDK can submit crash reports on the next launch; browser exceptions are manual and sanitized.

The website is a static GitHub Pages export, so it cannot host PostHog request-forwarding routes. A reverse proxy remains blocked on obtaining a custom domain and configuring PostHog's managed proxy with its generated DNS CNAME; `NEXT_PUBLIC_POSTHOG_HOST` should then be updated to that proxy origin.

The public website token and ingestion host are GitHub repository variables. The personal PostHog key is stored only as the `POSTHOG_CLI_API_KEY` GitHub Actions secret, and the project ID is a repository variable.

## Release and operations handoff

- `website/lib/analytics.ts` owns website initialization, allowlists, sanitization, page metadata, and error classification.
- `website/components/analytics-provider.tsx` owns route, section, important-interaction, global-error, and preference handling.
- `Sources/SortyLib/Analytics/AnalyticsManager.swift` owns Mac consent gating, SDK lifecycle, allowlists, bucketing, error classification, and event helpers.
- `Sources/SortyLib/Analytics/AnalyticsConsentView.swift` owns the one-time Mac permission request.
- `docs/analytics.md` is the permanent instrumentation and privacy guide.

The website Pages workflow injects PostHog source-map identifiers, uploads maps, and deletes them before artifact publication. Release and nightly Mac workflows build dSYMs and upload them without source files. New events should be added only when an existing canonical event plus a bounded property cannot answer the product question.

## Verification

- PostHog dashboard and all five saved insights were created and queried through the PostHog CLI.
- The website passed focused ESLint, TypeScript checking, and a production static export with analytics variables configured.
- `SortyLib` passed a clean Swift build using an isolated SwiftPM scratch directory.
- Final website, app-target, workflow, deployment, and live-surface verification are recorded in the delivery commit and CI runs.

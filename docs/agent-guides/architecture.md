# Architecture & Patterns

## Data Flow
```
User Action → View → ViewModel/Manager → FolderOrganizer → AIClient → Response
                                              ↓
                                      OrganizationPlan → Preview → Apply
```

## Key Components

| Layer | Location | Purpose |
|-------|----------|---------|
| **SortyApp** | `Sources/SortyApp/` | SwiftUI lifecycle, `AppCoordinator` for background tasks |
| **SortyLib** | `Sources/SortyLib/` | All business logic shared by the app, Finder extension, and widgets |
| **SortyFinderSync** | `Sources/SortyFinderSync/` | Finder Sync extension |

### SortyLib Directories

| Directory | Contains |
|-----------|----------|
| `AI/` | AI clients, prompt builders, response parsers |
| `Models/` | Data models (`AIConfig`, `FileItem`, `OrganizationPlan`, `FeatureFlags`) |
| `Views/` | All SwiftUI views |
| `ViewModels/` | View models |
| `Managers/` | `@MainActor ObservableObject` state managers |
| `Organizer/` | Core workflow orchestration (`FolderOrganizer` state machine) |
| `Learnings/` | ML-based preference learning (`LearningsManager`, `LearningsAnalyzer`, `RuleInducer`) |
| `Utilities/` | Keychain, logging, deeplinks, security |
| `DesignSystem/` | Shared design tokens and reusable UI components |
| `FileSystem/` | File system access and scanning |
| `FinderExtension/` | Finder extension IPC helpers |
| `Services/` | App services |

## State Management
All managers are `@MainActor ObservableObject` classes created as `@StateObject` in `SortyApp.swift` and injected via `.environmentObject()` to the view hierarchy.

## AI Client Pattern
New AI providers must:
1. Implement `AIClientProtocol` (in `AI/`)
2. Add a case to `AIProvider` enum
3. Register in `AIClientFactory`

## FolderOrganizer State Machine
`idle → scanning → organizing → ready → applying → completed`

## Deeplinks
URL scheme `sorty://` — see `DeeplinkHandler` for routes:
- `sorty://organize?path=/path&persona=Developer&autostart=true`
- `sorty://learnings?action=honing`
- `sorty://settings`

## Finder Extension
Uses App Groups (`group.com.sorty.app`) for IPC. Behind the `finderIntegrationEnabled` feature flag.
Quick Action and Finder Sync repair flows are exposed in-app via Finder Integration settings.
The Finder Sync `.appex` registration repair path is `ExtensionCommunication.repairFinderSyncExtensionRegistration` and should be preferred over external terminal instructions.

### Background Agent
- `LoginItemManager` manages both the main app login item (via `SMAppService.mainApp`) and a background LaunchAgent (`com.sorty.app.background-agent.plist`).
- On sync, it auto-migrates off the legacy agent plist (`com.sorty.app.plist`) that reused the app's service label.
- `backgroundAgentConfigurationIssues(label:bundleProgram:mainAppServiceLabel:)` validates agent configuration at build/test time.

### Finder Sync Menu Icon Rendering (CRITICAL)
- **`isTemplate` does NOT work** in Finder Sync extensions. Finder ignores it for extension-provided menu item images. Do not use `isTemplate = true` for dark/light mode adaptation — this has caused repeated regressions.
- The correct approach (in `finderWatchImage()`): detect appearance via `prefersDarkAppearance()`, render the SF Symbol into a new `NSImage` via `lockFocus` with **proportional scaling and centering** (not force-drawn into the full rect — non-square symbols like "eye" get distorted), then tint with `.sourceAtop` (`drawColor.set()` + `NSRect.fill(using: .sourceAtop)`), and set `isTemplate = false`.
- See `docs/agent-guides/finder-integration.md` → "Menu Icon Rendering" for the full pattern and list of approaches that must NOT be used.
- Asset catalog images (`NSImage(named:)`) are inaccessible from the extension bundle — use SF Symbols rendered at runtime.
- A stale Finder Sync binary can stay active even when workspace code is updated; after deploy, `pkill -f SortyFinderSync`, re-enable `com.sorty.app.SortyFinderSync`, and restart Finder.

## Learnings System
User preference learning stored in `LearningsProfile`. Secured with biometric auth via `SecurityManager`.

## UI Presentation Pitfalls

### Liquid Glass Surfaces
- Use `Sources/SortyLib/Views/AboutView.swift` as the visual reference for a correct liquid glass surface.
- If a view needs to look like the About window, do not assume SwiftUI `.popover` or `.sheet` chrome will preserve that look. The presenter shell can make system glass read like a dark AppKit panel even when `glassEffect` is applied correctly.
- `ModelSelectionPopover` in Settings and Automation Settings intentionally does **not** use the native popover presenter. It is anchored with `modelSelectorTriggerBounds()` and rendered via `modelSelectionOverlay(...)` from `Sources/SortyLib/Views/ModelSelector.swift`.
- When updating liquid glass UI, separate the **glass surface** from the **presentation shell**. If the shell is visually wrong, replace the presenter first instead of stacking more material/glass modifiers.
- For any UI described as "system liquid glass" (especially dropdowns/popovers), use system presentation + system glass only. Do not simulate with custom material.
- **Do not use** `.regularMaterial`, `.thinMaterial`, `.ultraThinMaterial`, or custom gradient/blur backgrounds to approximate glass in these surfaces.
- If `glassEffect` is unavailable for the deployment target, prefer default system chrome (no custom material fallback) instead of trying to mimic glass.
- Reuse shared liquid-glass helpers and keep them system-only; do not add custom material fallback branches.

### Button Styles
All interactive buttons must use Sorty's pill-style button system defined in `Sources/SortyLib/Utilities/ButtonStyles.swift`. Do **not** use `.buttonStyle(.bordered)` or plain system button styles for action buttons.

| Style | Usage | Example |
|-------|-------|---------|
| `.tintedPill(.red, size: .small)` | Destructive/cancel actions | Cancel, Delete |
| `.tintedPill(.indigo, size: .small)` | Model/AI actions | Model picker |
| `.onboardingPill(size: .small)` | Primary/positive actions | Regenerate, Choose Folder |
| `.sortyPrimary` | Main CTA (e.g., Apply) | Apply button |
| `.sortySecondary(size: .small, color:)` | Secondary actions | Reset |

Always pair buttons with `HapticFeedbackManager.shared.tap()` on press, and use `HStack(spacing: 4)` with an SF Symbol icon + `.caption.bold()` text for compact pill button labels.

## Common Tasks
- **Add AI provider**: Create client in `AI/`, implement `AIClientProtocol`, add to `AIProvider` enum + `AIClientFactory`
- **Add settings option**: Update `AIConfig`, `SettingsViewModel`, `SettingsView`
- **Add new view**: Create in `Views/`, add case to `AppState.AppView`, add navigation in `ContentView`
- **Test deeplinks**: Set `XCUITEST_DEEPLINK` environment variable before launch

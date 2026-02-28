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
| **SortyLib** | `Sources/SortyLib/` | All business logic, shared with CLI and Finder extension |
| **LearningsCLI** | `Sources/LearningsCLI/` | `learnings` command-line tool for profile management |
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

### Finder Icon Troubleshooting
- `Watch with Sorty` icon color variants are file-based assets in `Resources/Assets.xcassets/WatchIcon.imageset/`.
- Light mode should resolve to `eye_black.png`; dark mode should resolve to `eye_white.png`.
- If icon behavior appears unchanged after code edits, first verify the extension target itself builds: `xcodebuild -project Sorty.xcodeproj -target SortyFinderSync -configuration Debug -destination 'platform=macOS' build`.
- A stale Finder Sync binary can stay active even when workspace code is updated; after deploy, re-enable `com.sorty.app.SortyFinderSync` and restart Finder to force reload.

## Learnings System
User preference learning stored in `LearningsProfile`. Secured with biometric auth via `SecurityManager`.

## Common Tasks
- **Add AI provider**: Create client in `AI/`, implement `AIClientProtocol`, add to `AIProvider` enum + `AIClientFactory`
- **Add settings option**: Update `AIConfig`, `SettingsViewModel`, `SettingsView`
- **Add new view**: Create in `Views/`, add case to `AppState.AppView`, add navigation in `ContentView`
- **Test deeplinks**: Set `XCUITEST_DEEPLINK` environment variable before launch

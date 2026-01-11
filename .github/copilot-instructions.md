# Sorty - AI Coding Agent Instructions

## Architecture Overview

Sorty is a **native macOS SwiftUI app** (macOS 15.1+, Swift 6) that uses AI to organize folders. The architecture follows **MVVM with service layers** and state injection via `@EnvironmentObject`.

### Core Components

| Layer | Location | Purpose |
|-------|----------|---------|
| **App Entry** | `Sources/SortyApp/` | SwiftUI lifecycle, `AppCoordinator` for background tasks |
| **Library** | `Sources/SortyLib/` | All business logic, shared with CLI and Finder extension |
| **CLI** | `Sources/LearningsCLI/` | `learnings` command-line tool for profile management |

### Key Data Flow
```
User Action → View → ViewModel/Manager → FolderOrganizer → AIClient → Response
                                              ↓
                                      OrganizationPlan → Preview → Apply
```

- **`FolderOrganizer`** ([FolderOrganizer.swift](Sources/SortyLib/Organizer/FolderOrganizer.swift)) - Main orchestrator with state machine (`idle → scanning → organizing → ready → applying → completed`)
- **`AppState`** ([AppCommands.swift](Sources/SortyLib/Views/AppCommands.swift#L229)) - Global navigation and UI state
- **AI Clients** use `AIClientProtocol` with factory pattern in `AIClientFactory`

## Build & Test Commands

```bash
make build      # Full build with tests
make run        # Build and launch app
make test       # Unit tests only (swift test)
make test-ui    # UI tests via Xcode
make now        # Fast debug build, skip tests, launch immediately
make quick      # Compile only, skip tests
make cli        # Build the 'learnings' CLI tool
```

**Important**: Tests run by default on `make build`. Use `SKIP_TESTS=true` to bypass.

## Project Conventions

### State Management Pattern
All managers are `@MainActor` `ObservableObject` classes injected via `@EnvironmentObject` at app root:
```swift
// In SortyApp.swift - managers created once, injected to all views
@StateObject private var organizer = FolderOrganizer()
@StateObject private var learningsManager = LearningsManager()
// ...
.environmentObject(organizer)
.environmentObject(learningsManager)
```

### AI Client Pattern
New AI providers must implement `AIClientProtocol` and register in `AIClientFactory`:
```swift
public protocol AIClientProtocol: Sendable {
    func analyze(files: [FileItem], customInstructions: String?, 
                 personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan
    func generateText(prompt: String, systemPrompt: String?) async throws -> String
    @MainActor var streamingDelegate: StreamingDelegate? { get set }
}
```

### Testing Patterns
- **Unit tests**: Use mock AI clients (see `MockAIClient` in [FileOrganizerTests.swift](Tests/SortyTests/FileOrganizerTests.swift))
- **UI tests**: Navigate via sidebar identifiers (e.g., `"OrganizeSidebarItem"`, `"SettingsSidebarItem"`)
- **Temporary directories**: Always create in `setUp()` and clean in `tearDown()`
```swift
tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
```

### View Accessibility
All sidebar items and key controls have `accessibilityIdentifier` for UI testing:
```swift
.accessibilityIdentifier("ReasoningToggle")
.accessibilityIdentifier("SettingsSidebarItem")
```

## Key Integration Points

### Deeplinks
URL scheme `sorty://` handles app automation:
- `sorty://organize?path=/path&persona=Developer&autostart=true`
- `sorty://learnings?action=honing`
- `sorty://settings`

See `DeeplinkHandler` for full route list.

### Finder Extension
Uses App Groups (`group.com.sorty.app`) for IPC. Extension code in `Sources/SortyLib/FinderExtension/`. Requires separate build target `SortyExtension`.

### Learnings System
User preference learning stored in `LearningsProfile`. Key components:
- `LearningsManager` - Main coordinator with consent/security
- `LearningsAnalyzer` + `RuleInducer` - Pattern extraction
- Secured with biometric auth via `SecurityManager`

## File Organization

| Directory | Contains |
|-----------|----------|
| `Sources/SortyLib/AI/` | All AI clients, prompt builders, response parsers |
| `Sources/SortyLib/Models/` | Data models (`AIConfig`, `FileItem`, `OrganizationPlan`, etc.) |
| `Sources/SortyLib/Views/` | All SwiftUI views |
| `Sources/SortyLib/Organizer/` | Core workflow orchestration |
| `Sources/SortyLib/Learnings/` | ML-based preference learning |
| `Sources/SortyLib/Utilities/` | Keychain, logging, deeplinks, security |
| `scripts/` | Build, release, notarization scripts |

## Common Tasks

**Add a new AI provider**: Create client in `AI/`, implement `AIClientProtocol`, add case to `AIProvider` enum and `AIClientFactory`.

**Add a new settings option**: Update `AIConfig` model, `SettingsViewModel`, and `SettingsView`.

**Add a new view**: Create in `Views/`, add case to `AppState.AppView`, add navigation in `ContentView`.

**Test deeplinks in UI tests**: Set `XCUITEST_DEEPLINK` environment variable before launch.

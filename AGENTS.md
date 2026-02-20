# Sorty

AI-powered macOS folder organizer — native SwiftUI app (macOS 15+, Swift 6, SPM + Xcode).

## Commands
- `make dev` — fast debug build (no tests)
- `make build` — full build with tests
- `make test` — unit tests (`swift test --disable-sandbox`)
- `swift test --filter SortyTests.TestClass/testMethod` — single test
- `make now` — debug build + launch

## Architecture
MVVM with service layers. State injected via `@EnvironmentObject` from `SortyApp`.
- **SortyLib** (`Sources/SortyLib/`): All business logic — AI/, Models/, Views/, Organizer/, Learnings/, Utilities/
- **SortyApp** (`Sources/SortyApp/`): App entry point and lifecycle
- **LearningsCLI** (`Sources/LearningsCLI/`): `learnings` CLI tool
- Flow: `View → Manager → FolderOrganizer → AIClient → OrganizationPlan → Apply`

## Code Style
- Managers: `@MainActor ObservableObject`, injected via `@EnvironmentObject`
- AI providers: implement `AIClientProtocol`, register in `AIClientFactory`
- Views: always set `accessibilityIdentifier` on interactive controls
- Tests: use `MockAIClient`; create temp dirs in `setUp()`, clean in `tearDown()`
- Feature flags: `defaults write com.sorty.app <key> -bool true` (see [docs/agent-guides/feature-flags.md](docs/agent-guides/feature-flags.md))
- Release: push `v*` tag to trigger CI build (e.g., 'git push origin v1.0.5')

## Finder Integration Notes
- Quick Action and Finder Sync extension repair should be handled from in-app UI controls.
- Use Settings → Finder Integration → `Install`/`Reinstall` Quick Action and `Repair Finder Sync` before suggesting external commands.
- Finder Sync `.appex` registration and stale-registration cleanup are implemented in `ExtensionCommunication.repairFinderSyncExtensionRegistration`.
- If Finder still shows stale menu/icon state, open Extensions settings from the app and re-enable Sorty there.

## Detailed Guides
- [Architecture & Patterns](docs/agent-guides/architecture.md)
- [Feature Flags](docs/agent-guides/feature-flags.md)

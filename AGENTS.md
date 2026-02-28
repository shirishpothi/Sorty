# Sorty

AI-powered macOS folder organizer — native SwiftUI app (macOS 15+, Swift 6, SPM + Xcode).

## Commands
- `make dev` — fast debug build (no tests)
- `make build` — full build with tests
- `make test` — unit tests (`swift test --disable-sandbox`)
- `swift test --filter SortyTests.TestClass/testMethod` — single test
- `make now` — debug build + launch
- **Xcode** — open `Sorty.xcodeproj`, select the **Sorty** scheme, and Build (Cmd+B) / Run (Cmd+R)

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

## Xcode Project Notes
- The Xcode project (`Sorty.xcodeproj`) uses a **local SPM package** reference to `Package.swift`. SortyLib is built as a separate module by SPM, then linked into the native Sorty app target.
- The Sorty app target only compiles the 3 files in `Sources/SortyApp/`. All SortyLib code comes from the package — **no file drift**: new `.swift` files in `Sources/SortyLib/` are picked up automatically.
- Sparkle is resolved transitively through the local package's dependency graph.
- The `#if canImport(SortyLib)` guards in `Sources/SortyApp/` enable both the SPM executable build (where SortyLib is a module) and the Xcode build.
- **Unit tests**: The native `SortyTests` target links `SortyLib` from the package. Tests use `@testable import SortyLib`. Runnable from Xcode's Test navigator or via `make test` (SPM).
- **UI tests**: The native `SortyUITests` target runs against the Sorty app.
- **FinderSync extension**: Built as a separate native target (`SortyFinderSync`), embedded in the app bundle.

## Finder Integration Notes
- Finder Sync `.appex` registration and stale-registration cleanup are implemented in `ExtensionCommunication.repairFinderSyncExtensionRegistration`.
- Finder watch icon assets are sourced from `Resources/Assets.xcassets/WatchIcon.imageset/`:
- Light mode uses `eye_black.png`.
- Dark mode uses `eye_white.png`.
- If Finder icon changes do not appear, verify the extension target builds directly: `xcodebuild -project Sorty.xcodeproj -target SortyFinderSync -configuration Debug -destination 'platform=macOS' build`.
- Finder can keep a previously installed extension binary; after rebuilding/deploying, reload by re-enabling `com.sorty.app.SortyFinderSync` and restarting Finder.


## Detailed Guides
- [Architecture & Patterns](docs/agent-guides/architecture.md)
- [Feature Flags](docs/agent-guides/feature-flags.md)
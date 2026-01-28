# Sorty - AI Coding Agent Instructions

## Build & Test Commands
```bash
make build          # Full build with tests
make test           # Unit tests only (swift test)
swift test --filter SortyTests.TestClassName   # Run single test class
swift test --filter SortyTests.TestClassName/testMethodName  # Run single test
make test-ui        # UI tests via Xcode
make quick          # Compile only, skip tests
make now            # Fast debug build + launch (skips tests)
make cli            # Build 'learnings' CLI tool
```

## Architecture
Native macOS SwiftUI app (macOS 15.1+, Swift 6) using MVVM with service layers. State injection via `@EnvironmentObject`.
- **SortyLib** (`Sources/SortyLib/`): Core library with AI clients, Models, Views, Organizer, Learnings, Utilities
- **SortyApp** (`Sources/SortyApp/`): App entry, AppCoordinator
- **LearningsCLI** (`Sources/LearningsCLI/`): `learnings` CLI tool
- **Tests** (`Tests/SortyTests/`): Unit tests; `Tests/SortyUITests/`: UI tests

Key flow: `View → ViewModel/Manager → FolderOrganizer → AIClient → OrganizationPlan → Preview → Apply`

## Code Style
- All managers: `@MainActor` `ObservableObject` classes injected via `@EnvironmentObject` at app root
- AI providers: Implement `AIClientProtocol`, register in `AIClientFactory`
- Views: Add `accessibilityIdentifier` for UI testing (e.g., `"SettingsSidebarItem"`)
- Tests: Use `MockAIClient`; create temp dirs in `setUp()`, clean in `tearDown()`
- Deeplinks: `sorty://` URL scheme (see `DeeplinkHandler`)
- Finder extension uses App Groups (`group.com.sorty.app`)

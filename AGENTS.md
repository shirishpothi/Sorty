# Sorty

AI-powered macOS folder organizer — native SwiftUI app (macOS 15+, Swift 6, SPM + Xcode).

## Commands
- `make now` — debug build + launch
- `make dev` — fast debug build (no tests)
- `make build` — full build with tests
- `make test` — unit tests (`swift test --disable-sandbox`)
- `make ci` — run CI checks locally (security, build, test, app bundle)
- `make ci-report` — run CI locally + report pass/fail to GitHub
- `swift test --filter SortyTests.TestClass/testMethod` — single test
- Xcode: open `Sorty.xcodeproj`, select **Sorty**, Build/Run

## Architecture
MVVM + service layers. State is injected from `SortyApp` via `@EnvironmentObject`.
- **SortyLib** (`Sources/SortyLib/`): Core logic (AI, Models, Views, Organizer, Learnings, Utilities)
- **SortyApp** (`Sources/SortyApp/`): App lifecycle
- **LearningsCLI** (`Sources/LearningsCLI/`): `learnings` CLI
- Flow: `View -> Manager -> FolderOrganizer -> AIClient -> OrganizationPlan -> Apply`

## Conventions
- Managers: `@MainActor ObservableObject`
- AI providers: implement `AIClientProtocol` and register in `AIClientFactory`
- Interactive controls: set `accessibilityIdentifier`
- Tests: use `MockAIClient`; create temp dirs in `setUp()` and clean in `tearDown()`
- Feature flags: `defaults write com.sorty.app <key> -bool true`

## UX & Microinteractions
Sorty is a polished, detail-oriented Mac app. Be thoughtful about the small things:
- **Haptics**: Use `HapticFeedbackManager.shared` for tactile feedback — `.selection()` on hover, `.light()` on click, `.success()` / `.error()` for outcomes.
- **Hover effects**: Interactive elements should respond to hover with subtle visual changes (opacity shifts, color transitions, slight movement).
- **Animations**: Use `.animatedAppearance(delay:)` for staggered card entrances. Prefer `.spring()` or `.easeInOut` for state transitions. Keep durations short (0.15–0.3s).
- **Layout polish**: Consistent spacing, proper alignment, and compact designs. Prefer icon+label rows or icon grids over verbose lists when space is tight.
- When adding or modifying any interactive UI, always consider whether it needs haptics, hover states, and smooth transitions — don't wait to be asked.

## Detailed Guides
- [Architecture & Patterns](docs/agent-guides/architecture.md)
- [Feature Flags](docs/agent-guides/feature-flags.md)
- [Xcode Project](docs/agent-guides/xcode-project.md)
- [Finder Integration](docs/agent-guides/finder-integration.md)

## Git Commit Messages
Use a concise, descriptive subject line that captures the user-facing impact (roughly 50–70 characters).
Follow up with as much context as needed in the body. Include the rationale, notable tradeoffs, relevant logs, or reproduction steps—future debugging benefits from having the full story directly in git history.
Reference any related GitHub issues in the body if the change tracks ongoing work.
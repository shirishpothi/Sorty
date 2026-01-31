# Sorty - AI Coding Agent Instructions

## Build & Test Commands (Optimized)
All builds use parallel compilation with auto-detected CPU cores for maximum speed.

### Development (Fastest)
```bash
make dev            # Fastest dev build: debug + parallel + no tests
make quick          # Compile only, skip tests, parallel build
make now            # Fast debug build + launch (skips tests, parallel)
make debug          # Debug build with symbols + launch
```

### Production Builds
```bash
make build          # Full optimized build with tests (parallel)
make cli            # Build 'learnings' CLI tool (parallel)
```

### Testing
```bash
make test           # Unit tests only (parallel execution)
make test-fast      # Fast tests only (excludes slow UI tests)
make test-full      # Unit + UI tests with coverage
make test-ui        # UI tests via Xcode
swift test --filter SortyTests.TestClassName   # Run single test class
swift test --filter SortyTests.TestClassName/testMethodName  # Run single test
```

### Build Profiling & Optimization
```bash
make build-profile  # Identify slow-compiling files and functions
make clean          # Clean all build artifacts
```

### Build Configuration
- **Package.swift**: Swift 6.0 with optimized compiler flags per configuration
- **BuildConfig.xcconfig**: Shared build settings for consistent optimization
- **Debug builds**: `-Onone` + batch mode for speed (~40-60% faster)
- **Release builds**: `-O` + whole-module optimization + dead code stripping + LTO
- **Parallel compilation**: Auto-detects CPU cores (e.g., `--jobs 8` on 8-core Mac)
- **Eager linking**: Unblocks downstream targets faster (Xcode 14+)
- **Test execution**: Parallel test running for ~2-3x faster test completion

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

 Release
- **Always push a `v*` tag** (e.g., `git push origin v1.0.5`) to trigger the GitHub Actions workflow that builds Sorty.zip; **never** use `gh release create` manually as it skips the build process and only creates source code archives.
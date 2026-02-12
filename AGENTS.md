# Sorty - AI Coding Agent Instructions

## Commands
- `make dev` / `make now` — fast debug build (skips tests)
- `make build` — full build with tests
- `make test` — unit tests only
- `swift test --filter SortyTests.TestClass/testMethod` — run single test

## Architecture
Native macOS SwiftUI app (macOS 15.1+, Swift 6), MVVM with service layers via `@EnvironmentObject`.
- **SortyLib** (`Sources/SortyLib/`): Core library (AI/, Models/, Views/, Organizer/, Learnings/, Utilities/)
- **SortyApp** (`Sources/SortyApp/`): App entry point
- **LearningsCLI** (`Sources/LearningsCLI/`): CLI tool
- Flow: `View → Manager → FolderOrganizer → AIClient → OrganizationPlan → Apply`

## Code Style
- Managers: `@MainActor ObservableObject` classes, injected via `@EnvironmentObject`
- AI providers: Implement `AIClientProtocol`, register in `AIClientFactory`
- Views: Add `accessibilityIdentifier` for UI tests
- Tests: Use `MockAIClient`; temp dirs in `setUp()`, clean in `tearDown()`
- URL scheme: `sorty://` (see `DeeplinkHandler`)
- Finder extension: App Groups (`group.com.sorty.app`)

## Feature Flags
Feature flags are controlled via `defaults` and defined in `Sources/SortyLib/Models/FeatureFlags.swift`.

| Flag | Key | Default | Description |
|------|-----|---------|-------------|
| Finder Integration | `finderIntegrationEnabled` | `false` | Enables the Finder Integration settings section and all Finder integration features (Quick Actions, toolbar button, etc.) |
| GitHub Update Checker | `githubUpdateCheckerEnabled` | `false` | Enables the GitHub Releases-based in-app update dialog. Sparkle is the preferred update mechanism and is always active. |
| Privacy Mode | `privacyModeEnabled` | `true` | Blurs sensitive handles until hover and hides API keys with a manual reveal toggle. |
| File Tagging | `fileTaggingEnabled` | `true` | Enables Finder file tagging during organization. Tags may not apply correctly in all macOS sandboxed environments. |
| Batch Organization | `batchOrganizationEnabled` | `false` | Enables the Batch Organization (multi-folder) feature in the sidebar. |
| Advanced Notification Controls | `advancedNotificationSettingsEnabled` | `false` | Shows technical notification controls in Settings (backend selection, NotifiCLI internals, test actions, and advanced toggles). |

Enable Finder Integration: `defaults write com.sorty.app finderIntegrationEnabled -bool true`
Disable Finder Integration: `defaults write com.sorty.app finderIntegrationEnabled -bool false`

Enable GitHub Update Checker: `defaults write com.sorty.app githubUpdateCheckerEnabled -bool true`
Disable GitHub Update Checker: `defaults write com.sorty.app githubUpdateCheckerEnabled -bool false`

Enable Privacy Mode: `defaults write com.sorty.app privacyModeEnabled -bool true`
Disable Privacy Mode: `defaults write com.sorty.app privacyModeEnabled -bool false`

Enable File Tagging: `defaults write com.sorty.app fileTaggingEnabled -bool true`
Disable File Tagging: `defaults write com.sorty.app fileTaggingEnabled -bool false`

Enable Batch Organization: `defaults write com.sorty.app batchOrganizationEnabled -bool true`
Disable Batch Organization: `defaults write com.sorty.app batchOrganizationEnabled -bool false`

Enable Advanced Notification Controls: `defaults write com.sorty.app advancedNotificationSettingsEnabled -bool true`
Disable Advanced Notification Controls: `defaults write com.sorty.app advancedNotificationSettingsEnabled -bool false`

## Release
Push `v*` tag (e.g., `git push origin v1.0.5`) to trigger GitHub Actions build.

Where possible and helpful, spin up subagents to parallelise work.

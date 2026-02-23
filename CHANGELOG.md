# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-02-13

### Added

- **Delete All Data** — New option in Troubleshooting settings to completely wipe usage history, watched folders, and local caches for a fresh start.

### Changed

- **Improved Reset Flow** — The "Reset All Settings" action now returns you to the onboarding experience immediately, eliminating the need for an app restart.
- **URL Normalization** — Custom AI provider endpoints now automatically handle missing URI schemes (e.g., prepending `https://` if omitted).

### Fixed

- **Session Stability** — Fixed a potential `NSGenericException` crash when changing AI configurations rapidly.
- **Release Integrity** — Resolved issues with code signing entitlements and NotifiCLI architecture in production builds.
- **Script Permissions** — Fixed a bug where bundled CLI scripts would lose executable permissions in the release package.
- **UI Polishing** — Fixed a visual artifact with the completion checkmark and resolved an issue where the menu bar mascot would fail to load in release builds.

## [1.1.0] - 2026-02-11

### Highlights

**Sorty v1.1** is a major evolution, featuring a complete visual redesign and powerful new ways to automate your digital life. This release introduces **Batch Organization**, **Automated Scheduling**, and a **Redesigned Workspace Health** engine to keep your machine in peak condition.

### Added


- **Naming Presets** — Create reuseable naming schemes for your folders using AI-powered templates.
- **Conflict Resolution Engine** — New UI for handling filename collisions, letting you choose between overwrite, skip, or keep both.
- **CLI Installer** — A one-click setup to install the `sorty` tool to your path, enabling powerful scripting integrations.
- **Sparkle Updates** — Seamless in-app update experience to get the latest features as soon as they drop.
- **Privacy Mode** — New option to blur sensitive paths and hide API keys, perfect for screensharing or streaming.

### Changed

- **Visual Identity (v2)** — A complete branding overhaul including our new mascot, Sorty! The app now features a modern "Glassmorphism" design system.
- **Interactive Onboarding** — A redesigned first-run experience with a simulated demo and narrated walkthrough.
- **Categorized Settings** — A much-needed overhaul of the settings panel, separating AI configuration, automation, and system preferences.
- **Enhanced AI Preview** — Every suggested move now shows "Reasoning Badges" that explain *why* the AI made its decision.
- **Semantic Duplicates** — The duplicate detector now uses lightweight content analysis to find matches that have different filenames.
- **Performance** — Optimized directory scanning engine that is up to 40% faster on large SSDs.

### Fixed

- **Memory Management** — Fixed several leaks in the Folder Watcher during long-running background sessions.
- **Finder Integration** — Resolved communication delays between the Finder Extension and the main application.
- **Notification Persistence** — Fixed an issue where background organization notifications would sometimes fail to appear.

## [1.0.5] - 2026-01-31

## [1.0.4] - 2026-01-29

## [1.0.2] - 2026-01-28

### Fixed

- **CI Test Stability** — Fixed flaky `HistoryTests.testPersistence` test that was failing intermittently in GitHub Actions due to unreliable `UserDefaults.synchronize()` timing. Tests now use isolated UserDefaults suites for deterministic behavior.

## [1.0.1] - 2026-01-28

### Fixed

- **Notification App Icon** — System notifications now consistently display the Sorty app icon. Previously, notifications often appeared without any icon.

## [1.0.0] - 2026-01-27

### Highlights

**Sorty** is a native macOS app that uses AI to organize your files intelligently. Point it at a messy folder, and it will analyze the contents and suggest a clean folder structure based on what's actually in your files—not just their names or extensions.

### Features

- **AI-Powered Organization** — Works with OpenAI, Anthropic, Groq, Ollama, GitHub Copilot, or Apple's on-device Foundation Models. Understands file content, not just filenames.

- **Learnings Profile** — Sorty watches how you organize files and learns your preferences. Over time, its suggestions get smarter.

- **Custom Personas** — Create specialized AI profiles for different workflows. A "Developer" persona organizes differently than a "Photographer" persona.

- **Vision Support** — For AI providers that support it, Sorty can analyze image content when deciding where files belong.

- **Finder Extension** — Right-click any folder in Finder to start organizing.

- **Workspace Health** — Monitor folder health with clutter detection, duplicate scanning, and actionable cleanup suggestions.

- **Interactive Preview** — Review every suggested move before anything happens. Tweak, approve, or reject individual changes.

- **Full Undo** — Every organization is tracked in history. Roll back any operation completely.

- **Watched Folders** — Monitor folders for changes and organize automatically in the background.

- **CLI Tools** — Two command-line utilities: `learnings` for managing your learning profile, and `sorty` for scripting and automation.

- **Deeplinks** — Control Sorty via `sorty://` URLs for Shortcuts, automation, and external integrations.

- **Menu Bar & Keyboard Shortcuts** — Full keyboard navigation with standard macOS shortcuts.

### Requirements

- macOS 15.1 or later
- For AI features: API key for your preferred provider, or Apple Intelligence enabled for on-device processing

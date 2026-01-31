## [1.0.5] - 2026-01-31

## [1.0.4] - 2026-01-29

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

- **Vision Support** — For AI providers that support it (GPT-4o, Claude 3, Gemini), Sorty can analyze image content when deciding where files belong.

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

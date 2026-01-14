# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-14

### Added
- **Initial public release**
- Pre-release update system verification (Phase 12) to validate UpdateManager before releases
- `update` and `version` commands to `fileorg` CLI with `-v`/`--version` flags
- Comprehensive test suite with 150+ unit tests covering:
  - AppState and menu bar controls
  - PersonaGenerator for custom persona creation
  - UpdateManager for version checking
  - SecurityManager for biometric authentication
  - LearningsHoningEngine for user profiling
  - ContentAnalyzer for file content extraction
  - DeeplinkHandler for URL scheme navigation
  - WorkspaceHealth for clutter monitoring
  - DuplicateDetector for finding duplicate files
  - ExclusionRules for file filtering
- Full menu bar support with keyboard shortcuts:
  - File menu: New Session, Open Directory, Export Results
  - View menu: Navigation commands, Sidebar toggle
  - Organize menu: Start, Regenerate, Apply, Preview, Cancel
  - Learnings menu: Dashboard, Honing, Stats, Export/Import
  - Help menu: Documentation, Updates, About
- Updated documentation in HELP.md and README.md

### Changed
- Enhanced keyboard shortcuts coverage

### Fixed
- Replaced unreliable DispatchSource file monitoring with robust FSEvents implementation
- Added proper App Sandbox entitlement handling with security-scoped bookmark restoration
- Added access status indicators for watched folders (valid, stale, lost access)
- Added validation to prevent auto-organization when no AI provider is configured
- Added user notifications for background organization failures

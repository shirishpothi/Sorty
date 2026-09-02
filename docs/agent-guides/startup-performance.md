# Startup performance

Sorty must present its first window before it reads large persisted stores or restores security-scoped bookmarks. Keep manager initializers cheap. An initializer may create in-memory defaults, register observers, and read a small scalar needed by AppKit before the window appears. It must not decode a file, replay a journal, resolve bookmarks, initialize an AI client, or start automation.

## Loading contract

`SortyApp.configureGlobalsIfNeeded()` starts these loads in parallel after yielding the first SwiftUI frame:

- `SettingsViewModel.loadPersistedState()` reads and decodes `aiConfig`.
- `OrganizationHistory.loadPersistedState()` reads the History file and retains the newest 100 entries.
- `WatchedFoldersManager.loadPersistedState()` replays the append-only watched-folder journal.
- `StorageLocationsManager.loadPersistedState()` reads and normalizes saved storage locations.
- `LearningsManager.loadPersistedState()` restores its model selection and resolves saved reference-model directories.

The main content appears immediately and observes the managers as persisted state arrives. Settings persistence is disabled until hydration completes, so an early view mutation cannot overwrite saved configuration. History, watched folders, storage locations, and Learnings may also publish after the window appears. Automation, widget sync, and bookmark restoration wait for all five loads.

`LoginItemManager` keeps construction free of `SMAppService` queries. Its registration observation starts from `configureGlobalsIfNeeded()` after the first window appears, and startup reconciliation runs off the main actor so it cannot stall the first interactive frame.

The loaders are idempotent. A second caller awaits the existing task. History and storage changes made during hydration are held or merged before saving. Clearing a store invalidates an in-flight result so deleted data cannot reappear.

## Threading rules

File reads, journal replay, and JSON decoding run in detached user-initiated tasks. Published state and persistence writes remain on the main actor. `UserDefaultsDataReader` exposes reads only and uses the documented thread-safe `UserDefaults` read behavior. Do not add write methods to it.

Security-scoped bookmark resolution stays on the main actor after hydration. Moving it to a detached task would change resource-access ownership and needs separate design and testing.

## Verification

Use focused tests while developing:

```sh
swift test --filter 'SettingsViewModelStartupTests|HistoryTests|FolderWatcherTests|StorageLocationsReliabilityTests'
```

Then run `make dev` to verify the app target and Swift 6 isolation checks. For acceptance, launch the built app repeatedly with the same persisted data and compare time to first visible window. A successful build or unit test does not prove the visible launch-time change.

Debug builds log manager constructors slower than 1 ms with the `SortyLaunch:` prefix. Treat those timings as diagnostics, not acceptance evidence; use the launch-smoke result written by `MainWindowRootView.onAppear` for before-and-after measurements.

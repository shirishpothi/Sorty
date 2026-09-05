# Startup performance

Keep the main thread available to draw Sorty's first window and handle input. Launch-path initializers may create in-memory defaults, register observers, and read small scalar preferences needed for the initial interface. Store decoding, journal replay, bookmark resolution, credential lookup, subprocess probes, AI client creation, and automation startup belong in explicit loading or startup methods.

Apply this rule to dependencies reached through `SortyApp`, `WindowSession`, view-owned objects, and `.shared` properties. A cheap initializer can still trigger an expensive singleton. `Task { @MainActor in ... }` retains main-actor work; making a method `async` does not move its synchronous work off that actor.

## Loading contract

`SortyApp.configureGlobalsIfNeeded()` starts these loads in parallel from a view task:

- `SettingsViewModel.loadPersistedState()` reads and decodes `aiConfig`.
- `OrganizationHistory.loadPersistedState()` reads the History file and retains the newest 100 entries.
- `WatchedFoldersManager.loadPersistedState()` replays the append-only watched-folder journal.
- `StorageLocationsManager.loadPersistedState()` reads and normalizes saved storage locations.
- `LearningsManager.loadPersistedState()` restores its model selection and resolves saved reference-model directories.

The main content observes the managers as persisted state arrives. Settings persistence is disabled until hydration completes, so an early view mutation cannot overwrite saved configuration. Automation, widget sync, and bookmark restoration wait for their required stores to load. Manual organization and deeplink entry points must also await the state they depend on, especially exclusion rules. Empty loading state must never mean that a user's rules can be skipped.

`LoginItemManager` keeps construction free of `SMAppService` queries. Its registration observation starts from `configureGlobalsIfNeeded()`, and startup reconciliation runs off the main actor.

The loaders are idempotent. A second caller awaits the existing task. Hold or merge edits made during hydration before saving. Clearing or resetting a store invalidates an in-flight result so deleted data cannot reappear. Preserve these contracts when adding another loader.

`Task.yield()` only offers the executor a scheduling opportunity. Neither it nor SwiftUI `onAppear` proves that a frame has reached the display. Keep synchronous work after suspension points short as well; replacing a blocking initializer with a blocking view task merely moves the stall.

## Threading rules

File reads, journal replay, and JSON decoding run in detached user-initiated tasks. Published state and persistence writes remain on the main actor. `UserDefaultsDataReader` exposes reads only and uses the documented thread-safe `UserDefaults` read behavior. Do not add write methods to it.

For asynchronous bookmark restoration, snapshot the bookmark and item identity before leaving the main actor. Accept a result only if that item and bookmark still match. Keep access ownership explicit, balance every successful security-scope acquisition with its eventual release, and discard stale results after removal, reauthorization, or reset. Serialize or coalesce repeated restoration calls. Await required access before automation uses a folder.

## Verification

Use focused tests while developing:

```sh
swift test --filter 'SettingsViewModelStartupTests|HistoryTests|FolderWatcherTests|StorageLocationsReliabilityTests'
```

For substantive startup changes, run `make dev` to verify the app target and Swift 6 isolation checks. Focus tests on stored-state restoration, edits or resets during loading, dependent operations waiting for hydration, and stale bookmark results. Documentation-only changes do not need a build. Local checks do not replace required Blacksmith checks.

For launch-time acceptance:

- Compare the same signed Release configuration and persisted data, outside a debugger or hot-reload process. Record the exact build and app path.
- Measure launch request to first visible frame, then separately to usable controls. Distinguish process launch from reopening a window in an already-running app.
- Report repeated run values and medians. Keep warm-cache launches separate from the first launch after reboot; preserve real user data and quit gracefully after hydration finishes.
- Use Instruments App Launch and Time Profiler to attribute delays. Add signposts for expensive startup phases when the trace cannot distinguish them.
- Treat `SortyLaunch:` constructor logs as diagnostics. The `MainWindowRootView.onAppear` smoke marker proves that the view lifecycle ran, not that the window was painted or interactive. The analytics `launchDuration` and reliability launch span also cover different initialization intervals, not Dock-click-to-first-frame time.
- State missing evidence plainly. Builds, tests, and source inspection cannot establish a measured launch-time reduction.

See Apple's [Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time) for first-frame measurement and separate startup-activity instrumentation.

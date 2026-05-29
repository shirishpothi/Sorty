# Fast Development Loop Guide

Optimized workflows for rapid iteration on Sorty.

## Quick Reference

| Goal | Command | Typical Time |
|------|---------|-------------|
| Build + launch (no tests) | `make now` | ~7s incremental |
| Build only (no tests) | `make dev` | ~7s incremental |
| Local diagnostic build + tests | `make build` | ~30-60s |
| Harness mode (targeted view) | `make harness` | ~7s incremental |
| Profile slow files | `make build-profile` | ~30s |
| Benchmark all builds | `make benchmark` | ~5-10min |

## Harness Mode

The preview harness launches the app with minimal dependency initialization, targeting a specific view for rapid visual feedback.

### Usage

```bash
# Launch harness (default view)
make harness

# Target a specific view
make harness-settings
make harness-organize
```

### How It Works

- Sets `SORTY_HARNESS_MODE=1` environment variable
- `FeatureFlags.harnessMode` gates heavy startup (folder watchers, AI prewarm, notification setup)
- `FeatureFlags.harnessView` controls which view appears on launch
- Skips tests automatically for maximum speed

### Adding Harness Support for New Views

1. Add a case to `FeatureFlags.harnessView` handling
2. Add a `make harness-<view>` target in the Makefile
3. Ensure the view doesn't crash without full manager initialization

## Build Speed Optimizations

These are already configured — no action needed:

- **Index store disabled** for debug builds (`BuildConfig.xcconfig`, `Makefile`)
- **Parallel compilation** using all CPU cores (`-j $(CORES)`)
- **Batch mode** for debug builds (SPM manages incremental compilation internally)
- **Test target** depends only on `SortyLib` (not the executable target)
- **Concurrency checking** set to `minimal` to reduce type-check overhead
- **FinderSync extension cached** — only rebuilds when source files change (~33s saved on incremental builds)
- **View bodies split** into smaller computed properties to reduce type-checker complexity (MainWindowRootView.body went from 9.9s → 0.2s)

### Type-Checker Performance

Large SwiftUI view `body` properties with many chained modifiers cause exponential type-checking time. When adding view modifiers:
- Break chains of >15 modifiers into separate `some View` computed properties
- Each `some View` return type creates a type-erasure boundary for the compiler
- Group related modifiers: environment injection, lifecycle, notifications

## Benchmarking

```bash
# Capture a baseline before making changes
make benchmark-save

# After changes, compare against baseline
make benchmark-compare

# Raw benchmark (outputs to .build/benchmark-results.json)
make benchmark
```

The benchmark script measures:
1. Clean debug build
2. Incremental build (single file touch)
3. Full test build + run
4. Release build

## Profiling Slow Files

```bash
make build-profile
```

This builds with `-warn-long-function-bodies=100 -warn-long-expression-type-checking=100` and reports any files/expressions exceeding 100ms compile time. Refactor those into smaller composable units.

## Future: Modularization

SortyLib is a monolithic target (199 files, ~85K lines). Clean builds take ~160s because all files compile sequentially within the target. Splitting into smaller targets would enable parallel target compilation:

- **SortyCore** — Models/, Utilities/, Services/
- **SortyAI** — AI/ (depends on SortyCore)
- **SortyOrganizer** — Organizer/, FileSystem/, Learnings/ (depends on SortyCore, SortyAI)
- **SortyUI** — Views/, ViewModels/, DesignSystem/, Managers/ (depends on all above)

## Tips

- **Use `make now` as your default** — it's the fastest path to a running app
- **Touch only what you're editing** — incremental builds only recompile changed files
- **Avoid `make clean`** unless you're debugging build cache issues
- **Use `make test-fast`** for a local unit-test diagnostic pass; Blacksmith remains the merge/release gate
- **Close Xcode** when using SPM builds — Xcode's indexer competes for resources
- **For liquid glass changes, do a visual check** — compile/test success is not enough. Compare against `AboutView` if the goal is “system liquid glass”, because native `.popover` or `.sheet` chrome can look wrong even when `glassEffect` compiles.

### Liquid Glass Regression Guard

Before merging any dropdown/popover changes that should be "system liquid glass":
- Verify no custom material was introduced in that path (`.regularMaterial`, `.thinMaterial`, `.ultraThinMaterial`).
- Verify the implementation uses system presentation and `glassEffect` where available.
- If `glassEffect` is unavailable on the target OS, keep default system presentation (no custom material simulation).
- Do a runtime visual check; build success alone is not sufficient.

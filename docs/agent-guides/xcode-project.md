# Xcode Project

## Project Structure
- `Sorty.xcodeproj` references the local `Package.swift`.
- `SortyLib` is built by SPM and linked into the native `Sorty` app target.
- The app target compiles files in `Sources/SortyApp/`; `Sources/SortyLib/` files are discovered by SPM automatically.
- `#if canImport(SortyLib)` guards support both SPM executable and Xcode builds.
- Sparkle is resolved through the package dependency graph.

## Build and Run
- Open `Sorty.xcodeproj` in Xcode.
- Select the `Sorty` scheme and destination `My Mac`.
- Build with `Cmd+B` and run with `Cmd+R`.
- For extension-only validation, switch to `SortyFinderSync` target/scheme and build.

## Test Targets
- `SortyTests` links `SortyLib` and uses `@testable import SortyLib`.
- `SortyUITests` runs against the native app target.
- Use the Test navigator or `Cmd+U` with the active test scheme.

## Notes for Edits
- New files in `Sources/SortyLib/` do not require manual Xcode project edits.
- Keep app entry logic in `Sources/SortyApp/` and shared logic in `Sources/SortyLib/`.
- If adding files under `Sources/SortyApp/`, confirm target membership in Xcode.

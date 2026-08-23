# Finder Integration

## Current design

- Finder commands use macOS Quick Actions installed in `~/Library/Services`.
- The embedded `SortyFinderSync` target is an inert migration shell. It registers no directories and supplies no menus or toolbar UI.
- Do not re-enable or add behavior to the Finder Sync extension. Filesystem-wide registration triggered a Finder toolbar layout loop on affected Macs.
- `ExtensionCommunication.retireFinderSyncExtensionIfNeeded()` disables known current and legacy extension identifiers once after update and stops a running legacy extension process.
- The legacy `finderIntegrationEnabled` preference remains false for migration compatibility.

## Repair flow

1. Open `Settings -> Finder Integration`.
2. Use `Repair Menu Actions` if Organize, Watch, or Exclude is missing.
3. The repair reinstalls Quick Actions and refreshes the Services registry.

Do not direct users to enable Sorty under macOS Finder Extensions.

## Quick Action icon rendering

Quick Action workflow icons use appearance-specific raster assets. Keep proportional scaling and test both light and dark Finder appearances. The Finder extension bundle may remain an asset lookup fallback during migration, but Finder Sync itself must stay inert.

## Verification

- Confirm `SortyFinderSync.init()` assigns an empty `directoryURLs` set.
- Confirm `menu(for:)` always returns `nil`.
- Confirm app launch calls the retirement migration and never calls Finder Sync auto-repair.
- Confirm Organize, Watch, and Exclude remain available through Finder's right-click menu.
- For the original incident, compare Finder CPU and sampled stacks before and after updating an installation that previously had SortyFinderSync enabled.

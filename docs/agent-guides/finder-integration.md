# Finder Integration

## Basics
- Finder Sync extension target: `SortyFinderSync` (embedded `.appex`).
- IPC uses app group `group.com.sorty.app`.
- Feature flag key: `finderIntegrationEnabled`.
- In-app repair path: `ExtensionCommunication.repairFinderSyncExtensionRegistration`.

## Preferred Repair Flow
1. Enable Finder Integration if needed.
2. Open `Settings -> Finder Integration`.
3. Use `Install/Reinstall` for Quick Action.
4. Use `Repair Finder Sync` (or `Activate Extension`) for the `.appex`.
5. Use `Open Extensions` and confirm `com.sorty.app.SortyFinderSync` is enabled.

## Extension Isolation
- If Sorty is running from `/Applications` or `~/Applications`, Finder Sync is registered from that app bundle directly.
- If Sorty is running from a non-Applications path (for example, a workspace `releases/` build), repair stages the app in `~/Applications/Sorty.app` and registers Finder Sync from there so Finder can activate right-click menus.
- On launch the app auto-repairs the extension registration if it doesn't match the current build (`autoRepairFinderSyncIfNeeded`).
- Repair also kills any stale `SortyFinderSync` process and force-removes the old `pluginkit` registration before re-adding.

## Troubleshooting
- Verify extension target builds:
  - `xcodebuild -project Sorty.xcodeproj -target SortyFinderSync -configuration Debug -destination 'platform=macOS' build`
- Watch icon assets:
  - `Resources/Assets.xcassets/WatchIcon.imageset/eye_black.png` (light mode)
  - `Resources/Assets.xcassets/WatchIcon.imageset/eye_white.png` (dark mode)
- If behavior is stale after rebuilding, re-enable `com.sorty.app.SortyFinderSync` and restart Finder.

# Feature Flags

Feature flags are controlled via `defaults` and defined in `Sources/SortyLib/Models/FeatureFlags.swift`.

## Usage
```bash
# Enable a flag
defaults write com.sorty.app <key> -bool true

# Disable a flag
defaults write com.sorty.app <key> -bool false
```

## Available Flags

| Flag | Key | Default | Description |
|------|-----|---------|-------------|
| GitHub Update Checker | `githubUpdateCheckerEnabled` | `false` | GitHub Releases-based in-app update dialog (Sparkle is always active) |
| Privacy Mode | `privacyModeEnabled` | `true` | Blurs sensitive handles until hover; hides API keys with manual reveal |
| File Tagging | `fileTaggingEnabled` | `true` | Finder file tagging during organization (may not work in sandboxed envs) |
| Batch Organization | `batchOrganizationEnabled` | `false` | Multi-folder batch organization in the sidebar |
| Advanced Notification Controls | `advancedNotificationSettingsEnabled` | `false` | Technical notification controls in Settings |
| Feature Demo | `featureDemoEnabled` | `false` | Interactive demo step during onboarding |

## Finder Integration Repair

Finder Integration is a core app feature. Quick Action and Finder Sync repair should be done from the app UI:

1. Open Settings -> Finder Integration
2. Use `Install`/`Reinstall` for Quick Action
3. Use `Repair Finder Sync` (or `Activate Extension`) for the `.appex`
4. Use `Open Extensions` to confirm Sorty is enabled in macOS Extensions settings

Do not require users to run external terminal commands for normal Quick Action/Finder Sync repair.

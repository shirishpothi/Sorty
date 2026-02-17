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
| Finder Integration | `finderIntegrationEnabled` | `false` | Finder Integration settings and features (Quick Actions, toolbar) |
| GitHub Update Checker | `githubUpdateCheckerEnabled` | `false` | GitHub Releases-based in-app update dialog (Sparkle is always active) |
| Privacy Mode | `privacyModeEnabled` | `true` | Blurs sensitive handles until hover; hides API keys with manual reveal |
| File Tagging | `fileTaggingEnabled` | `true` | Finder file tagging during organization (may not work in sandboxed envs) |
| Batch Organization | `batchOrganizationEnabled` | `false` | Multi-folder batch organization in the sidebar |
| Advanced Notification Controls | `advancedNotificationSettingsEnabled` | `false` | Technical notification controls in Settings |
| Feature Demo | `featureDemoEnabled` | `false` | Interactive demo step during onboarding |

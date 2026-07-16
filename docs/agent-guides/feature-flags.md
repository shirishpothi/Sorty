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
| Feature Demo | `featureDemoEnabled` | `false` | Interactive demo step during onboarding |
| Shaders | `shadersEnabled` | `false` | Recovered shader gallery in the Help menu |
| Support the Developer | `supportDeveloperEnabled` | `true` | In-app links and buttons for supporting the developer; uses the sandbox-container commands below |

### Shaders
Quit Sorty before changing the value, then reopen it so the Help menu is rebuilt.

```bash
# Show the Shaders window entry in the Help menu
defaults -container com.sorty.app write com.sorty.app shadersEnabled -bool true

# Hide it again
defaults -container com.sorty.app write com.sorty.app shadersEnabled -bool false

# Restore the hidden-by-default state
defaults -container com.sorty.app delete com.sorty.app shadersEnabled
```

### Support the Developer
Quit Sorty before changing the value, then reopen it. The `-container` option writes to the same sandboxed preferences domain that Sorty reads; omitting it writes a separate host preference that the app does not reliably see.

```bash
# Hide all Support the Developer links and buttons
defaults -container com.sorty.app write com.sorty.app supportDeveloperEnabled -bool false

# Show them again
defaults -container com.sorty.app write com.sorty.app supportDeveloperEnabled -bool true

# Restore the default, which is shown
defaults -container com.sorty.app delete com.sorty.app supportDeveloperEnabled

# Confirm the stored value
defaults -container com.sorty.app read com.sorty.app supportDeveloperEnabled
```

## Finder Integration Repair

Finder Integration is a core app feature. Quick Action and Finder Sync repair should be done from the app UI:

1. Open Settings -> Finder Integration
2. Use `Install`/`Reinstall` for Quick Action
3. Use `Repair Finder Sync` (or `Activate Extension`) for the `.appex`
4. Use `Open Extensions` to confirm Sorty is enabled in macOS Extensions settings

Do not require users to run external terminal commands for normal Quick Action/Finder Sync repair.

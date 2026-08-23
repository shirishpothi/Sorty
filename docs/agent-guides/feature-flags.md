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

Flags are defined in `Sources/SortyLib/Models/FeatureFlags.swift`. Terminal keys use the `com.sorty.app` defaults domain unless noted.

| Flag | Key | Default | Description |
|------|-----|---------|-------------|
| Finder Sync | `finderIntegrationEnabled` | `false` | Retired legacy preference. Existing installs migrate to Quick Actions and the extension stays disabled. |
| Privacy Mode | `privacyModeEnabled` | `true` | Blurs sensitive handles until hover; hides API keys with manual reveal |
| Internet Privacy Mode | `internetPrivacyModeEnabled` | `false` | Blocks all internet (network) connections from the app |
| Sensitive Action Authentication | `sensitiveActionAuthenticationEnabled` | `false` | Requires authentication for sensitive actions such as deleting usage data, changing network privacy mode, and revealing secrets |
| Subscription Auth | `subscriptionAuthEnabled` | `true` | Makes subscription-based auth methods available for supported AI providers |
| Feature Demo | `featureDemoEnabled` | `false` | Interactive demo step during onboarding |
| Shaders | `shadersEnabled` (see note) | `false` | Recovered shader gallery in the Help menu |
| Support the Developer | `supportDeveloperEnabled` | `true` | In-app links and buttons for supporting the developer; uses the sandbox-container commands below |

### Harness Mode

Harness mode is controlled by environment variables, not `defaults`:

| Flag | Variable | Default | Description |
|------|----------|---------|-------------|
| Harness Mode | `SORTY_HARNESS_MODE` | unset | Boots the app with minimal dependencies and mock services |

Set via `make harness`; see `docs/agent-guides/fast-loop.md`.

### Shaders
Quit Sorty before changing the value, then reopen it so the Help menu is rebuilt.

```bash
# Show the Shaders window entry in the Help menu
defaults write com.sorty.app.feature-flags shadersEnabled -bool true

# Hide it again
defaults write com.sorty.app.feature-flags shadersEnabled -bool false

# Restore the hidden-by-default state
defaults delete com.sorty.app.feature-flags shadersEnabled
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

Finder Integration uses macOS Quick Actions:

1. Open Settings -> Finder Integration
2. Use `Repair Menu Actions` if any action is missing

Do not re-enable the retired Finder Sync extension.

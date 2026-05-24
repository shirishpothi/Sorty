# Sparkle Update System Setup

This document describes how to configure Sparkle automatic updates for Sorty.

## Overview

Sorty uses [Sparkle 2](https://sparkle-project.org/) for automatic in-app updates. The system includes:
- Automatic update checks on app launch (once per 24 hours)
- Ed25519 signature verification for security
- In-app download and installation
- Custom update dialog UI

## Configuration

### 1. Info.plist Keys

The following keys are configured in `Info.plist`:

```xml
<key>SUFeedURL</key>
<string>https://github.com/shirishpothi/Sorty/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>cQdl4m9jYnfXOXAZ0SGwoVpc+/T/j3akfG7CLsmOTOM=</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

### 2. GitHub Secrets

For signed updates to work, you must set up the following GitHub Secret:

**`SPARKLE_PRIVATE_KEY`**
- Value: `rTq0oPPIYi/NJ0TRg07alpydkzLMow1tvHN9i/OXrFQ=`
- This is the base64-encoded Ed25519 private key used to sign updates

**How to set up:**
1. Go to your GitHub repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `SPARKLE_PRIVATE_KEY`
4. Value: `rTq0oPPIYi/NJ0TRg07alpydkzLMow1tvHN9i/OXrFQ=`
5. Click "Add secret"

⚠️ **IMPORTANT**: Never commit the private key to the repository. It's already added to `.gitignore`.

## How It Works

### Release Process

1. Developer pushes a version tag (e.g., `v1.0.6`)
2. GitHub Actions workflow triggers automatically
3. Workflow builds the app and creates `Sorty.pkg`
4. `generate_appcast_ci.sh` signs the ZIP with Ed25519
5. Signed `appcast.xml` is generated and attached to the release
6. Appcast is published to GitHub Releases

### User Experience

1. App checks for updates automatically on launch (24h interval)
2. If update available, Sparkle shows update dialog
3. User clicks "Install Update"
4. Update downloads and installs automatically
5. App restarts with new version

## Regenerating Keys

If you need to regenerate the Ed25519 key pair:

```bash
./scripts/generate_sparkle_keys.sh
```

This will:
1. Generate new Ed25519 key pair
2. Display the public key (update Info.plist)
3. Display the private key (update GitHub Secret)
4. Save keys to `sparkle_keys/` directory (not committed to git)

## Troubleshooting

### Updates Not Working

1. Check that `SUPublicEDKey` in Info.plist matches the public key
2. Verify `SPARKLE_PRIVATE_KEY` GitHub Secret is set correctly
3. Check that appcast.xml is accessible at the SUFeedURL
4. Review GitHub Actions logs for signing errors

### Signature Verification Fails

1. Ensure private key used for signing matches the public key in the app
2. Check that the ZIP file wasn't modified after signing
3. Verify the Ed25519 signature format is correct in appcast.xml

## Files Changed

- `Package.swift` - Added Sparkle dependency
- `Info.plist` - Updated SUPublicEDKey
- `Sources/SortyLib/Utilities/SparkleUpdateManager.swift` - New file
- `Sources/SortyLib/Views/AppCommands.swift` - Changed to SparkleUpdateManager
- `scripts/generate_appcast_ci.sh` - Updated for Ed25519 signing
- `scripts/generate_sparkle_keys.sh` - New helper script
- `.gitignore` - Added sparkle_keys/ directory

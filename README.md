<h1 align="center">Sorty <img src="Sources/SortyLib/Resources/Images/SortyMascotHead.png" alt="Sorty logo" width="32" style="vertical-align:middle; height:32px; display:inline-block; margin:0 8px;" /> - AI-Powered Folder Organizer for macOS</h1>


[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-15.1+-blue.svg)](https://www.apple.com/macos)
[![Security Checks](https://github.com/shirishpothi/Sorty/actions/workflows/swift.yml/badge.svg)](https://github.com/shirishpothi/Sorty/actions/workflows/swift.yml)

A native macOS SwiftUI application that uses AI to intelligently organize directory contents into relevant, semantically-named folders.

<div align="center">

| <img src="Assets/Screenshots/New UI/Live Insights View.png" width="300" /> | <img src="Assets/Screenshots/New UI/Watched Folder View.png" width="300" /> | <img src="Assets/Screenshots/New UI/Post Generation View.png" width="300" /> |
| :---: | :---: | :---: |
| *Streaming AI Organisation, with Live Insights* | *Watched Folders* | *Interactive preview* |

</div>


## Features

- **Intelligent Organization**: Uses AI to understand file content and context for accurate categorization.
- **The Learnings Profile**: A passive learning system that trains from your existing folder structures, manual corrections, and even cancelled organizations to continuously improve future suggestions.
- **Custom Personas**: Create and edit specialized AI profiles for different workflows (e.g., Developer, Photographer, Student).
- **Multiple AI Providers**: 
  - OpenAI-compatible APIs (OpenAI, Anthropic, GitHub Copilot, Groq, Ollama, etc.)
  - Apple Foundation Models (on-device, privacy-focused, requires macOS 15+).
- **AI Vision Support**: Multimodal analysis for providers that support it to understand image content when organizing.
- **Finder Extension**: Right-click any folder in Finder to instantly start the organization process.
- **Workspace Health Monitoring**: Monitor and analyze the health of your directories with actionable insights and quick actions.
- **App-Wide Deeplinks**: Control the app externally via `sorty://` URL schemes for automation and shortcuts.
- **Menu Bar Controls**: Quick access with keyboard shortcuts for common actions.
- **Interactive Preview**: Review and tweak suggested organization before any files are moved.
- **Organization History**: Track all operations with detailed analytics, reasoning, and rollback support.
- **Automatic Updates**: Background update checking on app launch (once per 24 hours) with manual check available via menu.
- **Storage Locations**: Define custom storage destinations for organized files.
- **HUD & Toast Notifications**: Non-intrusive visual feedback for operations and status updates.
- **Cleanup Preview**: Preview and confirm cleanup actions before execution.
- **Safe by Design**: Includes dry-run modes, comprehensive validation, duplicate protection settings, and exclusion rules.


## Quick Start

### Prerequisites
- macOS 15.1 or later
- Xcode 16.0 or later
- (Optional) API key for OpenAI or compatible provider

### Installation

#### Option 1: Download Pre-Built Release (Easiest)

1. Download the latest `.zip` from the [Releases](https://github.com/shirishpothi/Sorty/releases) page.
2. Unzip and drag `Sorty.app` to your `/Applications` folder.
   > **Note**: Moving the app to `/Applications` is highly recommended. It ensures that security bookmarks for "Watched Folders" persist reliably across app restarts.
3. **Important**: Since the app is not notarized (no Apple Developer certificate), you need to remove the quarantine attribute:
   ```bash
   xattr -cr /Applications/Sorty.app
   ```
4. Double-click to launch.

> [!NOTE]
> The `xattr -cr` command removes macOS's quarantine flag that blocks unsigned apps. This is safe for apps you trust and have downloaded from a known source.

#### Option 2: Build from Source

**Using Make (Recommended):**
```bash
git clone https://github.com/shirishpothi/Sorty.git
cd Sorty
make run
```

**Using Xcode:**
1. Open `Sorty.xcodeproj` in Xcode.
2. Select the `Sorty` scheme and your Mac as the destination.
3. Press `⌘R` to build and run.

## Configuration

### 1. AI Provider Setup
- Navigate to the **Settings** tab in the app.
- Configure your preferred provider:
  - **OpenAI-Compatible**: Enter the API URL and your private key.
  - **Apple Foundation Models**: Requires macOS 15+ with Apple Intelligence enabled.

### 2. Finder Extension (disabled by default via defaults feature flag)
To enable the "Organize with AI..." context menu in Finder:
1. Build and run the `SortyExtension` target.
2. Go to **System Settings → Privacy & Security → Extensions → Finder Extensions**.
3. Enable **SortyExtension**.
4. Restart Finder if necessary: `killall Finder`.

> [!IMPORTANT]
> The Finder extension requires **App Groups** to be configured in both the main app and extension targets using the identifier `group.com.sorty.app`.

### 3. Watched Folders
- Add folders to the "Watched" list in the sidebar to enable automatic background monitoring.
- **Note**: The "Auto-Organize" feature will remain disabled until a valid AI provider is configured in Settings.


## Security Considerations

Sorty is designed with security and privacy in mind:

**Data Handling:**
- File analysis happens via your chosen AI provider (OpenAI, Anthropic, Ollama, Apple Intelligence)
- File contents are NOT uploaded unless you explicitly enable Deep Scan
- API keys are stored in the macOS Keychain
- The Learnings profile is encrypted with AES-256 and protected by Touch ID/Face ID
- **Privacy Mode**: Enabled by default, blurs sensitive handles until hover and hides API keys with a manual reveal toggle.

**Release Signing:**
Pre-built releases are NOT code-signed. You will need to remove macOS quarantine flags after installation (see Installation section). Build from source if you prefer complete control.

**Best Practices:**
- Use Ollama or Apple Foundation Models for on-device processing. (However, for remotely large directories small local model likely won't suffice)
- Review which files are being sent to cloud AI providers
- Enable Safe Deletion for duplicate management
- Regularly backup important directories

For detailed security information, see [SECURITY.md](SECURITY.md).

## Troubleshooting

### "Watched Folders" Access Lost
If you see an error indicating that access to a watched folder has been lost (e.g., "Permission Denied" or missing bookmarks):
1. This is often due to macOS App Sandbox restrictions.
2. Ensure the app is running from the `/Applications` folder.
3. Remove the folder from the Watched list and add it again to refresh the security bookmark.

### AI Not Configured / Auto-Organize Disabled
- If "Auto-Organize" is grayed out or not functioning, check **Settings → AI Provider**.
- A valid API configuration (or Apple Intelligence setup) is required for the app to analyze and sort files.

### Update Check Issues
- If update checks fail, verify you have an active internet connection.
- Check if you can access [GitHub Releases](https://github.com/shirishpothi/Sorty/releases) in your browser.
- Rate limiting may occur if too many requests are made; wait a few minutes and try again.


### Verifying App is Up to Date
1. Open **Settings** and click **Check for Updates**.
2. If the app shows "Up to date", you have the latest version.
3. Alternatively, compare the version in **About** with the [latest release](https://github.com/shirishpothi/Sorty/releases/latest).

## Project Structure

- `Sources/SortyLib/`: Core implementation including AI, FileSystem, Models, and Views.
- `Sources/SortyApp/`: Main macOS application entry and navigation.
- `Tests/`: Unit and UI test suites organized by component.
- `Assets/`: App icons and screenshots.
- `scripts/`: Build and automation scripts.

## Contributing

We welcome contributions. See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Detailed development environment setup
- Architecture overview and code style guidelines
- How to add new AI providers
- Testing requirements and PR process

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Testing

### Local CI (Recommended)

Run the same checks as GitHub Actions on your machine for faster feedback:
```bash
make ci              # Security scan, build, tests, app bundle
make ci-report       # Same + report result to GitHub (skips redundant remote CI)
```

### Running Tests

**Using Swift Package Manager:**
```bash
swift test
```

**Using Xcode:**
1. Open the project in Xcode.
2. Press `⌘U` to run all tests.

### Test Coverage

Tests are located in `Tests/SortyTests/` and cover the following areas:

- **Unit Tests**: Core functionality including file organization, duplicate detection, exclusion rules, response parsing, and utility functions.
- **Integration Tests**: End-to-end workflows for AI providers, file system operations, history management, and workspace health monitoring.
- **Component Tests**: Individual modules such as personas, learnings manager, deeplinks, and security.

Key test files include:
- `SortyTests.swift` - Core organization logic
- `WorkspaceHealthTests.swift` - Health monitoring features
- `LearningsManagerTests.swift` - Passive learning system
- `FinderIntegrationStatusTests.swift` - Finder Sync diagnostics, registration parsing, and auto-repair
- `StorageDestinationNormalizerTests.swift` - Storage location path resolution and normalization
- `StorageLocationsReliabilityTests.swift` - Storage validation and reliability
- `PrivacyPathMaskerTests.swift` - Privacy-sensitive path redaction
- `CustomPersonaTests.swift` - Persona management
- `DeeplinkTests.swift` - URL scheme handling
- `UpdateManagerTests.swift` - Update checking functionality

## Deeplinks Reference

Sorty supports the `sorty://` URL scheme for automation and external control:

| Deeplink | Description |
|----------|-------------|
| `sorty://organize?path=<path>&persona=<id>&autostart=true` | Start organization |
| `sorty://duplicates?path=<path>&autostart=true` | Scan for duplicates |
| `sorty://learnings?action=honing` | Open Learnings with specific action |
| `sorty://settings?section=ai` | Open specific settings section |
| `sorty://health` | Open Workspace Health |
| `sorty://history` | Open organization history |
| `sorty://persona?generate=true&prompt=<text>` | Generate a persona |
| `sorty://watched?action=add&path=<path>` | Add watched folder |
| `sorty://rules?action=add&pattern=<pattern>` | Add exclusion rule |
| `sorty://help?section=<topic>` | Open help section |

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

Sorty bundles [NotifiCLI](https://github.com/saihgupr/NotifiCLI) for enhanced notifications.
NotifiCLI is licensed under the MIT License (Copyright (c) 2026 saihgupr).
See [Resources/NotifiCLI/LICENSE](Resources/NotifiCLI/LICENSE) for the full license text.

## Support

- **Documentation**: See [HELP.md](https://github.com/shirishpothi/Sorty/blob/main/HELP.md) for detailed usage guides
- **Bug Reports**: Use the [Bug Report template](../../issues/new?template=bug_report.md)
- **Feature Requests**: Use the [Feature Request template](../../issues/new?template=feature_request.md)
- **Security Issues**: Email shirish.pothi.27@gmail.com (do not open public issues)
- **Questions**: Open a [GitHub Discussion](../../discussions)

#

<div align="center">
  <img src="Assets/AppIcon/AppIcon-Release.png" alt="Sorty logo" width="150" />
  <br>
  <strong>Sorty: The FOSS AI File Organiser</strong>
</div>

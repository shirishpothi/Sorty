# Sorty - macOS AI-Powered Directory Management

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-15.1+-blue.svg)](https://www.apple.com/macos)

A native macOS SwiftUI application that uses AI to intelligently organize directory contents into relevant, semantically-named folders.

<div align="center">

| <img src="Assets/Screenshots/A%20preview%20of%20the%20mid-generation%20UI,%20with%20streaming%20enabled.png" width="300" /> | <img src="Assets/Screenshots/A%20preview%20of%20the%20settings%20page.png" width="300" /> | <img src="Assets/Screenshots/A%20preview%20of%20the%20post-organisation%20UI.png" width="300" /> |
| :---: | :---: | :---: |
| *Streaming AI responses* | *Advanced settings* | *Interactive preview* |

</div>


## ✨ Features

- 🤖 **Intelligent Organization**: Uses AI to understand file content and context for accurate categorization.
- 🧠 **The Learnings Profile**: A passive learning system that trains a local, example-based AI organizer from your existing folder structures and manual examples.
- 🎭 **Custom Personas**: Create and edit specialized AI profiles for different workflows (e.g., Developer, Photographer, Student).
- 🔌 **Multiple AI Providers**: 
  - OpenAI-compatible APIs (OpenAI, Anthropic, GitHub Copilot, etc.)
  - Apple Foundation Models (on-device, privacy-focused, requires macOS 15+).
- 🖱️ **Finder Extension**: Right-click any folder in Finder to instantly start the organization process.
- 📊 **Workspace Health Monitoring**: Monitor and analyze the health of your directories with actionable insights and quick actions.
- 🔗 **App-Wide Deeplinks**: Control the app externally via `sorty://` URL schemes for automation and shortcuts.
- ⌨️ **CLI Tooling**: A companion command-line tool `learnings` for managing organization projects and analysis from the terminal.
- 🎛️ **Menu Bar Controls**: Quick access with keyboard shortcuts for common actions.
- 👁️ **Interactive Preview**: Review and tweak suggested organization before any files are moved.
- 🗂️ **Organization History**: Track all operations with detailed analytics, reasoning, and rollback support.
- 🔄 **Check for Updates**: Built-in update checker to keep Sorty current with the latest features.
- 🛡️ **Safe by Design**: Includes dry-run modes, comprehensive validation, duplicate protection settings, and exclusion rules.


## 🚀 Quick Start

### Prerequisites
- macOS 15.1 or later
- Xcode 16.0 or later
- (Optional) API key for OpenAI or compatible provider

### Installation

#### Option 1: Download Pre-Built Release (Easiest)

1. Download the latest `.zip` from the [Releases](https://github.com/shirishpothi/FileOrganizer/releases) page.
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
git clone https://github.com/shirishpothi/FileOrganizer.git
cd FileOrganizer
make run
```

**Using Xcode:**
1. Open `FileOrganiser.xcodeproj` in Xcode.
2. Select the `FileOrganiser` scheme and your Mac as the destination.
3. Press `⌘R` to build and run.

## ⚙️ Configuration

### 1. AI Provider Setup
- Navigate to the **Settings** tab in the app.
- Configure your preferred provider:
  - **OpenAI-Compatible**: Enter the API URL and your private key.
  - **Apple Foundation Models**: Requires macOS 15+ with Apple Intelligence enabled.

### 2. Finder Extension (Optional)
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

## ❓ Troubleshooting

### "Watched Folders" Access Lost
If you see an error indicating that access to a watched folder has been lost (e.g., "Permission Denied" or missing bookmarks):
1. This is often due to macOS App Sandbox restrictions.
2. Ensure the app is running from the `/Applications` folder.
3. Remove the folder from the Watched list and add it again to refresh the security bookmark.

### AI Not Configured / Auto-Organize Disabled
- If "Auto-Organize" is grayed out or not functioning, check **Settings → AI Provider**.
- A valid API configuration (or Apple Intelligence setup) is required for the app to analyze and sort files.

## 🛠 Project Structure

- `Sources/SortyLib/`: Core implementation including AI, FileSystem, Models, and Views.
- `Sources/SortyApp/`: Main macOS application entry and navigation.
- `Sources/LearningsCLI/`: Implementation of the `learnings` command-line tool.
- `Tests/`: Unit and UI test suites organized by component.
- `Assets/`: App icons and screenshots.
- `scripts/`: Build and automation scripts.

## 📜 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## 🧪 Testing

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
- **Component Tests**: Individual modules such as personas, learnings manager, deeplinks, security, and the CLI tooling.

Key test files include:
- `FileOrganizerTests.swift` - Core organization logic
- `WorkspaceHealthTests.swift` - Health monitoring features
- `LearningsManagerTests.swift` - Passive learning system
- `CustomPersonaTests.swift` - Persona management
- `DeeplinkTests.swift` - URL scheme handling
- `UpdateManagerTests.swift` - Update checking functionality

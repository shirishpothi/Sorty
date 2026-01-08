# File Organizer - macOS AI-Powered Directory Management

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
- 🧠 **The Learnings Profile**: Train a local, example-based file organizer that learns from your existing folder structures and manual examples.
- 🎭 **Custom Personas**: Create and edit specialized AI profiles for different workflows (e.g., Developer, Photographer, Student).
- 🔌 **Multiple AI Providers**: 
  - OpenAI-compatible APIs (OpenAI, Anthropic, GitHub Copilot, etc.)
  - Apple Foundation Models (on-device, privacy-focused, requires macOS 15+).
- 🖱️ **Finder Extension**: Right-click any folder in Finder to instantly start the organization process.
- 🔗 **App-Wide Deeplinks**: Control the app externally via `fileorganizer://` URL schemes for automation and shortcuts.
- ⌨️ **CLI Tooling**: A companion command-line tool `learnings` for managing organization projects and analysis from the terminal.
- 👁️ **Interactive Preview**: Review and tweak suggested organization before any files are moved.
- 🗂️ **Organization History**: Track all operations with detailed analytics, reasoning, and rollback support.
- 🛡️ **Safe by Design**: Includes dry-run modes, comprehensive validation, duplicate protection settings, and exclusion rules.


## 🚀 Quick Start

### Prerequisites
- macOS 15.1 or later
- Xcode 16.0 or later
- (Optional) API key for OpenAI or compatible provider

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/[your-username]/FileOrganizer.git
   cd FileOrganizer
   ```
2. Open `FileOrganizer.xcodeproj` in Xcode.
3. Select the `FileOrganizer` scheme and your Mac as the destination.
4. Press `⌘R` to build and run.

## ⚙️ Configuration

### 1. AI Provider Setup
- Navigate to the **Settings** tab in the app.
- Configure your preferred provider:
  - **OpenAI-Compatible**: Enter the API URL and your private key.
  - **Apple Foundation Models**: Requires macOS 15+ with Apple Intelligence enabled.

### 2. Finder Extension (Optional)
To enable the "Organize with AI..." context menu in Finder:
1. Build and run the `FileOrganizerExtension` target.
2. Go to **System Settings → Privacy & Security → Extensions → Finder Extensions**.
3. Enable **FileOrganizerExtension**.
4. Restart Finder if necessary: `killall Finder`.

> [!IMPORTANT]
> The Finder extension requires **App Groups** to be configured in both the main app and extension targets using the identifier `group.com.fileorganizer.app`.

## 🛠 Project Structure

- `Sources/FileOrganizerLib/`: Core implementation including AI, FileSystem, Models, and Views.
- `Sources/FileOrganizerApp/`: Main macOS application entry and navigation.
- `Sources/LearningsCLI/`: Implementation of the `learnings` command-line tool.
- `Tests/`: Unit and UI test suites organized by component.
- `FinderExtension/`: macOS Finder context menu support.
- `Logs/`: Directory for persistent application and operation logs.

## 📜 License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

# File Organizer - macOS AI-Powered Directory Management

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-26.0+-blue.svg)](https://www.apple.com/macos)

A native macOS SwiftUI application that uses AI to intelligently organize directory contents into relevant, semantically-named folders.

<div align="center">

| <img src="Assets/Screenshots/A%20preview%20of%20the%20mid-generation%20UI,%20with%20streaming%20enabled.png" width="300" /> | <img src="Assets/Screenshots/A%20preview%20of%20the%20settings%20page.png" width="300" /> | <img src="Assets/Screenshots/A%20preview%20of%20the%20post-organisation%20UI.png" width="300" /> |
| :---: | :---: | :---: |
| *Streaming AI responses* | *Advanced settings* | *Interactive preview* |

</div>


## ✨ Features

- 🤖 **Intelligent Organization**: Uses AI to understand file content and context for accurate categorization.
- 🔌 **Multiple AI Providers**: 
  - OpenAI-compatible APIs (OpenAI, Anthropic, GitHub Copilot, etc.)
  - Apple Foundation Models (on-device, privacy-focused, requires macOS 15+).
- 🖱️ **Finder Extension**: Right-click any folder in Finder to instantly start the organization process.
- 👁️ **Interactive Preview**: Review and tweak suggested organization before any files are moved.
- 🗂️ **Organization History**: Track all operations with detailed analytics and reasoning.
- 🛡️ **Safe by Design**: Includes dry-run modes, comprehensive validation, and exclusion rules.


## 🚀 Quick Start

### Prerequisites
- macOS 13.0 or later
- Xcode 15.0 or later
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

- `AI/`: AI client implementations (OpenAI, Apple ML).
- `FileSystem/`: Core logic for directory scanning and file operations.
- `Views/` & `ViewModels/`: SwiftUI interface layers.
- `Models/`: Core data structures.
- `Organizer/`: Business logic for organization strategies.
- `FinderExtension/`: Integrated macOS context menu support.

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

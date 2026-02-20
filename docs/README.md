# Sorty Documentation

Welcome to the official Sorty documentation. Sorty is an AI-powered file organization app for macOS that intelligently sorts your files into logical folders.

## Table of Contents

- [Getting Started](#getting-started)
- [Features](#features)
- [Organization](#organization)
- [The Learnings](#the-learnings)
- [Personas](#personas)
- [Duplicate Detection](#duplicate-detection)
- [Exclusion Rules](#exclusion-rules)
- [Watched Folders](#watched-folders)
- [Finder Integration](#finder-integration)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [App Deeplinks](#app-deeplinks)
- [CLI Tool](#cli-tool)
- [Privacy & Security](#privacy--security)
- [FAQ](#faq)

---

## Getting Started

### Quick Start

1. **Select a Folder**: Click "Open Directory" (⌘O) or drag a folder onto the app
2. **Choose a Persona**: Select a persona (e.g., "Developer", "Photographer") to tailor organization
3. **Preview**: Click "Organize" to see the AI's proposed folder structure
4. **Apply**: Review the preview and click "Apply Changes" — undo anytime with ⌘Z

### System Requirements

- macOS 15.1 or later
- Apple Silicon or Intel Mac
- An AI provider configured (Apple Intelligence, OpenAI, or local Ollama)

---

## Features

### Smart Organization
AI-powered sorting based on filenames, file types, and optionally content metadata. The AI recognizes patterns like project structures, date sequences, and semantic groupings.

### Deep Scan
When enabled, Sorty reads file content for better accuracy:
- PDF text extraction
- Image EXIF metadata (camera, date, location)
- Document titles and keywords
- Audio/video metadata

### File Tagging
Files can be tagged with Finder-compatible tags like "Invoice", "Personal", "Important", or "Archive". These tags are searchable in Spotlight and Finder.

### Workspace Health
Monitor your directories for clutter growth, identify cleanup opportunities, and track organization patterns over time.

---

## Organization

### How It Works

1. **Scanning**: Sorty scans your selected directory and collects information about each file
2. **AI Analysis**: The AI analyzes patterns (naming conventions, file types, dates, project structures)
3. **Structure Proposal**: Based on analysis, the AI proposes a folder structure
4. **Tagging**: Files receive relevant Finder tags for easy searching

### Custom Instructions

Before organizing, you can provide specific guidance:
- "Group all 2024 files together"
- "Organize by client name"
- "Keep design files separate from code"

### Temperature Control

Adjust the AI's creativity in Settings:
- **Low (0.0-0.3)**: More predictable, strict categorization
- **Medium (0.4-0.6)**: Balanced approach
- **High (0.7-1.0)**: More creative groupings

---

## The Learnings

The Learnings is a passive learning system that builds a personalized understanding of how you prefer to organize files.

### What Gets Learned

| Behavior | Description | Priority |
|----------|-------------|----------|
| Steering Prompts | Post-organization feedback | Highest |
| Honing Answers | Explicit preferences from Q&A | High |
| Guiding Instructions | Pre-organization instructions | High |
| Manual Corrections | Files you move after AI organization | Medium |
| Reverts | Sessions you undo | Medium |

### Security

- **Biometric Protection**: Touch ID / Face ID required
- **AES-256 Encryption**: All learning data encrypted
- **Local Storage Only**: Data never leaves your device

---

## Personas

Personas customize how the AI organizes your files based on your profession or use case.

| Persona | Best For | Key Features |
|---------|----------|--------------|
| **General** | Most users | Standard categories (Documents, Media, Archives) |
| **Developer** | Programmers | Groups by project, language, and tech stack |
| **Photographer** | Photo professionals | Organizes by shoots, dates, camera metadata |
| **Music Producer** | Audio creators | Groups projects, samples, stems, sessions |
| **Student** | Academic work | Organizes by subject, course, semester |
| **Business** | Professional work | Groups by client, project, fiscal period |

---

## Duplicate Detection

Sorty uses SHA-256 content hashing to find files with identical content, regardless of filename.

### Safe Deletion

When enabled (default), "deleted" duplicates aren't immediately removed:
- Files are tracked and can be restored later
- Go to History → find the cleanup session → click "Restore"
- Disk space is only recovered after you confirm the deletion

### Bulk Operations

- **Delete All (Keep Newest)**: Removes duplicates, keeping most recently modified
- **Delete All (Keep Oldest)**: Removes duplicates, keeping the original version

---

## Exclusion Rules

Define files and folders to skip during organization.

### Rule Types

| Type | Description | Example |
|------|-------------|---------|
| File Extension | Exclude by extension | `.tmp`, `.log` |
| File Name | Exclude exact filenames | `.DS_Store` |
| Folder Name | Exclude folders by name | `node_modules`, `.git` |
| Path Contains | Exclude paths with text | `/backup/` |
| File Size | Exclude by size | `> 100MB` |
| Hidden Files | Skip `.` prefixed files | All hidden files |
| System Files | Skip macOS system files | `.DS_Store`, etc. |

### Managing Rules

- **Add Rule**: Click "Add Rule" button
- **Toggle**: Enable/disable individual rules
- **Clear All**: Remove all exclusion rules at once

---

## Watched Folders

Set up automatic organization for folders like Downloads. New files are organized as they arrive.

### Configuration

1. Navigate to Watched Folders view
2. Click "Add Folder" or use suggested folders (Downloads, Desktop, Documents)
3. Configure auto-organization settings
4. Enable the folder to start monitoring

---

## Finder Integration

Sorty can expose Finder actions without needing terminal commands.

### Quick Action and Finder Sync Repair (In-App)

1. Open **Settings -> Finder Integration**
2. In **Quick Action**, click **Install** (or **Uninstall/Install** to reinstall)
3. Click **Repair Finder Sync** (or **Activate Extension**) to refresh the `.appex` registration
4. Click **Open Extensions** and confirm Sorty is enabled under Finder extensions

If Finder still shows stale state, run the in-app repair buttons again and then re-open Finder.

---

## Keyboard Shortcuts

### Navigation

| Shortcut | Action |
|----------|--------|
| ⌘O | Open Directory |
| ⌘1 | Organize View |
| ⌘2 | Workspace Health |
| ⌘3 | Duplicates |
| ⌘4 | Exclusions |
| ⌘5 | Watched Folders |
| ⌘, | Settings |
| ⇧⌘H | History |
| ⇧⌘L | The Learnings |

### Organization

| Shortcut | Action |
|----------|--------|
| ⌘R | Start Organization |
| ⇧⌘R | Regenerate |
| ⌘⏎ | Apply Changes |
| ⌘Z | Undo |
| ⎋ | Cancel |

---

## App Deeplinks

Control Sorty via URL schemes.

### Examples

```
sorty://organize?path=/Users/me/Downloads&autostart=true
sorty://duplicates?path=/Users/me/Documents
sorty://persona?action=generate&prompt=sci-fi%20collector
sorty://watched?action=add&path=/Users/me/Downloads
sorty://rules?action=add&type=pattern&pattern=*.log
sorty://learnings?action=honing
sorty://settings
```

---

## CLI Tool

Sorty includes a CLI tool for terminal control.

### Installation

```bash
make install
```

### Usage

```bash
# Organize a folder
sorty organize /path/to/folder --persona developer

# Scan for duplicates
sorty duplicates /path/to/scan --auto

# Add watched folder
sorty watched add /path/to/watch

# Manage learnings
learnings-cli --status
learnings-cli --clear
```

---

## Privacy & Security

### Data Processing

| Data Type | Local | Cloud |
|-----------|-------|-------|
| File names | ✓ | ✓ (sent to AI) |
| File metadata | ✓ | ✓ (sent to AI) |
| File content | ✓ (Deep Scan) | ✗ |
| Organization history | ✓ | ✗ |
| Settings | ✓ | ✗ |

### AI Providers

- **Apple Intelligence**: Processed on-device (M-series chip required)
- **OpenAI/Compatible**: Cloud-based, metadata sent to API
- **Ollama**: Local processing, nothing leaves your machine

---

## FAQ

### Can I undo organization?
Yes! Press ⌘Z immediately after applying, or go to History and click "Revert" on any past session.

### Will Sorty delete my files?
No. Organization only moves files into folders. The only deletion feature is for duplicates, with Safe Deletion enabled by default.

### Does Deep Scan upload my file contents?
No. Deep Scan extracts metadata locally. Only file names and metadata summaries are sent to the AI.

### Can I use Sorty offline?
Yes, with Ollama (local AI) or Apple Intelligence. Cloud providers require internet.

### How do I get better organization results?
1. Choose the right persona
2. Enable Deep Scan for content-aware organization
3. Provide custom instructions
4. Use exclusion rules to protect files that shouldn't move

---

## Support

- [GitHub Repository](https://github.com/shirishpothi/Sorty)
- [Report Issues](https://github.com/shirishpothi/Sorty/issues)
- [Full Help Documentation](../HELP.md)

---

*Sorty © 2024-2026 Shirish Pothi*

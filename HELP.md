# FileOrganiser Help

## Table of Contents
1. [Getting Started](#getting-started)
2. [Features Overview](#features-overview)
3. [Organizing Files](#organizing-files)
4. [The Learnings](#the-learnings)
5. [Personas](#personas)
6. [Managing Duplicates](#managing-duplicates)
7. [Watched Folders](#watched-folders)
8. [Exclusion Rules](#exclusion-rules)
9. [Workspace Health](#workspace-health)
10. [App Deeplinks](#app-deeplinks)
11. [CLI Tooling](#cli-tooling)
12. [Keyboard Shortcuts](#keyboard-shortcuts)
13. [Troubleshooting](#troubleshooting)
14. [Privacy & Data](#privacy--data)
15. [FAQ](#faq)

---

## Getting Started

Welcome to FileOrganiser! This app uses AI to intelligently sort your files into logical folders.

### Quick Start Guide

1. **Select a Folder**: Click "Open Directory" (⌘O) or drag a folder onto the app to choose the folder you want to organize.

2. **Choose a Persona**: Select a persona (e.g., "Developer", "Photographer") in Settings to tailor the organization logic to your workflow.

3. **Preview the Organization**: Click "Organize" to see a preview of the proposed changes. The AI will analyze your files and suggest a folder structure.

4. **Review and Customize**: Expand each suggested folder to see which files will be moved. You can remove files from suggestions if needed.

5. **Apply Changes**: If you're happy with the preview, click "Apply Changes". You can always undo with ⌘Z.

### First-Time Setup

Before your first organization, we recommend:

- **Configure your API Key** in Settings if using OpenAI (not needed for Apple Intelligence or local Ollama)
- **Set up Exclusion Rules** to protect important files you never want moved
- **Enable Deep Scan** for smarter organization (uses more resources)
- **Enable File Tagging** to get Finder-compatible tags on your files

---

## Features Overview

### Smart Organization
AI-powered sorting based on filenames, file types, and optionally content metadata. The AI recognizes patterns like project structures, date sequences, and semantic groupings.

### Deep Scan
When enabled, FileOrganiser reads file content for better accuracy:
- PDF text extraction
- Image EXIF metadata (camera, date, location)
- Document titles and keywords
- Audio/video metadata

### File Tagging
Files can be tagged with Finder-compatible tags like "Invoice", "Personal", "Important", or "Archive". These tags are searchable in Spotlight and Finder.

### Watched Folders
Set up automatic organization for folders like Downloads. New files are organized as they arrive.

### Duplicate Detection
Find and safely remove duplicate files using SHA-256 content hashing. Recover space while maintaining a safety net.

### Workspace Health
Monitor your directories for clutter growth, identify cleanup opportunities, and track organization patterns over time.

---

## Organizing Files

### How Organization Works

1. **Scanning**: FileOrganiser scans your selected directory and collects information about each file.

2. **AI Analysis**: The AI analyzes patterns in your files:
   - Naming conventions (project_v1, project_v2, etc.)
   - File types and categories
   - Date patterns (YYYY-MM-DD prefixes)
   - Project structures

3. **Structure Proposal**: Based on analysis, the AI proposes a folder structure with categories and subcategories.

4. **Tagging**: Files receive relevant Finder tags for easy searching.

### Custom Instructions

Before organizing, you can provide specific guidance:
- "Group all 2024 files together"
- "Organize by client name"
- "Keep design files separate from code"
- "Create a folder for each project"

Enter custom instructions in the text field before clicking "Organize".

### Temperature Control

Adjust the AI's creativity in Settings:
- **Low (0.0-0.3)**: More predictable, strict categorization
- **Medium (0.4-0.6)**: Balanced approach
- **High (0.7-1.0)**: More creative groupings, may find novel patterns

### Including Reasoning

Enable "Include Reasoning" in Settings to see detailed explanations for each folder:
- Why files are grouped together
- What patterns the AI noticed
- Why alternatives were rejected

This is helpful for understanding and fine-tuning the organization.

---

## The Learnings

The Learnings is a **passive learning system** that builds a personalized understanding of how you prefer to organize files. It observes your organization habits, corrections, and feedback to continuously improve AI suggestions over time.

### Getting Started

1. **Enable Learning**: Navigate to **The Learnings** (⇧⌘L) and grant consent
2. **Authenticate**: Set up Touch ID / Face ID / Passcode protection for your data
3. **Use the App Normally**: Organize files, provide feedback, and make corrections

After initial setup, you'll need to authenticate each time you access The Learnings dashboard (for security).

### What Gets Learned

| Behavior | What's Captured | Priority |
|----------|-----------------|----------|
| **Steering Prompts** | Post-organization feedback and instructions | Highest |
| **Honing Answers** | Your explicit preferences from Q&A sessions | High |
| **Guiding Instructions** | Instructions you provide before organizing | High |
| **Manual Corrections** | Files you move after AI organization | Medium |
| **Reverts** | Organization sessions you undo | Medium |
| **Additional Instructions** | Custom instructions during organization | Medium |

### How Learning Improves AI

The system uses your learnings in several ways:

1. **Pattern Recognition**: Identifies how you prefer to organize specific file types
2. **Temporal Weighting**: Recent behavior is weighted more heavily than older patterns
3. **Rule Induction**: AI analyzes patterns to create explicit organization rules
4. **Contextual Understanding**: Learns folder preferences for different contexts

### The Dashboard

The Learnings dashboard has three tabs:

- **Overview**: Quick stats, learning progress, and action buttons
- **Preferences**: Grouped view of all learned preferences (honing answers, inferred rules, feedback)
- **Activity**: Timeline of corrections, reverts, and instructions with expandable details

### Honing Sessions

Use the **Refine Preferences** button to start a honing session:

1. Answer 3-5 questions about your organization philosophy
2. Questions are AI-generated based on your recent activity
3. Answers become high-priority preferences for future organizations
4. Honing is also offered after completing an organization

**Example questions:**
- "When you finish a project, what is your preferred archival strategy?"
- "How do you prefer to organize documents by date?"

### Security & Privacy

| Feature | Description |
|---------|-------------|
| **Biometric Protection** | Touch ID / Face ID required after initial setup |
| **AES-256 Encryption** | All learning data encrypted with Keychain-stored keys |
| **Local Storage Only** | Data never leaves your device |
| **Session Timeout** | Automatic lock after 5 minutes of inactivity |
| **Secure Deletion** | Data overwritten before removal |

### Data Management

- **Pause Learning**: Stop data collection while preserving existing data
- **Delete All Data**: Permanently and securely remove all learning data
- **Export**: (Coming soon) Export your preferences as JSON

### CLI Commands

```bash
# View learning status
learnings-cli --status

# Clear all learning data
learnings-cli --clear

# Open Learnings dashboard
fileorg learnings
```

### Deeplinks

| Deeplink | Description |
|----------|-------------|
| `fileorganizer://learnings` | Open Learnings dashboard |
| `fileorganizer://learnings?action=honing` | Start a honing session |
| `fileorganizer://learnings?action=stats` | View learning statistics |

---

## Personas

Personas customize how the AI organizes your files based on your profession or use case.

### Available Personas

| Persona | Best For | Key Features |
|---------|----------|--------------|
| **General** | Most users | Standard categories (Documents, Media, Archives) |
| **Developer** | Programmers | Groups by project, language, and tech stack |
| **Photographer** | Photo professionals | Organizes by shoots, dates, camera metadata |
| **Music Producer** | Audio creators | Groups projects, samples, stems, sessions |
| **Student** | Academic work | Organizes by subject, course, semester |
| **Business** | Professional work | Groups by client, project, fiscal period |

### Customizing Personas

You can customize the system prompt for each persona:

1. Go to Settings → Advanced Settings
2. Select the persona to customize
3. Edit the "Custom System Prompt" text
4. Your changes persist per-persona

**Tip**: Reset to default by clicking "Reset to Default" next to the prompt editor.

---

## Managing Duplicates

### How Duplicate Detection Works

FileOrganiser uses SHA-256 content hashing to find files with **identical content**, regardless of filename. Files are grouped by hash, and you can choose which copy to keep.

### Safe Deletion (Recommended)

When enabled, "deleted" duplicates aren't immediately removed:
- Files are tracked and can be restored later
- Go to History → find the cleanup session → click "Restore"
- Disk space is only recovered after you confirm the deletion

### Bulk Operations

- **Delete All (Keep Newest)**: Removes all duplicates, keeping the most recently modified version
- **Delete All (Keep Oldest)**: Removes all duplicates, keeping the original version

### Independent Scanning

You can scan any folder for duplicates without changing your main organization target. Use the "Settings" button in the Duplicates view to configure scanning depth and file filters.

---

## App Deeplinks

FileOrganiser provides comprehensive URL schemes to control all aspect of the application.

### Organization Routes
| Route | Parameters | Description |
|-------|------------|-------------|
| **Organize** | `fileorganizer://organize` | Open the organization view |
| | `path` | Path to organize |
| | `persona` | ID of persona (fileorganizer_general, developer, etc) |
| | `autostart=true` | Automatically begin organization |
| **Duplicates** | `fileorganizer://duplicates` | Open duplicates view |
| | `path` | Path to scan |
| | `autostart=true` | Automatically begin scan |

### Management Routes
| Route | Parameters | Description |
|-------|------------|-------------|
| **Persona** | `fileorganizer://persona` | Manage personas |
| | `action=generate` | Generate a new persona |
| | `prompt` | Description for generation |
| | `generate=true` | Trigger generation immediately |
| **Watched** | `fileorganizer://watched` | Manage watched folders |
| | `action=add` | Add a new watched folder |
| | `path` | Path to add |
| **Rules** | `fileorganizer://rules` | Manage exclusion rules |
| | `action=add` | Add a new rule |
| | `pattern` | Pattern to exclude (e.g., "*.tmp") |

### Navigation Routes
| Route | Parameters | Description |
|-------|------------|-------------|
| **Settings** | `fileorganizer://settings` | Open Settings |
| **Learnings** | `fileorganizer://learnings` | Open Learnings |
| **History** | `fileorganizer://history` | Open History |
| **Health** | `fileorganizer://health` | Open Workspace Health |
| **Help** | `fileorganizer://help` | Open Help |

---

## CLI Tooling

FileOrganiser includes a comprehensive CLI tool called `fileorg` that allows you to control the application from your terminal.

### Installation
Run `make install` (or ensure `CLI/fileorg` is in your path).

### Usage
`fileorg <command> [options]`

### Commands

**Organization**
```bash
# Organize current folder
fileorg organize .

# Organize specific folder with specific persona
fileorg organize /Users/me/Downloads --persona developer

# Auto-start organization
fileorg organize . --auto
```

**Maintenance**
```bash
# Scan for duplicates
fileorg duplicates /path/to/scan --auto

# Add watched folder
fileorg watched add /path/to/watch

# Add exclusion rule
fileorg rules add "*.log"
```

**Generative AI**
```bash
# Generate a new persona from description
fileorg persona generate "I want to organize my sci-fi ebook collection by author"
```

**Navigation**
```bash
fileorg settings
fileorg history
fileorg learnings
fileorg health
fileorg help
```

---

## Watched Folders

### Setting Up Watched Folders

1. Go to Settings → Watched Folders
2. Click "Add Folder"
3. Select the directory to monitor
4. Configure per-folder settings

### Per-Folder Settings

Each watched folder can have:
- Its own persona (e.g., Developer for your code folder)
- Custom enable/disable state
- Smart Drop mode settings

### Smart Drop Mode

When enabled, only **new** files dropped into the folder root are organized:
- Existing files and nested contents are left untouched
- Prevents infinite reorganization loops
- Files are sorted into existing folder structure

### Calibration

Run "Calibrate" to perform a one-time full organization. This establishes the baseline folder structure that Smart Drop will use going forward.

---

## Exclusion Rules

### Types of Rules

| Rule Type | Examples |
|-----------|----------|
| **Pattern Matching** | `*.log`, `*.tmp`, `config*` |
| **Folder Exclusions** | `/node_modules`, `/.git`, `/venv` |
| **Extension Filters** | `.DS_Store`, `.gitignore` |
| **Size-Based** | Files > 1GB, Files < 1KB |

### Creating Rules

1. Go to Settings → Exclusion Rules
2. Click "Add Rule"
3. Choose rule type and enter criteria
4. Rule applies immediately to future organizations

### Common Exclusion Patterns

- `node_modules/*` - JavaScript dependencies
- `.git/*` - Git repository data
- `*.tmp`, `*.temp` - Temporary files
- `Desktop.ini`, `.DS_Store` - System files
- `*.log` - Log files

---

## Workspace Health

### Health Metrics

| Metric | Description |
|--------|-------------|
| **Space Distribution** | How disk space is used across file types |
| **Clutter Growth** | Rate of new unorganized files |
| **Empty Folders** | Directories with no contents |
| **Very Old Files** | Files not accessed in 1+ year |
| **Broken Symlinks** | Symbolic links pointing to missing targets |
| **Duplicate Candidates** | Potential duplicate files |

### Cleanup Opportunities

FileOrganiser identifies:
- **Screenshot Clutter**: Many screenshots that could be organized
- **Download Clutter**: Old files in Downloads folder
- **Large Files**: Files > 100MB that may need attention
- **Temporary Files**: Cache and temp files safe to delete
- **Unorganized Files**: Files in folder root needing organization

### Growth Tracking

Weekly insights show:
- How much your folders grew
- Which file types are accumulating
- Recommendations for keeping things tidy

---

## Keyboard Shortcuts

### Navigation

| Shortcut | Action |
|----------|--------|
| ⌘1 | Go to Organize |
| ⌘2 | Go to Workspace Health |
| ⌘3 | Go to Duplicates |
| ⌘4 | Go to Exclusions |
| ⌘5 | Go to Watched Folders |
| ⌘6 | Go to The Learnings |
| ⌘, | Open Settings |
| ⇧⌘H | Open History |
| ⇧⌘L | Open The Learnings |
| ⌘\ | Toggle Sidebar |

### File Operations

| Shortcut | Action |
|----------|--------|
| ⌘N | New Session |
| ⌘O | Open Directory |
| ⌘E | Export Results |
| ⌘A | Select All Files |
| ⌘Z | Undo |

### Organization

| Shortcut | Action |
|----------|--------|
| ⌘R | Start/Regenerate Organization |
| ⌘⏎ | Apply Changes |
| ⎋ | Cancel Operation |

---

## Troubleshooting

### AI Not Responding

- ✓ Check your internet connection
- ✓ Verify your API Key is correct in Settings
- ✓ Ensure the API URL is correct for your provider
- ✓ Check if the selected model is available
- ✓ Try increasing the Request Timeout in Advanced Settings
- ✓ For Ollama: ensure the server is running (`ollama serve`)

### Files Not Moving

- ✓ Check Exclusion Rules to ensure files aren't protected
- ✓ Verify you have write permissions for the directory
- ✓ Ensure the source files still exist
- ✓ Check for file locks (files open in other apps)

### Slow Organization

- ✓ Disable Deep Scan for faster processing
- ✓ Reduce the number of files by using exclusions
- ✓ Enable Streaming for responsive feedback
- ✓ Consider using a faster AI model

### Tags Not Appearing

- ✓ Ensure "Enable File Tagging" is ON in Settings
- ✓ Tags only apply after "Apply Changes" is clicked
- ✓ Refresh Finder (close and reopen the folder)
- ✓ Enable reasoning to verify AI is suggesting tags

### Safe Deletion Issues

- ✓ Check History tab for restoration options
- ✓ Verify files weren't permanently deleted (Safe Deletion was ON)
- ✓ Look in the original locations for restored files

---

## Privacy & Data

### What Data is Processed

| Data Type | Local | Cloud |
|-----------|-------|-------|
| File names | ✓ | ✓ (sent to AI) |
| File metadata | ✓ | ✓ (sent to AI) |
| File content | ✓ (Deep Scan only) | ✗ |
| Organization history | ✓ | ✗ |
| Settings | ✓ | ✗ |

### AI Providers

- **Apple Intelligence**: Processed on-device (requires M-series chip + macOS 15.1+)
- **OpenAI/Compatible**: Cloud-based, file names and metadata sent to API
- **Ollama**: Local processing, nothing leaves your machine

### Data Storage

All data is stored locally:
- Organization history: `~/Library/Preferences/`
- Safe deletion metadata: Local database
- Settings: UserDefaults

### Clearing Data

- **Help → Delete All Usage Data**: Removes Safe Deletion history
- **Reset Settings**: Restores all settings to defaults

---

## FAQ

### Q: Can I undo organization?

**A**: Yes! Press ⌘Z immediately after applying, or go to History and click "Revert" on any past session.

### Q: Will FileOrganiser delete my files?

**A**: No. Organization only **moves** files into folders. The only deletion feature is for duplicates, and it has Safe Deletion enabled by default.

### Q: Does "Deep Scan" upload my file contents?

**A**: No. Deep Scan extracts metadata locally. Only file names and metadata summaries are sent to the AI.

### Q: Can I use FileOrganiser offline?

**A**: Yes, with Ollama (local AI) or Apple Intelligence. Cloud providers (OpenAI) require internet.

### Q: How do I get better organization results?

**A**: 
1. Choose the right persona for your work
2. Enable Deep Scan for content-aware organization
3. Provide custom instructions before organizing
4. Use exclusion rules to protect files that shouldn't move

### Q: Why are some files marked "unorganized"?

**A**: The AI couldn't confidently categorize them. This happens with:
- Files with generic names
- Uncommon file types
- Files that don't fit clear categories

### Q: Can I customize the folder names?

**A**: Yes! After previewing, you can edit folder names before applying. Or provide custom instructions like "use lowercase folder names".

---

*FileOrganiser © 2025-2026 Shirish Pothi. Special thanks to the Apple Developer community.*

//
//  HelpView.swift
//  Sorty
//
//  Comprehensive built-in Help window
//

import SwiftUI

struct HelpView: View {
    @State private var searchText = ""
    @State private var selectedSection: HelpSection
    
    init(initialSection: HelpSection = .gettingStarted) {
        _selectedSection = State(initialValue: initialSection)
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with sections
            List(HelpSection.allCases, id: \.self, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Section Header
                    HStack {
                        Image(systemName: selectedSection.icon)
                            .font(.title)
                            .foregroundColor(.accentColor)
                        Text(selectedSection.title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.bottom, 10)
                    
                    // Section Content
                    selectedSection.content
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Sorty Help")
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Help Sections

@MainActor
public enum HelpSection: String, CaseIterable {
    case gettingStarted
    case onboarding
    case organizing
    case personas
    case learnings
    case duplicates
    case watchedFolders
    case exclusions
    case workspaceHealth
    case cliAndDeeplinks
    case shortcuts
    case updates
    case downloads
    case troubleshooting
    case diagnostics
    case privacy
    case about
    
    var title: String {
        switch self {
        case .gettingStarted: return "Getting Started"
        case .onboarding: return "Onboarding"
        case .organizing: return "Organizing Files"
        case .personas: return "Personas"
        case .learnings: return "The Learnings"
        case .duplicates: return "Managing Duplicates"
        case .watchedFolders: return "Watched Folders"
        case .exclusions: return "Exclusion Rules"
        case .workspaceHealth: return "Workspace Health"
        case .shortcuts: return "Keyboard Shortcuts"
        case .cliAndDeeplinks: return "CLI & Deeplinks"
        case .updates: return "Version & Updates"
        case .downloads: return "Downloads"
        case .troubleshooting: return "Troubleshooting"
        case .diagnostics: return "Diagnostics & Logs"
        case .privacy: return "Privacy & Data"
        case .about: return "About"
        }
    }
    
    var icon: String {
        switch self {
        case .gettingStarted: return "star.fill"
        case .onboarding: return "hand.wave.fill"
        case .organizing: return "folder.badge.gear"
        case .personas: return "person.3.fill"
        case .learnings: return "brain.head.profile"
        case .duplicates: return "doc.on.doc.fill"
        case .watchedFolders: return "eye.fill"
        case .exclusions: return "eye.slash.fill"
        case .workspaceHealth: return "heart.text.clipboard.fill"
        case .shortcuts: return "keyboard.fill"
        case .cliAndDeeplinks: return "terminal.fill"
        case .updates: return "arrow.down.circle.fill"
        case .downloads: return "square.and.arrow.down.fill"
        case .troubleshooting: return "wrench.and.screwdriver.fill"
        case .diagnostics: return "stethoscope"
        case .privacy: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }
    
    @ViewBuilder
    var content: some View {
        switch self {
        case .gettingStarted:
            GettingStartedContent()
        case .onboarding:
            OnboardingHelpContent()
        case .organizing:
            OrganizingContent()
        case .personas:
            PersonasContent()
        case .learnings:
            LearningsHelpContent()
        case .duplicates:
            DuplicatesContent()
        case .watchedFolders:
            WatchedFoldersContent()
        case .exclusions:
            ExclusionsContent()
        case .workspaceHealth:
            WorkspaceHealthContent()
        case .cliAndDeeplinks:
            CLIDeepLinksContent()
        case .shortcuts:
            ShortcutsContent()
        case .updates:
            UpdatesHelpContent()
        case .downloads:
            DownloadsContent()
        case .troubleshooting:
            TroubleshootingContent()
        case .diagnostics:
            DiagnosticsContent()
        case .privacy:
            PrivacyContent()
        case .about:
            AboutContent()
        }
    }
}

// MARK: - Section Content Views

private struct GettingStartedContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Sorty! This app uses AI to intelligently sort your files into logical folders.")
                .font(.body)
            
            HelpStepView(number: 1, title: "Select a Folder", description: "Click \"Open Directory\" (⌘O) or drag a folder onto the app to choose the folder you want to organize.")
            
            HelpStepView(number: 2, title: "Choose a Persona", description: "Select a persona (e.g., \"Developer\", \"Photographer\") to tailor the organization logic to your workflow.")
            
            HelpStepView(number: 3, title: "Preview the Organization", description: "Click \"Organize\" to see a preview of the proposed changes. The AI will analyze your files and suggest a folder structure.")
            
            HelpStepView(number: 4, title: "Apply Changes", description: "If you're happy with the preview, click \"Apply Changes\". You can always undo with ⌘Z.")
            
            Divider()
            
            Text("Tip: Enable \"Include Reasoning\" in Settings to see detailed explanations for each organization decision.")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
        }
    }
}

private struct OnboardingHelpContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The onboarding flow helps you set up Sorty for the first time. For new users, onboarding is mandatory and covers all the essential setup steps.")
                .font(.body)
            
            Text("What's Covered in Onboarding")
                .font(.headline)
            
            HelpFeatureView(icon: "cloud.fill", title: "AI Provider Setup", description: "Choose your AI provider (OpenAI, Anthropic, or Ollama) and enter your API key. Your data stays private - files are processed using your own API credentials.")
            
            HelpFeatureView(icon: "lock.shield.fill", title: "Permissions", description: "Grant necessary permissions for file access, Finder automation, and notifications to enable full functionality.")
            
            HelpFeatureView(icon: "person.crop.circle.badge.checkmark", title: "Workflow Selection", description: "Choose a persona that matches how you work - Developer, Photographer, Student, or General use.")
            
            HelpFeatureView(icon: "play.circle.fill", title: "Live Demo", description: "See Sorty in action! Select a real folder and watch as files are organized in real-time.")
            
            Divider()
            
            Text("Revisit Onboarding")
                .font(.headline)
            
            Text("Want to see the onboarding flow again? Click the button below to restart the setup process.")
                .font(.callout)
                .foregroundColor(.secondary)
            
            Button(action: {
                appState.showOnboarding()
            }) {
                Label("View Onboarding Again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct OrganizingContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Section {
                Text("Sorty uses AI to understand your files and create a logical folder structure. Here's how the process works:")
                
                HelpFeatureView(icon: "magnifyingglass", title: "Scanning", description: "The app scans your selected directory and collects information about each file including name, type, size, and optionally content metadata.")
                
                HelpFeatureView(icon: "brain", title: "AI Analysis", description: "The AI analyzes patterns in your files: naming conventions, file types, project structures, and date patterns.")
                
                HelpFeatureView(icon: "folder.badge.plus", title: "Structure Proposal", description: "Based on the analysis, the AI proposes a folder structure with clear categories and subcategories.")
                
                HelpFeatureView(icon: "tag.fill", title: "Tagging", description: "Files can be tagged with Finder-compatible tags for easy searching (e.g., 'Invoice', 'Personal', 'Important').")
            }
            
            Divider()
            
            Section {
                Text("Advanced Features")
                    .font(.headline)
                
                HelpFeatureView(icon: "doc.text.magnifyingglass", title: "Deep Scan", description: "Enable in Settings to analyze file content (PDF text, EXIF data for photos) for smarter organization.")
                
                HelpFeatureView(icon: "thermometer.medium", title: "Temperature Control", description: "Adjust the AI's creativity. Lower values = more predictable organization, higher = more creative groupings.")
                
                HelpFeatureView(icon: "text.bubble", title: "Custom Instructions", description: "Provide specific guidance before organizing (e.g., 'Group by client name' or 'Keep all 2024 files together').")
            }
        }
    }
}

private struct PersonasContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personas are specialized AI profiles that optimize organization for specific use cases.")
            
            Text("Built-in Personas")
                .font(.headline)
            
            HelpFeatureView(icon: "folder.fill", title: "General", description: "A balanced approach for everyday file organization. Suitable for most users.")
            
            HelpFeatureView(icon: "chevron.left.forwardslash.chevron.right", title: "Developer", description: "Understands code projects, recognizes package.json, Cargo.toml, and organizes by language/framework.")
            
            HelpFeatureView(icon: "camera.fill", title: "Photographer", description: "Uses EXIF data to organize by date, camera, and event. Separates RAW from processed files.")
            
            HelpFeatureView(icon: "graduationcap.fill", title: "Student", description: "Organizes by subjects, courses, and semesters. Groups assignments and research materials.")
            
            HelpFeatureView(icon: "building.2.fill", title: "Business", description: "Groups by clients, projects, and fiscal periods. Recognizes invoices, contracts, and reports.")
            
            Divider()
            
            Text("Custom Personas")
                .font(.headline)
            
            HelpFeatureView(icon: "plus.circle.fill", title: "Create Your Own", description: "Click 'Create' in the persona picker to design your own organization persona with custom AI instructions.")
            
            HelpFeatureView(icon: "pencil.circle.fill", title: "Edit & Delete", description: "Right-click on any custom persona to edit its settings or delete it. Changes are saved automatically.")
            
            HelpFeatureView(icon: "wand.and.stars", title: "Prompt Template", description: "Use the 'Insert Template' button when creating a persona to start with a structured prompt format.")
            
            Divider()
            
            Text("You can customize the system prompt for each persona in Settings → Advanced Settings → Custom System Prompt.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

private struct LearningsHelpContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("The Learnings is a trainable, local-first, example-based file organization engine that learns from your preferences.")
            
            Text("Getting Started")
                .font(.headline)
            
            HelpFeatureView(icon: "folder.badge.plus", title: "Create a Project", description: "Start by creating a project with source directories to scan and example folders showing your preferred organization.")
            
            HelpFeatureView(icon: "plus.rectangle.on.folder", title: "Add Examples", description: "Teach the engine by providing source→destination examples, or point it to already-organized folders to learn from.")
            
            HelpFeatureView(icon: "magnifyingglass", title: "Analyze", description: "Run analysis to infer organization rules and generate proposals for unorganized files.")
            
            Divider()
            
            Text("Apply & Rollback")
                .font(.headline)
            
            HelpFeatureView(icon: "checkmark.circle.fill", title: "Apply Changes", description: "Review proposals and apply file moves. Choose to apply only high-confidence matches or all suggestions.")
            
            HelpFeatureView(icon: "arrow.uturn.backward", title: "Rollback", description: "Made a mistake? Use the 'Undo Last Apply' button to restore files to their original locations.")
            
            HelpFeatureView(icon: "externaldrive.fill.badge.checkmark", title: "Backups", description: "Enable backups when applying to create a safety net. Files are copied before being moved.")
            
            Divider()
            
            Text("CLI Tool")
                .font(.headline)
            
            Text("The Learnings also includes a command-line tool for scripted or headless use:")
                .font(.callout)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("make cli").font(.system(.caption, design: .monospaced))
                Text("learnings init-project --name \"Photos\" --root ~/Downloads").font(.system(.caption, design: .monospaced))
                Text("learnings analyze --project \"Photos\"").font(.system(.caption, design: .monospaced))
                Text("learnings apply --project \"Photos\" --confirm").font(.system(.caption, design: .monospaced))
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

private struct DuplicatesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find and safely remove duplicate files to recover disk space.")
            
            HelpFeatureView(icon: "rectangle.on.rectangle.angled", title: "Detection", description: "Duplicates are detected using SHA-256 content hashing. Files with identical content are grouped together.")
            
            HelpFeatureView(icon: "lifepreserver.fill", title: "Safe Deletion", description: "When enabled, deleted duplicates are not immediately removed. They can be restored from the History tab if you change your mind.")
            
            HelpFeatureView(icon: "trash", title: "Bulk Delete", description: "Use the bulk delete options to remove all duplicates at once, keeping either the newest or oldest version of each file.")
            
            Divider()
            
            Text("Settings")
                .font(.headline)
            
            HelpFeatureView(icon: "gearshape", title: "Access Settings", description: "Click the gear icon in the Duplicates header to configure detection behavior.")
            
            HelpFeatureView(icon: "slider.horizontal.2.rectangle.and.arrow.triangle.2.circlepath", title: "Keep Strategy", description: "Choose what to keep by default: newest, oldest, largest, smallest, or shortest path.")
            
            HelpFeatureView(icon: "doc.text.magnifyingglass", title: "File Filters", description: "Set minimum file size, scan depth, and include/exclude specific file extensions.")
            
            HelpFeatureView(icon: "sparkles", title: "Semantic Duplicates", description: "Enable to find similar files (not just exact matches) using configurable similarity threshold.")
            
            Divider()
            
            Text("Safe Deletion Best Practices")
                .font(.headline)
            
            Text("• Keep Safe Deletion ON when first using the feature\n• Review the History tab periodically to confirm deletions\n• Flush the safe deletion cache only when you're certain\n• Use the Preview feature before bulk operations")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

private struct WatchedFoldersContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automatically organize new files dropped into specific folders.")
            
            HelpFeatureView(icon: "plus.circle", title: "Adding a Watched Folder", description: "Go to Settings → Watched Folders and click 'Add Folder'. Select the directory you want to monitor.")
            
            HelpFeatureView(icon: "gearshape.2.fill", title: "Per-Folder Settings", description: "Each watched folder can have its own persona, enabling different organization styles for different directories.")
            
            HelpFeatureView(icon: "bolt.fill", title: "Smart Drop Mode", description: "When enabled, only NEW files dropped into the root of the folder are organized. Existing files and nested contents are left untouched.")
            
            HelpFeatureView(icon: "arrow.triangle.2.circlepath", title: "Calibration", description: "Use 'Calibrate' to run a one-time full organization, establishing the folder structure that Smart Drop will use going forward.")
            
            Divider()
            
            Text("Tip: Watched folders work best for Downloads or Inbox-style directories where files arrive frequently.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

private struct ExclusionsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prevent specific files or folders from being organized or moved.")
            
            HelpFeatureView(icon: "xmark.circle", title: "Pattern Matching", description: "Exclude files by name pattern (e.g., '*.log' to exclude all log files).")
            
            HelpFeatureView(icon: "folder.badge.minus", title: "Folder Exclusions", description: "Exclude entire directories. Useful for system folders, node_modules, or virtual environments.")
            
            HelpFeatureView(icon: "doc.badge.gearshape", title: "Extension Filters", description: "Exclude specific file types (e.g., all .DS_Store or .gitignore files).")
            
            HelpFeatureView(icon: "ruler", title: "Size-Based Rules", description: "Exclude files above or below certain sizes (e.g., exclude files larger than 1GB).")
        }
    }
}

private struct WorkspaceHealthContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Analyze your workspace for potential issues and optimization opportunities.")
            
            HelpFeatureView(icon: "chart.pie.fill", title: "Space Analysis", description: "See how disk space is distributed across file types and folders.")
            
            HelpFeatureView(icon: "folder.fill.badge.questionmark", title: "Empty Folders", description: "Identify and optionally remove empty directories cluttering your workspace.")
            
            HelpFeatureView(icon: "clock.badge.exclamationmark", title: "Old Files", description: "Find files that haven't been accessed in over a year and may be candidates for archiving.")
            
            HelpFeatureView(icon: "exclamationmark.triangle.fill", title: "Broken Symlinks", description: "Detect symbolic links that point to non-existent targets.")
            
            HelpFeatureView(icon: "doc.on.doc.fill", title: "Duplicate Detection", description: "Quick summary of potential duplicate files in your workspace.")
        }
    }
}

private struct ShortcutsContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master Sorty with these keyboard shortcuts.")
            
            ShortcutSection(title: "Navigation", shortcuts: [
                ("⌘1", "Go to Organize"),
                ("⌘2", "Go to Workspace Health"),
                ("⌘3", "Go to Duplicates"),
                ("⌘4", "Go to Exclusions"),
                ("⌘,", "Open Settings"),
                ("⇧⌘H", "Open History"),
                ("⌘\\", "Toggle Sidebar")
            ])
            
            ShortcutSection(title: "File Operations", shortcuts: [
                ("⌘N", "New Session"),
                ("⌘O", "Open Directory"),
                ("⌘E", "Export Results"),
                ("⌘A", "Select All Files"),
                ("⌘Z", "Undo")
            ])
            
            ShortcutSection(title: "Organization", shortcuts: [
                ("⌘R", "Regenerate Preview"),
                ("⌘⏎", "Apply Changes"),
                ("⎋", "Cancel Operation")
            ])
        }
    }
}

private struct TroubleshootingContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Step-by-step guides for fixing common issues. Each section provides detailed diagnostic steps and solutions.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                // AI Provider Issues
                DetailedTroubleshootSection(
                    icon: "wifi.exclamationmark",
                    iconColor: .red,
                    problem: "AI Provider Not Responding",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Test Connection in Settings",
                            details: "Open Settings → AI Provider and click 'Test Connection'. If it fails, check the error message displayed."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Verify API Key",
                            details: "Log into your AI provider dashboard (OpenAI, Anthropic, etc.) and confirm: 1) The key is active, 2) You have available credits, 3) The key hasn't expired. Generate a new key if needed."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Check API URL Format",
                            details: "Ensure the URL matches your provider's requirements. OpenAI: https://api.openai.com/v1, Ollama: http://localhost:11434, Anthropic: https://api.anthropic.com/v1. Do not include trailing slashes."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Adjust Timeout Settings",
                            details: "Go to Settings → Advanced. Increase the timeout from 60s to 120s for slower connections. If using Ollama locally on an older Mac, consider 180s."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Check Network and Firewall",
                            details: "Verify your internet connection. Check if you're behind a corporate firewall or VPN that blocks AI provider APIs. Try accessing the provider's website in a browser. Temporarily disable VPN to test."
                        )
                    ]
                )
                
                // Ollama Specific Issues
                DetailedTroubleshootSection(
                    icon: "server.rack",
                    iconColor: .purple,
                    problem: "Ollama Local AI Issues",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Start Ollama Server",
                            details: "Open Terminal and run 'ollama serve' to start the server. You should see a message indicating it's listening on port 11434. Keep this Terminal window open while using Sorty."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Verify URL Configuration",
                            details: "In Sorty Settings → AI Provider, ensure the URL is exactly 'http://localhost:11434' (no trailing slash). If Ollama is on another machine, use its IP address instead of localhost."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Download Required Model",
                            details: "Run 'ollama pull llama4' (or your preferred model) in Terminal. The model must be fully downloaded before use. You can check available models with 'ollama list'."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Check Architecture Compatibility",
                            details: "On Apple Silicon Macs, ensure you're using the ARM-native version of Ollama, not the Intel version running under Rosetta. Check Activity Monitor - Ollama should show 'Apple' architecture, not 'Intel'."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Verify Port Availability",
                            details: "Run 'lsof -i :11434' in Terminal to check if Ollama is using the port. If another service is using this port, either stop that service or configure Ollama to use a different port."
                        )
                    ]
                )
                
                // File Operations Issues
                DetailedTroubleshootSection(
                    icon: "folder.badge.questionmark",
                    iconColor: .orange,
                    problem: "Files Not Moving or Organizing",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Check Exclusion Rules",
                            details: "Open the Exclusions tab and review active rules. Common culprits: '*.tmp' patterns, folder exclusions, or size limits. Temporarily disable exclusions to test if they're blocking your files."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Verify File Permissions",
                            details: "In Finder, right-click the folder and select 'Get Info' (⌘I). Check the 'Sharing & Permissions' section. Ensure your user account has 'Read & Write' access. If not, click the lock icon and change permissions."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Close Applications Using Files",
                            details: "Files cannot be moved if they're open in another app. Close Preview, TextEdit, or any other applications that might have files open. For stubborn locks, restart your Mac."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Check Available Disk Space",
                            details: "Open System Settings → General → Storage. Ensure you have at least 10% free space on the drive. Organization requires temporary space for file operations."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Verify Sandbox Permissions",
                            details: "The app runs in macOS Sandbox. If permissions were revoked, remove the folder from Sorty and re-add it to refresh the security bookmark. This forces macOS to re-prompt for permission."
                        )
                    ]
                )
                
                // Watched Folders Issues
                DetailedTroubleshootSection(
                    icon: "eye.slash",
                    iconColor: .cyan,
                    problem: "Watched Folders Not Working",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Confirm App Location",
                            details: "The app MUST be in /Applications for Watched Folders to work reliably. If it's in Downloads or Desktop, move it: 1) Quit Sorty, 2) Drag to /Applications, 3) Re-launch. Remove and re-add watched folders after moving."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Refresh Security Bookmarks",
                            details: "Bookmarks can become stale if folders move. Remove all watched folders in Settings, then add them back one by one. This refreshes the macOS security bookmarks that allow file access."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Check AI Provider Configuration",
                            details: "Watched Folders require a working AI provider. In Settings → AI Provider, confirm: Test Connection passes, timeout is reasonable (60s+), and you have API credits. Auto-organize won't work without valid AI configuration."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Verify Smart Drop Settings",
                            details: "If using Smart Drop mode, ensure the folder has been calibrated first. Click 'Calibrate' to perform an initial organization. Smart Drop only organizes NEW files dropped after calibration, not existing files."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Check Console for Errors",
                            details: "Open Console.app (from Applications → Utilities), search for 'Sorty', and look for error messages related to bookmarks or file monitoring. These logs help identify the root cause."
                        )
                    ]
                )
                
                // Performance Issues
                DetailedTroubleshootSection(
                    icon: "speedometer",
                    iconColor: .blue,
                    problem: "Slow Performance or High Resource Usage",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Disable Deep Scan",
                            details: "Go to Settings → Advanced and turn OFF 'Deep Scan'. Deep Scan reads file contents (PDF text, image EXIF) which significantly slows analysis, especially for large media files."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Add Exclusions for Large Directories",
                            details: "Exclude directories like node_modules, .git, build/, DerivedData/, or virtual environments. These contain thousands of small files that slow scanning. Go to Exclusions tab and add patterns like '*/node_modules/*'."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Enable Streaming Mode",
                            details: "In Settings → Advanced, enable 'Stream AI Responses'. This shows results progressively instead of waiting for the complete response, improving perceived performance."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Use Local AI for Large Batches",
                            details: "For organizing thousands of files, consider using Ollama (local) instead of cloud providers. Local models have no rate limits and can process large batches more efficiently."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Reduce Folder Size",
                            details: "If organizing 1000+ files, split into smaller batches (200-300 files). Sorty analyzes all files together, so smaller batches reduce memory usage and improve response times."
                        )
                    ]
                )
                
                // App Crashes or Freezes
                DetailedTroubleshootSection(
                    icon: "exclamationmark.triangle",
                    iconColor: .yellow,
                    problem: "App Crashes, Freezes, or Unexpected Behavior",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Check for Updates",
                            details: "Go to Help → Check for Updates. Many stability issues are fixed in newer versions. Install the latest release before troubleshooting further."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Clear App Data",
                            details: "Go to Help → Delete All Usage Data in the menu bar. This clears caches, temporary files, and resets some settings without affecting your files. Restart the app after clearing."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Reinstall the App",
                            details: "Delete Sorty.app from /Applications, empty trash, then reinstall the latest version. This ensures no corrupted files persist. Your settings are stored separately and will be preserved."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Check Console Logs",
                            details: "Open Console.app, filter by 'Sorty', and look for crash reports or error messages around the time the issue occurred. Look for 'Exception', 'Crash', or 'Error' keywords."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Reset NVRAM/PRAM (Advanced)",
                            details: "If issues persist, reset NVRAM: Restart your Mac and immediately hold Option-Command-P-R for 20 seconds. This clears low-level system settings that might affect app stability."
                        )
                    ]
                )
                
                // Finder Extension Issues
                DetailedTroubleshootSection(
                    icon: "puzzlepiece.extension",
                    iconColor: .green,
                    problem: "Finder Extension Not Appearing",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Enable in System Settings",
                            details: "Go to System Settings → Privacy & Security → Extensions → Finder Extensions. Ensure 'SortyExtension' is checked. If it's not listed, rebuild the extension target in Xcode."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Restart Finder",
                            details: "Option-click the Finder icon in the Dock and select 'Relaunch'. Or run 'killall Finder' in Terminal. The extension requires a Finder restart to activate after enabling."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Check App Group Configuration",
                            details: "The extension requires App Groups to communicate with the main app. In Xcode, ensure both Sorty and SortyExtension targets have the same App Group entitlement: 'group.com.sorty.app'."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Build Extension Target",
                            details: "In Xcode, select the 'SortyExtension' scheme and build it (⌘B). The extension is a separate target that must be built alongside the main app. Run the extension target at least once."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Grant Full Disk Access (If Needed)",
                            details: "Some directories require Full Disk Access. Go to System Settings → Privacy & Security → Full Disk Access. Add Sorty if it's not already there. This allows the extension to work in protected folders."
                        )
                    ]
                )
                
                // Update Issues
                DetailedTroubleshootSection(
                    icon: "arrow.down.circle.dotted",
                    iconColor: .pink,
                    problem: "Update Check or Download Fails",
                    steps: [
                        DiagnosticStep(
                            number: 1,
                            title: "Check Internet Connection",
                            details: "Verify you can access https://github.com/shirishpothi/Sorty in a web browser. The update system fetches data from GitHub's API and requires internet access."
                        ),
                        DiagnosticStep(
                            number: 2,
                            title: "Wait for Rate Limit Reset",
                            details: "GitHub API has rate limits (60 requests/hour for unauthenticated users). If you see 'Rate limited' errors, wait 60 minutes and try again."
                        ),
                        DiagnosticStep(
                            number: 3,
                            title: "Check Firewall Settings",
                            details: "Ensure your firewall or security software allows connections to api.github.com and github.com. Corporate networks may block these. Try with a different network if possible."
                        ),
                        DiagnosticStep(
                            number: 4,
                            title: "Manually Check for Updates",
                            details: "Compare your version (in About menu) with the latest release at https://github.com/shirishpothi/Sorty/releases. Download and install manually if automatic check fails."
                        ),
                        DiagnosticStep(
                            number: 5,
                            title: "Check Console for Errors",
                            details: "Open Console.app and search for 'Sorty' during an update check. Look for network errors, SSL issues, or JSON parsing failures that might indicate the problem."
                        )
                    ]
                )
            }
            
            // Error Code Reference
            VStack(alignment: .leading, spacing: 12) {
                Text("Common Error Codes")
                    .font(.headline)
                    .padding(.top, 16)
                
                Text("HTTP error codes from AI providers and what they mean:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                    ErrorBadge(code: "401", meaning: "Invalid API key", color: .red)
                    ErrorBadge(code: "403", meaning: "Forbidden/Rate limited", color: .orange)
                    ErrorBadge(code: "404", meaning: "Model not found", color: .yellow)
                    ErrorBadge(code: "429", meaning: "Too many requests", color: .orange)
                    ErrorBadge(code: "500", meaning: "Server error", color: .gray)
                    ErrorBadge(code: "503", meaning: "Service unavailable", color: .gray)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            
            // Getting More Help
            VStack(alignment: .leading, spacing: 12) {
                Text("Still Need Help?")
                    .font(.headline)
                
                Text("If these steps don't resolve your issue:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HelpFeatureView(icon: "doc.text", title: "Check the Logs", description: "Open Console.app, search for 'Sorty', and review error messages. See the Diagnostics section for detailed log collection steps.")
                    
                    HelpFeatureView(icon: "ladybug.fill", title: "Report an Issue", description: "Go to Help → Report an Issue to open GitHub with a pre-filled bug report template. Include your Console logs.")
                    
                    HelpFeatureView(icon: "book.fill", title: "Read Documentation", description: "Visit the GitHub repository for detailed guides: https://github.com/shirishpothi/Sorty")
                }
            }
            .padding(.top, 16)
        }
    }
}

private struct DiagnosticStep: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let details: String
}

private struct DetailedTroubleshootSection: View {
    let icon: String
    let iconColor: Color
    let problem: String
    let steps: [DiagnosticStep]
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(iconColor)
                        .frame(width: 32)
                    
                    Text(problem)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(iconColor.opacity(0.08))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(steps) { step in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text("\(step.number)")
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(iconColor)
                                    .clipShape(Circle())
                                
                                Text(step.title)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                            
                            Text(step.details)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 34)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .padding(.leading, 32)
            }
        }
    }
}

private struct TroubleshootSection: View {
    let icon: String
    let iconColor: Color
    let problem: String
    let solutions: [(icon: String, text: String)]
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(iconColor)
                        .frame(width: 32)
                    
                    Text(problem)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(iconColor.opacity(0.08))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(solutions, id: \.text) { solution in
                        HStack(spacing: 10) {
                            Image(systemName: solution.icon)
                                .font(.caption)
                                .foregroundColor(iconColor)
                                .frame(width: 20)
                            Text(solution.text)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.leading, 32)
            }
        }
    }
}

private struct ErrorBadge: View {
    let code: String
    let meaning: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(code)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color)
                .cornerRadius(6)
            Text(meaning)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Error Explanation Helper
private struct ErrorExplanation: View {
    let error: String
    let explanation: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(error)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.red)
            Text(explanation)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct PrivacyContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("We respect your privacy and are transparent about data handling.")
            
            HelpFeatureView(icon: "desktopcomputer", title: "Local Processing", description: "File scanning, analysis, and organization operations happen entirely on your Mac.")
            
            HelpFeatureView(icon: "cloud", title: "AI Provider", description: "File names and metadata are sent to your chosen AI provider (OpenAI, Ollama, or Apple Intelligence) for analysis. File contents are NOT uploaded unless Deep Scan is enabled.")
            
            HelpFeatureView(icon: "externaldrive.fill", title: "Local Storage", description: "Organization history, Safe Deletion metadata, and settings are stored locally on your Mac.")
            
            HelpFeatureView(icon: "trash.slash", title: "Clear Data", description: "You can delete all stored data via Help → Delete All Usage Data in the menu bar.")
            
            Divider()
            
            Text("For maximum privacy, use Ollama (local AI) or Apple Intelligence instead of cloud-based providers.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

private struct AboutContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            // App Icon
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            
            // App Name
            Text("Sorty")
                .font(.system(size: 32, weight: .bold, design: .rounded))
            
            // Description
            Text("Intelligently organize your files with AI. Learn from your patterns and keep your workspace tidy.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Divider()
                .frame(maxWidth: 300)
            
            // Version Info
            VStack(spacing: 6) {
                Text("Version \(BuildInfo.version)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text("Build \(BuildInfo.build)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.secondary)
                
                // Commit link
                if BuildInfo.hasValidCommit {
                    Link(destination: URL(string: "https://github.com/shirishpothi/Sorty/commit/\(BuildInfo.commit)")!) {
                        Text("Commit \(BuildInfo.shortCommit)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Commit \(BuildInfo.shortCommit)")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            // Update Status Area
            VStack(spacing: 8) {
                switch appState.updateManager.updateState {
                case .idle:
                    EmptyView()
                case .checking:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking for updates...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .available(let version, let releaseNotes):
                    VStack(spacing: 4) {
                        Text("New version available: \(version)")
                            .font(.headline)
                            .foregroundColor(.green)
                        Text("Use Check for Updates to install")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let notes = releaseNotes, !notes.isEmpty {
                            Text(notes.prefix(100) + (notes.count > 100 ? "..." : ""))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                case .upToDate:
                    Text("Sorty is up to date.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .error(let message):
                    VStack(spacing: 4) {
                        Text("Update check failed")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        Text(message)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.05))
                    .cornerRadius(6)
                case .downloading:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Downloading update...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .installing:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Installing update...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .disabled:
                    EmptyView()
                }
            }
            .frame(minHeight: 40, maxHeight: 100)
            
            Spacer().frame(height: 10)
            
            // Buttons
            HStack(spacing: 16) {
                Button(action: {
                    print("Update button clicked")
                    Task {
                        await appState.updateManager.checkForUpdates()
                    }
                }) {
                    Label("Check for Updates", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .disabled(appState.updateManager.updateState == .checking)

                Button(action: {
                    if let url = URL(string: "https://github.com/shirishpothi/Sorty#readme") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Documentation", systemImage: "book.fill")
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    if let url = URL(string: "https://github.com/shirishpothi/Sorty") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
            }
            
            Spacer().frame(height: 10)
            
            // Copyright
            Text("© 2024-2026 Shirish Pothi")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}

// MARK: - Diagnostics Content

private struct DiagnosticsContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Collect and review diagnostic information to troubleshoot issues or report bugs.")
                .font(.body)
            
            // Log Collection
            VStack(alignment: .leading, spacing: 12) {
                Text("Collecting Logs")
                    .font(.headline)
                
                Text("Console.app is the primary tool for reviewing Sorty logs on macOS.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HelpStepView(
                        number: 1,
                        title: "Open Console.app",
                        description: "Press ⌘Space, type 'Console', and press Enter. Or find it in Applications → Utilities."
                    )
                    
                    HelpStepView(
                        number: 2,
                        title: "Filter for Sorty Logs",
                        description: "In the search bar, type 'Sorty' and press Enter. This shows all log messages from the app."
                    )
                    
                    HelpStepView(
                        number: 3,
                        title: "Set Time Range",
                        description: "Click 'Now' button to see real-time logs, or adjust the time range to when the issue occurred."
                    )
                    
                    HelpStepView(
                        number: 4,
                        title: "Export Logs",
                        description: "Select relevant log entries, right-click, and choose 'Export Selected Items'. Save as a text file to include in bug reports."
                    )
                }
                
                Divider()
                
                Text("Important Log Categories")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Error messages")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Look for red error badges in Console. These indicate failures.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Network requests")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Search for your AI provider name (OpenAI, Anthropic) to see API calls.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "folder.badge.gear")
                            .foregroundColor(.orange)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("File operations")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Look for 'Bookmark' or 'Permission' messages when folders won't organize.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Divider()
            
            // System Information
            VStack(alignment: .leading, spacing: 12) {
                Text("System Information")
                    .font(.headline)
                
                Text("When reporting issues, include this information:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    SystemInfoRow(label: "Sorty Version", value: BuildInfo.version)
                    SystemInfoRow(label: "Build Number", value: BuildInfo.build)
                    SystemInfoRow(label: "macOS Version", value: ProcessInfo.processInfo.operatingSystemVersionString)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
                Button(action: {
                    copySystemInfo()
                }) {
                    Label("Copy System Info to Clipboard", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            // AI Provider Diagnostics
            VStack(alignment: .leading, spacing: 12) {
                Text("AI Provider Diagnostics")
                    .font(.headline)
                
                Text("Test your AI provider connection and view detailed diagnostics.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HelpFeatureView(
                        icon: "gear",
                        title: "Connection Test",
                        description: "Go to Settings → AI Provider and click 'Test Connection'. This verifies your API key, URL format, and network connectivity."
                    )
                    
                    HelpFeatureView(
                        icon: "clock",
                        title: "Response Times",
                        description: "Note the response time shown during organization. Cloud providers typically respond in 5-30 seconds. Local Ollama may take longer depending on your Mac's performance."
                    )
                    
                    HelpFeatureView(
                        icon: "dollarsign.circle",
                        title: "API Usage",
                        description: "Check your AI provider dashboard for usage statistics. High token usage may indicate Deep Scan is enabled unnecessarily."
                    )
                }
            }
            
            Divider()
            
            // Safe Data Review
            VStack(alignment: .leading, spacing: 12) {
                Text("Safe Data Review")
                    .font(.headline)
                
                Text("What data is safe to include in bug reports:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SAFE to share:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Error messages", systemImage: "checkmark.circle.fill")
                            Label("Sorty version", systemImage: "checkmark.circle.fill")
                            Label("macOS version", systemImage: "checkmark.circle.fill")
                            Label("General settings", systemImage: "checkmark.circle.fill")
                            Label("Persona names (not prompts)", systemImage: "checkmark.circle.fill")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DO NOT share:")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Label("API keys or tokens", systemImage: "xmark.circle.fill")
                            Label("File contents", systemImage: "xmark.circle.fill")
                            Label("Personal file paths", systemImage: "xmark.circle.fill")
                            Label("Learnings data", systemImage: "xmark.circle.fill")
                            Label("System passwords", systemImage: "xmark.circle.fill")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Report Issue Button
            VStack(alignment: .leading, spacing: 12) {
                Text("Report an Issue")
                    .font(.headline)
                
                Text("Once you have collected diagnostic information:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if let url = URL(string: "https://github.com/shirishpothi/Sorty/issues/new?template=bug_report.md") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Label("Open GitHub Issue", systemImage: "ladybug.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
    
    private func copySystemInfo() {
        let info = """
        Sorty Version: \(BuildInfo.version)
        Build: \(BuildInfo.build)
        Commit: \(BuildInfo.commit)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info, forType: .string)
    }
}

private struct SystemInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Helper Views

private struct HelpStepView: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HelpFeatureView: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutSection: View {
    let title: String
    let shortcuts: [(String, String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .padding(.top, 8)
            
            ForEach(shortcuts, id: \.0) { shortcut in
                HStack {
                    Text(shortcut.0)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .frame(width: 60, alignment: .leading)
                    Text(shortcut.1)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}



#Preview {
    HelpView()
        .environmentObject(AppState())
}

// MARK: - Updates Help Content

private struct UpdatesHelpContent: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sorty includes a built-in update checker that helps you stay current with the latest features and bug fixes.")
            
            // How to Check
            VStack(alignment: .leading, spacing: 12) {
                Text("Checking for Updates")
                    .font(.headline)
                
                HelpFeatureView(
                    icon: "arrow.down.circle",
                    title: "Manual Check",
                    description: "Go to Help → Check for Updates... to manually check for new versions."
                )
                
                HelpFeatureView(
                    icon: "bell.badge",
                    title: "Automatic Notifications",
                    description: "Sorty periodically checks for updates in the background and notifies you when a new version is available."
                )
                
                HelpFeatureView(
                    icon: "doc.text",
                    title: "Release Notes",
                    description: "When an update is available, you'll see release notes describing new features and bug fixes."
                )
            }
            
            Divider()
            
            // How it Works
            VStack(alignment: .leading, spacing: 12) {
                Text("How the Update System Works")
                    .font(.headline)
                
                Text("Sorty checks the GitHub Releases API for the latest version:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Text("1.")
                            .fontWeight(.bold)
                        Text("Fetches the latest release from github.com/shirishpothi/Sorty")
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("2.")
                            .fontWeight(.bold)
                        Text("Compares the remote version with your installed version")
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Text("3.")
                            .fontWeight(.bold)
                        Text("Shows a dialog if an update is available with download link")
                    }
                }
                .font(.callout)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Troubleshooting
            VStack(alignment: .leading, spacing: 12) {
                Text("Update Check Troubleshooting")
                    .font(.headline)
                
                TroubleshootSection(
                    icon: "arrow.down.circle.dotted",
                    iconColor: .orange,
                    problem: "Update Check Failed",
                    solutions: [
                        ("wifi", "Check internet connection"),
                        ("clock", "Rate limit - wait 60 minutes"),
                        ("shield", "Firewall may block api.github.com"),
                        ("arrow.clockwise", "Try again later")
                    ]
                )
                
                HStack(spacing: 16) {
                    ErrorBadge(code: "403", meaning: "Rate limited", color: .orange)
                    ErrorBadge(code: "404", meaning: "No releases yet", color: .gray)
                }
                .padding(.top, 8)
            }
            
            // Check Now Button
            Divider()
            
            Button(action: {
                appState.updateManager.checkForUpdates()
            }) {
                Label("Check for Updates Now", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct CLIDeepLinksContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sorty supports powerful automation via deep links and a command-line interface.")
            
            // App Deep Links Section
            VStack(alignment: .leading, spacing: 12) {
                Text("App Deep Links")
                    .font(.headline)
                
                Text("Control the app via standard URL schemes:")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                // Organization
                DeepLinkSection(title: "Organization", routes: [
                    DeepLinkRow(title: "Organize Folder", url: "sorty://organize?path=/Downloads&persona=developer"),
                    DeepLinkRow(title: "Scan Duplicates", url: "sorty://duplicates?path=/&autostart=true")
                ])
                
                // Management
                DeepLinkSection(title: "Management", routes: [
                    DeepLinkRow(title: "Generate Persona", url: "sorty://persona?action=generate&prompt=..."),
                    DeepLinkRow(title: "Add Watched Folder", url: "sorty://watched?action=add&path=..."),
                    DeepLinkRow(title: "Add Exclusion Rule", url: "sorty://rules?action=add&pattern=*.log")
                ])
                
                // Navigation
                DeepLinkSection(title: "Navigation", routes: [
                    DeepLinkRow(title: "Open Settings", url: "sorty://settings"),
                    DeepLinkRow(title: "View History", url: "sorty://history")
                ])
            }
            
            Divider()
            
            // CLI Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Command Line Interface (CLI)")
                    .font(.headline)
                
                Text("The 'sorty' tool allows you to control the app from your terminal.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("Organization")
                        .font(.caption)
                        .fontWeight(.bold)
                    CLICodeBlock(cmd: "sorty organize . --auto", desc: "Organize current folder")
                    CLICodeBlock(cmd: "sorty organize ~/Downloads --persona developer", desc: "Organize with specific persona")
                    
                    Text("Maintenance")
                        .font(.caption)
                        .fontWeight(.bold)
                    CLICodeBlock(cmd: "sorty rules add \"*.tmp\"", desc: "Add exclusion rule")
                    CLICodeBlock(cmd: "sorty persona generate \"Organize by date\"", desc: "Generate new persona")
                }
            }
            
            tipCard(icon: "terminal.fill", title: "Installation", message: "Run 'make install' to add 'sorty' to your path, or find it in the CLI/ directory.")
        }
    }
}

private struct DeepLinkSection: View {
    let title: String
    let routes: [DeepLinkRow]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            
            ForEach(routes.indices, id: \.self) { index in
                routes[index]
            }
        }
    }
}

private struct DeepLinkRow: View {
    let title: String
    let url: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack {
                Text(url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.accentColor)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
        }
    }
}

private struct CLICodeBlock: View {
    let cmd: String
    let desc: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(desc)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack {
                Text("$ \(cmd)")
                    .font(.system(.caption, design: .monospaced))
                Spacer()
            }
            .padding(8)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.green)
            .cornerRadius(6)
        }
    }
}

private func tipCard(icon: String, title: String, message: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
            .foregroundColor(.blue)
        
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
    .padding()
    .background(Color.blue.opacity(0.1))
    .cornerRadius(8)
}

// MARK: - Downloads Content

private enum DownloadState {
    case idle
    case downloading
    case completed(URL)
    case failed(String)
    case installing
    case installed
    case installFailed(String)
}

private struct DownloadsContent: View {
    @State private var cliDownloadState: DownloadState = .idle
    
    private let repoOwner = "shirishpothi"
    private let repoName = "Sorty"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Download additional Sorty resources directly from GitHub Releases.")
                .font(.body)
            
            // CLI Tool Download Card
            DownloadCard(
                icon: "terminal.fill",
                title: "Command Line Tool",
                description: "Control Sorty from your terminal. Install to /usr/local/bin for easy access.",
                fileName: "Sorty-CLI.zip",
                downloadState: cliDownloadState,
                onDownload: { await downloadAsset(name: "Sorty-CLI.zip", state: $cliDownloadState) },
                onInstall: { url in await installCLI(from: url) },
                isCLI: true
            )
            
            // Source Code Link
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source Code")
                        .font(.headline)
                    Text("Available as auto-generated archives on the GitHub Releases page.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Link(destination: URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!) {
                    Label("View Releases", systemImage: "arrow.up.right")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            Divider()
            
            // Manual Download Option
            VStack(alignment: .leading, spacing: 8) {
                Text("Manual Download")
                    .font(.headline)
                
                Text("You can also download these files directly from the GitHub Releases page:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Link(destination: URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")!) {
                    HStack {
                        Image(systemName: "safari")
                        Text("Open GitHub Releases")
                    }
                }
                .buttonStyle(.link)
            }
            
            Divider()
            
            // CLI Installation Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("CLI Installation")
                    .font(.headline)
                
                Text("After downloading, install the CLI tool:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 8) {
                    CLICodeBlock(cmd: "unzip Sorty-CLI.zip", desc: "Extract the archive")
                    CLICodeBlock(cmd: "chmod +x sorty", desc: "Make it executable")
                    CLICodeBlock(cmd: "sudo mv sorty /usr/local/bin/", desc: "Install to PATH")
                    CLICodeBlock(cmd: "sorty --version", desc: "Verify installation")
                }
            }
        }
    }
    
    private func downloadAsset(name: String, state: Binding<DownloadState>) async {
        state.wrappedValue = .downloading
        
        // Get latest release info from GitHub
        let apiURL = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
        
        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("Sorty/\(BuildInfo.version)", forHTTPHeaderField: "User-Agent")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                state.wrappedValue = .failed("Failed to fetch release info")
                return
            }
            
            // Parse JSON to find the asset URL
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]] else {
                state.wrappedValue = .failed("Invalid release data")
                return
            }
            
            // Find the matching asset
            guard let asset = assets.first(where: { ($0["name"] as? String) == name }),
                  let downloadURLString = asset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                state.wrappedValue = .failed("Asset '\(name)' not found in latest release")
                return
            }
            
            // Download the file
            let (fileURL, _) = try await URLSession.shared.download(from: downloadURL)
            
            // Move to Downloads folder
            let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let destinationURL = downloadsURL.appendingPathComponent(name)
            
            // Remove existing file if present
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: fileURL, to: destinationURL)
            
            state.wrappedValue = .completed(destinationURL)
            
            // Open in Finder
            NSWorkspace.shared.selectFile(destinationURL.path, inFileViewerRootedAtPath: downloadsURL.path)
            
        } catch {
            state.wrappedValue = .failed(error.localizedDescription)
        }
    }
    
    private func installCLI(from zipURL: URL) async {
        cliDownloadState = .installing
        
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipURL.path, "-d", tempDir.path]
            unzipProcess.standardOutput = FileHandle.nullDevice
            unzipProcess.standardError = FileHandle.nullDevice
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            guard unzipProcess.terminationStatus == 0 else {
                cliDownloadState = .installFailed("Failed to extract archive")
                return
            }
            
            let extractedBinary = tempDir.appendingPathComponent("sorty")
            guard fileManager.fileExists(atPath: extractedBinary.path) else {
                cliDownloadState = .installFailed("Binary 'sorty' not found in archive")
                return
            }
            
            let installPath = "/usr/local/bin/sorty"
            let script = """
                do shell script "mkdir -p /usr/local/bin && mv '\(extractedBinary.path)' '\(installPath)' && chmod +x '\(installPath)'" with administrator privileges
            """
            
            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else {
                cliDownloadState = .installFailed("Failed to create installation script")
                return
            }
            
            appleScript.executeAndReturnError(&error)
            
            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Installation cancelled or failed"
                cliDownloadState = .installFailed(errorMessage)
                return
            }
            
            guard fileManager.fileExists(atPath: installPath),
                  fileManager.isExecutableFile(atPath: installPath) else {
                cliDownloadState = .installFailed("Installation verification failed")
                return
            }
            
            try? fileManager.removeItem(at: tempDir)
            
            cliDownloadState = .installed
            
        } catch {
            try? fileManager.removeItem(at: tempDir)
            cliDownloadState = .installFailed(error.localizedDescription)
        }
    }
}

private struct DownloadCard: View {
    let icon: String
    let title: String
    let description: String
    let fileName: String
    let downloadState: DownloadState
    let onDownload: () async -> Void
    var onInstall: ((URL) async -> Void)?
    var isCLI: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                HStack {
                    switch downloadState {
                    case .idle:
                        Button(action: {
                            Task { await onDownload() }
                        }) {
                            Label("Download \(fileName)", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        
                    case .downloading:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Downloading...")
                                .foregroundColor(.secondary)
                        }
                        
                    case .completed(let url):
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Downloaded to \(url.lastPathComponent)")
                                    .foregroundColor(.secondary)
                                
                                Button("Show in Finder") {
                                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                                }
                                .buttonStyle(.link)
                            }
                            
                            if isCLI, let onInstall = onInstall {
                                Button(action: {
                                    Task { await onInstall(url) }
                                }) {
                                    Label("Install Now", systemImage: "arrow.right.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        
                    case .installing:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing to /usr/local/bin...")
                                .foregroundColor(.secondary)
                        }
                        
                    case .installed:
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Installed successfully! Run 'sorty --version' to verify.")
                                .foregroundColor(.secondary)
                        }
                        
                    case .installFailed(let error):
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            
                            Text("You can still install manually using the instructions below.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    case .failed(let error):
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .foregroundColor(.secondary)
                                .font(.caption)
                            
                            Button("Retry") {
                                Task { await onDownload() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }
}

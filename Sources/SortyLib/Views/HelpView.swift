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
    case troubleshooting
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
        case .troubleshooting: return "Troubleshooting"
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
        case .troubleshooting: return "wrench.and.screwdriver.fill"
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
        case .troubleshooting:
            TroubleshootingContent()
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Use the guides below to diagnose and fix common issues. If problems persist, check the GitHub Issues page or contact support.")
                .font(.body)
                .foregroundColor(.secondary)
            
            // API Connection Issues
            TroubleshootItem(
                problem: "AI Not Responding or Connection Failed",
                solutions: [
                    "Step 1: Click 'Test Connection' in Settings to verify connectivity",
                    "Step 2: For OpenAI - verify your API key is correct and has credits",
                    "Step 3: Check the API URL (should be 'https://api.openai.com' for OpenAI)",
                    "Step 4: Try a different model (e.g., 'gpt-3.5-turbo' instead of 'gpt-4')",
                    "Step 5: Increase Request Timeout to 120s in Advanced Settings",
                    "Step 6: Check if you're behind a proxy or firewall blocking API access"
                ]
            )
            
            // Ollama Specific Issues
            TroubleshootItem(
                problem: "Ollama Connection Issues",
                solutions: [
                    "Ensure Ollama is running: open Terminal and run 'ollama serve'",
                    "Verify the server URL (default: http://localhost:11434)",
                    "Check if the model is downloaded: run 'ollama list' in Terminal",
                    "Download missing models: run 'ollama pull llama3' in Terminal",
                    "If using Apple Silicon, ensure Ollama is ARM-native for best performance",
                    "For remote Ollama servers, enable API Key authentication if required"
                ]
            )
            
            // Files Not Moving
            TroubleshootItem(
                problem: "Files Not Moving After Apply",
                solutions: [
                    "Check Exclusion Rules in Settings to ensure files aren't protected",
                    "Verify you have read/write permissions for both source and destination",
                    "Ensure files aren't locked by another application (close other apps)",
                    "Check for special characters in file names that may cause issues",
                    "Verify sufficient disk space for file operations",
                    "Try running Sorty with elevated permissions (right-click → Open)"
                ]
            )
            
            // Crash Recovery
            TroubleshootItem(
                problem: "App Crashed or Unexpected Behavior",
                solutions: [
                    "Files in History tab can be reverted if the operation was interrupted",
                    "Check ~/Library/Preferences/ for backup settings if needed",
                    "Force quit and restart the app if it becomes unresponsive",
                    "Clear app cache: Help → Delete All Usage Data",
                    "If crashes persist, check Console.app for crash logs",
                    "Report persistent crashes on GitHub with system details"
                ]
            )
            
            // Performance
            TroubleshootItem(
                problem: "Slow Organization or High CPU Usage",
                solutions: [
                    "Disable Deep Scan for faster processing (uses less CPU)",
                    "Use exclusion rules to skip large folders (node_modules, .git)",
                    "Enable Streaming for progressive updates instead of waiting",
                    "For 1000+ files, consider organizing in smaller batches",
                    "Lower AI temperature for faster, more deterministic results",
                    "Use a local model (Ollama) for faster response times"
                ]
            )
            
            // Tags Not Working
            TroubleshootItem(
                problem: "Finder Tags Not Appearing",
                solutions: [
                    "Ensure 'Enable File Tagging' is ON in Settings",
                    "Tags only apply when you click 'Apply Changes'",
                    "Refresh Finder: close and reopen the folder window",
                    "Check File Info (⌘I) to see if tags were applied",
                    "Enable 'Include Reasoning' to see if AI suggests tags",
                    "Some file types may not support extended attributes for tags"
                ]
            )
            
            // Common Error Messages
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Common Error Messages")
                    .font(.headline)
                
                ErrorExplanation(
                    error: "Error 401: Unauthorized",
                    explanation: "Your API key is invalid or expired. Check your key in Settings."
                )
                
                ErrorExplanation(
                    error: "Error 429: Rate Limited",
                    explanation: "Too many requests. Wait a few minutes or upgrade your API plan."
                )
                
                ErrorExplanation(
                    error: "Connection Refused",
                    explanation: "The server is not reachable. Check URL and network connection."
                )
                
                ErrorExplanation(
                    error: "Model Not Found",
                    explanation: "The specified model doesn't exist. Check model name in Settings."
                )
            }
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
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
                switch appState.updateManager.state {
                case .idle:
                    EmptyView()
                case .checking:
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Checking for updates...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .available(let version, let url, _):
                    VStack(spacing: 4) {
                        Text("New version available: \(version)")
                            .font(.headline)
                            .foregroundColor(.green)
                        Button("Download Update") {
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
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
                }
            }
            .frame(minHeight: 40, maxHeight: 100)
            
            Spacer().frame(height: 10)
            
            // Buttons
            HStack(spacing: 16) {
                Button(action: {
                    Task {
                        await appState.updateManager.checkForUpdates()
                    }
                }) {
                    Label("Check for Updates", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(.bordered)
                .disabled(appState.updateManager.state == .checking)

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

private struct TroubleshootItem: View {
    let problem: String
    let solutions: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text(problem)
                    .font(.headline)
            }
            
            ForEach(solutions, id: \.self) { solution in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(solution)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 24)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
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
                
                TroubleshootItem(
                    problem: "Update Check Failed",
                    solutions: [
                        "Check your internet connection",
                        "GitHub API rate limit may be exceeded - wait 60 minutes",
                        "Firewall may be blocking api.github.com",
                        "Try again later if GitHub is experiencing issues"
                    ]
                )
                
                ErrorExplanation(
                    error: "Error 403: Rate Limited",
                    explanation: "GitHub limits API requests. Wait an hour and try again."
                )
                
                ErrorExplanation(
                    error: "Error 404: Not Found",
                    explanation: "No releases published yet. You have the latest version."
                )
            }
            
            // Check Now Button
            Divider()
            
            Button(action: {
                Task {
                    await appState.updateManager.checkForUpdates()
                }
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
                
                Text("The 'fileorg' tool allows you to control the app from your terminal.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("Organization")
                        .font(.caption)
                        .fontWeight(.bold)
                    CLICodeBlock(cmd: "fileorg organize . --auto", desc: "Organize current folder")
                    CLICodeBlock(cmd: "fileorg organize ~/Downloads --persona developer", desc: "Organize with specific persona")
                    
                    Text("Maintenance")
                        .font(.caption)
                        .fontWeight(.bold)
                    CLICodeBlock(cmd: "fileorg rules add \"*.tmp\"", desc: "Add exclusion rule")
                    CLICodeBlock(cmd: "fileorg persona generate \"Organize by date\"", desc: "Generate new persona")
                }
            }
            
            tipCard(icon: "terminal.fill", title: "Installation", message: "Run 'make install' to add 'fileorg' to your path, or find it in the CLI/ directory.")
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

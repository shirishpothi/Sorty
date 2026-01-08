//
//  AppCommands.swift
//  Sorty
//
//  Comprehensive menu bar commands with keyboard shortcuts
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - App Commands

public struct SortyCommands: Commands {
    @ObservedObject var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sorty") {
                appState.showAbout()
            }
            
            Button("Check for Updates...") {
                Task {
                    await appState.updateManager.checkForUpdates()
                }
            }
        }

        // Replace default New/Open with custom commands
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appState.resetSession()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open Directory...") {
                appState.showDirectoryPicker = true
            }
            .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("Export Results...") {
                appState.exportResults()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!appState.hasResults)
        }

        // Edit menu additions
        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Select All Files") {
                appState.selectAllFiles()
            }
            .keyboardShortcut("a", modifiers: .command)
            .disabled(!appState.hasFiles)
        }

        // View menu - use CommandGroup to add to existing View menu, not create a new one
        CommandGroup(replacing: .sidebar) {
            Button(appState.showingSidebar ? "Hide Sidebar" : "Show Sidebar") {
                appState.showingSidebar.toggle()
            }
            .keyboardShortcut("\\", modifiers: .command)
        }
        
        // Navigation commands added to View menu
        CommandGroup(after: .sidebar) {
            Divider()
            
            // Main Views section
            Text("Navigation")
                .font(.caption)
            
            Button("Organize") {
                appState.currentView = .organize
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Workspace Health") {
                appState.currentView = .workspaceHealth
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Duplicates") {
                appState.currentView = .duplicates
            }
            .keyboardShortcut("3", modifiers: .command)
            
            Button("The Learnings") {
                appState.currentView = .learnings
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            // Configuration Views section
            Button("Settings") {
                appState.currentView = .settings
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("History") {
                appState.currentView = .history
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Exclusions") {
                appState.currentView = .exclusions
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Watched Folders") {
                appState.currentView = .watchedFolders
            }
            .keyboardShortcut("5", modifiers: .command)
        }

        // Organize menu
        CommandMenu("Organize") {
            Button("Start Organization") {
                appState.startOrganization()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!appState.canStartOrganization)

            Button("Regenerate Organization") {
                appState.regenerateOrganization()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!appState.hasCurrentPlan)

            Divider()

            Button("Apply Changes") {
                appState.applyChanges()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!appState.canApply)

            Button("Preview Changes") {
                appState.previewChanges()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!appState.hasCurrentPlan)

            Divider()

            Button("Cancel") {
                appState.cancelOperation()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!appState.isOperationInProgress)
        }

        // Learnings menu
        CommandMenu("Learnings") {
            Button("Open Dashboard") {
                appState.currentView = .learnings
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            
            Divider()
            
            Button("Start Honing Session") {
                appState.startHoningSession()
            }
            .keyboardShortcut("h", modifiers: [.command, .option])
            
            Button("View Statistics") {
                appState.showLearningsStats()
            }
            
            Divider()
            
            Button("Pause Learning") {
                appState.pauseLearning()
            }
            
            Button("Export Learning Profile...") {
                appState.exportLearningsProfile()
            }
            
            Button("Import Learning Profile...") {
                appState.importLearningsProfile()
            }
        }

        // Help menu additions
        CommandGroup(replacing: .help) {
            Button("Sorty Help") {
                appState.showHelp()
            }
            .keyboardShortcut("?", modifiers: .command)

            Button("Delete All Usage Data") {
                appState.deleteUsageData()
            }
            
            Divider()
            
            Link("GitHub Repository", destination: URL(string: "https://github.com/shirishpothi/Sorty")!)

            Divider()

            Button("About Sorty") {
                appState.showAbout()
            }
            
            Button("Check for Updates...") {
                Task {
                    await appState.updateManager.checkForUpdates()
                }
            }
        }
    }
}

// MARK: - App State

@MainActor
public class AppState: ObservableObject {
    @Published public var currentView: AppView = .organize
    @Published public var showingSidebar: Bool = true
    @Published public var showDirectoryPicker: Bool = false
    @Published public var selectedDirectory: URL?
    @Published public var updateManager = UpdateManager()

    // State derived from FolderOrganizer
    public weak var organizer: FolderOrganizer?
    public var calibrateAction: ((WatchedFolder) -> Void)?
    
    // Window controllers - retained to prevent use-after-free crashes
    // These MUST be retained to keep windows alive during animations
    private var aboutWindowController: NSWindowController?
    private var helpWindowController: NSWindowController?

    public enum AppView: Equatable, Sendable {
        case settings
        case organize
        case history
        case workspaceHealth
        case duplicates
        case exclusions
        case watchedFolders
        case learnings
    }

    public init() {}

    public var hasResults: Bool {
        organizer?.currentPlan != nil && organizer?.state == .completed
    }

    public var hasFiles: Bool {
        organizer?.currentPlan != nil
    }

    public var canStartOrganization: Bool {
        selectedDirectory != nil && (organizer?.state == .idle || organizer?.state == .completed)
    }

    public var hasCurrentPlan: Bool {
        organizer?.currentPlan != nil
    }

    public var canApply: Bool {
        organizer?.state == .ready
    }

    public var isOperationInProgress: Bool {
        guard let state = organizer?.state else { return false }
        switch state {
        case .scanning, .organizing, .applying:
            return true
        default:
            return false
        }
    }

    public func resetSession() {
        selectedDirectory = nil
        organizer?.reset()
    }

    public func exportResults() {
        guard let plan = organizer?.currentPlan else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json, .html]
        panel.nameFieldStringValue = "organization_results_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-"))"
        panel.message = "Export Organization Results"
        panel.canSelectHiddenExtension = true
        
        // Add accessory view for format selection
        let formatPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 30), pullsDown: false)
        formatPopup.addItems(withTitles: ["CSV (Spreadsheet)", "JSON (Machine-readable)", "HTML (Report)"])
        panel.accessoryView = formatPopup

        if panel.runModal() == .OK, let url = panel.url {
            let selectedFormat = formatPopup.indexOfSelectedItem
            
            do {
                let content: String
                var finalURL = url
                
                switch selectedFormat {
                case 0: // CSV
                    content = generateCSV(from: plan)
                    if !finalURL.pathExtension.lowercased().contains("csv") {
                        finalURL = finalURL.deletingPathExtension().appendingPathExtension("csv")
                    }
                case 1: // JSON
                    content = generateJSON(from: plan)
                    if !finalURL.pathExtension.lowercased().contains("json") {
                        finalURL = finalURL.deletingPathExtension().appendingPathExtension("json")
                    }
                case 2: // HTML
                    content = generateHTML(from: plan)
                    if !finalURL.pathExtension.lowercased().contains("html") {
                        finalURL = finalURL.deletingPathExtension().appendingPathExtension("html")
                    }
                default:
                    content = generateCSV(from: plan)
                }
                
                try content.write(to: finalURL, atomically: true, encoding: .utf8)
                HapticFeedbackManager.shared.success()
                
                // Open the exported file
                NSWorkspace.shared.open(finalURL)
            } catch {
                DebugLogger.log("Failed to export results: \(error)")
                HapticFeedbackManager.shared.error()
            }
        }
    }

    private func generateCSV(from plan: OrganizationPlan) -> String {
        var csv = "Original File,Original Path,New Location,Reasoning,Tags\n"

        func processSuggestion(_ suggestion: FolderSuggestion, parentPath: String) {
            let folderPath = parentPath + "/" + suggestion.folderName
            for file in suggestion.files {
                let originalName = file.displayName
                let originalPath = file.path
                let destination = folderPath + "/" + (suggestion.renameMapping(for: file)?.suggestedName ?? originalName)
                let reasoning = suggestion.reasoning
                let tags = suggestion.semanticTags.joined(separator: "; ")
                
                csv += "\(csvEscape(originalName)),\"\(csvEscape(originalPath))\",\(csvEscape(destination)),\(csvEscape(reasoning)),\"\(csvEscape(tags))\"\n"
            }
            for sub in suggestion.subfolders {
                processSuggestion(sub, parentPath: folderPath)
            }
        }

        for suggestion in plan.suggestions {
            processSuggestion(suggestion, parentPath: "")
        }

        return csv
    }
    
    private func generateJSON(from plan: OrganizationPlan) -> String {
        struct ExportEntry: Codable {
            let originalFile: String
            let originalPath: String
            let destinationPath: String
            let reasoning: String
            let tags: [String]
        }
        
        struct ExportData: Codable {
            let exportDate: String
            let totalFiles: Int
            let totalFolders: Int
            let entries: [ExportEntry]
        }
        
        var entries: [ExportEntry] = []
        var folderCount = 0
        
        func processSuggestion(_ suggestion: FolderSuggestion, parentPath: String) {
            let folderPath = parentPath + "/" + suggestion.folderName
            folderCount += 1
            
            for file in suggestion.files {
                let destination = folderPath + "/" + (suggestion.renameMapping(for: file)?.suggestedName ?? file.displayName)
                entries.append(ExportEntry(
                    originalFile: file.displayName,
                    originalPath: file.path,
                    destinationPath: destination,
                    reasoning: suggestion.reasoning,
                    tags: suggestion.semanticTags
                ))
            }
            for sub in suggestion.subfolders {
                processSuggestion(sub, parentPath: folderPath)
            }
        }
        
        for suggestion in plan.suggestions {
            processSuggestion(suggestion, parentPath: "")
        }
        
        let exportData = ExportData(
            exportDate: ISO8601DateFormatter().string(from: Date()),
            totalFiles: entries.count,
            totalFolders: folderCount,
            entries: entries
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let jsonData = try? encoder.encode(exportData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{\"error\": \"Failed to encode\"}"
    }
    
    private func generateHTML(from plan: OrganizationPlan) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Sorty Export</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 1200px; margin: 0 auto; padding: 20px; background: #f5f5f7; }
                h1 { color: #1d1d1f; margin-bottom: 10px; }
                .meta { color: #6e6e73; margin-bottom: 30px; }
                .folder { background: white; border-radius: 12px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
                .folder-name { font-size: 18px; font-weight: 600; color: #1d1d1f; margin-bottom: 8px; }
                .reasoning { color: #6e6e73; font-size: 14px; margin-bottom: 12px; font-style: italic; }
                .files { font-size: 14px; }
                .file { padding: 8px 0; border-bottom: 1px solid #e5e5e5; display: flex; justify-content: space-between; }
                .file:last-child { border-bottom: none; }
                .file-name { font-weight: 500; }
                .file-path { color: #6e6e73; font-size: 12px; }
                .tag { background: #007aff; color: white; padding: 2px 8px; border-radius: 10px; font-size: 11px; margin-right: 4px; }
            </style>
        </head>
        <body>
            <h1>📁 Sorty Export</h1>
            <p class="meta">Generated on \(Date().formatted(date: .long, time: .shortened))</p>
        """
        
        func processSuggestion(_ suggestion: FolderSuggestion, parentPath: String, depth: Int) {
            let folderPath = parentPath.isEmpty ? suggestion.folderName : parentPath + "/" + suggestion.folderName
            
            html += """
            <div class="folder" style="margin-left: \(depth * 20)px;">
                <div class="folder-name">📂 \(suggestion.folderName)</div>
                <div class="reasoning">\(suggestion.reasoning)</div>
            """
            
            if !suggestion.semanticTags.isEmpty {
                html += "<div class=\"tags\">"
                for tag in suggestion.semanticTags {
                    html += "<span class=\"tag\">\(tag)</span>"
                }
                html += "</div>"
            }
            
            if !suggestion.files.isEmpty {
                html += "<div class=\"files\">"
                for file in suggestion.files {
                    let newName = suggestion.renameMapping(for: file)?.suggestedName
                    html += """
                    <div class="file">
                        <div>
                            <span class="file-name">\(htmlEscape(file.displayName))</span>
                            \(newName != nil ? "<span style='color:#6e6e73;'> → \(htmlEscape(newName!))</span>" : "")
                        </div>
                        <span class="file-path">\(htmlEscape(file.path))</span>
                    </div>
                    """
                }
                html += "</div>"
            }
            
            html += "</div>"
            
            for sub in suggestion.subfolders {
                processSuggestion(sub, parentPath: folderPath, depth: depth + 1)
            }
        }
        
        for suggestion in plan.suggestions {
            processSuggestion(suggestion, parentPath: "", depth: 0)
        }
        
        html += """
        </body>
        </html>
        """
        
        return html
    }

    public func selectAllFiles() {
        // TODO: Implement select all
    }

    public func startOrganization() {
        guard let organizer = organizer, let directory = selectedDirectory else { return }
        Task {
            try? await organizer.organize(directory: directory)
        }
    }

    public func regenerateOrganization() {
        guard let organizer = organizer else { return }
        Task {
            try? await organizer.regeneratePreview()
        }
    }

    public func applyChanges() {
        guard let organizer = organizer, let directory = selectedDirectory else { return }
        Task {
            try? await organizer.apply(at: directory)
        }
    }

    public func previewChanges() {
        // Navigation to preview is handled by view logic
    }

    public func cancelOperation() {
        organizer?.reset()
    }

    public func showHelp(initialSection: HelpSection = .gettingStarted) {
        // Reuse existing window if still open
        if let existingController = helpWindowController,
           let existingWindow = existingController.window,
           existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        // Create new window with proper lifecycle management
        let helpView = HelpView(initialSection: initialSection)
            .environmentObject(self)
        let hostingController = NSHostingController(rootView: helpView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Sorty Help"
        window.center()
        
        // Create and retain the window controller to prevent deallocation during animations
        let controller = NSWindowController(window: window)
        helpWindowController = controller
        controller.showWindow(nil)
    }
    
    // MARK: - Learnings Actions
    
    public func startHoningSession() {
        currentView = .learnings
        // Post notification to trigger honing in the Learnings view
        NotificationCenter.default.post(name: .startHoningSession, object: nil)
    }
    
    public func showLearningsStats() {
        currentView = .learnings
        // Post notification to show stats tab
        NotificationCenter.default.post(name: .showLearningsStats, object: nil)
    }
    
    public func pauseLearning() {
        // Post notification to pause learning
        NotificationCenter.default.post(name: .pauseLearning, object: nil)
    }
    
    public func exportLearningsProfile() {
        currentView = .learnings
        // Post notification to trigger export
        NotificationCenter.default.post(name: .exportLearningsProfile, object: nil)
    }
    
    public func importLearningsProfile() {
        currentView = .learnings
        // Post notification to trigger import
        NotificationCenter.default.post(name: .importLearningsProfile, object: nil)
    }
    
    public func deleteUsageData() {
        DuplicateRestorationManager.shared.clearAllData()
        // Could also clear history key if desired
        // UserDefaults.standard.removeObject(forKey: "organizationHistory")
    }
    
    public func showAbout() {
        // Open Help window with About section selected
        showHelp(initialSection: .about)
    }
    
    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    private func htmlEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

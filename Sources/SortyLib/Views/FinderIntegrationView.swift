//
//  FinderIntegrationView.swift
//  Sorty
//
//  Settings view for configuring Finder integration options
//  Toolbar button, Quick Action, Menu Bar, and keyboard shortcuts
//

import SwiftUI
import AppKit

public struct FinderIntegrationView: View {
    @State private var integrationStatus = ExtensionCommunication.FinderIntegrationStatus.empty
    @State private var isInstalling = false
    @State private var installationResults: [(name: String, success: Bool, message: String)] = []
    @State private var showingInstructions = false
    @State private var showCLITools = false
    @State private var frontmostFinderFolder: URL?
    @AppStorage("globalShortcutEnabled") private var globalShortcutEnabled = false
    @StateObject private var shortcutManager = GlobalShortcutManager.shared
    @EnvironmentObject private var automationManager: AutomationManager

    public init() {}
    
    public var body: some View {
        if !FeatureFlags.finderSyncEnabled {
            VStack(spacing: 16) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Finder Integration is currently disabled.")
                    .font(.title3)
                Text("This feature is behind a feature flag. Enable it by running:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("defaults write com.sorty.app finderIntegrationEnabled -bool true")
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(8)
                    .textSelection(.enabled)
                Text("Then relaunch Sorty.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    headerSection

                    // Status Overview
                    statusOverview

                    // Integration Options
                    integrationOptions

                    // Finder workflow status and mini preview
                    finderWorkflowStatusSection

                    // Automation Permission
                    automationPermissionSection

                    // Optional CLI Tools
                    optionalCLIToolsSection

                    // Instructions
                    if showingInstructions {
                        instructionsSection
                    }

                    // Installation Results
                    if !installationResults.isEmpty {
                        resultsSection
                    }
                }
                .padding(24)
            }
            .frame(minWidth: 600, minHeight: 500)
            .task {
                await refreshStatus()
                automationManager.requestAutomationPermissionCheck()
                refreshFinderContext()
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "puzzlepiece.extension.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.linearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Finder Integration")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Organize files directly from Finder without opening the app")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await refreshStatus()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh status")
            }
        }
    }
    
    private var statusOverview: some View {
        HStack(spacing: 16) {
            StatusCard(
                title: "Overall Status",
                value: integrationStatus.overallStatus,
                icon: integrationStatus.integrationCount > 0 ? "checkmark.circle.fill" : "xmark.circle.fill",
                color: integrationStatus.integrationCount > 0 ? .green : .orange
            )
            
            StatusCard(
                title: "Active Integrations",
                value: "\(integrationStatus.integrationCount)/\(ExtensionCommunication.FinderIntegrationStatus.totalIntegrations)",
                icon: "square.grid.2x2.fill",
                color: .blue
            )
        }
    }
    
    private var integrationOptions: some View {
        IntegrationOptionsView(
            integrationStatus: integrationStatus,
            isInstalling: isInstalling,
            showingInstructions: $showingInstructions,
            repairFinderSyncExtension: repairFinderSyncExtension,
            installToolbarButton: installToolbarButton,
            revealToolbarApp: revealToolbarApp,
            installQuickWatchAction: installQuickWatchAction,
            uninstallAllQuickActions: uninstallAllQuickActions,
            showQuickPanel: showQuickPanel,
            installAll: installAll
        )
    }

    private var finderWorkflowStatusSection: some View {
        SettingsCard(title: "Finder Workflow", icon: "sparkles.rectangle.stack", color: .mint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: automationManager.hasValidFinderSelection ? "checkmark.seal.fill" : "scope")
                        .font(.title2)
                        .foregroundStyle(automationManager.hasValidFinderSelection ? .green : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(automationManager.statusMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Selection: \(automationManager.selectedFinderItems.count) item\(automationManager.selectedFinderItems.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Refresh") {
                        refreshFinderContext()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("FinderWorkflowRefreshButton")
                }

                if let folder = frontmostFinderFolder {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Front Finder Folder")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(folder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                }

                HStack(spacing: 10) {
                    Button {
                        openFinderSelectionInSorty()
                    } label: {
                        Label("Organize Finder Selection", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!automationManager.hasValidFinderSelection && frontmostFinderFolder == nil)
                    .accessibilityIdentifier("FinderWorkflowOrganizeButton")

                    Button {
                        if let folder = frontmostFinderFolder {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                        }
                    } label: {
                        Label("Reveal Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(frontmostFinderFolder == nil)
                    .accessibilityIdentifier("FinderWorkflowRevealButton")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var optionalCLIToolsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Optional CLI Tools")
                    .font(.headline)
                Spacer()
                Button(showCLITools ? "Hide" : "Show") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCLITools.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("FinderToggleCLIToolsButton")
            }

            Text("CLI install is optional for Finder workflows and hidden by default to keep this experience lightweight.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showCLITools {
                CLIToolsSection()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private var keyboardShortcutSection: some View {
        SettingsCard(title: "Keyboard Shortcut", icon: "keyboard", color: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Toggle(isOn: $globalShortcutEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Global Shortcut")
                                .font(.subheadline)
                            Text("Organize the current Finder folder from anywhere")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .onChange(of: globalShortcutEnabled) { _, newValue in
                        if newValue {
                            shortcutManager.register()
                        } else {
                            shortcutManager.unregister()
                        }
                    }

                    Spacer()

                    Text(shortcutManager.shortcutDescription)
                        .font(.title3.monospaced())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                if shortcutManager.requiresAccessibility {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Accessibility permission is required for global shortcuts.")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Spacer()

                        Button("Open Accessibility Settings") {
                            shortcutManager.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                    Text("Press \(shortcutManager.shortcutDescription) to organize the folder shown in the frontmost Finder window. If no Finder window is open, Sorty will activate instead.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var automationPermissionSection: some View {
        SettingsCard(title: "Automation Permission", icon: "gearshape.2", color: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: automationManager.automationStatus.isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(automationManager.automationStatus.isGranted ? .green : .red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(automationManager.automationStatus.isGranted ? "Automation Granted" : "Automation Not Granted")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Allows Sorty to interact with Finder for file selection, window detection, and post-organization actions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !automationManager.automationStatus.isGranted {
                        Button("Open System Settings") {
                            automationManager.openAutomationSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !automationManager.automationStatus.isGranted {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Without Automation permission, features like global shortcuts, Finder selection monitoring, and post-organization reveal will not work.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(6)
                }

                HStack(spacing: 8) {
                    Text(automationManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Recover") {
                        automationManager.recoverAutomationState()
                        refreshFinderContext()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("FinderAutomationRecoverButton")
                }
            }
        }
    }
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.blue)
                Text("Setup Instructions")
                    .font(.headline)
            }
            
            Text(ExtensionCommunication.getToolbarInstructions())
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            
            Divider()
            
            Text("Keyboard Shortcut")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("You can set up a global keyboard shortcut in System Settings > Keyboard > Keyboard Shortcuts > Services")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Installation Results")
                    .font(.headline)
                
                Spacer()
                
                Button("Dismiss") {
                    installationResults = []
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            ForEach(installationResults.indices, id: \.self) { index in
                let result = installationResults[index]
                HStack(spacing: 12) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(result.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    
    private func refreshStatus() async {
        integrationStatus = await ExtensionCommunication.getIntegrationStatusAsync()
    }

    private func refreshFinderContext() {
        automationManager.checkPermissions()
        if automationManager.automationStatus.isGranted {
            automationManager.updateFinderSelection()
            frontmostFinderFolder = automationManager.getFrontmostFinderWindow()
        } else {
            frontmostFinderFolder = nil
        }
    }

    private func openFinderSelectionInSorty() {
        let selectedTarget: URL? = automationManager.selectedFinderItems.first.map { item in
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory ? item : item.deletingLastPathComponent()
        }
        let target = selectedTarget ?? frontmostFinderFolder
        guard let target else { return }
        var components = URLComponents()
        components.scheme = "sorty"
        components.host = "organize"
        components.queryItems = [
            URLQueryItem(name: "path", value: target.path),
            URLQueryItem(name: "source", value: "finder")
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func installToolbarButton() {
        isInstalling = true

        Task {
            let result = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: FinderToolbarHelper.createToolbarApp())
                }
            }

            installationResults = [("Toolbar Button", result.success, result.message)]
            if result.success {
                FinderToolbarHelper.revealToolbarApp()
            }
            await refreshStatus()
            isInstalling = false
        }
    }

    private func repairFinderSyncExtension() {
        isInstalling = true

        Task {
            let result = await ExtensionCommunication.repairFinderSyncExtensionRegistrationAsync()
            installationResults = [("Finder Sync Extension", result.success, result.message)]
            await refreshStatus()
            isInstalling = false
        }
    }
    
    private func revealToolbarApp() {
        FinderToolbarHelper.revealToolbarApp()
    }
    
    private func installQuickWatchAction() {
        isInstalling = true

        Task {
            let result = await ExtensionCommunication.installQuickWatchActionAsync()
            installationResults = [("Quick Watch Action", result.success, result.message)]
            await refreshStatus()
            isInstalling = false
        }
    }

    private func uninstallAllQuickActions() {
        isInstalling = true

        Task {
            let result = await ExtensionCommunication.uninstallAllQuickActionsAsync()
            if result.success {
                installationResults = [("Uninstall All", true, "Removed \(result.removed) Quick Action workflow(s).")]
            } else {
                installationResults = [("Uninstall All", false, "No Quick Action workflows found to remove.")]
            }
            await refreshStatus()
            isInstalling = false
        }
    }
    
    private func showQuickPanel() {
        QuickOrganizePanelController.shared.showPanel()
    }
    
    private func installAll() {
        isInstalling = true
        
        Task {
            let results = await ExtensionCommunication.installAllIntegrationsAsync()
            installationResults = results
            isInstalling = false
            await refreshStatus()

            // Show the toolbar app in Finder
            if results.contains(where: { $0.name == "Toolbar Button" && $0.success }) {
                FinderToolbarHelper.revealToolbarApp()
            }
        }
    }
}

// MARK: - Supporting Views

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

struct IntegrationRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isInstalled: Bool
    let action: () -> Void
    var secondaryAction: (() -> Void)?
    var secondaryLabel: String?
    var actionLabel: String = "Install"
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if isInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                if let secondaryAction = secondaryAction, let secondaryLabel = secondaryLabel {
                    Button(secondaryLabel, action: secondaryAction)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                
                Button(isInstalled && actionLabel == "Install" ? "Reinstall" : actionLabel, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct IntegrationOptionsView: View {
    let integrationStatus: ExtensionCommunication.FinderIntegrationStatus
    let isInstalling: Bool
    @Binding var showingInstructions: Bool
    let repairFinderSyncExtension: () -> Void
    let installToolbarButton: () -> Void
    let revealToolbarApp: () -> Void
    let installQuickWatchAction: () -> Void
    let uninstallAllQuickActions: () -> Void
    let showQuickPanel: () -> Void
    let installAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Integration Options")
                .font(.headline)

            IntegrationRow(
                title: "Finder Sync Extension",
                subtitle: "Native .appex context menu integration (repairable in-app)",
                icon: "puzzlepiece.extension",
                isInstalled: integrationStatus.finderSyncEnabled,
                action: repairFinderSyncExtension,
                secondaryAction: {
                    ExtensionCommunication.openFinderExtensionSettings()
                },
                secondaryLabel: "Open Extensions",
                actionLabel: integrationStatus.finderSyncEnabled ? "Repair" : "Activate"
            )

            IntegrationRow(
                title: "Finder Toolbar Button",
                subtitle: "Click to organize the current folder",
                icon: "rectangle.topthird.inset.filled",
                isInstalled: integrationStatus.toolbarAppInstalled,
                action: installToolbarButton,
                secondaryAction: integrationStatus.toolbarAppInstalled ? revealToolbarApp : nil,
                secondaryLabel: "Show in Finder"
            )

            // Quick Actions section with status badges
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Quick Actions")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Text("'Organize with Sorty' is intentionally available only in Finder's main context menu via Finder Sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                IntegrationRow(
                    title: "Watch with Sorty",
                    subtitle: "Add a folder to watched folders from Finder context menu",
                    icon: "eye.circle",
                    isInstalled: integrationStatus.quickWatchActionInstalled,
                    action: installQuickWatchAction,
                    secondaryAction: nil,
                    secondaryLabel: nil
                )

                HStack(spacing: 8) {
                    Spacer()
                    Button(action: uninstallAllQuickActions) {
                        Label("Uninstall All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.03))
            .cornerRadius(10)

            IntegrationRow(
                title: "Quick Organize Panel",
                subtitle: "Floating panel for fast organization",
                icon: "uiwindow.split.2x1",
                isInstalled: true,
                action: showQuickPanel,
                secondaryAction: nil,
                secondaryLabel: nil,
                actionLabel: "Open Panel"
            )

            dragAndDropSection

            HStack {
                Spacer()

                Button(action: installAll) {
                    HStack {
                        if isInstalling {
                            SortyGradientCircularLoader(size: 13, lineWidth: 2.4)
                        } else {
                            Image(systemName: "square.and.arrow.down.fill")
                        }
                        Text("Install All Integrations")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isInstalling)

                Button(action: { showingInstructions.toggle() }) {
                    Text(showingInstructions ? "Hide Instructions" : "Show Instructions")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private var dragAndDropSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "hand.draw")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Drag & Drop")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Drag folders onto the Sorty dock icon or menu bar icon to organize them instantly")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Label("Always Available", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - CLI Tools Section

struct CLIToolsSection: View {
    @StateObject private var installer = CLIInstaller.shared
    @State private var installResults: [(name: String, success: Bool, message: String)] = []
    @State private var showingPathHint = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(.linearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Command Line Tools")
                        .font(.headline)
                    Text("Use Sorty from Terminal with powerful CLI commands")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if installer.hasBundledCLIs {
                    Button(action: installAllCLIs) {
                        HStack(spacing: 6) {
                            if installer.isInstalling {
                                SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text("Install All")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(installer.isInstalling)
                }
            }
            
            Divider()
            
            if installer.hasBundledCLIs {
                // sorty CLI
                CLIToolRow(
                    name: "sorty",
                    description: "Organize files, manage watched folders, open settings",
                    isInstalled: installer.sortyCLIInstalled,
                    isInstalling: installer.isInstalling,
                    examples: ["sorty organize ~/Downloads", "sorty status", "sorty help"]
                ) {
                    Task {
                        let result = await installer.installSortyCLI()
                        installResults = [("sorty CLI", result.success, result.message)]
                    }
                }
                
                // learnings CLI
                CLIToolRow(
                    name: "learnings",
                    description: "Manage your learning profile, view stats, export data",
                    isInstalled: installer.learningsCLIInstalled,
                    isInstalling: installer.isInstalling,
                    examples: ["learnings status", "learnings stats", "learnings export"]
                ) {
                    Task {
                        let result = await installer.installLearningsCLI()
                        installResults = [("learnings CLI", result.success, result.message)]
                    }
                }
                
                // Installation results
                if !installResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(installResults.indices, id: \.self) { index in
                            let result = installResults[index]
                            HStack(spacing: 8) {
                                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.success ? .green : .red)
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button("Dismiss") {
                            installResults = []
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding()
                    .background(Color.green.opacity(0.05))
                    .cornerRadius(8)
                }
                
                // Uninstall option
                if installer.sortyCLIInstalled || installer.learningsCLIInstalled {
                    HStack {
                        Spacer()
                        Button(action: uninstallCLIs) {
                            Label("Uninstall CLI Tools", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                }
            } else {
                // CLI tools not bundled
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("CLI tools are bundled with release builds")
                            .font(.subheadline)
                    }
                    Text("Build the app with Xcode or run `make build` to include CLI tools in the app bundle.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.03))
        .cornerRadius(12)
        .onAppear {
            installer.refreshStatus()
        }
    }
    
    private func installAllCLIs() {
        Task {
            installResults = await installer.installAllCLIs()
        }
    }
    
    private func uninstallCLIs() {
        Task {
            let result = await installer.uninstallCLIs()
            installResults = [("Uninstall", result.success, result.message)]
        }
    }
}

struct CLIToolRow: View {
    let name: String
    let description: String
    let isInstalled: Bool
    let isInstalling: Bool
    let examples: [String]
    let installAction: () -> Void
    
    @State private var showExamples = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.subheadline.monospaced())
                            .fontWeight(.semibold)
                        
                        if isInstalled {
                            Label("Installed", systemImage: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { showExamples.toggle() }) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Show usage examples")
                
                Button(isInstalled ? "Reinstall" : "Install") {
                    installAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isInstalling)
            }
            
            if showExamples {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Examples:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    ForEach(examples, id: \.self) { example in
                        Text("$ \(example)")
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FinderIntegrationView()
        .frame(width: 700, height: 600)
}

//
//  FinderIntegrationView.swift
//  Sorty
//
//  Settings view for configuring Finder integration options
//  Toolbar button, Quick Action, Menu Bar, and keyboard shortcuts
//

import SwiftUI

public struct FinderIntegrationView: View {
    @State private var integrationStatus = ExtensionCommunication.getIntegrationStatus()
    @State private var isInstalling = false
    @State private var installationResults: [(name: String, success: Bool, message: String)] = []
    @State private var showingInstructions = false
    @State private var enableMenuBar = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection
                
                // Status Overview
                statusOverview
                
                // Integration Options
                integrationOptions
                
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
        .onAppear {
            refreshStatus()
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
                
                Button(action: refreshStatus) {
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
                value: "\(integrationStatus.integrationCount)/4",
                icon: "square.grid.2x2.fill",
                color: .blue
            )
        }
    }
    
    private var integrationOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Integration Options")
                .font(.headline)
            
            // Toolbar Button
            IntegrationRow(
                title: "Finder Toolbar Button",
                subtitle: "Click to organize the current folder",
                icon: "rectangle.topthird.inset.filled",
                isInstalled: integrationStatus.toolbarAppInstalled,
                action: installToolbarButton,
                secondaryAction: integrationStatus.toolbarAppInstalled ? revealToolbarApp : nil,
                secondaryLabel: "Show in Finder"
            )
            
            // Quick Action
            IntegrationRow(
                title: "Right-Click Menu",
                subtitle: "Organize with Sorty in context menu",
                icon: "contextualmenu.and.cursorarrow",
                isInstalled: integrationStatus.quickActionInstalled,
                action: installQuickAction,
                secondaryAction: nil,
                secondaryLabel: nil
            )
            
            // Menu Bar
            IntegrationRow(
                title: "Menu Bar Icon",
                subtitle: "Quick access from menu bar",
                icon: "menubar.rectangle",
                isInstalled: showMenuBarIcon,
                action: toggleMenuBar,
                secondaryAction: nil,
                secondaryLabel: nil
            )
            
            // Quick Panel
            IntegrationRow(
                title: "Quick Organize Panel",
                subtitle: "Floating panel for fast organization",
                icon: "uiwindow.split.2x1",
                isInstalled: true, // Always available
                action: showQuickPanel,
                secondaryAction: nil,
                secondaryLabel: nil,
                actionLabel: "Open Panel"
            )
            
            // Install All Button
            HStack {
                Spacer()
                
                Button(action: installAll) {
                    HStack {
                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.8)
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
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
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
    
    private func refreshStatus() {
        integrationStatus = ExtensionCommunication.getIntegrationStatus()
    }
    
    private func installToolbarButton() {
        let result = FinderToolbarHelper.createToolbarApp()
        installationResults = [("Toolbar Button", result.success, result.message)]
        if result.success {
            FinderToolbarHelper.revealToolbarApp()
        }
        refreshStatus()
    }
    
    private func revealToolbarApp() {
        FinderToolbarHelper.revealToolbarApp()
    }
    
    private func installQuickAction() {
        let result = ExtensionCommunication.installQuickAction()
        installationResults = [("Quick Action", result.success, result.message)]
        refreshStatus()
    }
    
    private func toggleMenuBar() {
        showMenuBarIcon.toggle()
        if showMenuBarIcon {
            MenuBarHelper.shared.setup()
        } else {
            MenuBarHelper.shared.remove()
        }
        refreshStatus()
    }
    
    private func showQuickPanel() {
        QuickOrganizePanelController.shared.showPanel()
    }
    
    private func installAll() {
        isInstalling = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let results = ExtensionCommunication.installAllIntegrations()
            
            DispatchQueue.main.async {
                self.installationResults = results
                self.isInstalling = false
                self.refreshStatus()
                
                // Show the toolbar app in Finder
                if results.contains(where: { $0.name == "Toolbar Button" && $0.success }) {
                    FinderToolbarHelper.revealToolbarApp()
                }
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

#Preview {
    FinderIntegrationView()
        .frame(width: 700, height: 600)
}

//
//  FinderIntegrationSettingsView.swift
//  Sorty
//
//  Finder Integration settings section
//

import SwiftUI

struct FinderIntegrationSettingsView: View {
    @State private var isQuickActionInstalled = ExtensionCommunication.isQuickActionInstalled()
    @State private var quickActionMessage: String?
    
    var body: some View {
        VStack(spacing: 16) {
            // Quick Action
            SettingsCard(title: "Quick Action", icon: "cursorarrow.click.badge.clock", color: .cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: isQuickActionInstalled ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.title2)
                            .foregroundStyle(isQuickActionInstalled ? .green : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isQuickActionInstalled ? "Quick Action Installed" : "Quick Action Not Installed")
                                .font(.subheadline.weight(.medium))
                            Text("Right-click folders in Finder to organize with Sorty")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if isQuickActionInstalled {
                            Button("Uninstall") {
                                if ExtensionCommunication.uninstallQuickAction() {
                                    isQuickActionInstalled = false
                                    quickActionMessage = "Quick Action removed"
                                    HapticFeedbackManager.shared.success()
                                }
                            }
                            .buttonStyle(.sortySecondary(size: .regular))
                        } else {
                            Button("Install") {
                                let result = ExtensionCommunication.installQuickAction()
                                isQuickActionInstalled = result.success
                                quickActionMessage = result.message
                                if result.success {
                                    HapticFeedbackManager.shared.success()
                                } else {
                                    HapticFeedbackManager.shared.error()
                                }
                            }
                            .buttonStyle(.sortyPrimary(size: .regular))
                        }
                    }
                    
                    if let message = quickActionMessage {
                        HStack(spacing: 6) {
                            Image(systemName: isQuickActionInstalled ? "checkmark.circle" : "exclamationmark.triangle")
                                .foregroundStyle(isQuickActionInstalled ? .green : .orange)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animatedAppearance(delay: 0.05)
            
            // URL Scheme Info
            SettingsCard(title: "URL Scheme", icon: "link", color: .blue) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use URL schemes to trigger Sorty from scripts, Alfred, Raycast, or other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        URLSchemeRow(scheme: "sorty://organize?path=/path/to/folder", description: "Organize a folder")
                        URLSchemeRow(scheme: "sorty://duplicates?path=/path", description: "Find duplicates")
                        URLSchemeRow(scheme: "sorty://settings", description: "Open settings")
                        URLSchemeRow(scheme: "sorty://settings?section=provider", description: "Open AI Provider settings")
                        URLSchemeRow(scheme: "sorty://settings?section=notifications", description: "Open Notification settings")
                        URLSchemeRow(scheme: "sorty://watched", description: "Open watched folders")
                        URLSchemeRow(scheme: "sorty://exclusions", description: "Open exclusion rules")
                        URLSchemeRow(scheme: "sorty://storage", description: "Open storage locations")
                        URLSchemeRow(scheme: "sorty://learnings?action=honing", description: "Start a Learnings honing session")
                    }
                }
            }
            .animatedAppearance(delay: 0.1)
            
            // Finder Extension (for signed builds)
            SettingsCard(title: "Finder Sync Extension", icon: "puzzlepiece.extension", color: .purple) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Requires code signing")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    
                    Text("The native Finder extension requires the app to be code-signed with an Apple Developer certificate. Use the Quick Action above for unsigned builds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Extension Preferences") {
                        ExtensionCommunication.openFinderExtensionSettings()
                    }
                    .buttonStyle(.sortySecondary(size: .small))
                }
            }
            .animatedAppearance(delay: 0.15)
        }
    }
}

#Preview {
    FinderIntegrationSettingsView()
        .frame(width: 500, height: 400)
}

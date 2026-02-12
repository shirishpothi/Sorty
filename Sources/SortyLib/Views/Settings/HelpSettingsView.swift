//
//  HelpSettingsView.swift
//  Sorty
//
//  Consolidated Help & Support section within Settings
//

import SwiftUI

struct HelpSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 20) {
            // Section 1: The Basics
            SettingsCard(title: "The Basics", icon: "star.fill", color: .yellow) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("New to Sorty? Here's the essential workflow to get your files organized in seconds.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HelpBulletPoint(icon: "1.circle.fill", text: "Select a folder using ⌘O or drag-and-drop.")
                    HelpBulletPoint(icon: "2.circle.fill", text: "Choose a Persona that matches your file types.")
                    HelpBulletPoint(icon: "3.circle.fill", text: "Preview the AI's plan and apply changes.")
                    
                    Button {
                        appState.showOnboarding()
                    } label: {
                        Label("Re-run Welcome Guide", systemImage: "hand.wave")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.onboardingPill)
                    .padding(.top, 4)
                }
            }
            .animatedAppearance(delay: 0.1)
            
            // Section 2: Organization Intelligence
            SettingsCard(title: "Organization Intelligence", icon: "brain.head.profile", color: .purple) {
                VStack(alignment: .leading, spacing: 16) {
                    HelpDetailRow(
                        title: "Personas",
                        description: "Specialized AI profiles (Developer, Accountant, etc.) that change how files are categorized.",
                        icon: "person.2.fill"
                    )
                    
                    HelpDetailRow(
                        title: "The Learnings",
                        description: "Sorty learns from your manual moves! Every time you correct a file's location, the AI adapts.",
                        icon: "lightbulb.fill"
                    )
                    
                    HelpDetailRow(
                        title: "Smart Tags",
                        description: "Enable tags in Organization Rules to have the AI label files with Finder-compatible colors and keywords.",
                        icon: "tag.fill"
                    )
                }
            }
            .animatedAppearance(delay: 0.2)
            
            // Section 3: Automation & Power User Features
            SettingsCard(title: "Automation", icon: "terminal.fill", color: .blue) {
                VStack(alignment: .leading, spacing: 16) {
                    HelpDetailRow(
                        title: "Keyboard Shortcuts",
                        description: "Use ⌘O to open, ⌘R to organize, and ⌘Z to undo any action instantly.",
                        icon: "keyboard"
                    )
                    
                    HelpDetailRow(
                        title: "CLI Tool",
                        description: "The 'learnings' command-line tool lets you manage profiles and trigger organization from scripts.",
                        icon: "chevron.right.terminal"
                    )
                }
            }
            .animatedAppearance(delay: 0.3)
            
            // Section 4: Privacy & App Info
            SettingsCard(title: "Privacy & Support", icon: "lock.shield.fill", color: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your privacy is our priority. Sorty never uploads your file contents to our servers—only metadata (names/types) is sent to your chosen AI provider.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Sorty \(BuildInfo.version) (\(BuildInfo.build))")
                                .font(.headline)
                            Text("© 2024-2026 Shirish Pothi")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 16) {
                        Link("Documentation", destination: URL(string: "https://github.com/shirishpothi/Sorty/blob/main/HELP.md")!)
                            .font(.subheadline)
                        
                        Link("Report Issue", destination: URL(string: "https://github.com/shirishpothi/Sorty/issues")!)
                            .font(.subheadline)
                        
                        Link("View Changelog", destination: URL(string: "https://github.com/shirishpothi/Sorty/blob/main/CHANGELOG.md")!)
                            .font(.subheadline)
                    }
                }
            }
            .animatedAppearance(delay: 0.4)
        }
    }
}

// MARK: - Components

private struct HelpBulletPoint: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct HelpDetailRow: View {
    let title: String
    let description: String
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    ScrollView {
        HelpSettingsView()
            .padding()
            .environmentObject(AppState())
    }
    .frame(width: 500)
}

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
            
            // Section 2: Privacy & App Info
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
                    
                    VStack(spacing: 6) {
                        HelpLinkRow(
                            title: "Documentation",
                            icon: "doc.text",
                            url: "https://github.com/shirishpothi/Sorty/blob/main/HELP.md"
                        )
                        HelpLinkRow(
                            title: "Report Issue",
                            icon: "exclamationmark.bubble",
                            url: "https://github.com/shirishpothi/Sorty/issues"
                        )
                        HelpLinkRow(
                            title: "View Changelog",
                            icon: "clock.arrow.circlepath",
                            url: "https://github.com/shirishpothi/Sorty/blob/main/CHANGELOG.md"
                        )
                    }
                }
            }
            .animatedAppearance(delay: 0.2)
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

private struct HelpLinkRow: View {
    let title: String
    let icon: String
    let url: String
    
    @State private var isHovered = false
    
    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .offset(x: isHovered ? 3 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
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

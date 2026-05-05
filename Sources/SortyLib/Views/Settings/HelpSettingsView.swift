//
//  HelpSettingsView.swift
//  Sorty
//
//  Consolidated Help & Support section within Settings
//

import SwiftUI
import AppKit

struct HelpSettingsView: View {
    @EnvironmentObject var appState: AppState

    private let deeplinkEntries: [DeeplinkEntry] = [
        DeeplinkEntry(title: "Organize Folder", url: "sorty://organize?path=/Users/me/Downloads&autostart=true", summary: "Open Organize with an optional path, persona, mode, and autostart."),
        DeeplinkEntry(title: "Duplicates", url: "sorty://duplicates?path=/Users/me/Downloads&autostart=true", summary: "Open Duplicate Files view with an optional path and autostart."),
        DeeplinkEntry(title: "Learnings", url: "sorty://learnings?action=honing", summary: "Open Learnings with action: honing, stats, withdraw, export, import, or clear."),
        DeeplinkEntry(title: "Settings", url: "sorty://settings?section=notifications", summary: "Open Settings and optionally jump to a section."),
        DeeplinkEntry(title: "Help", url: "sorty://help?section=personas", summary: "Open help/support destination with optional section."),
        DeeplinkEntry(title: "Open App", url: "sorty://open?path=/Users/me/Downloads", summary: "Bring Sorty to front and optionally preload a directory."),
        DeeplinkEntry(title: "History", url: "sorty://history", summary: "Open organization history."),
        DeeplinkEntry(title: "Workspace Health", url: "sorty://health", summary: "Open workspace health."),
        DeeplinkEntry(title: "Persona", url: "sorty://persona?action=create&generate=true&prompt=Design%20files", summary: "Create/select persona flows with optional generation prompt."),
        DeeplinkEntry(title: "Watched Folders", url: "sorty://watched?action=add&path=/Users/me/Projects", summary: "Open watched folders and optionally add a path."),
        DeeplinkEntry(title: "Rules", url: "sorty://rules?action=add&type=pathContains&pattern=.cache", summary: "Open rules/exclusions flow with optional add action and pattern."),
        DeeplinkEntry(title: "Exclusions", url: "sorty://exclusions?action=add&pattern=node_modules", summary: "Open exclusions and optionally add a new exclusion pattern."),
        DeeplinkEntry(title: "Scan", url: "sorty://scan?path=/Users/me/Downloads", summary: "Open workspace-health scan target for a folder."),
        DeeplinkEntry(title: "Storage", url: "sorty://storage?action=add&path=/Volumes/Archive", summary: "Open storage locations and optionally add a path."),
        DeeplinkEntry(title: "Legacy Path", url: "sorty:///Users/me/Downloads", summary: "Legacy path-only deeplink supported for compatibility.")
    ]
    
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
                    // Links row
                    HStack(spacing: 0) {
                        HelpIconLink(
                            title: "Documentation",
                            icon: "doc.text",
                            url: "https://github.com/shirishpothi/Sorty/blob/main/HELP.md"
                        )
                        HelpIconLink(
                            title: "Report Issue",
                            icon: "exclamationmark.bubble",
                            url: "https://github.com/shirishpothi/Sorty/issues"
                        )
                        HelpIconLink(
                            title: "View Changelog",
                            icon: "clock.arrow.circlepath",
                            url: "https://github.com/shirishpothi/Sorty/blob/main/CHANGELOG.md"
                        )
                    }

                    Divider()

                    // Privacy blurb
                    Text("Your privacy is our priority. Sorty never uploads your file contents to our servers—only metadata (names/types) is sent to your chosen AI provider.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Version & copyright
                    HStack {
                        Text("Sorty \(BuildInfo.version) (\(BuildInfo.build))")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("© 2024-2026 Shirish Pothi")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .animatedAppearance(delay: 0.2)

            SettingsCard(title: "Automation Deeplinks", icon: "link.badge.plus", color: .cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use these `sorty://` URLs from Shortcuts, Raycast, AppleScript, or shell scripts to jump directly into specific Sorty workflows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(deeplinkEntries.enumerated()), id: \.element.id) { index, entry in
                        DeeplinkEntryRow(entry: entry) { value in
                            copyDeeplink(value)
                        }

                        if index < deeplinkEntries.count - 1 {
                            Divider()
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("URL-encode `path` and `prompt` values when generating links programmatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .animatedAppearance(delay: 0.26)
        }
    }

    private func copyDeeplink(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        HapticFeedbackManager.shared.selection()
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

private struct HelpIconLink: View {
    let title: String
    let icon: String
    let url: String

    @State private var isHovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .trackHoveredURL(URL(string: url)!)
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            HapticFeedbackManager.shared.tap()
        })
    }
}

private struct DeeplinkEntry: Identifiable {
    let title: String
    let url: String
    let summary: String

    var id: String { url }
}

private struct DeeplinkEntryRow: View {
    let entry: DeeplinkEntry
    let onCopy: (String) -> Void
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    copy()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? .green : .primary)
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(copied ? Color.green.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(copied ? Color.green.opacity(0.42) : Color.secondary.opacity(0.14), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .scaleEffect(copied ? 1.05 : 1)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: copied)
            }

            Text(entry.url)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .textSelection(.enabled)

            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func copy() {
        onCopy(entry.url)
        resetTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            copied = true
        }

        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                copied = false
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

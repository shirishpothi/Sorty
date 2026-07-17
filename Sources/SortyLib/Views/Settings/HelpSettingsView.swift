//
//  HelpSettingsView.swift
//  Sorty
//
//  Help, support, and deeplink settings pages
//

import AppKit
import SwiftUI

struct HelpSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    private let docsURL = URL(string: "https://github.com/sorty-organizer/Sorty/blob/main/HELP.md")!
    private let issuesURL = URL(string: "https://github.com/sorty-organizer/Sorty/issues")!
    private let changelogURL = URL(string: "https://sorty-organizer.github.io/Sorty/changelog")!
    private let privacyPolicyURL = URL(string: "https://sorty-organizer.github.io/Sorty/privacy-policy")!
    private let termsOfServiceURL = URL(string: "https://sorty-organizer.github.io/Sorty/terms")!
    private let developerURL = URL(string: "https://github.com/shirishpothi")!

    @State private var copiedIssueDetails = false

    var body: some View {
        VStack(spacing: 20) {
            SettingsCard(title: "Support", icon: "questionmark.circle.fill", color: .teal) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        HelpIconLink(
                            title: "Documentation",
                            icon: "doc.text",
                            color: .blue,
                            url: docsURL
                        )

                        HelpIconLink(
                            title: "Report Issue",
                            icon: "exclamationmark.bubble",
                            color: .red,
                            url: issuesURL
                        )

                        HelpIconLink(
                            title: "View Changelog",
                            icon: "clock.arrow.circlepath",
                            color: .purple,
                            url: changelogURL
                        )
                    }

                    Divider()

                    HStack(spacing: 10) {
                        HelpIconLink(
                            title: "Privacy Policy",
                            icon: "hand.raised",
                            color: .green,
                            url: privacyPolicyURL
                        )

                        HelpIconLink(
                            title: "Terms of Service",
                            icon: "doc.text",
                            color: .indigo,
                            url: termsOfServiceURL
                        )
                    }

                    Divider()

                    HStack(alignment: .center, spacing: 12) {
                        Text("Sorty \(BuildInfo.version) (\(BuildInfo.build))")
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        HStack(spacing: 8) {
                            Text("Built by")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                open(developerURL)
                            } label: {
                                HStack(spacing: 6) {
                                    GitHubMarkIcon()
                                    Text("Shirish Pothi")
                                }
                            }
                            .buttonStyle(.sortyBordered(intent: .info, size: .small))
                            .trackHoveredURL(developerURL)
                        }
                    }
                }
            }
            .animatedAppearance(delay: 0.1)

            SettingsCard(title: "Issue Details", icon: "clipboard", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Copy a ready-to-paste environment block for GitHub issues.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        SupportDetailChip(label: "App", value: BuildInfo.fullVersion)
                        SupportDetailChip(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                        SupportDetailChip(label: "Arch", value: systemArchitecture)
                    }

                    Button {
                        copyIssueDetails()
                    } label: {
                        Label(copiedIssueDetails ? "Copied Issue Details" : "Copy Issue Details", systemImage: copiedIssueDetails ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sortyProminent(intent: .secondary))
                    .accessibilityIdentifier("CopyIssueDetailsButton")
                    .onHover { hovering in
                        if hovering {
                            HapticFeedbackManager.shared.selection()
                        }
                    }
                }
            }
            .animatedAppearance(delay: 0.16)
        }
    }

    private func copyIssueDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issueDetailsText, forType: .string)
        HapticFeedbackManager.shared.success()

        withAnimation(.easeInOut(duration: 0.15)) {
            copiedIssueDetails = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.15)) {
                copiedIssueDetails = false
            }
        }
    }

    private func open(_ url: URL) {
        HapticFeedbackManager.shared.tap()
        NSWorkspace.shared.open(url)
    }

    private var issueDetailsText: String {
        let processInfo = ProcessInfo.processInfo
        let config = viewModel.config
        let defaults = UserDefaults.standard
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        let memory = ByteCountFormatter.string(fromByteCount: Int64(processInfo.physicalMemory), countStyle: .memory)
        let appSupportPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sorty")
            .path ?? "unknown"
        let cachesPath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleID)
            .path ?? "unknown"

        return """
        ### Environment
        - Sorty: \(BuildInfo.fullVersion)
        - Commit: \(BuildInfo.shortCommit)
        - Bundle ID: \(bundleID)
        - Bundle path: \(Bundle.main.bundlePath)

        ### System
        - macOS: \(processInfo.operatingSystemVersionString)
        - Architecture: \(systemArchitecture)
        - CPU cores: \(processInfo.activeProcessorCount)
        - Memory: \(memory)
        - Locale: \(Locale.current.identifier)

        ### AI Configuration
        - Provider: \(config.provider.displayName)
        - Model: \(config.model.isEmpty ? config.provider.defaultModel : config.model)
        - Auth method: \(config.authMethod(for: config.provider).displayName)
        - API URL configured: \(yesNo(config.apiURL?.isEmpty == false))
        - Requires API key: \(yesNo(config.requiresAPIKey))
        - Mode: \(config.mode.displayName)
        - Deep scan: \(yesNo(config.enableDeepScan))
        - Vision: \(yesNo(config.enableVision))
        - Vision detail: \(config.effectiveVisionDetailLevel.displayName)
        - Vision batch: \(config.limitVisionImages ? "\(config.visionBatchStrategy.displayName), max \(config.visionBatchSize)" : "All images")
        - Smart rename: \(yesNo(config.enableSmartRename))
        - Duplicate detection: \(yesNo(config.detectDuplicates))
        - File tagging: \(yesNo(config.enableFileTagging))
        - Strict exclusions: \(yesNo(config.strictExclusions))
        - Streaming: \(yesNo(config.enableStreaming))
        - Reasoning: \(yesNo(config.enableReasoning))
        - Request timeout: \(Int(config.requestTimeout))s
        - Resource timeout: \(Int(config.resourceTimeout))s

        ### App Settings
        - Privacy mode: \(yesNo(defaults.bool(forKey: "privacyModeEnabled")))
        - Internet privacy mode: \(yesNo(FeatureFlags.internetPrivacyModeEnabled))
        - Menu bar extra: \(yesNo(defaults.object(forKey: "showMenuBarExtra") as? Bool ?? true))
        - Completed onboarding: \(yesNo(defaults.bool(forKey: "hasCompletedOnboarding")))
        - App support path: \(appSupportPath)
        - Caches path: \(cachesPath)
        """
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private var systemArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

private struct GitHubMarkIcon: View {
    var body: some View {
        if let image = NSImage(named: NSImage.Name("GitHub")) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        }
    }
}

struct DeeplinkSettingsView: View {
    @State private var isShowingEncodingInfo = false

    private var groups: [DeeplinkGroup] {
        var organizationEntries = [
            DeeplinkEntry(title: "Organize Folder", url: "sorty://organize?path=/Users/me/Downloads&autostart=true", summary: "Open Organize with an optional path, persona, mode, and autostart."),
            DeeplinkEntry(title: "Duplicates", url: "sorty://duplicates?path=/Users/me/Downloads&autostart=true", summary: "Open Duplicate Files with an optional path and autostart."),
            DeeplinkEntry(title: "Storage", url: "sorty://storage?action=add&path=/Volumes/Archive", summary: "Open storage locations and optionally add a path.")
        ]

        return [
            DeeplinkGroup(
                title: "Core",
                icon: "app.badge",
                color: .blue,
                entries: [
                    DeeplinkEntry(title: "Open App", url: "sorty://open?path=/Users/me/Downloads", summary: "Bring Sorty to front and optionally preload a directory."),
                    DeeplinkEntry(title: "Settings", url: "sorty://settings?section=notifications", summary: "Open Settings and optionally jump to a section."),
                    DeeplinkEntry(title: "Help", url: "sorty://help?section=personas", summary: "Open help/support with an optional section."),
                    DeeplinkEntry(title: "History", url: "sorty://history", summary: "Open organization history.")
                ]
            ),
            DeeplinkGroup(
                title: "Organization",
                icon: "folder.badge.gearshape",
                color: .green,
                entries: organizationEntries
            ),
            DeeplinkGroup(
                title: "Automation",
                icon: "bolt.circle",
                color: .orange,
                entries: [
                    DeeplinkEntry(title: "Watched Folders", url: "sorty://watched?action=add&path=/Users/me/Projects", summary: "Open watched folders and optionally add a path."),
                    DeeplinkEntry(title: "Rules", url: "sorty://rules?action=add&type=pathContains&pattern=.cache", summary: "Open rules/exclusions and optionally add a rule."),
                    DeeplinkEntry(title: "Exclusions", url: "sorty://exclusions?action=add&pattern=node_modules", summary: "Open exclusions and optionally add a pattern."),
                    DeeplinkEntry(title: "Persona", url: "sorty://persona?action=create&generate=true&prompt=Design%20files", summary: "Open persona create/select flows with optional generation."),
                    DeeplinkEntry(title: "Learnings", url: "sorty://learnings?action=stats", summary: "Open Learnings with action: stats, withdraw, export, import, or clear."),
                    DeeplinkEntry(title: "Provider Settings", url: "sorty://settings?section=provider", summary: "Jump straight to provider setup.")
                ]
            ),
            DeeplinkGroup(
                title: "Finder",
                icon: "folder.badge.plus",
                color: .cyan,
                entries: [
                    DeeplinkEntry(title: "Organize with Sorty", url: "sorty://organize?path=/Users/me/Downloads&autostart=true", summary: "Finder service target for organizing a selected folder."),
                    DeeplinkEntry(title: "Watch with Sorty", url: "sorty://watched?action=add&path=/Users/me/Projects", summary: "Finder service target for adding a selected folder to watched folders."),
                    DeeplinkEntry(title: "Exclude with Sorty", url: "sorty://exclude?path=/Users/me/Downloads/Archive", summary: "Finder service target for adding a selected file or folder to exclusions."),
                    DeeplinkEntry(title: "Finder Settings", url: "sorty://settings?section=finder", summary: "Jump straight to Finder and Services integration.")
                ]
            ),
            DeeplinkGroup(
                title: "Compatibility",
                icon: "arrow.triangle.2.circlepath",
                color: .secondary,
                entries: [
                    DeeplinkEntry(title: "Legacy Path", url: "sorty:///Users/me/Downloads", summary: "Legacy path-only deeplink for older launchers.")
                ]
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label("Deeplink Library", systemImage: "link.badge.plus")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Button {
                        HapticFeedbackManager.shared.tap()
                        isShowingEncodingInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isShowingEncodingInfo, arrowEdge: .bottom) {
                        Text("URL-encode path and prompt values when generating links programmatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(width: 280, alignment: .leading)
                            .systemLiquidGlassPopover(cornerRadius: 12)
                    }
                    .help("About generating deeplinks")
                    .accessibilityLabel("Deeplink encoding information")
                }

                Text("Copy `sorty://` URLs for Shortcuts, Raycast, AppleScript, shell scripts, and other launchers.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { group in
                    DeeplinkGroupSection(group: group)
                }
            }
        }
    }
}

private struct HelpIconLink: View {
    let title: String
    let icon: String
    let color: Color
    let url: URL

    @State private var isHovered = false

    var body: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            NSWorkspace.shared.open(url)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(isHovered ? color : .secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHovered ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.vertical, 8)
            .background(isHovered ? color.opacity(0.14) : Color.secondary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isHovered ? color.opacity(0.32) : Color.secondary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .trackHoveredURL(url)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
    }
}

private struct SupportDetailChip: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeeplinkGroup: Identifiable {
    let title: String
    let icon: String
    let color: Color
    let entries: [DeeplinkEntry]

    var id: String { title }
}

private struct DeeplinkEntry: Identifiable {
    let title: String
    let url: String
    let summary: String

    var id: String { url }
}

private struct DeeplinkGroupSection: View {
    let group: DeeplinkGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(group.title, systemImage: group.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(group.color)

            VStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    DeeplinkEntryRow(entry: entry, color: group.color)

                    if entry.id != group.entries.last?.id {
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
    }
}

private struct DeeplinkEntryRow: View {
    let entry: DeeplinkEntry
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 150, maxWidth: 220, alignment: .leading)

            Text(entry.url)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            copyButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var copyButton: some View {
        Button {
            copy(entry.url)
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.caption.weight(.semibold))
                .foregroundStyle(copied ? .green : color)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(copied ? .green.opacity(0.14) : color.opacity(0.08))
                )
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: copied)
        }
        .buttonStyle(.plain)
        .help("Copy \(entry.title) deeplink")
        .accessibilityLabel("Copy \(entry.title) deeplink")
        .accessibilityValue(copied ? "Copied" : "")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        HapticFeedbackManager.shared.tap()

        copied = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            copied = false
        }
    }
}

#Preview("Help & Support") {
    ScrollView {
        HelpSettingsView()
            .padding()
            .environmentObject(SettingsViewModel())
    }
    .frame(width: 560)
}

#Preview("Deeplinks") {
    ScrollView {
        DeeplinkSettingsView()
            .padding()
    }
    .frame(width: 620)
}

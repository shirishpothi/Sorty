//
//  HelpSettingsView.swift
//  Sorty
//
//  Help and support settings
//

import AppKit
import SwiftUI

struct HelpSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let docsURL = URL(string: "https://github.com/sorty-organizer/Sorty/blob/main/HELP.md")!
    private let issuesURL = URL(string: "https://github.com/sorty-organizer/Sorty/issues")!
    private let changelogURL = URL(string: "https://sorty-organizer.github.io/Sorty/changelog")!
    private let privacyPolicyURL = URL(string: "https://sorty-organizer.github.io/Sorty/privacy-policy")!
    private let termsOfServiceURL = URL(string: "https://sorty-organizer.github.io/Sorty/terms")!
    private let developerURL = URL(string: "https://github.com/shirishpothi")!

    @State private var copiedIssueDetails = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            SettingsCard(title: "Support", icon: "questionmark.circle.fill", color: .teal) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        HelpIconLink(
                            title: "Documentation",
                            icon: "doc.text",
                            color: .blue,
                            url: docsURL,
                            focusTarget: .helpDocumentation
                        )

                        HelpIconLink(
                            title: "Report Issue",
                            icon: "exclamationmark.bubble",
                            color: .red,
                            url: issuesURL,
                            focusTarget: .helpReportIssue
                        )

                        HelpIconLink(
                            title: "View Changelog",
                            icon: "clock.arrow.circlepath",
                            color: .purple,
                            url: changelogURL,
                            focusTarget: .helpChangelog
                        )
                    }

                    Divider()

                    HStack(spacing: 10) {
                        HelpIconLink(
                            title: "Privacy Policy",
                            icon: "hand.raised",
                            color: .green,
                            url: privacyPolicyURL,
                            focusTarget: .helpPrivacy
                        )

                        HelpIconLink(
                            title: "Terms of Service",
                            icon: "doc.text",
                            color: .indigo,
                            url: termsOfServiceURL,
                            focusTarget: .helpTerms
                        )
                    }
                    .settingsFocusable(.helpLegal)

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
            .settingsFocusable(.helpSupport)
            .animatedAppearance(delay: 0.1)

            SettingsCard(title: "Support Report", icon: "clipboard", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Copy a privacy-safe report containing app and configuration details. It never includes file names, folder paths, prompts, credentials, or AI responses.")
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
                        HStack(spacing: 8) {
                            Image(systemName: copiedIssueDetails ? "checkmark" : "doc.on.doc")
                                .symbolReplaceTransition(animationValue: copiedIssueDetails)

                            Text(copiedIssueDetails ? "Copied Support Report" : "Copy Support Report")
                                .numericTextTransition(animationValue: copiedIssueDetails)
                        }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.sortyProminent(intent: .secondary))
                    .accessibilityIdentifier("CopyIssueDetailsButton")
                    .accessibilityValue(copiedIssueDetails ? "Copied" : "")
                    .onHover { hovering in
                        if hovering {
                            HapticFeedbackManager.shared.selection()
                        }
                    }
                }
            }
            .settingsFocusable(.helpIssueDetails)
            .animatedAppearance(delay: 0.16)

        }
        .onDisappear {
            copyResetTask?.cancel()
        }
    }

    private func copyIssueDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(issueDetailsText, forType: .string)
        HapticFeedbackManager.shared.success()
        AnalyticsManager.shared.captureFeature(
            feature: "support",
            subfeature: "support_report",
            action: "copied",
            outcome: "success"
        )

        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
            copiedIssueDetails = true
        }

        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
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
        return """
        ### What happened
        <!-- Describe what you expected and what Sorty did instead. -->

        ### Environment
        - Sorty: \(BuildInfo.fullVersion)
        - Commit: \(BuildInfo.shortCommit)
        - Bundle ID: \(bundleID)

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
        - Images selected for vision: \(config.limitVisionImages ? "\(config.visionBatchStrategy.displayName), max \(config.visionBatchSize)" : "All images")
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

private struct HelpIconLink: View {
    let title: String
    let icon: String
    let color: Color
    let url: URL
    let focusTarget: SettingsFocusTarget

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
                Text(LocalizedStringKey(title))
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
        .settingsFocusable(
            focusTarget,
            shape: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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

#Preview("Help & Support") {
    ScrollView {
        HelpSettingsView()
            .padding()
            .environmentObject(SettingsViewModel())
            .environmentObject(AppState())
    }
    .frame(width: 560)
}

//
//  ExperimentalSettingsView.swift
//  Sorty
//
//  Experimental features section showing disabled feature flags with enablement guidance
//

import SwiftUI

struct ExperimentalSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("These optional controls are intentionally hidden from the main workflow. You can enable them directly here or with Terminal commands.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(experimentalFlags) { flag in
                ExperimentalFlagRow(flag: flag)
            }
        }
    }

    private var experimentalFlags: [ExperimentalFlag] {
        [
            ExperimentalFlag(
                name: "Nightly Updates",
                description: "Check the nightly Sparkle feed for the latest main-branch builds. Nightlies can include unfinished changes.",
                defaultsKey: SparkleUpdateFeed.nightlyUpdatesEnabledKey,
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app nightlyUpdatesEnabled -bool true",
                disableCommand: "defaults write com.sorty.app nightlyUpdatesEnabled -bool false",
                restartMessage: "Use Check for Updates after switching channels."
            ),
            ExperimentalFlag(
                name: "Advanced Notification Controls",
                description: "Shows technical notification controls including backend selection and test actions.",
                defaultsKey: "advancedNotificationSettingsEnabled",
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app advancedNotificationSettingsEnabled -bool true",
                disableCommand: "defaults write com.sorty.app advancedNotificationSettingsEnabled -bool false"
            ),
            ExperimentalFlag(
                name: "Workspace Health",
                description: "Shows Workspace Health navigation, menu actions, deeplinks, and shortcuts.",
                defaultsKey: "workspaceHealthEnabled",
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app workspaceHealthEnabled -bool true",
                disableCommand: "defaults write com.sorty.app workspaceHealthEnabled -bool false"
            ),
        ]
    }
}

struct ExperimentalFlag: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let defaultsKey: String
    let defaultValue: Bool
    let enableCommand: String
    let disableCommand: String
    let restartMessage: String

    init(
        name: String,
        description: String,
        defaultsKey: String,
        defaultValue: Bool,
        enableCommand: String,
        disableCommand: String,
        restartMessage: String = "Relaunch Sorty to ensure all views pick up this change."
    ) {
        self.name = name
        self.description = description
        self.defaultsKey = defaultsKey
        self.defaultValue = defaultValue
        self.enableCommand = enableCommand
        self.disableCommand = disableCommand
        self.restartMessage = restartMessage
    }

    func currentValue() -> Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

struct ExperimentalFlagRow: View {
    let flag: ExperimentalFlag
    @State private var copied = false
    @State private var isEnabled: Bool

    init(flag: ExperimentalFlag) {
        self.flag = flag
        _isEnabled = State(initialValue: flag.currentValue())
    }

    var body: some View {
        SettingsCard(title: flag.name, icon: isEnabled ? "checkmark.circle.fill" : "circle.dashed", color: isEnabled ? .green : .secondary) {
            VStack(alignment: .leading, spacing: 10) {
                Text(flag.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Enable in Sorty",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { newValue in
                            UserDefaults.standard.set(newValue, forKey: flag.defaultsKey)

                            withAnimation(.easeOut(duration: 0.2)) {
                                isEnabled = newValue
                            }
                            HapticFeedbackManager.shared.selection()
                        }
                    )
                )
                .toggleStyle(.switch)
                let command = isEnabled ? flag.disableCommand : flag.enableCommand
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(command, forType: .string)
                        HapticFeedbackManager.shared.tap()
                        withAnimation { copied = true }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy command")
                }
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(6)

                Text(flag.restartMessage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            isEnabled = flag.currentValue()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ExperimentalFlag-\(flag.name)")
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}

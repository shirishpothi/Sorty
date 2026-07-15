//
//  ExperimentalSettingsView.swift
//  Sorty
//
//  Experimental features section showing disabled feature flags with enablement guidance
//

import SwiftUI

struct ExperimentalSettingsView: View {
    @EnvironmentObject private var entitlementManager: EntitlementManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("These optional features are intentionally hidden from the main workflow. Use the toggles below to enable or disable them.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProLockedSettingsContent(
                isLocked: !entitlementManager.allowsExperimentalSettings,
                message: "Experimental settings are available with a paid unlock."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(experimentalFlags) { flag in
                        ExperimentalFlagRow(flag: flag)
                    }
                }
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
                restartMessage: "Use Check for Updates after switching channels."
            )
        ]
    }
}

struct ExperimentalFlag: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let defaultsKey: String
    let defaultValue: Bool
    let restartMessage: String

    init(
        name: String,
        description: String,
        defaultsKey: String,
        defaultValue: Bool,
        restartMessage: String = "Relaunch Sorty to ensure all views pick up this change."
    ) {
        self.name = name
        self.description = description
        self.defaultsKey = defaultsKey
        self.defaultValue = defaultValue
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

                Toggle("Enable in Sorty", isOn: featureEnabledBinding)
                    .toggleStyle(.switch)

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

    private var featureEnabledBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                UserDefaults.standard.set(newValue, forKey: flag.defaultsKey)

                withAnimation(.easeOut(duration: 0.2)) {
                    isEnabled = newValue
                }
                HapticFeedbackManager.shared.selection()
            }
        )
    }
}

#Preview {
    ExperimentalSettingsView()
        .environmentObject(AppState())
        .environmentObject(EntitlementManager())
        .frame(width: 500, height: 600)
}

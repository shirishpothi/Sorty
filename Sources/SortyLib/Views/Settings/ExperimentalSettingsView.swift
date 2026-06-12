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
            Text("These optional features are intentionally hidden from the main workflow. Use the toggles below to enable or disable them.")
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
                restartMessage: "Use Check for Updates after switching channels."
            ),
            ExperimentalFlag(
                name: "Workspace Health",
                description: "Shows Workspace Health navigation, menu actions, deeplinks, and shortcuts.",
                defaultsKey: "workspaceHealthEnabled",
                defaultValue: false
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
    @State private var isDeprecationNoticePresented = false

    private let forkURL = URL(string: "https://github.com/sorty-organizer/Sorty/fork")!
    private let featureRequestURL = URL(string: "https://github.com/sorty-organizer/Sorty/issues/new")!

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

                featureToggle

                Text(flag.restartMessage)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .overlay(alignment: .topTrailing) {
            if flag.defaultsKey == "workspaceHealthEnabled" {
                deprecationNoticeButton
                    .padding(12)
            }
        }
        .onAppear {
            isEnabled = flag.currentValue()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ExperimentalFlag-\(flag.name)")
    }

    @ViewBuilder
    private var featureToggle: some View {
        let toggle = Toggle("Enable in Sorty", isOn: featureEnabledBinding)

        if flag.defaultsKey == "workspaceHealthEnabled" {
            toggle.toggleStyle(DeprecatingFeatureToggleStyle())
        } else {
            toggle.toggleStyle(.switch)
        }
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

    private var deprecationNoticeButton: some View {
        Button {
            HapticFeedbackManager.shared.selection()
            isDeprecationNoticePresented.toggle()
        } label: {
            Image(systemName: "scissors")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
                .background(.red.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .help("Workspace Health deprecation warning")
        .accessibilityLabel("Workspace Health deprecation warning") // [VERIFY] confirm label matches intent
        .accessibilityHint("Shows details and options for supporting the feature")
        .popover(isPresented: $isDeprecationNoticePresented, arrowEdge: .top) {
            deprecationNotice
                .systemLiquidGlassPopover(cornerRadius: 12)
        }
    }

    private var deprecationNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scheduled for deprecation", systemImage: "scissors")
                .font(.headline)
                .foregroundStyle(.red)

            Text("Workspace Health is on the chopping block and may be removed from a future version of Sorty.")
                .font(.subheadline)

            Text("To keep it alive, fork the open-source code or file a GitHub issue explaining why the feature should remain.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Link(destination: forkURL) {
                    Label("Fork Sorty", systemImage: "tuningfork")
                }
                .buttonStyle(.sortyBordered(intent: .info, size: .small))
                .trackHoveredURL(forkURL)

                Link(destination: featureRequestURL) {
                    Label("Advocate on GitHub", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.sortyBordered(intent: .primary, size: .small))
                .trackHoveredURL(featureRequestURL)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DeprecatingFeatureToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                configuration.label

                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.accentColor : Color.red.opacity(0.7))

                    Circle()
                        .fill(.white)
                        .padding(3)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                }
                .frame(width: 48, height: 26)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}

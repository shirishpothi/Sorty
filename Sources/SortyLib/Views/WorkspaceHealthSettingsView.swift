//
//  WorkspaceHealthSettingsView.swift
//  Sorty
//
//  Configuration interface for Workspace Health
//

import SwiftUI

struct WorkspaceHealthSettingsView: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    @Environment(\.dismiss) private var dismiss
    
    // Local state for editing
    @State private var config: WorkspaceHealthConfig
    
    init(healthManager: WorkspaceHealthManager) {
        self.healthManager = healthManager
        _config = State(initialValue: healthManager.config)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    thresholdsSection
                    sensitivitySection
                    enabledChecksSection
                    ignoredPathsSection
                }
                .padding(20)
            }

            Divider()

            footerActions
        }
        .frame(minWidth: 620, idealWidth: 680, maxWidth: 820, minHeight: 700, idealHeight: 760)
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: config.enabledChecks)
    }

    private var header: some View {
        HStack(spacing: 14) {
            GlassyBackButton {
                HapticFeedbackManager.shared.tap()
                dismiss()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Workspace Health Rules")
                    .font(.title3.weight(.semibold))
                Text("Tune thresholds and detection checks for cleaner workspace insights.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Reset Defaults") {
                HapticFeedbackManager.shared.tap()
                config = WorkspaceHealthConfig()
            }
            .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                HapticFeedbackManager.shared.tap()
                dismiss()
            }
            .buttonStyle(.sortyBordered(intent: .destructive, size: .small))

            Spacer()

            Button("Done") {
                healthManager.updateConfig(config)
                HapticFeedbackManager.shared.success()
                dismiss()
            }
            .buttonStyle(.onboardingPill(size: .small))
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var thresholdsSection: some View {
        SettingsCard(title: "Thresholds", icon: "slider.horizontal.3", color: .mint) {
            VStack(alignment: .leading, spacing: 14) {
                thresholdSliderRow(
                    title: "Large File Threshold",
                    valueText: ByteCountFormatter.string(fromByteCount: config.largeFileSizeThreshold, countStyle: .file),
                    value: Binding(
                        get: { Double(config.largeFileSizeThreshold) },
                        set: { config.largeFileSizeThreshold = Int64($0) }
                    ),
                    range: 10_000_000...1_000_000_000,
                    step: 10_000_000,
                    minLabel: "10 MB",
                    maxLabel: "1 GB"
                )

                thresholdSliderRow(
                    title: "Old File Threshold",
                    valueText: "\(Int(config.oldFileThreshold / 86400)) days",
                    value: Binding(
                        get: { config.oldFileThreshold / 86400 },
                        set: { config.oldFileThreshold = $0 * 86400 }
                    ),
                    range: 30...730,
                    step: 30,
                    minLabel: "1m",
                    maxLabel: "2y"
                )

                thresholdSliderRow(
                    title: "Download Clutter Threshold",
                    valueText: "\(Int(config.downloadClutterThreshold / 86400)) days",
                    value: Binding(
                        get: { config.downloadClutterThreshold / 86400 },
                        set: { config.downloadClutterThreshold = $0 * 86400 }
                    ),
                    range: 7...90,
                    step: 7,
                    minLabel: "1w",
                    maxLabel: "3m"
                )
            }
        }
    }

    private var sensitivitySection: some View {
        SettingsCard(title: "Detection Sensitivity", icon: "scope", color: .teal) {
            VStack(alignment: .leading, spacing: 14) {
                thresholdSliderRow(
                    title: "Min Screenshots",
                    valueText: "\(config.minScreenshotCount)",
                    value: Binding(
                        get: { Double(config.minScreenshotCount) },
                        set: { config.minScreenshotCount = Int($0) }
                    ),
                    range: 5...50,
                    step: 1,
                    minLabel: "5",
                    maxLabel: "50"
                )

                thresholdSliderRow(
                    title: "Min Download Files",
                    valueText: "\(config.minDownloadCount)",
                    value: Binding(
                        get: { Double(config.minDownloadCount) },
                        set: { config.minDownloadCount = Int($0) }
                    ),
                    range: 3...50,
                    step: 1,
                    minLabel: "3",
                    maxLabel: "50"
                )

                thresholdSliderRow(
                    title: "Min Unorganized Files",
                    valueText: "\(config.minUnorganizedCount)",
                    value: Binding(
                        get: { Double(config.minUnorganizedCount) },
                        set: { config.minUnorganizedCount = Int($0) }
                    ),
                    range: 5...50,
                    step: 1,
                    minLabel: "5",
                    maxLabel: "50"
                )

                thresholdSliderRow(
                    title: "Min Old Files",
                    valueText: "\(config.minOldFileCount)",
                    value: Binding(
                        get: { Double(config.minOldFileCount) },
                        set: { config.minOldFileCount = Int($0) }
                    ),
                    range: 5...50,
                    step: 1,
                    minLabel: "5",
                    maxLabel: "50"
                )
            }
        }
    }

    private var enabledChecksSection: some View {
        SettingsCard(title: "Enabled Checks", icon: "checklist", color: .green) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                ForEach(CleanupOpportunity.OpportunityType.allCases, id: \.self) { type in
                    Toggle(isOn: Binding(
                        get: { config.enabledChecks.contains(type) },
                        set: { isEnabled in
                            if isEnabled {
                                config.enabledChecks.insert(type)
                            } else {
                                config.enabledChecks.remove(type)
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: type.icon)
                                .foregroundStyle(type.color)
                                .frame(width: 18)
                            Text(type.rawValue)
                                .font(.subheadline)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var ignoredPathsSection: some View {
        SettingsCard(title: "Ignored Paths", icon: "folder.badge.questionmark", color: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                if config.ignoredPaths.isEmpty {
                    Text("No ignored paths yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ForEach(Array(config.ignoredPaths.enumerated()), id: \.offset) { index, path in
                        HStack(spacing: 10) {
                            PrivacySensitivePathText(path: path)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 8)

                            Button {
                                HapticFeedbackManager.shared.tap()
                                config.ignoredPaths.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove path")
                        }
                        .padding(.vertical, 4)

                        if index < config.ignoredPaths.count - 1 {
                            Divider()
                        }
                    }
                }

                Button("Add Ignored Path...") {
                    HapticFeedbackManager.shared.tap()
                    addIgnoredPaths()
                }
                .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                .padding(.top, 4)
            }
        }
    }

    private func thresholdSliderRow(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        minLabel: String,
        maxLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Spacer()

                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step)
                .tint(.mint)

            HStack {
                Text(minLabel)
                Spacer()
                Text(maxLabel)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func addIgnoredPaths() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        var didAddPath = false
        for url in panel.urls where !config.ignoredPaths.contains(url.path) {
            config.ignoredPaths.append(url.path)
            didAddPath = true
        }

        if didAddPath {
            HapticFeedbackManager.shared.success()
        }
    }
}

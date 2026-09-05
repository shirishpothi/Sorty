//
//  ExperimentalSettingsView.swift
//  Sorty
//
//  PostHog-backed experimental features
//

import SwiftUI

struct ExperimentalSettingsView: View {
    @SortyHotReload private var hotReload
    @ObservedObject private var analytics = AnalyticsManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 12) {
            if isCodexSkillInstallerEnabled {
                CodexSkillInstallerCard()
            }

            Group {
                if analytics.isLoadingExperimentalFeatures {
                    loadingState
                } else if !otherExperimentalFeatures.isEmpty {
                    featureList
                } else if !isCodexSkillInstallerEnabled {
                    emptyState
                }
            }
        }
        // Section-level target: the card, list, or empty state swap
        // conditionally, so the focus ID must live on the container
        // that is always present.
        .settingsFocusable(.experimentalEmptyState)
        .task {
            analytics.reloadExperimentalFeatures()
            guard !hasAppeared else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            hasAppeared = true
        }
    }

    private var isCodexSkillInstallerEnabled: Bool {
        FeatureFlags.codexSkillInstallerEnabled
            || analytics.experimentalFeatures.contains { $0.id == FeatureFlags.codexSkillInstallerKey }
    }

    private var otherExperimentalFeatures: [ExperimentalFeature] {
        analytics.experimentalFeatures.filter { $0.id != FeatureFlags.codexSkillInstallerKey }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Checking the lab…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .systemLiquidGlassBackground(cornerRadius: 12, interactive: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Checking for experimental features.")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image("ExperimentalEmptyState")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 92, height: 92)
                .accessibilityIgnoresInvertColors()
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.8)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.5, dampingFraction: 0.7).delay(0.1),
                    value: hasAppeared
                )
                .accessibilityHidden(true)

            Text("The lab is quiet")
                .font(.subheadline.bold())
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.5, dampingFraction: 0.8).delay(0.2),
                    value: hasAppeared
                )

            Text("Sorty has no experimental features available right now.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.5, dampingFraction: 0.8).delay(0.3),
                    value: hasAppeared
                )
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .systemLiquidGlassBackground(cornerRadius: 12, interactive: false)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No experimental features are available right now.")
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(otherExperimentalFeatures) { feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 28, height: 28)
                        .background(.indigo.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(feature.title)
                                .font(.subheadline.weight(.semibold))
                            if let variant = feature.variant {
                                Text(variant)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                        Text(feature.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if feature.id != otherExperimentalFeatures.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemLiquidGlassBackground(cornerRadius: 12, interactive: false)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 8)
        .animation(
            reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.45, dampingFraction: 0.82),
            value: hasAppeared
        )
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 320)
        .padding(24)
}

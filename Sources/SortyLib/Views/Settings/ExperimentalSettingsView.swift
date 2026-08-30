//
//  ExperimentalSettingsView.swift
//  Sorty
//
//  PostHog-backed experimental features
//

import SwiftUI

struct ExperimentalSettingsView: View {
    @ObservedObject private var analytics = AnalyticsManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @AppStorage(FeatureFlags.legacyDeeplinksDefaultsKey) private var legacyDeeplinksEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            legacyDeeplinksCard
            if analytics.isLoadingExperimentalFeatures {
                loadingState
            } else if !analytics.experimentalFeatures.isEmpty {
                featureList
            }
        }
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

    private var legacyDeeplinksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $legacyDeeplinksEnabled) {
                Label("Legacy deep links", systemImage: "link.badge.plus")
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.switch)
            .onChange(of: legacyDeeplinksEnabled) { _, isEnabled in
                AnalyticsManager.shared.captureFeature(
                    feature: "experimental",
                    subfeature: "legacy_deeplinks",
                    action: isEnabled ? "enabled" : "disabled",
                    outcome: "success"
                )
            }

            Text("Restores external sorty:// automation links. This compatibility layer is off by default and is on the chopping block.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link(
                "Ask us to keep it",
                destination: URL(string: "https://github.com/sorty-organizer/Sorty/issues/new?title=Keep%20legacy%20deep%20links")!
            )
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
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
        .systemLiquidGlassBackground(cornerRadius: 12)
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
        .systemLiquidGlassBackground(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .settingsFocusable(.experimentalEmptyState)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No experimental features are available right now.")
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(analytics.experimentalFeatures) { feature in
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

                if feature.id != analytics.experimentalFeatures.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .settingsFocusable(.experimentalEmptyState)
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

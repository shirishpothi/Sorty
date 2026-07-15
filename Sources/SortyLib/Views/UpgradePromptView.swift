import SwiftUI

struct UpgradePromptView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var appState: AppState

    let capability: ProductCapability

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 18) {
                ZStack {
                    AccessibleLiquidGlassPanel(cornerRadius: 22)
                        .frame(width: 84, height: 84)

                    Image(systemName: capability.systemImage)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.88))
                        .accessibilityHidden(true)
                }

                VStack(spacing: 10) {
                    Text("\(capability.displayName) needs an unlock")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text(capability.unlockSummary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)

                    if let primaryUnlock = EntitlementCatalog.shared.primaryUnlock(for: capability) {
                        Text("Unlock with \(primaryUnlock.title) or the \(ProductSKU.proBundle.displayName) bundle.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            Text(statusMessage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    AccessibleLiquidGlassPanel(cornerRadius: 999)
                )

            OpenLicensingButton(size: .regular)
                .accessibilityIdentifier("UpgradePromptOpenLicensingButton")

            HStack(spacing: 12) {
                Button {
                    Task {
                        let restored = await entitlementManager.restorePurchases()
                        if restored {
                            HapticFeedbackManager.shared.success()
                        } else {
                            HapticFeedbackManager.shared.error()
                        }
                    }
                } label: {
                    Label("Restore", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.onboardingPill(isSecondary: true))
                .disabled(entitlementManager.isSyncing || !entitlementManager.hasStoredPurchases)

                Button {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(reduceMotion ? nil : .pageTransition) {
                        appState.currentView = .organize
                    }
                } label: {
                    Label("Back to Organize", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.onboardingPill(isSecondary: true))
            }
            .accessibilityIdentifier("UpgradePromptBackButton")
        }
        .padding(34)
        .frame(maxWidth: 580)
        .background(
            AccessibleLiquidGlassPanel(cornerRadius: 30)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 28, y: 14)
        .accessibilityIdentifier("UpgradePromptView_\(capability.rawValue)")
    }

    private var statusMessage: String {
        switch entitlementManager.state {
        case .unknown, .free:
            return "You're currently using Sorty's free core tier."
        case .partiallyUnlocked:
            return "Some paid unlocks are active on this device, but this capability is still locked."
        case .bundleUnlocked:
            return "This feature should be available in the active bundle. If you still see this message, refresh entitlements."
        case .grace(_, let expiresAt):
            if let expiresAt {
                return "Your previous unlock is in grace mode until \(expiresAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return "Your previous unlock is in grace mode."
        case .expired:
            return "Your previous unlock has expired, so Sorty is currently using free-core access rules."
        }
    }
}

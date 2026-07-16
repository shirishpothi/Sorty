import SwiftUI

struct LicensingSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var entitlementManager: EntitlementManager

    @State private var licenseKey = ""
    @State private var isHoveringActivate = false
    @State private var isHoveringRefresh = false
    @State private var isHoveringRestore = false
    @State private var isHoveringRemove = false
    @State private var isShowingRemoveConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            statusCard
                .animatedAppearance(delay: 0.02)

            activationCard
                .animatedAppearance(delay: 0.06)

            if !entitlementManager.activeLicenses.isEmpty || !entitlementManager.snapshot.unlockedEntitlements.isEmpty {
                unlockedAccessCard
                    .animatedAppearance(delay: 0.1)
            }

            policyCard
                .animatedAppearance(delay: 0.14)
        }
        .confirmationDialog(
            "Remove the Sorty license from this Mac?",
            isPresented: $isShowingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove License", role: .destructive, action: removeLicense)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sorty will remove the license key and encrypted verification cache stored on this Mac. You can activate again later with the same Gumroad license key.")
        }
    }

    private var statusCard: some View {
        SettingsCard(title: "License Status", icon: "checkmark.seal", color: .mint) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(statusHeadline)
                            .font(.headline)

                        Text(statusBadge)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .systemLiquidGlassBackground(cornerRadius: 999)
                    }

                    Text(statusSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let validatedAt = entitlementManager.validatedAt
                    ?? entitlementManager.nextValidationAt?.addingTimeInterval(-86_400) {
                    detailRow("Last verified", value: validatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let nextValidationAt = entitlementManager.nextValidationAt {
                    detailRow("Next refresh", value: nextValidationAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let graceExpiresAt = entitlementManager.graceExpiresAt {
                    detailRow("Offline grace until", value: graceExpiresAt.formatted(date: .abbreviated, time: .shortened))
                }

                if let customerEmail = entitlementManager.customerEmail, !customerEmail.isEmpty {
                    detailRow("Licensed email", value: customerEmail)
                }

                if let warningMessage = entitlementManager.warningMessage, !warningMessage.isEmpty {
                    Label(warningMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let lastError = entitlementManager.lastErrorMessage, !lastError.isEmpty {
                    Label(lastError, systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var activationCard: some View {
        SettingsCard(title: "Activation", icon: "key.horizontal", color: .orange) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Get Sorty Pro on Gumroad")
                            .font(.subheadline.weight(.semibold))
                        Text("After checkout, copy the license key from your Gumroad receipt and paste it below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Link(destination: entitlementManager.purchaseURL) {
                        Label("Get a License Key", systemImage: "cart")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .accessibilityHint("Opens the Sorty product page on Gumroad")
                }

                Divider()

                SettingsSecureField(
                    title: "Gumroad license key",
                    text: $licenseKey
                )

                HStack(spacing: 10) {
                    actionButton(
                        title: entitlementManager.isSyncing && entitlementManager.syncReason == .activate ? "Activating..." : "Activate Key",
                        systemImage: "checkmark.circle.fill",
                        isHovered: $isHoveringActivate,
                        tint: .orange
                    ) {
                        Task {
                            let succeeded = await entitlementManager.activate(licenseKey: licenseKey)
                            if succeeded {
                                HapticFeedbackManager.shared.success()
                                licenseKey = ""
                            } else {
                                HapticFeedbackManager.shared.error()
                            }
                        }
                    }
                    .disabled(entitlementManager.isSyncing || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    actionButton(
                        title: entitlementManager.isSyncing && entitlementManager.syncReason == .refresh ? "Refreshing..." : "Refresh Access",
                        systemImage: "arrow.clockwise",
                        isHovered: $isHoveringRefresh,
                        tint: .blue
                    ) {
                        Task {
                            let succeeded = await entitlementManager.refreshEntitlements(force: true)
                            succeeded ? HapticFeedbackManager.shared.success() : HapticFeedbackManager.shared.error()
                        }
                    }
                    .disabled(entitlementManager.isSyncing || !entitlementManager.hasStoredPurchases)

                    actionButton(
                        title: entitlementManager.isSyncing && entitlementManager.syncReason == .restore ? "Restoring..." : "Restore on This Mac",
                        systemImage: "arrow.uturn.backward.circle",
                        isHovered: $isHoveringRestore,
                        tint: .green
                    ) {
                        Task {
                            let succeeded = await entitlementManager.restorePurchases()
                            succeeded ? HapticFeedbackManager.shared.success() : HapticFeedbackManager.shared.error()
                        }
                    }
                    .disabled(entitlementManager.isSyncing || !entitlementManager.hasStoredPurchases)
                }

                Divider()

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("License storage")
                            .font(.subheadline.weight(.semibold))
                        Text("Sorty stores the key in Keychain and an encrypted verification cache on this Mac. Removing it returns this installation to the free tier.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    actionButton(
                        title: "Remove License",
                        systemImage: "trash",
                        isHovered: $isHoveringRemove,
                        tint: .red
                    ) {
                        isShowingRemoveConfirmation = true
                    }
                    .disabled(entitlementManager.isSyncing || !entitlementManager.hasStoredPurchases)
                }
            }
        }
    }

    private var unlockedAccessCard: some View {
        SettingsCard(title: "Unlocked Access", icon: "sparkles", color: .accentColor) {
            VStack(alignment: .leading, spacing: 14) {
                if !entitlementManager.activeLicenses.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active purchases on this Mac")
                            .font(.subheadline.weight(.semibold))

                        ForEach(entitlementManager.activeLicenses) { license in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "ticket")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(license.productName)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(license.sku.displayName) • \(license.keyHint)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let email = license.email, !email.isEmpty {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }

                                Spacer()
                            }
                        }
                    }
                }

                if !entitlementManager.snapshot.unlockedEntitlements.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Capabilities active right now")
                            .font(.subheadline.weight(.semibold))

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], alignment: .leading, spacing: 8) {
                            ForEach(Array(entitlementManager.snapshot.unlockedEntitlements).sorted(by: { $0.displayName < $1.displayName }), id: \.self) { entitlement in
                                Text(entitlement.displayName)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .systemLiquidGlassBackground(cornerRadius: 999)
                            }
                        }
                    }
                }
            }
        }
    }

    private var policyCard: some View {
        SettingsCard(title: "How Sorty Licensing Works", icon: "doc.text", color: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                policyRow(
                    icon: "tray.full",
                    title: "Free core stays usable",
                    description: "Free tier includes 5 local organizations, 1 watched folder, 1 storage location, basic notifications, and the supported free providers."
                )
                policyRow(
                    icon: "bag",
                    title: "Bring your own provider costs",
                    description: "Paid Sorty unlocks do not include inference. Your OpenAI, Anthropic, Gemini, or Apple Foundation costs remain on your own account."
                )
                policyRow(
                    icon: "checkmark.shield",
                    title: "Direct Gumroad verification",
                    description: "Sorty sends the product ID and license key directly to Gumroad over HTTPS, then keeps the key in Keychain and the last verified access state in encrypted local storage for seven days of offline use."
                )
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }

    private func policyRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isHovered: Binding<Bool>,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            HapticFeedbackManager.shared.tap()
            action()
        }) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(tint.opacity(isHovered.wrappedValue ? 0.24 : 0.14))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(tint.opacity(isHovered.wrappedValue ? 0.45 : 0.2), lineWidth: 1)
                )
                .offset(y: isHovered.wrappedValue && !reduceMotion ? -1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isHovered.wrappedValue)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard hovering != isHovered.wrappedValue else { return }
            isHovered.wrappedValue = hovering
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
    }

    private func removeLicense() {
        Task {
            let succeeded = await entitlementManager.removeLicense()
            succeeded ? HapticFeedbackManager.shared.success() : HapticFeedbackManager.shared.error()
        }
    }

    private var statusHeadline: String {
        switch entitlementManager.state {
        case .unknown:
            return "Checking access"
        case .free:
            return "Free core active"
        case .partiallyUnlocked:
            return "Paid unlocks active"
        case .bundleUnlocked:
            return "Sorty Pro active"
        case .grace:
            return "Grace period active"
        case .expired:
            return "License expired"
        }
    }

    private var statusBadge: String {
        switch entitlementManager.state {
        case .unknown:
            return "Checking"
        case .free:
            return "Free"
        case .partiallyUnlocked:
            return "Partial"
        case .bundleUnlocked:
            return "Pro"
        case .grace:
            return "Grace"
        case .expired:
            return "Expired"
        }
    }

    private var statusColor: Color {
        switch entitlementManager.state {
        case .unknown:
            return .secondary
        case .free:
            return .blue
        case .partiallyUnlocked, .bundleUnlocked:
            return .green
        case .grace:
            return .orange
        case .expired:
            return .red
        }
    }

    private var statusSummary: String {
        switch entitlementManager.state {
        case .unknown:
            return "Sorty is loading the last known entitlement state and will refresh it when the service is available."
        case .free:
            return "No paid licenses are currently active on this Mac. Free tier includes 5 local organizations, 1 watched folder, 1 storage location, and the supported providers."
        case .partiallyUnlocked(let entitlements):
            return "This Mac has \(entitlements.count) paid \(entitlements.count == 1 ? "unlock" : "unlocks") active. Feature gates update immediately after Gumroad verification."
        case .bundleUnlocked:
            return "The full Sorty Pro bundle is active on this Mac. All paid capabilities and the premium provider pack are unlocked."
        case .grace(_, let expiresAt):
            if let expiresAt {
                return "Sorty is holding onto the last verified access state while the service is unavailable. Grace ends on \(expiresAt.formatted(date: .abbreviated, time: .shortened))."
            }
            return "Sorty is holding onto the last verified access state while the service is unavailable."
        case .expired:
            return "The previous paid access state is no longer valid, so Sorty has downgraded to free-core rules until the licenses are refreshed."
        }
    }
}

#Preview("Licensing Settings") {
    let appState = AppState()
    return LicensingSettingsView()
        .environmentObject(EntitlementManager.shared)
        .environmentObject(appState)
        .frame(width: 900, height: 640)
}

import SwiftUI
import TourKit

public struct WhatsNewTourView: View {
    @Binding private var nightlyUpdatesEnabled: Bool
    private let onFinish: () -> Void

    public init(
        nightlyUpdatesEnabled: Binding<Bool>,
        onFinish: @escaping () -> Void
    ) {
        _nightlyUpdatesEnabled = nightlyUpdatesEnabled
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 16) {
            TourSlideshowView(
                pages: pages,
                continueButtonTitle: "Continue",
                finishButtonTitle: "Start using Sorty",
                onFinish: onFinish,
                onClose: onFinish
            )

            nightlyUpdatesCard
        }
        .padding(.bottom, 18)
        .frame(width: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var nightlyUpdatesCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 36, height: 36)
                .background(Color.purple.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Get future nightly builds")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("This update is available on the regular release channel. Turn on nightlies if you want newer, more fragile builds after this one.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("Nightly", isOn: $nightlyUpdatesEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Enable nightly builds")
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var pages: [TourPage] {
        [
            TourPage(
                imageName: "whats-new-design-system.png",
                imageBundle: .module,
                title: "A cleaner Sorty",
                description: "This build introduces the new design system: calmer surfaces, clearer hierarchy, and a friendlier organizer flow."
            ),
            TourPage(
                imageName: "whats-new-preview.png",
                imageBundle: .module,
                title: "Preview before files move",
                description: "Review Sorty’s suggested folders and file moves before applying anything to your Mac."
            ),
            TourPage(
                imageName: "whats-new-nightly.png",
                imageBundle: .module,
                title: "Nightlies are now available",
                description: "Everyone gets this first nightly-style build through the normal updater. Future nightly builds are optional and may be less polished."
            ),
        ]
    }
}

#Preview {
    WhatsNewTourView(nightlyUpdatesEnabled: .constant(false)) {}
}

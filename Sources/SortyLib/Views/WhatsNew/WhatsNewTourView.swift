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
            updateChannelCard

            TourSlideshowView(
                pages: pages,
                width: 760,
                continueButtonTitle: "Continue",
                finishButtonTitle: "Start using Sorty",
                onFinish: onFinish,
                onClose: onFinish
            )

            nightlyUpdatesCard
        }
        .padding(.bottom, 20)
        .frame(width: 820)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var updateChannelCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.18), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 5) {
                Text("Available from the regular updater")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Everyone on Sorty 1.1.2 can find this build with Check for Updates. After installing it, you can choose whether future checks use stable or nightly builds.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.top, 18)
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
                title: "A cleaner organizer",
                description: "The main Sorty flow now has a calmer sidebar, clearer folder drop zone, and a more polished visual system."
            ),
            TourPage(
                imageName: "whats-new-preview.png",
                imageBundle: .module,
                title: "Choose how Sorty handles files",
                description: "Pick Organize Only, Organize & Rename, or Rename Only before choosing a folder."
            ),
            TourPage(
                imageName: "whats-new-nightly.png",
                imageBundle: .module,
                title: "Nightly builds are available",
                description: "This build arrives through the normal updater. Turn on Nightly Updates only if you want future, less-polished builds."
            ),
        ]
    }
}

#Preview {
    WhatsNewTourView(nightlyUpdatesEnabled: .constant(false)) {}
}

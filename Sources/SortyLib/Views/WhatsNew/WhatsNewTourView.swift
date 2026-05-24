import SwiftUI

public struct WhatsNewTourView: View {
    @Binding private var nightlyUpdatesEnabled: Bool
    private let onFinish: () -> Void
    @State private var currentPage = 0
    @State private var workflowImageIndex = 0

    public init(
        nightlyUpdatesEnabled: Binding<Bool>,
        onFinish: @escaping () -> Void
    ) {
        _nightlyUpdatesEnabled = nightlyUpdatesEnabled
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 12) {
            if currentPage == 0 {
                updateChannelCard
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ZStack {
                tourPage(page)
                    .id(currentPage)
                    .transition(.opacity)
            }

            if currentPage == pages.count - 1 {
                nightlyUpdatesCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.vertical, 16)
        .frame(width: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.24), value: currentPage)
        .onReceive(
            Timer.publish(every: 3.8, on: .main, in: .common).autoconnect()
        ) { _ in
            guard currentPage == 0 else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                workflowImageIndex = (workflowImageIndex + 1) % workflowImages.count
            }
        }
    }

    private var updateChannelCard: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("Available from the regular updater")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Everyone on Sorty 1.1.2 can find this build with Check for Updates. After installing it, you can choose whether future checks use stable or nightly builds.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
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
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 18)
    }

    private var page: WhatsNewPage {
        pages[currentPage]
    }

    private var pages: [WhatsNewPage] {
        [
            WhatsNewPage(
                imageNames: workflowImages,
                title: "Choose the right flow",
                description: "Start with Organize Only, Organize & Rename, or Rename Only from the same compact control."
            ),
            WhatsNewPage(
                imageName: "whats-new-mid-generation.png",
                title: "A new design system",
                description: "The organize and rename flows now share cleaner controls, calmer spacing, and the new mid-generation surface."
            ),
            WhatsNewPage(
                imageName: "whats-new-nightly.png",
                title: "Choose future builds",
                description: "Keep stable updates by default, or turn on nightlies if you want newer, less-polished builds after this release."
            ),
        ]
    }

    private var workflowImages: [String] {
        ["whats-new-preview.png", "whats-new-rename-only.png"]
    }

    private func tourPage(_ page: WhatsNewPage) -> some View {
        VStack(spacing: 0) {
            imageSection(page)

            VStack(spacing: 6) {
                pageIndicator

                Text(page.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.description)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)

                actionButton
                    .padding(.top, 12)
            }
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .frame(width: 640)
        .background(Color(white: 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        }
    }

    private func imageSection(_ page: WhatsNewPage) -> some View {
        ZStack(alignment: .top) {
            Image(page.imageNames[imageIndex(for: page)], bundle: .module)
                .resizable()
                .scaledToFill()
                .frame(width: 640, height: 360)
                .clipped()
                .id(page.imageNames[imageIndex(for: page)])
                .transition(.opacity)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color(white: 0.10).opacity(0.20), location: 0.45),
                    .init(color: Color(white: 0.10), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            topControls
        }
        .frame(width: 640, height: 360)
        .animation(.easeInOut(duration: 0.45), value: workflowImageIndex)
    }

    private func imageIndex(for page: WhatsNewPage) -> Int {
        page.imageNames.count > 1 ? workflowImageIndex : 0
    }

    private var topControls: some View {
        HStack {
            Button {
                guard currentPage > 0 else { return }
                currentPage -= 1
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .opacity(currentPage == 0 ? 0 : 1)
            .disabled(currentPage == 0)

            Spacer()

            Button(action: onFinish) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close What's New")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == currentPage ? Color.white.opacity(0.95) : Color.white.opacity(0.32))
                    .frame(width: index == currentPage ? 22 : 7, height: 7)
            }
        }
        .padding(.bottom, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
    }

    private var actionButton: some View {
        Button {
            if currentPage == pages.count - 1 {
                onFinish()
            } else {
                currentPage += 1
            }
        } label: {
            Text(currentPage == pages.count - 1 ? "Start using Sorty" : "Continue")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 200, height: 40)
                .background(Color.accentColor)
                .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }
}

private struct WhatsNewPage: Identifiable, Hashable {
    let id = UUID()
    let imageNames: [String]
    let title: String
    let description: String

    init(imageName: String, title: String, description: String) {
        self.imageNames = [imageName]
        self.title = title
        self.description = description
    }

    init(imageNames: [String], title: String, description: String) {
        self.imageNames = imageNames
        self.title = title
        self.description = description
    }
}

#Preview {
    WhatsNewTourView(nightlyUpdatesEnabled: .constant(false)) {}
}

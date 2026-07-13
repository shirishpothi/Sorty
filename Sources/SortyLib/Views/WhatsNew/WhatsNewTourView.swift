import AppKit
import SwiftUI

public struct WhatsNewTourView: View {
    private let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let imageTransitionAnimation = Animation.easeInOut(duration: 0.72)
    @State private var currentPage = 0
    @State private var workflowImageIndex = 0
    @State private var isActionHovering = false

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 12) {
            ZStack {
                tourPage(page)
                    .id(currentPage)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 16)
        .frame(width: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeOut(duration: 0.18), value: currentPage)
        .onReceive(
            Timer.publish(every: 3.8, on: .main, in: .common).autoconnect()
        ) { _ in
            guard page.imageNames.count > 1 else { return }
            withAnimation(imageTransitionAnimation) {
                workflowImageIndex = (workflowImageIndex + 1) % page.imageNames.count
            }
        }
    }

    private var page: WhatsNewPage {
        pages[currentPage]
    }

    private var pages: [WhatsNewPage] {
        [
            WhatsNewPage(
                imageName: "whats-new-preview.png",
                title: "Choose the right flow",
                description: "Start with Organize Only, Organize & Rename, or Rename Only from the same compact control."
            ),
            WhatsNewPage(
                imageNames: designSystemImages,
                title: "A new design system",
                description: "The organize and rename flows now share cleaner controls, calmer spacing, and the new mid-generation surface."
            ),
            WhatsNewPage(
                title: "Everything in Sorty 1.2.0",
                description: "A major release focused on capability, clarity, and reliability."
            ),
        ]
    }

    private var designSystemImages: [String] {
        [
            "whats-new-design-system-5.png",
            "whats-new-design-system-2.png",
            "whats-new-design-system-3.png",
            "whats-new-design-system-4.png",
            "whats-new-design-system-1.png",
        ]
    }

    private func tourPage(_ page: WhatsNewPage) -> some View {
        VStack(spacing: 0) {
            if currentPage == pages.count - 1 {
                releaseSummary
            } else {
                imageSection(page)
            }

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

    private var releaseSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sorty 1.2.0")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                topControls
                    .padding(0)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    releaseSection(
                        title: "New",
                        symbol: "sparkles",
                        color: .cyan,
                        items: [
                            "Cloud and external storage organization",
                            "Finder integration diagnostics",
                            "Sensitive action protection",
                            "Privacy-safe paths",
                        ]
                    )
                    releaseSection(
                        title: "Improved",
                        symbol: "arrow.up.right.circle.fill",
                        color: .green,
                        items: [
                            "Focused organization experience",
                            "Native Mac design",
                            "Smarter organization decisions",
                            "Cloud reliability",
                            "Learnings and history portability",
                            "Updates and downloads",
                        ]
                    )
                    releaseSection(
                        title: "Fixed",
                        symbol: "wrench.and.screwdriver.fill",
                        color: .orange,
                        items: [
                            "Fresh-download setup",
                            "Finder extension recovery",
                            "Storage safety",
                            "Organization and history reliability",
                            "Compatibility and lifecycle stability",
                        ]
                    )
                }
                .padding(.trailing, 12)
            }
        }
        .padding(28)
        .frame(width: 640, height: 400, alignment: .topLeading)
        .background(Color(white: 0.10))
    }

    private func releaseSection(title: String, symbol: String, color: Color, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(color)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Circle()
                        .fill(Color.white.opacity(0.48))
                        .frame(width: 4, height: 4)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(Color.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func imageSection(_ page: WhatsNewPage) -> some View {
        ZStack(alignment: .top) {
            if let imageName = page.activeImageName(at: imageIndex(for: page)) {
                bundledImage(imageName)
                    .frame(width: 640, height: 400)
                    .id(imageName)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 1.006)),
                            removal: .opacity.combined(with: .scale(scale: 0.994))
                        )
                    )
            } else {
                finderIntegrationPreview
                    .frame(width: 640, height: 400)
            }

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
        .frame(width: 640, height: 400)
        .animation(imageTransitionAnimation, value: workflowImageIndex)
    }

    private func imageIndex(for page: WhatsNewPage) -> Int {
        page.imageNames.count > 1 ? workflowImageIndex : 0
    }

    @ViewBuilder
    private func bundledImage(_ name: String) -> some View {
        if let image = WhatsNewImageLoader.image(named: name) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            missingImagePlaceholder(name)
        }
    }

    private func missingImagePlaceholder(_ name: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            Text(name)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var finderIntegrationPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: 500, height: 276)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(Color.red.opacity(0.85)).frame(width: 10, height: 10)
                    Circle().fill(Color.yellow.opacity(0.85)).frame(width: 10, height: 10)
                    Circle().fill(Color.green.opacity(0.85)).frame(width: 10, height: 10)
                    Spacer()
                    Image(systemName: "folder")
                        .foregroundStyle(.cyan)
                }
                .padding(16)

                Divider().overlay(Color.white.opacity(0.12))

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        finderSidebarRow("Downloads", icon: "arrow.down.circle", isActive: true)
                        finderSidebarRow("Desktop", icon: "desktopcomputer", isActive: false)
                        finderSidebarRow("Documents", icon: "doc.text", isActive: false)
                    }
                    .padding(14)
                    .frame(width: 160, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.white.opacity(0.04))

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(["Invoices", "Screenshots", "Loose PDFs"], id: \.self) { folder in
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.cyan)
                                Text(folder)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))
                                Spacer()
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: 500, height: 276)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 7) {
                finderMenuItem("Organize with Sorty", icon: "sparkles", isPrimary: true)
                finderMenuItem("Watch with Sorty", icon: "eye", isPrimary: false)
                Divider().overlay(Color.white.opacity(0.12))
                finderMenuItem("Repair Finder Extension", icon: "puzzlepiece.extension", isPrimary: false)
            }
            .padding(10)
            .frame(width: 220)
            .background(Color(white: 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .offset(x: 136, y: 58)
        }
    }

    private func finderSidebarRow(_ title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(isActive ? .cyan : .white.opacity(0.46))
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isActive ? .white.opacity(0.9) : .white.opacity(0.58))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isActive ? Color.cyan.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func finderMenuItem(_ title: String, icon: String, isPrimary: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(isPrimary ? .cyan : .white.opacity(0.7))
            Text(title)
                .font(.system(size: 12, weight: isPrimary ? .semibold : .medium, design: .rounded))
                .foregroundStyle(.white.opacity(isPrimary ? 0.95 : 0.78))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(isPrimary ? Color.cyan.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                    .systemLiquidGlassBackground(cornerRadius: 999)
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
                    .systemLiquidGlassBackground(cornerRadius: 999)
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
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(width: 156, height: 24)
        }
        .buttonStyle(.onboardingPill)
        .overlay {
            GeometryReader { proxy in
                Rectangle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: .white.opacity(0.52), location: 0),
                                .init(color: .white.opacity(0.18), location: 0.24),
                                .init(color: .white.opacity(0.06), location: 0.46),
                                .init(color: .clear, location: 0.78),
                            ],
                            center: UnitPoint(x: 0.5, y: -0.22),
                            startRadius: 0,
                            endRadius: max(proxy.size.width * 0.58, 1)
                        )
                    )
                    .blur(radius: 4)
            }
            .clipShape(Capsule())
            .blendMode(.screen)
            .opacity(reduceTransparency ? 0 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .onboardingBeamBorder(
            variant: currentPage == pages.count - 1 ? .featured : .info,
            active: true,
            isIntensified: isActionHovering,
            includesInteriorGlow: isActionHovering
        )
        .contentShape(Capsule())
        .scaleEffect(isActionHovering ? 1.03 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.84), value: isActionHovering)
        .onHover { hovering in
            if hovering && !isActionHovering {
                HapticFeedbackManager.shared.selection()
            }
            isActionHovering = hovering
        }
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

    init(title: String, description: String) {
        self.imageNames = []
        self.title = title
        self.description = description
    }

    init(imageNames: [String], title: String, description: String) {
        self.imageNames = imageNames
        self.title = title
        self.description = description
    }

    func activeImageName(at index: Int) -> String? {
        guard imageNames.indices.contains(index) else { return nil }
        return imageNames[index]
    }
}

private enum WhatsNewImageLoader {
    static func image(named name: String) -> NSImage? {
        let resourceName = (name as NSString).deletingPathExtension
        let resourceExtension = (name as NSString).pathExtension

        if let url = Bundle.module.url(forResource: resourceName, withExtension: resourceExtension),
           let image = NSImage(contentsOf: url) {
            return image
        }

        if let url = Bundle.module.url(forResource: name, withExtension: nil),
           let image = NSImage(contentsOf: url) {
            return image
        }

        return NSImage(named: name)
    }
}

#Preview {
    WhatsNewTourView {}
}

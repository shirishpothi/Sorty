import SwiftUI

public struct ProviderLogoView: View {
    public let provider: AIProvider
    public var size: CGFloat = 24

    public init(provider: AIProvider, size: CGFloat = 24) {
        self.provider = provider
        self.size = size
    }

    private var providerImage: Image {
        if provider.usesSystemImage {
            return Image(systemName: provider.logoImageName)
        }

        if let nsImage = resolvedProviderImage() {
            nsImage.isTemplate = !provider.hasColorLogo
            return Image(nsImage: nsImage)
        }

        return Image(systemName: "cpu")
    }

    private func resolvedProviderImage() -> NSImage? {
        if let image = SortyResources.image(named: provider.logoImageName), isUsableProviderImage(image) {
            return image
        }

        // AppKit named lookup covers assets compiled into the app-level catalog.
        if let image = NSImage(named: NSImage.Name(provider.logoImageName)), isUsableProviderImage(image) {
            return image
        }

        // Last fallback: ask resource loader for explicit PNG file lookup.
        if let image = SortyResources.image(named: provider.logoImageName, withExtension: "png"), isUsableProviderImage(image) {
            return image
        }

        return nil
    }

    private func isUsableProviderImage(_ image: NSImage) -> Bool {
        image.size.width > 2 && image.size.height > 2
    }

    private var renderingMode: Image.TemplateRenderingMode {
        if provider.usesSystemImage || !provider.hasColorLogo {
            return .template
        }
        return .original
    }

    private var foregroundColor: Color {
        provider.brandColor
    }

    public var body: some View {
        providerImage
            .renderingMode(renderingMode)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(renderingMode == .template ? foregroundColor : .primary)
    }
}

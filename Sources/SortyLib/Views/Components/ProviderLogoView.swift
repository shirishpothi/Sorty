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

        if let nsImage = SortyResources.image(named: provider.logoImageName) {
            nsImage.isTemplate = !provider.hasColorLogo
            return Image(nsImage: nsImage)
        }

        return Image(systemName: "cpu")
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

import SwiftUI

public struct ProviderLogoView: View {
    public let provider: AIProvider
    public var size: CGFloat = 24

    public init(provider: AIProvider, size: CGFloat = 24) {
        self.provider = provider
        self.size = size
    }

    private var providerImage: Image {
        // System images (for generic providers like OpenAI-Compatible)
        if provider.usesSystemImage {
            return Image(systemName: provider.logoImageName)
        }

        // Use SortyResources.image() which handles:
        // 1. Asset catalog (when compiled .car file exists - Xcode builds)
        // 2. Images subdirectory (SPM .copy() resources - swift build)
        // 3. Direct bundle resource lookup
        if let nsImage = SortyResources.image(named: provider.logoImageName) {
            // Ensure logo assets render in full color even if the image is marked as template.
            nsImage.isTemplate = false
            return Image(nsImage: nsImage)
        }

        // Ultimate fallback: generic system icon
        return Image(systemName: "cpu")
    }

    public var body: some View {
        providerImage
            .renderingMode(provider.usesSystemImage ? .template : .original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(provider.usesSystemImage ? provider.brandColor : .primary)
    }
}

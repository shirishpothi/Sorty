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
        
        // Try to load from Images folder in bundle (for SPM)
        if let resourceURL = Bundle.module.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // Fallback to asset catalog (for Xcode builds)
        return Image(provider.logoImageName, bundle: .module)
    }
    
    public var body: some View {
        providerImage
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

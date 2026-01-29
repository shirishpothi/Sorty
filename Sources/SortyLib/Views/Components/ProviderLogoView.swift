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
        
        // Use safe resource bundle resolver (works for both SPM and Xcode builds)
        let bundle = SortyResources.bundle
        
        // 1. Try loading from Images subdirectory
        if let resourceURL = bundle.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // 2. Try main bundle Resources/Images (Xcode builds)
        if let resourceURL = Bundle.main.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // 3. Try loading directly from bundle (flat resources)
        if let resourceURL = bundle.url(forResource: provider.logoImageName, withExtension: "png"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // 4. Try asset catalog
        if let nsImage = NSImage(named: provider.logoImageName) {
            return Image(nsImage: nsImage)
        }
        
        // 5. Ultimate fallback - use a generic system icon
        return Image(systemName: "cpu")
    }
    
    public var body: some View {
        providerImage
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

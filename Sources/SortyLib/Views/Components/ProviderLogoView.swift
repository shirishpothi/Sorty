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
        
        // Try multiple approaches to load the image, with graceful fallback
        
        // 1. Try Bundle.module (SPM builds) - safely check if it exists
        #if SWIFT_PACKAGE
        if let resourceURL = Bundle.module.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        #endif
        
        // 2. Try loading from main bundle Resources/Images (Xcode builds)
        if let resourceURL = Bundle.main.url(forResource: provider.logoImageName, withExtension: "png", subdirectory: "Images"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // 3. Try loading directly from main bundle (flat resources)
        if let resourceURL = Bundle.main.url(forResource: provider.logoImageName, withExtension: "png"),
           let nsImage = NSImage(contentsOf: resourceURL) {
            return Image(nsImage: nsImage)
        }
        
        // 4. Try asset catalog in main bundle
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

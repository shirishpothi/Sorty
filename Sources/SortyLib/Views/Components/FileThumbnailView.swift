import SwiftUI

/// A view that displays a file thumbnail with fallback and async loading
public struct FileThumbnailView: View {
    let url: URL
    let size: CGSize
    
    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    
    public init(url: URL, size: CGSize = CGSize(width: 20, height: 20)) {
        self.url = url
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isLoading {
                // Subtle loading state
                Color.secondary.opacity(0.1)
                    .frame(width: size.width, height: size.height)
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.5)
                    )
            } else {
                // Fallback icon
                Image(systemName: "doc.fill")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: url) {
            isLoading = true
            thumbnail = await FileThumbnailProvider.shared.thumbnail(for: url, size: size)
            withAnimation(.easeOut(duration: 0.2)) {
                isLoading = false
            }
        }
    }
}

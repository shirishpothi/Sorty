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
                // Subtle loading state - use system icon as placeholder instead of progress view
                Image(nsImage: placeholderIcon())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.6)
            } else {
                // Fallback icon - use actual system icon
                Image(nsImage: placeholderIcon())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
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
    
    private func placeholderIcon() -> NSImage {
        if FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let ext = url.pathExtension
        if !ext.isEmpty {
            return NSWorkspace.shared.icon(forFileType: ext)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}
